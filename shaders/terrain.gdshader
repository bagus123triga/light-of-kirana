// LIGHT OF KIRANA — terrain bertekstur (minta Bagus 2026-11-09: tanah
// terlalu polos; revisi: tekstur kurang bagus -> tambah lapisan detail
// biar tidak kelihatan berulang). Tekstur CC0 Poly Haven 1K JPG:
// leafy_grass, dirt_floor, rock_face. Sampling pakai posisi dunia (XZ);
// COLOR vertex = mask jenis tanah (r=tanah gundul, g=rumput, b=batu).
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D grass_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D dirt_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_tex : filter_linear_mipmap, repeat_enable;
uniform float tex_scale = 0.33; // 1 tile per 3 meter

varying vec3 world_pos;

// Satu tekstur disampling 2x (skala beda + offset) lalu dicampur —
// pola pengulangan tile jadi samar, detail lebih halus.
vec3 sample_detail(sampler2D tex, vec2 uv) {
	vec3 a = texture(tex, uv).rgb;
	vec3 b = texture(tex, uv * 2.7 + vec2(0.37, 0.61)).rgb;
	return mix(a, b, 0.5);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_pos.xz * tex_scale;
	vec3 grass_c = sample_detail(grass_tex, uv);
	vec3 dirt_c = sample_detail(dirt_tex, uv);
	vec3 rock_c = sample_detail(rock_tex, uv);
	vec3 col = grass_c * COLOR.g + dirt_c * COLOR.r + rock_c * COLOR.b;
	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.5;
}
