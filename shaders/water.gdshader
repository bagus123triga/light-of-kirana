shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Air stylized ala Zelda: ombak sinus di vertex + riak bergerak di fragment.
// Tanpa depth texture (aman di GL Compatibility): warna dangkal/dalam
// dicampur dari riak, plus pantulan langit tipis di tepi pandang.

uniform vec4 shallow_color : source_color = vec4(0.30, 0.62, 0.66, 0.72);
uniform vec4 deep_color : source_color = vec4(0.06, 0.28, 0.48, 0.92);
uniform float wave_height = 0.10;
uniform float wave_speed = 0.9;
uniform float wave_length = 3.0;

varying vec3 v_pos;

void vertex() {
	float w1 = sin(VERTEX.x * 6.28318 / wave_length + TIME * wave_speed) * wave_height;
	float w2 = sin(VERTEX.z * 6.28318 / (wave_length * 0.6) + TIME * wave_speed * 1.3) * wave_height * 0.6;
	VERTEX.y += w1 + w2;
	v_pos = VERTEX;
}

void fragment() {
	float ripple = sin(v_pos.x * 2.0 + TIME * 1.5) * sin(v_pos.z * 2.4 - TIME * 1.2);
	vec3 col = mix(shallow_color.rgb, deep_color.rgb, 0.5 + ripple * 0.18);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	col = mix(col, vec3(0.80, 0.90, 1.0), fres * 0.35);
	float sparkle = smoothstep(0.92, 1.0, sin(v_pos.x * 3.1 + TIME * 2.0) * sin(v_pos.z * 2.7 - TIME * 1.7));
	col += sparkle * 0.15;
	ALBEDO = col;
	ALPHA = mix(shallow_color.a, deep_color.a, 0.5);
	ROUGHNESS = 0.08;
	SPECULAR = 0.6;
}
