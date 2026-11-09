// Rumput 3D — DARI REPO gameidea-studio/3d-grass-shader
// (https://github.com/gameidea-studio/3d-grass-shader, MIT),
// file godot-4-grass.gdshader. Dipakai sebagai basis.
// Yang diadaptasi (minta Bagus): warna rumput ngikut warna tanah di
// bawahnya (INSTANCE_CUSTOM, bukan uniform grass_color tetap); angin
// diskala wind_amount (SATU nilai dengan suara angin, kadang 0);
// arah angin diubah world->model biar serentak; interaksi pakai
// posisi kamera (mode kamera saja, tanpa pemain).
// Catatan: repo ini versi awal penulisnya — fragment-nya cuma satu
// warna datar, tanpa taper/gradasi seperti artikel. Taper-nya dipindah
// ke geometri bilah (mesh meruncing), bukan discard di shader.
shader_type spatial;
render_mode cull_disabled;

// Warna tanah di bawah helai ini (INSTANCE_CUSTOM.rgb dari MultiMesh).
varying vec3 v_ground;

// Player interaction parameters (repo)
uniform vec3 player_position = vec3(0.0, -100.0, 0.0);
uniform float interaction_power = 0.5;
uniform float interaction_radius = 1.0;

// Wind sway parameters (repo)
uniform sampler2D wind_noise;
uniform vec2 wind_horizontal_direction = vec2(1.0, 0.0);
uniform float wind_texture_tile_size = 20.0;
uniform float wind_speed = 0.05;
uniform float wind_strength = 1.0;
uniform float wind_vertical_strength = 0.5;
// Kekuatan angin global 0..1 dari world.gd — SATU nilai dengan suara
// angin, kadang 0 (reda total) kadang 1 (berhembus). Bukan dari repo.
uniform float wind_amount = 0.5;

void vertex() {
	v_ground = INSTANCE_CUSTOM.rgb;

	// Player position distort shader (repo)
	vec3 world_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 direction_to_player = world_vertex - player_position;
	direction_to_player.y = 0.0;
	direction_to_player = normalize(direction_to_player);
	float distance_to_player = distance(player_position, world_vertex);
	float interaction_strength = smoothstep(interaction_radius, 0.0, distance_to_player);
	// Arah dorong diubah world->model (repo memakai w=1.0 di sini yang
	// ikut menambahkan translasi — diperbaiki jadi arah murni).
	vec3 local_push_dir = mat3(inverse(MODEL_MATRIX)) * direction_to_player;
	VERTEX += local_push_dir * interaction_strength * interaction_power * (1.0 - UV.y);

	// Wind shader (repo)
	vec3 world_vertex2 = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 normalized_wind_direction = normalize(wind_horizontal_direction);
	vec2 world_uv = world_vertex2.xz / wind_texture_tile_size + normalized_wind_direction * TIME * wind_speed;
	// we displace only the top part of the mesh
	float displacement_affect = (1.0 - UV.y);
	float wind_noise_intensity = (textureLod(wind_noise, world_uv, 0.0).r - 0.5);
	// We convert the direction of the wind into model space from world space
	// if we used it directly in vertex space, rotated blades of grass wouldn't behave properly
	// (repo memakai vec4(dir.x, dir.y, 0, 0) + .xy — sumbu-nya keliru
	// untuk bidang XZ; diperbaiki jadi vec4(dir.x, 0, dir.y, 0) + .xz.)
	vec3 model_dir = (inverse(MODEL_MATRIX) * vec4(normalized_wind_direction.x, 0.0, normalized_wind_direction.y, 0.0)).xyz;
	vec3 wind_vector = vec3(
		wind_noise_intensity * model_dir.x,
		1.0 - wind_noise_intensity,
		wind_noise_intensity * model_dir.z
	);
	wind_vector = normalize(wind_vector);
	wind_vector *= vec3(
		wind_strength,
		wind_vertical_strength,
		wind_strength
	);
	VERTEX += wind_vector * displacement_affect * wind_amount;
}

void fragment() {
	// Repo: ALBEDO = grass_color.rgb (satu warna tetap).
	// Di sini: ngikut warna tanah di bawahnya — ujung sedikit lebih
	// terang, pangkal = warna tanah.
	ALBEDO = mix(v_ground * 1.3, v_ground, UV.y);
	ROUGHNESS = 0.8;
}
