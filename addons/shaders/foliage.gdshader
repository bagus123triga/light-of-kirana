// Interactive foliage: vertex-coloured flat-shaded look + wind sway + bending away from
// the player (and a damped wobble afterwards, driven by a short trail of recent positions).
// Used for plants AND tree canopies; each material sets its own radius/height/wind.
shader_type spatial;
render_mode cull_disabled;

// Set at runtime by a player-tracking script if the game has one; at rest otherwise.
global uniform vec3 lf_player_pos;
global uniform vec3 lf_player_vel;
global uniform vec4 lf_player_trail_0; // xyz = position, w = fx_time when recorded
global uniform vec4 lf_player_trail_1;
global uniform vec4 lf_player_trail_2;
global uniform vec4 lf_player_trail_3;
global uniform float lf_fx_time;
// Weather (published by Weather / WeatherVisuals every frame).
global uniform vec4 lf_wind;       // dir.x, dir.z, strength, gustiness
global uniform vec4 lf_weather;    // cloud, rain, wetness, fog
global uniform vec4 lf_wind_phase; // x = gust travel distance (m, along wind), y = oscillation phase (rad)

// No LFEnvironment in the scene (a baked map on its own): nothing advances lf_wind_phase, so sway on the clock
// at LFEnvironment's rates instead.
vec4 lf_sway_phase() {
	if (lf_wind_phase.x != 0.0 || lf_wind_phase.y != 0.0) {
		return lf_wind_phase;
	}
	float w = clamp(lf_wind.z, 0.0, 1.0);
	return vec4(TIME * (1.0 + 9.0 * w), TIME * (1.2 + 3.5 * w), 0.0, 0.0);
}

uniform float tree_height = 0.0;   // > 0 = tree canopy: whole-tree bend (m at scale 1), 0 = plant
uniform float tree_amp = 1.0;      // tree bend multiplier (match the trunk material)
uniform float max_tree_offset = 0.7; // cap (m) on tree top displacement (match the trunk material)
uniform float flutter = 0.05;      // extra canopy leaf flutter (m at full wind)
uniform float push_radius = 1.2;   // metres around the player that get pushed
uniform float height_ref = 0.7;    // height above the base (m) where push is at full strength
uniform float wind_response = 1.0; // 1 = grass, lower = canopies
uniform float max_wind_offset = 0.5; // hard cap (m) on wind displacement so meshes never tear
uniform float push_strength = 0.55; // max horizontal shove (m)
uniform float squash = 0.2;        // downward squash (m) at full push
uniform float wobble_decay = 2.2;  // how fast the after-wobble dies (1/s)
uniform float wobble_freq = 9.0;   // wobble speed (rad/s)
uniform float trail_life = 2.5;    // seconds a trail sample keeps affecting foliage
// Tree canopies dissolve (ordered dither) when the camera is inside or right next to them, so the
// third-person camera never ends up staring at the inside of a leaf blob.
uniform float cam_fade_near = 1.0; // fully gone closer than this (m from the camera)
uniform float cam_fade_far = 3.2;  // fully solid beyond this

#include "res://addons/lowland_forge/shaders/wind.gdshaderinc"

varying vec3 v_color;

vec3 srgb_to_linear(vec3 c) {
	// MSAA can sample a varying just outside a thin triangle (grass blades), where the colour gradient
	// extrapolates below zero: pow() of that is NaN, which glow spreads into big white balls.
	c = max(c, vec3(0.0));
	return mix(pow((c + vec3(0.055)) / vec3(1.055), vec3(2.4)), c / vec3(12.92), step(c, vec3(0.04045)));
}

// Push away from point `p` (treated as a vertical capsule ~1.6 m tall). strength in 0..1.
vec3 push_from(vec3 wp, vec3 p, float strength) {
	float cy = clamp(wp.y, p.y + 0.2, p.y + 1.6);
	vec3 d = wp - vec3(p.x, cy, p.z);
	float dist = length(d);
	float fall = 1.0 - smoothstep(0.0, push_radius, dist);
	vec2 dir = wp.xz - p.xz;
	float dl = length(dir);
	if (dl > 0.02) {
		dir = dir / dl;
	} else {
		dir = vec2(1.0, 0.0);
	}
	return vec3(dir.x, -squash / push_strength, dir.y) * (fall * strength);
}

// Small plants (bushes, ferns, flowers, grass): lean the WHOLE plant away from point `p`,
// using the plant's base (instance origin) instead of each vertex. This keeps the shape intact
// (berries stay on the bush) instead of every vertex fleeing the player and flattening it.
// Standing right in the middle there's no clear direction, so it just squashes down a little.
vec3 push_plant(vec3 origin, vec3 p, float strength) {
	vec2 d = origin.xz - p.xz;
	float dist = length(d);
	float fall = 1.0 - smoothstep(0.0, push_radius, dist);
	fall *= 1.0 - smoothstep(1.0, 2.0, abs(origin.y - p.y)); // ignore if far above/below
	vec2 dir = d / max(dist, 0.001) * smoothstep(0.05, 0.4, dist);
	return vec3(dir.x * 0.7, -squash / push_strength, dir.y * 0.7) * (fall * strength);
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;                  // instance base (includes MultiMesh transform)
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = max(wp.y - origin.y, 0.0);
	float w = clamp(h / height_ref, 0.0, 1.0);
	w *= w; // quadratic: bottoms stay put, tips move most (player push weight)

	vec3 off;
	if (tree_height > 0.0) {
		// Tree canopy: same whole-tree bend as the trunk (identical parameters) + leaf flutter.
		float s = length(MODEL_MATRIX[1].xyz);
		off = tree_bend(wp, origin, tree_height * s, tree_amp, max_tree_offset * s, lf_wind, lf_sway_phase());
		off += leaf_flutter(wp, flutter, lf_wind, lf_sway_phase());
	} else {
		off = plant_wind(wp, origin, height_ref, wind_response, max_wind_offset, lf_wind, lf_sway_phase());
	}
	float t = lf_fx_time;

	// Player contact. Canopies deform per vertex around the body; plants lean as a whole.
	bool is_plant = tree_height <= 0.0;
	vec3 push = is_plant ? push_plant(origin, lf_player_pos, 1.0) : push_from(wp, lf_player_pos, 1.0);
	vec3 contact = is_plant ? origin : wp;
	push.xz += lf_player_vel.xz * 0.04 * (1.0 - smoothstep(0.0, push_radius, distance(contact.xz, lf_player_pos.xz)));
	off += push * push_strength * w;

	// Damped spring wobble left behind by recent positions.
	vec4 trail[4] = vec4[4](lf_player_trail_0, lf_player_trail_1, lf_player_trail_2, lf_player_trail_3);
	for (int i = 0; i < 4; i++) {
		float age = t - trail[i].w;
		if (age > 0.0 && age < trail_life) {
			float spring = exp(-wobble_decay * age) * sin(wobble_freq * age);
			// Positive swing pushes away from where the player was, then back and past.
			vec3 tp = is_plant ? push_plant(origin, trail[i].xyz, spring * 0.6) : push_from(wp, trail[i].xyz, spring * 0.6);
			off += tp * push_strength * w;
		}
	}

	// Convert the world-space offset back to model space (rotation + uniform-ish scale).
	mat3 m = mat3(MODEL_MATRIX);
	float s2 = max(dot(m[0], m[0]), 0.0001);
	VERTEX += (transpose(m) * off) / s2;
	v_color = COLOR.rgb;
	if (tree_height > 0.0) {
		// Per-tree tint from the instance position: some canopies darker/bluer, some lighter/yellower.
		float h1 = fract(sin(dot(floor(origin.xz * 2.0), vec2(12.9898, 78.233))) * 43758.5453);
		float h2 = fract(sin(dot(floor(origin.xz * 2.0), vec2(39.3468, 11.135))) * 24634.6345);
		v_color *= mix(0.8, 1.15, h1);
		v_color *= mix(vec3(0.92, 0.98, 1.1), vec3(1.15, 1.04, 0.85), h2);
	}
}

float bayer4(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int i = x + y * 4;
	int m[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i]) + 0.5) / 16.0;
}

void fragment() {
	if (tree_height > 0.0) {
		float fade = smoothstep(cam_fade_near, cam_fade_far, length(VERTEX));  // VERTEX is view space
		if (fade < bayer4(FRAGCOORD.xy)) {
			discard;
		}
	}
	float wet = lf_weather.z;
	ALBEDO = srgb_to_linear(v_color) * mix(1.0, 0.72, wet);
	ROUGHNESS = mix(1.0, 0.55, wet);
	SPECULAR = mix(0.2, 0.45, wet);
}
