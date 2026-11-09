// Stylised lake / sea water. One shader for the whole global water plane (y = 0).
//  * Vertex waves on a dense grid near the player; flat-shaded facets via screen derivatives.
//  * Colour + opacity from real water depth (scene depth vs the water surface).
//  * Shoreline foam band + two animated foam lines that roll towards the shore ("lapping").
//  * With a shore map (LFShoreMap: the ground height round the player, LFWorld sets it): a long sea swell
//    that dies in the shallows, breakers rolling in along the depth contours, steepening and breaking into
//    foam, and a wash running up the beach and draining back.
// All lighting is left to the engine (no emission), so it follows day/night automatically.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, specular_schlick_ggx;

global uniform vec4 lf_wind;     // dir.x, dir.z, strength 0..1, gust 0..1
global uniform vec4 lf_weather;  // cloud, rain, wetness, fog
// Accumulated on the CPU (LFWaterWaves) so wind changes never jump the phase: never use TIME * wind.
global uniform vec4 lf_water_wave; // swell phase (rad), lapping phase, fleck drift x, z
global uniform vec4 lf_water_dir;  // old swell angle, new swell angle, blend 0..1 (fixed directions, cross-faded)

// No LFEnvironment in the scene (a baked map on its own): nothing advances lf_water_wave, so run the waves on
// the clock at LFWaterWaves' rates instead.
vec4 lf_waves() {
	if (lf_water_wave != vec4(0.0)) {
		return lf_water_wave;
	}
	float w = clamp(lf_wind.z, 0.0, 1.0);
	return vec4(TIME * (0.8 + 1.6 * w), TIME * (0.10 + 0.16 * w + 0.05 * clamp(lf_wind.w, 0.0, 1.0)),
			lf_wind.xy * 0.6 * TIME);
}

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

uniform vec3 shallow_color : source_color = vec3(0.16, 0.56, 0.58);
uniform vec3 deep_color : source_color = vec3(0.04, 0.20, 0.30);
uniform vec3 foam_color : source_color = vec3(0.92, 0.97, 1.0);
uniform float depth_falloff = 0.55;     // bigger = colour reaches "deep" in fewer metres
uniform float min_alpha = 0.35;         // opacity in very shallow water
uniform float max_alpha = 0.90;         // opacity in deep water
uniform float wave_amp = 1.0;           // overall vertex-wave multiplier
uniform float facet_tilt = 1.6;         // exaggerates facet slope so lighting reads (1 = geometric)
uniform float fade_start = 50.0;        // waves fade to flat between these distances from the mesh centre
uniform float fade_end = 78.0;
uniform float lap_speed = 1.0;          // lapping animation speed multiplier
uniform float lap_range = 1.0;          // how far from shore (water depth) lapping lines start
uniform float darken = 1.0;             // colour multiplier (rain_fx lowers it in rain)
// --- sea swell and shore waves ---
uniform sampler2D shore_tex : filter_linear, repeat_disable;   // ground height (m), LFShoreMap
uniform vec4 shore_rect = vec4(0.0);    // x0, z0, size (m) of shore_tex; w = 1 when set
uniform float sea_level = 0.0;          // water above it (a lake up in the hills) gets lake_waves of the sea's
uniform float swell_amp = 0.12;         // open-sea swell height (m) in a calm; about x2.5 in a gale
uniform float shore_wave_amp = 0.22;    // breaker height (m) where they peak, in a calm; x2 in a gale
uniform float shore_wave_k = 7.0;       // breakers per sqrt(m) of depth (x 2 pi): higher = closer together
uniform float swash_amp = 0.11;         // how high (m) the wash runs up the beach, in a calm; x1.6 in a gale
uniform float lake_waves = 0.35;        // share of the swell and shore waves on lakes

varying vec3 wpos;
varying float v_fade;
varying float v_river;   // 1 on a river (the mesh's COLOR.a = 1 - river; no colours: none)
varying float v_depth;   // water depth (m) under this point at rest, from the shore map (100: no map)
varying float v_sea;     // 1 on the sea, lake_waves on a lake, 0 on a river

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// Smooth value noise, 0..1.
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1, 0)), f.x),
			mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), f.x), f.y);
}

// One wave set travelling along angle `a` (rad, world XZ) at accumulated phase `ph`.
float wave_set(vec2 p, float a, float ph, float ws) {
	vec2 wd = vec2(cos(a), sin(a));
	vec2 pd = vec2(-wd.y, wd.x);
	// swell travels with the wind, two cross waves add chop
	float h = sin(dot(p, wd) * 0.70 - ph) * 0.55;
	h += sin(dot(p, wd * 0.6 + pd * 0.6) * 1.05 - ph * 1.25 + 1.7) * 0.30;
	h += sin(dot(p, wd * 0.5 - pd * 0.9) * 1.45 - ph * 1.6 + 4.1) * 0.15 * (0.4 + ws);
	return h;
}

float wave_height(vec2 p) {
	float ws = clamp(lf_wind.z, 0.0, 1.0);
	float ph = lf_waves().x;
	float h = wave_set(p, lf_water_dir.y, ph, ws);
	if (lf_water_dir.z < 0.999) { // wind turned: the old direction fades out, the new one fades in
		h = mix(wave_set(p, lf_water_dir.x, ph, ws), h, smoothstep(0.0, 1.0, lf_water_dir.z));
	}
	float amp = 0.015 + 0.09 * ws + 0.03 * lf_weather.y; // calm lake -> windy chop; rain adds a little
	return h * amp * wave_amp;
}

// Ground height under `xz` from the shore map, or far below where there is none.
float ground_at(vec2 xz) {
	if (shore_rect.w < 0.5) {
		return -100.0;
	}
	vec2 uv = (xz - shore_rect.xy) / shore_rect.z;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return -100.0;
	}
	return textureLod(shore_tex, uv, 0.0).r;
}

// The long sea swell at `p` (-1..1) and its slope, from the swell phase `ph`: two long waves along the wind.
vec3 swell(vec2 p, float ph) {
	vec2 wd = vec2(cos(lf_water_dir.y), sin(lf_water_dir.y));
	vec2 wd2 = vec2(wd.x * 0.8 - wd.y * 0.6, wd.y * 0.8 + wd.x * 0.6);
	float a = dot(p, wd) * 0.09 - ph * 0.45;
	float b = dot(p, wd2) * 0.13 - ph * 0.6 + 1.3;
	vec2 slope = wd * (cos(a) * 0.09 * 0.65) + wd2 * (cos(b) * 0.13 * 0.35);
	return vec3(sin(a) * 0.65 + sin(b) * 0.35, slope);
}

// A breaker at water depth `depth`: (height 0..1 of its profile, where in its cycle this point is 0..1). Crests
// follow the depth contours, so they run along the shore and roll in towards it (sqrt(depth): waves slow down
// as the water shallows, like real ones). The profile has a gentle back and a steep shoreward front.
vec2 breaker(float depth, float lap) {
	float f = fract(sqrt(max(depth, 0.0)) * shore_wave_k / 6.2832 + lap);
	float h = f > 0.25 ? pow(smoothstep(1.0, 0.25, f), 2.0) : smoothstep(0.0, 0.25, f);
	return vec2(h, f);
}

// How far up the beach the wash has run (0..1) at this point of the lapping cycle: fast up, slow drain.
float swash_run(float lap) {
	float u = fract(lap - 0.25);   // 0 when a crest reaches the waterline
	return smoothstep(0.0, 0.16, u) * (1.0 - smoothstep(0.3, 0.9, u));
}

void vertex() {
	v_river = 1.0 - COLOR.a;
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 c = MODEL_MATRIX[3].xyz;
	float d = max(abs(w.x - c.x), abs(w.z - c.z));
	v_fade = 1.0 - smoothstep(fade_start, fade_end, d);
	float ws = clamp(lf_wind.z, 0.0, 1.0);
	float depth = w.y - ground_at(w.xz);
	v_depth = depth;
	v_sea = mix(lake_waves, 1.0, 1.0 - smoothstep(0.3, 1.0, w.y - sea_level)) * (1.0 - v_river);
	float h = wave_height(w.xz);
	// the long swell from open water, fading out as the water shallows
	vec4 wv = lf_waves();
	float sw = swell(w.xz, wv.x).x;
	// (only with a shore map: without one, a baked map, it would run up the beaches)
	h += sw * swell_amp * (1.0 + 1.5 * ws) * smoothstep(0.8, 5.0, depth) * v_sea * step(0.5, shore_rect.w);
	if (shore_rect.w > 0.5) {
		float lap = wv.y * lap_speed;
		// breakers: build up over the last few metres of depth, break at about half a metre
		float env = smoothstep(4.0, 1.0, depth) * smoothstep(0.0, 0.7, depth);
		h += breaker(depth, lap).x * env * shore_wave_amp * (1.0 + ws) * v_sea;
		// the wash: the water by the waterline rises and runs up the sand, then drains
		float near = 1.0 - smoothstep(0.0, 0.9, abs(depth + 0.1));
		h += swash_run(lap) * near * swash_amp * (1.0 + 0.6 * ws) * v_sea;
	}
	w.y += h * v_fade;
	wpos = w;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(w, 1.0)).xyz;
}

void fragment() {
	float t = TIME;
	float ws = clamp(lf_wind.z, 0.0, 1.0);
	float calm = 1.0 - ws;

	// --- faceted normal: geometric triangle normal with exaggerated tilt ---
	vec3 gn = cross(dFdx(wpos), dFdy(wpos));
	gn = length(gn) > 1e-9 ? normalize(gn) : vec3(0, 1, 0);
	if (gn.y < 0.0) gn = -gn;
	vec3 wn = normalize(vec3(gn.x * facet_tilt, gn.y, gn.z * facet_tilt));
	// rain: tiny quantised ripple cells
	float rr = lf_weather.y;
	if (rr > 0.02) {
		vec2 rc = floor(wpos.xz * 1.3);
		float ph = fract(t * 1.7 + hash21(rc));
		float ring = abs(length(fract(wpos.xz * 1.3) - 0.5) - ph * 0.5);
		float drop = (1.0 - smoothstep(0.0, 0.07, ring)) * (1.0 - ph) * step(0.6, hash21(rc + 7.0)) * rr;
		wn = normalize(wn + vec3(drop * 0.6, 0.0, drop * 0.3));
	}
	// past the wave grid the swell is only shading: long rolling bands out to the horizon (exaggerated, as the
	// facets are)
	vec3 swl = swell(wpos.xz, lf_waves().x);
	float swell_on = step(0.5, shore_rect.w) * v_sea;
	if (swell_on > 0.0) {
		vec2 sl = swl.yz * swell_amp * (1.0 + 1.5 * ws) * 9.0 * (1.0 - v_fade) * swell_on;
		wn = normalize(wn + vec3(-sl.x, 0.0, -sl.y));
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);

	// --- water depth below this fragment (vertical metres) ---
	float sd = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	float vdepth = 50.0;
	if (sd > 0.00001) {
		vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, sd, 1.0);
		v.xyz /= v.w;
		float sy = (INV_VIEW_MATRIX * vec4(v.xyz, 1.0)).y;
		vdepth = max(wpos.y - sy, 0.0);
	}

	float dk = clamp(1.0 - exp(-vdepth * depth_falloff), 0.0, 1.0);
	// quantise colour steps slightly for the stylised banded look
	// anti-aliased over how fast the depth changes here: a hard step flickered into hatching along the
	// contours where the depth buffer's precision wobbles across a band's edge
	float dk6 = dk * 6.0;
	float aa = clamp(fwidth(dk6), 0.02, 0.5);
	dk = (floor(dk6) + smoothstep(0.5 - aa, 0.5 + aa, fract(dk6))) / 6.0;
	vec3 col = mix(shallow_color, deep_color, dk) * darken;
	float alpha = mix(min_alpha, max_alpha, dk);
	if (sd <= 0.00001) {
		// nothing drawn below (past the loaded terrain): open deep water, not see-through to the sky behind
		// (which showed as a pale "sand" band out at sea)
		alpha = 1.0;
	}

	// fresnel: more opaque / reflective at grazing angles
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	alpha = clamp(alpha + fres * 0.25, 0.0, 1.0);

	// --- shoreline foam ---
	float fw = clamp(fwidth(vdepth), 0.02, 0.6);
	float edge_noise = vnoise(wpos.xz * 0.9 + vec2(t * 0.05, 0.0));
	// Thresholds are water DEPTH (m). Shores are gentle, so keep these small: a few cm of depth
	// is already ~0.5-1 m of horizontal distance from the waterline.
	float lap = lf_waves().y * lap_speed;   // accumulated: (0.10 + 0.16 * wind + 0.05 * gust) cycles/s
	float shore_on = shore_rect.w > 0.5 ? v_sea * v_fade : 0.0;
	float shore_w = 0.035 + 0.04 * edge_noise + 0.03 * ws + 0.02 * swash_run(lap) * shore_on;
	float foam = step(vdepth, max(shore_w, min(fw * 0.8, 0.1))) * 0.85;

	// --- lapping lines: roll towards the shore, then fade ---
	float range = (0.18 + 0.22 * ws) * lap_range;
	float wob = vnoise(wpos.xz * 0.12) * 0.5;       // bends the lines so they aren't parallel stripes
	float line_w = max(0.012 + 0.01 * ws, fw * 0.7);
	for (int i = 0; i < 2; i++) {
		float ph = fract(lap + float(i) * 0.5 + wob);
		float dl = 0.04 + range * (1.0 - ph);        // line depth shrinks -> moves to shore
		float env = smoothstep(0.0, 0.15, ph) * (1.0 - smoothstep(0.7, 1.0, ph));
		float segs = step(0.38 - 0.2 * ws, vnoise(wpos.xz * 0.30 + float(i) * 11.0 + vec2(0.0, wob * 3.0)));
		float line = step(abs(vdepth - dl), line_w) * env * segs * (0.45 + 0.35 * ws) * (1.0 - v_river);   // a lake's, not a river's
		foam = max(foam, line * (1.0 - 0.75 * shore_on));   // the breakers take over where there is a shore map
	}
	// breaking crests: white along the top and the steep front of a breaker in the shallows, white water
	// left behind it as it runs in
	if (shore_on > 0.0) {
		vec2 bk = breaker(v_depth, lap);
		float shallow = smoothstep(2.2, 0.6, v_depth) * step(0.0, v_depth);
		float crest = smoothstep(0.55, 0.95, bk.x) * (bk.y < 0.35 ? 1.0 : 0.6);
		float trail = (1.0 - smoothstep(0.25, 0.55, bk.y)) * step(0.25, bk.y) * smoothstep(1.2, 0.3, v_depth) * 0.7;
		float patchy = smoothstep(0.25, 0.55, vnoise(wpos.xz * 0.45 + vec2(lap * 1.7, 0.0)));
		foam = max(foam, max(crest, trail) * shallow * patchy * shore_on * (0.75 + 0.25 * ws));
	}
	// whitecaps out at sea: only in a strong wind, sparse, and only on the crests of the swell (foam belongs to
	// the shore; open water shows its rolling waves instead)
	float crest_w = mix(1.0, smoothstep(0.45, 0.9, swl.x), swell_on);
	float fleck = step(0.93 - 0.05 * ws, vnoise(wpos.xz * 1.4 + lf_waves().zw)) * smoothstep(0.6, 0.9, ws) * crest_w;
	foam = clamp(max(foam, fleck * dk), 0.0, 1.0);

	ALBEDO = mix(col, foam_color, foam);
	ALPHA = mix(alpha, 1.0, foam * 0.9);
	ROUGHNESS = mix(0.10 + 0.25 * lf_weather.y, 1.0, foam);
	SPECULAR = mix(0.9, 0.0, foam);
	METALLIC = 0.0;
	if (!FRONT_FACING) { // seen from below: flat murky colour, no foam
		ALBEDO = deep_color * darken;
		ALPHA = 0.55;
		ROUGHNESS = 0.3;
	}
}
