// LIGHT OF KIRANA — terrain bertekstur (minta Bagus 2026-11-09: tanah
// terlalu polos). Tekstur CC0 Poly Haven 1K JPG: leafy_grass, dirt_floor,
// rock_face. Sampling pakai posisi dunia (XZ) biar tiling seragam;
// COLOR vertex = mask jenis tanah (r=tanah gundul, g=rumput, b=batu).
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D grass_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D dirt_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_tex : filter_linear_mipmap, repeat_enable;
uniform float tex_scale = 0.25; // 1 tile per 4 meter

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_pos.xz * tex_scale;
	vec3 grass_c = texture(grass_tex, uv).rgb;
	vec3 dirt_c = texture(dirt_tex, uv).rgb;
	vec3 rock_c = texture(rock_tex, uv).rgb;
	vec3 col = grass_c * COLOR.g + dirt_c * COLOR.r + rock_c * COLOR.b;
	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.5;
}
