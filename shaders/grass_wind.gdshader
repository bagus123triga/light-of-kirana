// Rumput 3D dengan angin & distorsi — DARI gameidea.org, "3D Grass Shader
// with Distortion & Wind" (2023-12-03). Kode shader ini mengikuti artikel
// itu langkah demi langkah (bentuk bilah, gradasi warna, variasi noise,
// angin + hembusan, interaksi pemain, highlight angin & shading akhir).
// Yang diadaptasi cuma: tekstur noise dibuat di kode (NoiseTexture2D) dan
// player_position diisi posisi kamera (mode kamera saja, tanpa pemain).
// UV bilah: UV.y = 0.0 di ujung, 1.0 di pangkal (syarat artikel).
shader_type spatial;

render_mode cull_disabled, depth_draw_opaque;

uniform float blade_height_taper = 2.0;
uniform float blade_width = 1.0;
uniform vec3 color_variation : source_color = vec3(0.9, 0.9, 0.2);
uniform float patch_scale = 5.0;
uniform sampler2D wind_noise : hint_default_white;
uniform vec2 wind_direction = vec2(1.0, 0.0);
uniform float wind_texture_scale = 20.0;
uniform float wind_speed = 0.1;
uniform float still_sway_speed = 4.5;
uniform float still_sway_strength = 0.1;
uniform float gust_strength = 1.0;
uniform float gust_frequency = 0.08;
// Kekuatan angin global 0..1 dari world.gd — SATU nilai dengan suara
// angin, kadang 0 (reda total) kadang 1 (berhembus). Bukan dari artikel.
uniform float wind_amount = 0.5;
uniform vec3 player_position = vec3(0.0, -100.0, 0.0);
uniform float interaction_radius = 1.0;
uniform float interaction_push = 1.0;
uniform float blade_bend = 0.5;

varying float v_patch;
varying float v_wind_intensity;
varying float v_height;
// Warna tanah di bawah helai ini (INSTANCE_CUSTOM.rgb dari MultiMesh) —
// warna rumput ngikut warna bawahnya (minta Bagus), bukan warna tetap.
varying vec3 v_ground;
varying float v_var;

void vertex() {
	v_height = UV.y;
	v_ground = INSTANCE_CUSTOM.rgb;
	v_var = INSTANCE_CUSTOM.a;

	vec3 world_pos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;

	// variation patch factor
	float patch_factor = texture(wind_noise, world_pos.xz / patch_scale).r;
	v_patch = patch_factor;

	// wind calculation
	vec2 global_uv = world_pos.xz / wind_texture_scale;
	vec2 move_uv = global_uv + (normalize(wind_direction) * TIME * wind_speed);
	float noise_val = texture(wind_noise, move_uv).r;
	float gust_mask = smoothstep(gust_frequency, 1.0, noise_val);
	float idle_sway = sin(TIME * still_sway_speed + world_pos.x + world_pos.z) * still_sway_strength;
	float flutter = sin(TIME * 20.0 + world_pos.x) * 0.1;
	float gust_push = (gust_mask * gust_strength) + (gust_mask * flutter);
	v_wind_intensity = gust_mask;

	vec3 vertex_pos = VERTEX;
	float height_factor = 1.0 - UV.y;
	float bend_strength = pow(height_factor, 2.0);

	// Arah angin & lengkung dihitung di WORLD space biar semua helai
	// condong ke arah yang SAMA (serentak). Versi artikel menghitungnya
	// di local space (object_right/object_forward) — tiap instance
	// diputar acak sumbu Y, jadi tiap helai condong ke arah beda.
	// Trik yang sama dengan interaksi pemain di artikel: offset world
	// diubah ke local lewat inverse(MODEL_MATRIX).
	vec2 wind_dir = normalize(wind_direction);
	// Angin diskala wind_amount (0 = reda total, bilah tegak diam).
	vec3 world_offset = vec3(wind_dir.x, 0.0, wind_dir.y) * ((idle_sway + gust_push) * wind_amount + blade_bend) * bend_strength;

	// preserve volume / prevent stretching
	float dist_moved = length(world_offset.xz);
	float y_drop = dist_moved * 0.2 * bend_strength;

	VERTEX = vertex_pos + mat3(inverse(MODEL_MATRIX)) * world_offset;
	VERTEX.y -= y_drop;

	// interaction
	vec3 interaction_offset = vec3(0.0);
	vec3 diff_vec = world_pos - player_position;
	float dist_3d = length(diff_vec);
	if (dist_3d < interaction_radius) {
		float push_strength = smoothstep(interaction_radius, 0.0, dist_3d);
		vec3 push_dir_flat = diff_vec;
		push_dir_flat.y = 0.0;
		push_dir_flat = normalize(push_dir_flat);
		vec3 local_push_dir = mat3(inverse(MODEL_MATRIX)) * push_dir_flat;
		interaction_offset += local_push_dir * push_strength * interaction_push * bend_strength;
	}
	VERTEX += interaction_offset;
}

void fragment() {
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}

	// shape
	float center_dist = abs(UV.x - 0.5) * 2.0;
	float shape_mask = pow(UV.y, 1.0 / blade_height_taper);
	if (center_dist > shape_mask * blade_width) discard;

	// color — ngikut warna tanah di bawahnya: ujung lebih terang,
	// pangkal = warna tanah. Variasi kecil per helai dari INSTANCE_CUSTOM.a.
	vec3 tip_col = v_ground * 1.5;
	vec3 gradient = mix(tip_col, v_ground, UV.y);
	vec3 wind_highlight = tip_col * 1.5;
	vec3 varied_color = mix(gradient, color_variation, v_patch * 0.2);
	varied_color *= 0.9 + v_var * 0.2;
	vec3 final_color = mix(varied_color, wind_highlight, v_wind_intensity * 0.4 * wind_amount);
	ALBEDO = final_color;

	float bottom_to_top = v_height; // 0 = tip, 1 = base
	AO = bottom_to_top + v_wind_intensity * 0.3;
	AO = clamp(AO, 0.0, 1.0);
	AO_LIGHT_AFFECT = 1.0;

	vec3 world_up_view = normalize(mat3(VIEW_MATRIX) * vec3(0.0, 1.0, 0.0));
	NORMAL = mix(NORMAL, world_up_view, bottom_to_top * 0.5);

	ROUGHNESS = 0.8;
	SPECULAR = 0.2;
	BACKLIGHT = ALBEDO * 0.3;
}
