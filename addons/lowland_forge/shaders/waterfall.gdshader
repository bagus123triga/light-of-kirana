// A waterfall (LFWaterfall): the curtain, streaks running down it, or (pool) the foam at its foot, churning.
// UV: the curtain's (m across, m fallen); the pool's world x, z. COLOR.a: opacity (fades at the edges).
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform bool pool = false;
uniform vec3 water_color : source_color = vec3(0.62, 0.78, 0.86);
uniform vec3 foam_color : source_color = vec3(0.95, 0.97, 1.0);
uniform float fall_speed = 4.0;   // m per second down the curtain
uniform float opacity = 0.85;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1, 0)), f.x),
			mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	float n;
	float a;
	vec3 col;
	if (pool) {
		vec2 p = UV * 0.9;
		n = vnoise(p + vec2(TIME * 0.7, -TIME * 0.4)) * 0.6 + vnoise(p * 2.3 - vec2(TIME * 0.5, TIME * 0.9)) * 0.4;
		a = COLOR.a * smoothstep(0.25, 0.65, n * (0.6 + 0.6 * COLOR.a));
		col = foam_color;
	} else {
		// streaks: stretched noise along the fall, scrolling down, faster lower down
		float down = UV.y - TIME * fall_speed;
		n = vnoise(vec2(UV.x * 2.2, down * 0.35)) * 0.65 + vnoise(vec2(UV.x * 5.0, down * 0.8)) * 0.35;
		a = COLOR.a * (0.55 + 0.45 * n);
		col = mix(water_color, foam_color, smoothstep(0.45, 0.85, n) * 0.85 + 0.1);
	}
	ALBEDO = col;
	ALPHA = clamp(a * opacity, 0.0, 1.0);
	ROUGHNESS = 0.35;
	SPECULAR = 0.3;
}
