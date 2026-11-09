// River current overlay: a transparent mesh just above the water showing streaks that
// scroll along the flow direction. Per-vertex COLOR:
//   r,g = flow direction * speed, encoded 0.5 + 0.5 * v   (so 0.5,0.5 = still)
//   b   = overlay opacity (0 at the river's tapering ends / over land)
//   a   = bank closeness (1 at the shore, 0 in the deep middle) -> foam at the banks
// Two-phase flow map: each pattern lookup is shifted along the flow by a phase that
// repeats; two copies half a period apart are cross-faded, so the pattern never smears.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 streak_color : source_color = vec3(0.9, 0.96, 1.0);
uniform float flow_speed = 1.4;      // metres per second at full strength
uniform float period = 3.0;          // seconds before a phase resets (shorter = less distortion)
uniform float streak_strength = 0.14;
uniform float bank_foam = 0.16;
uniform float darken = 1.0;

varying vec3 wpos;
varying vec2 vflow;

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

// Long thin streaks in the flow frame (a = along the flow, c = across it): narrow bands across, slowly
// varying along, a few of them (wide blobs read as camouflage, not running water).
float streaks(vec2 p, vec2 dir, float shift, float seed) {
	float a = dot(p, dir) - shift;
	float c = dot(p, vec2(-dir.y, dir.x));
	float n = vnoise(vec2(a * 0.08, c * 1.6) + seed);
	n = n * 0.75 + 0.25 * vnoise(vec2(a * 0.2, c * 3.1) + seed * 2.0);
	return smoothstep(0.66, 0.72, n); // hard-ish edge for the low-poly look
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vflow = (COLOR.rg - 0.5) * 2.0;
}

void fragment() {
	vec2 f = vflow;
	float spd = length(f);
	vec2 dir = spd > 0.001 ? f / spd : vec2(1.0, 0.0);
	float dist = flow_speed * period * 0.5 * spd + 0.001; // metres travelled per phase
	float p0 = fract(TIME / period);
	float p1 = fract(TIME / period + 0.5);
	float w0 = abs(2.0 * p0 - 1.0);   // 1 when phase 0 is about to reset -> weight
	w0 = 1.0 - w0;                      // weight of phase 0 (0 at its reset)
	float w1 = 1.0 - w0;
	float s0 = streaks(wpos.xz, dir, p0 * dist * 2.0, 0.0);
	float s1 = streaks(wpos.xz, dir, p1 * dist * 2.0, 5.3);
	float s = s0 * w0 + s1 * w1;

	float bank = COLOR.a;
	// bank foam: broken, slowly pulsing patches near the shore
	float bn = step(0.5, vnoise(wpos.xz * vec2(0.9, 0.9) - dir * TIME * flow_speed * 0.4 * spd));   // drifts downstream
	float foam = bank * bank * bn * bank_foam;

	float a = clamp(s * streak_strength * (0.5 + 0.5 * spd) + foam, 0.0, 0.45) * COLOR.b;
	ALBEDO = streak_color * darken;
	ALPHA = a;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	NORMAL = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
}
