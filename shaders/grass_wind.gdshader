shader_type spatial;
render_mode cull_disabled;

// Rumput kena angin — pola dari:
// https://gameidea.org/2023/12/03/3d-grass-shader-with-distortion-wind/
// (tutorial rumput angin yang terinspirasi Breath of the Wild).
// Ujung helai (UV.y = 0) goyang paling kuat, pangkal (UV.y = 1) diam.
// INSTANCE_CUSTOM.x = fase acak tiap helai, biar tidak gerak barengan.

uniform vec3 wind_direction = vec3(1.0, 0.0, 0.35);
uniform float wind_strength = 0.35;
uniform float wind_speed = 1.2;
uniform vec3 color_base : source_color = vec3(0.14, 0.34, 0.10);
uniform vec3 color_tip : source_color = vec3(0.45, 0.72, 0.25);

varying float v_wind;

void vertex() {
	float phase = INSTANCE_CUSTOM.x;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * wind_speed + phase + wp.x * 0.15 + wp.z * 0.12;
	float sway = sin(t) * 0.6 + sin(t * 2.3 + 1.7) * 0.4;
	float gust = sin(TIME * 0.35 + wp.x * 0.05 + wp.z * 0.04) * 0.5 + 0.5;
	float weight = 1.0 - UV.y;
	float amount = (sway * 0.5 + gust * 0.9) * wind_strength * weight;
	v_wind = amount;
	VERTEX.xz += normalize(wind_direction.xz) * amount * 0.22;
}

void fragment() {
	vec3 col = mix(color_base, color_tip, 1.0 - UV.y);
	col += v_wind * 0.10;
	ALBEDO = col;
	ROUGHNESS = 1.0;
}
