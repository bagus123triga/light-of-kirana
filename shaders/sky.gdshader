// LIGHT OF KIRANA — langit stylized (minta Bagus 2026-11-09: foto asli
// kelihatan "nempel" ke game; cari cara yang bener).
// Referensi: "Stylized Sky Shader With Clouds" (godotshaders.com) —
// shader_type sky: gradien siang/senja/malam + horizon glow + matahari
// (disc + halo) + bulan sabit + awan noise + bintang Voronoi, semuanya
// prosedural, TANPA tekstur foto. Awan & bintang pakai NoiseTexture2D
// yang dibuat di kode (sky.gd), bukan file.
// Arah matahari/bulan dibaca dari LIGHT0_DIRECTION (DirectionalLight3D
// yang diputar sky.gd mengikuti jam) — jadi shader otomatis ikut siklus
// hari. Tanpa use_half_res_pass (aman di renderer Compatibility).

shader_type sky;

// Gradien langit (atas/bawah) per waktu.
uniform vec3 day_top_color : source_color = vec3(0.18, 0.45, 0.98);
uniform vec3 day_bottom_color : source_color = vec3(0.68, 0.82, 0.98);
uniform vec3 sunset_top_color : source_color = vec3(0.25, 0.30, 0.60);
uniform vec3 sunset_bottom_color : source_color = vec3(0.95, 0.55, 0.35);
uniform vec3 night_top_color : source_color = vec3(0.015, 0.02, 0.06);
uniform vec3 night_bottom_color : source_color = vec3(0.04, 0.05, 0.10);

// Cahaya horizon.
uniform vec3 horizon_color_day : source_color = vec3(0.70, 0.82, 0.98);
uniform vec3 horizon_color_sunset : source_color = vec3(0.95, 0.60, 0.35);
uniform vec3 horizon_color_night : source_color = vec3(0.05, 0.07, 0.14);
uniform float horizon_falloff : hint_range(0.0, 1.0, 0.1) = 0.15;

// Matahari (disc + halo lembut).
uniform vec3 sun_col : source_color = vec3(1.0, 0.95, 0.80);
uniform float sun_size : hint_range(0.01, 1.0) = 0.08;
uniform float sun_blur : hint_range(0.01, 1.0) = 0.02;
uniform float sun_glow : hint_range(0.0, 1.0) = 0.35;

// Bulan (sabit: disc dikurangi disc geser).
uniform vec3 moon_col : source_color = vec3(0.92, 0.95, 1.0);
uniform float moon_size : hint_range(0.01, 1.0) = 0.06;
uniform float moon_crescent_offset : hint_range(-1.0, 1.0) = 0.35;

// Awan (3 lapis noise, hanyut ikut TIME; bentuk puff lembut ala Zelda).
uniform sampler2D clouds_texture : filter_linear_mipmap, repeat_enable;
uniform sampler2D clouds_distort_texture : filter_linear_mipmap, repeat_enable;
uniform sampler2D clouds_noise_texture : filter_linear_mipmap, repeat_enable;
uniform vec3 clouds_main_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 clouds_edge_color : source_color = vec3(0.85, 0.88, 0.95);
uniform float clouds_speed : hint_range(0.0, 0.1, 0.01) = 0.015;
uniform float clouds_scale : hint_range(0.0, 1.0, 0.01) = 0.35;
uniform float clouds_cutoff : hint_range(0.0, 1.0, 0.01) = 0.55;
uniform float clouds_fuzziness : hint_range(0.0, 1.0, 0.01) = 0.25;

// Bintang (Voronoi, cuma malam).
uniform sampler2D stars_texture : filter_linear_mipmap, repeat_enable;
uniform float stars_cutoff : hint_range(0.0, 1.0, 0.01) = 0.75;
uniform float stars_speed : hint_range(0.0, 0.1) = 0.005;

void sky() {
	vec2 sky_uv = EYEDIR.xz / max(EYEDIR.y, 0.08);

	// Siang / senja / malam dari ketinggian matahari.
	float day_amount = clamp(LIGHT0_DIRECTION.y, 0.0, 1.0);
	float sunset_amount = clamp(1.0 - abs(LIGHT0_DIRECTION.y), 0.0, 1.0);
	float night_amount = clamp(-LIGHT0_DIRECTION.y, 0.0, 1.0);

	vec3 gradient_day = mix(day_bottom_color, day_top_color, clamp(EYEDIR.y, 0.0, 1.0)) * day_amount;
	vec3 gradient_sunset = mix(sunset_bottom_color, sunset_top_color, clamp(EYEDIR.y, 0.0, 1.0)) * sunset_amount;
	vec3 gradient_night = mix(night_bottom_color, night_top_color, clamp(EYEDIR.y, 0.0, 1.0)) * night_amount;
	vec3 sky_gradients = gradient_day + gradient_sunset + gradient_night;

	float horizon = 1.0 - abs(EYEDIR.y + horizon_falloff);
	vec3 horizon_glow = clamp(horizon * day_amount, 0.0, 1.0) * horizon_color_day
		+ clamp(horizon * sunset_amount, 0.0, 1.0) * horizon_color_sunset
		+ clamp(horizon * night_amount, 0.0, 1.0) * horizon_color_night;

	// Matahari: disc tajam + halo lembut di sekelilingnya.
	float sun_distance = distance(EYEDIR.xyz, LIGHT0_DIRECTION);
	float sun_power = 1.0 - clamp(sun_distance / sun_size, 0.0, 1.0);
	float sun_disc = clamp(sun_power / max(sun_blur, 0.001), 0.0, 1.0);
	float sun_halo = pow(max(0.0, 1.0 - sun_distance / (sun_size * 5.0)), 3.0) * sun_glow;
	vec3 sun = sun_col * (sun_disc + sun_halo);

	// Bulan: disc dikurangi disc geser = sabit.
	float moon_distance = distance(EYEDIR.xyz, -LIGHT0_DIRECTION);
	float moon_power = 1.0 - clamp(moon_distance / moon_size, 0.0, 1.0);
	float moon_disc = clamp(moon_power / 0.01, 0.0, 1.0);
	float moon_crescent_distance = distance(vec3(EYEDIR.x + moon_crescent_offset, EYEDIR.y, EYEDIR.z), -LIGHT0_DIRECTION);
	float moon_crescent_power = 1.0 - clamp(moon_crescent_distance / moon_size, 0.0, 1.0);
	float moon_crescent_disc = clamp(moon_crescent_power / 0.01, 0.0, 1.0);
	vec3 moon = clamp(moon_col * moon_disc - moon_col * moon_crescent_disc, 0.0, 1.0);

	// Awan: 3 lapis noise (dasar + distorsi + detail), hanyut pelan.
	// Makin tinggi memandang, makin jelas awannya; di horizon memudar.
	float clouds_movement = TIME * clouds_speed * 0.5;
	float clouds_base_noise = texture(clouds_texture, (sky_uv + clouds_movement) * clouds_scale).r;
	float noise1 = texture(clouds_distort_texture, (sky_uv + clouds_base_noise + (clouds_movement * 0.75)) * clouds_scale).r;
	float noise2 = texture(clouds_noise_texture, (sky_uv + noise1 + (clouds_movement * 0.25)) * clouds_scale).r;
	float clouds_noise_value = clamp(noise1 * noise2, 0.0, 1.0) * clamp(EYEDIR.y, 0.0, 1.0);
	float clouds_value = clamp(smoothstep(clouds_cutoff, clouds_cutoff + clouds_fuzziness, clouds_noise_value), 0.0, 1.0);
	// Awan gelap di malam hari (biar tidak menyala).
	vec3 cloud_col = mix(clouds_edge_color, clouds_main_color, clouds_value);
	cloud_col *= mix(0.15, 1.0, day_amount + sunset_amount * 0.7);
	vec3 clouds = cloud_col * clouds_value;
	float clouds_negative = 1.0 - clouds_value;

	// Bintang: titik-titik dari noise Voronoi, cuma malam.
	vec3 stars = texture(stars_texture, sky_uv * 0.5 + (stars_speed * TIME)).rgb;
	stars *= night_amount;
	stars = step(stars_cutoff, stars);

	vec3 sun_moon = sun + moon;
	sun_moon = clamp(sun_moon * clouds_negative, 0.0, 1.0);
	sky_gradients = clamp(sky_gradients * clouds_negative, 0.0, 1.0);

	COLOR = horizon_glow + sky_gradients + sun_moon + stars + clouds;
}
