// Flat ring / foam blob lying on the water. The whole animation is driven by the
// global fx_time and this material's `birth` time, so nothing needs updating per frame.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

global uniform float lf_fx_time;

uniform float birth = -1000.0;     // fx_time when spawned
uniform float life = 1.2;          // seconds until fully faded
uniform float fill = 0.0;          // 0 = expanding ring, 1 = soft foam blob
uniform float start_size = 0.15;   // ring radius at birth (0..1 of the quad)
uniform vec3 tint : source_color = vec3(0.92, 0.98, 1.0);
uniform float strength = 0.8;

void fragment() {
	float t = clamp((lf_fx_time - birth) / life, 0.0, 1.0);
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float a = 0.0;
	if (fill < 0.5) {
		float e = 1.0 - (1.0 - t) * (1.0 - t); // ease-out expansion
		float r = mix(start_size, 0.95, e);
		float w = mix(0.07, 0.035, t);
		// hard-ish edge keeps the stylised low-poly feel
		a = 1.0 - smoothstep(w * 0.5, w, abs(d - r));
		a *= 1.0 - t;
	} else {
		float r = mix(0.5, 0.95, t);
		a = (1.0 - smoothstep(r - 0.12, r, d));
		a *= 1.0 - t * t;
		a *= step(0.0, 1.0 - d);
	}
	ALBEDO = tint;
	ALPHA = a * strength * (birth > 0.0 ? 1.0 : 0.0);
}
