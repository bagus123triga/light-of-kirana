// Tree trunks: flat vertex-colour look + whole-tree wind bend (matches the canopy in
// foliage.gdshader, which uses the same tree_bend() with the same parameters).
shader_type spatial;
render_mode cull_back;

#include "res://addons/lowland_forge/shaders/wind.gdshaderinc"

global uniform vec4 lf_wind;       // dir.x, dir.z, strength, gustiness
global uniform vec4 lf_weather;    // cloud, rain, wetness, fog
global uniform vec4 lf_wind_phase; // x = gust travel distance, y = oscillation phase

// No LFEnvironment in the scene (a baked map on its own): nothing advances lf_wind_phase, so sway on the clock
// at LFEnvironment's rates instead.
vec4 lf_sway_phase() {
	if (lf_wind_phase.x != 0.0 || lf_wind_phase.y != 0.0) {
		return lf_wind_phase;
	}
	float w = clamp(lf_wind.z, 0.0, 1.0);
	return vec4(TIME * (1.0 + 9.0 * w), TIME * (1.2 + 3.5 * w), 0.0, 0.0);
}

uniform float tree_height = 8.0;     // metres at scale 1 (must match the canopy material)
uniform float tree_amp = 1.0;        // bend strength multiplier (must match the canopy material)
uniform float max_tree_offset = 0.7; // cap (m) on top displacement (must match the canopy material)

varying vec3 v_color;

vec3 srgb_to_linear(vec3 c) {
	// MSAA can sample a varying just outside a thin triangle (grass blades), where the colour gradient
	// extrapolates below zero: pow() of that is NaN, which glow spreads into big white balls.
	c = max(c, vec3(0.0));
	return mix(pow((c + vec3(0.055)) / vec3(1.055), vec3(2.4)), c / vec3(12.92), step(c, vec3(0.04045)));
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float s = length(MODEL_MATRIX[1].xyz);
	vec3 off = tree_bend(wp, origin, tree_height * s, tree_amp, max_tree_offset * s, lf_wind, lf_sway_phase());
	mat3 m = mat3(MODEL_MATRIX);
	float s2 = max(dot(m[0], m[0]), 0.0001);
	VERTEX += (transpose(m) * off) / s2;
	v_color = COLOR.rgb;
}

void fragment() {
	float wet = lf_weather.z;
	ALBEDO = srgb_to_linear(v_color) * mix(1.0, 0.7, wet);
	ROUGHNESS = mix(1.0, 0.35, wet);
}
