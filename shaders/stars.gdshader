// LIGHT OF KIRANA — kubah bintang (minta Bagus 2026-11-09).
// Tekstur = foto langit malam asli (CC0, Wikimedia) — bukan titik asal bikin.
// Cuma piksel terang (bintang) yang kelihatan; langit gelap foto jadi
// transparan, jadi gradien langit ProceduralSkyMaterial tetap terlihat.
// Dilihat dari dalam (cull_front), tanpa kabut, tanpa cahaya.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, blend_mix;

uniform sampler2D star_tex : filter_linear_mipmap, repeat_enable;
uniform float star_brightness = 1.0;

void fragment() {
	vec3 c = texture(star_tex, UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	// Ambang: cuma bintang (terang) yang muncul, langit gelap hilang.
	float a = smoothstep(0.08, 0.35, l) * star_brightness;
	ALBEDO = c;
	ALPHA = a;
}
