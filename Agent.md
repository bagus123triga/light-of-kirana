# LIGHT OF KIRANA — Agent.md

Aturan kerja di repo ini. Baca file ini dulu sebelum mengubah apapun.

## Repo & branch

- Branch: `main` saja. Jangan bikin branch baru.
- 1 push per batch.
- File `.md` di repo ini hanya dua: `Agent.md` dan `README.md`. Jangan bikin file `.md` lain.

## Cara kerja dengan Bagus

- Diskusi dulu sebelum eksekusi; tahan aksi sampai Bagus memberi lampu hijau eksplisit ("buat", "fix", "gas", atau mengetuk opsi yang ditawarkan).
- Kalau Bagus cuma memberi info, jangan debat atau interogasi troubleshooting — jawab bisa/tidak secara langsung.
- Balasan chat harus pendek. Setiap rekomendasi disertai link langsung ke sumbernya, beberapa opsi sekaligus.
- Jangan pernah klaim build/merge/deploy/tes berhasil tanpa bukti nyata dari log, CI, atau tes di tablet Bagus.

## GitHub Actions

- Manual-only (`workflow_dispatch`, ketik `BUILD`). Jangan tambah trigger push/pull_request/schedule tanpa izin Bagus.
- Jangan jalankan CI tanpa izin eksplisit Bagus.

## Dunia v1 (`scripts/world.gd` + `shaders/` + `scripts/tree.gd`)

- Tanah: heightmap + FastNoiseLite, tanpa addon (Terrain3D ditolak dulu — banyak laporan buggy di Android). Satu rumus tinggi dipakai mesh, rumput, pohon, dan pemain (`get_height`); cat per-vertex: rumput / tanah gundul (noise) / batu (lereng curam). Tabrakan = HeightMapShape3D (grid 1 m, berpusat di origin).
- Rumput: MultiMesh (2600 helai, 2 quad menyilang) + `shaders/grass_wind.gdshader` (goyang + hembusan, fase acak via INSTANCE_CUSTOM — butuh `use_custom_data = true`). Rumput HANYA di tanah berumput, bukan tanah gundul/batu.
- Air: `shaders/water.gdshader` (ombak sinus + riak, tanpa depth texture — aman di GL Compatibility). Danau di (14, 12), permukaan y = -0.25. Pemain berendam = gerak melambat.
- Pohon (`scripts/tree.gd`, root StaticBody3D): 3 tebasan → goyang tiap tebasan → roboh menjauhi pemain → 3 kayu → tunggul → tumbuh lagi 60 dtk. Deteksi tebasan: jarak + hadap di `player_controller.gd` (bukan Area3D).
- Bebatuan: bola low-poly acak, tabrakan bola; yang besar jadi rintangan.
- Cahaya: 1 DirectionalLight3D (bayangan, max distance 60) + ProceduralSkyMaterial + kabut + glow. Tetap GL Compatibility.
- Suara (`scripts/ambience.gd`): prosedural dari noise (AudioStreamWAV) — angin loop (volume ikut `wind_strength` yang sama dengan rumput), air loop 3D di danau, langkah per permukaan (rumput/tanah/batu), tebasan, roboh, cipratan, burung acak. Angin & air aslinya memang noise terfilter, jadi sintesis ini dekat dengan aslinya; rekaman CC0 (Freesound/SFXMint) bisa menggantikan stream-nya nanti — jangan tambah file audio tanpa perintah Bagus.
- Mode kamera saja (tanpa pemain, minta Bagus 2026-11-09): `scripts/fly_camera.gd` (Camera3D, grup `fly_camera`) — kamera bebas terbang tanpa tabrakan; joystick/WASD gerak (10 m/s, 25 kalau CEPAT/Shift), NAIK/TURUN (tahan), Space/C, drag kanan lihat-lihat. `player_controller.gd` DIHAPUS. Logika tebang pohon (`tree.gd`) tetap hidup, dipanggil tes saja — pemain yang menebang menyusul kalau Bagus minta. Rumput gameidea didorong posisi kamera (`world.set_interaction_position`).
- Rumput & air DARI SOURCE, bukan bikin sendiri (koreksi Bagus 2026-11-09): rumput = shader gameidea.org "3D Grass Shader with Distortion & Wind" (`shaders/grass_wind.gdshader`, ikutin artikel langkah demi langkah; tekstur noise = NoiseTexture2D dibuat di `world.gd`); air = paket CC0 godotlearning "Stylized Water" (`water/`: shader + material + 2 normal map + `.import`-nya, path sudah diarahkan ke `res://water/`; hash `.import` = md5 path res://). Plane air 20 m, subdivide 80 (verteks tiap 0.25 m, sesuai petunjuk); node air jangan di-rotate/scale.
- Suara REKAMAN ASLI dari Mixkit (lisensi gratis, boleh dipakai di game), bukan sintesis (`scripts/ambience.gd`, file `assets/audio/*.ogg`, total ~1.7 MB): wind (Wind blowing ambience), water (Water flowing ambience loop), birds (Morning birds, potongan 30 dtk), step_grass (Grass step), step_dirt/step_rock (1 langkah 0.7 dtk dipotong dari loop Mixkit — tidak ada versi 1-langkahnya di sana), chop (Wood hard hit), fall (Tree branch brake), splash (Water splash). Loop diaktifkan di kode (`AudioStreamOgg.loop = true`).
- Warna tanah (koreksi Bagus 2026-11-09 "atas putih, bawah berwarna"): dicek headless — batu HAMPIR TIDAK PERNAH muncul (kemiringan maks terrain 0.58, threshold lama 0.55 cuma kena ~0.5%), jadi "putih" itu kemungkinan besar cahaya yang terlalu kuat bikin permukaan atas kepapar putih. Perbaikan: matahari 1.15 → 1.0, ambient 0.7 → 0.6, glow 0.3 → 0.2; batu tetap ada di lereng curam (threshold 0.42, ~4% terrain) dengan warna gelap (0.36,0.34,0.33) + batu besar digelapkan. Tes headless ngecek sebaran (batu < 25%, rumput > 40% dari 400 titik acak). **KOREKSI 2026-11-09 10:37 WIB (dari screenshot tablet Bagus): penyebab aslinya KETEMU — `SurfaceTool.generate_normals()` menghasilkan normal yang menghadap KE BAWAH semua (rata-rata Y -0.97) karena urutan segitiga [a,c,b] terbalik; tanah cuma kena ambient biru pucat → putih. Fix: urutan segitiga jadi [a,b,c, b,d,c], normal kini ke atas (rata-rata Y +0.97, 0/4225 menghadap bawah). Pelajaran: warna vertex-nya dari awal sudah benar (3139/4225 hijau) — yang rusak normalnya.**
- Bilah rumput HARUS quad penuh (koreksi dari screenshot yang sama): mesh bilah lamaku 1 segitiga per sisi — shader gameidea mengharapkan quad (UV.x 0..1 selebar bilah) biar discard-nya membentuk bilah meruncing; segitiga bikin rumput kelihatan duri kuning. Fix: `_blade_mesh` kini 2 quad menyilang (4 verteks + 2 segitiga tiap sisi, UV.y=0 di ujung). **KOREKSI 2026-11-09 10:58 WIB (screenshot ke-2): tanah sudah hijau, danau bagus — tapi rumput masih salah, kelihatan daun berserakan yang rebah. Penyebab: bilahku 0.44 x 0.7 m hampir persegi (artikel: 0.05 x 0.5 m, tipis 1:10) + lengkung 0.5 & hembusan 1.0 mendorong ujung ~0.7 m ke samping pada bilah 0.6 m → rebah. Fix (`bcdcaf8`): bilah tipis 0.07 x 0.6 m, blade_bend 0.5 → 0.2, gust_strength 1.0 → 0.6, jumlah 2600 → 5000 helai biar rapat. KOREKSI 2026-11-09 11:05 WIB (screenshot ke-3, close-up): rumput masih salah — (1) KAKU: bilah cuma 2 segitiga tanpa segmen tinggi, jadi miring seperti tongkat; fix: 3 segmen tinggi (4 baris verteks) biar melengkung; (2) KURANG RAPET: 5000 → 12000 helai, lebar 0.07 → 0.09, bayangan rumput dimatikan (bayangan tongkat panjang bikin makin kaku + hemat GPU); (3) ANGIN BEDA-BEDA: shader artikel menghitung angin/lengkung di LOCAL space, tiap instance diputar acak sumbu Y → tiap helai condong beda arah; fix: hitung offset di WORLD space (arah sama untuk semua helai) lalu ubah ke local lewat inverse(MODEL_MATRIX) — trik yang sama dengan interaksi pemain di artikel. Commit `ea0ea11`, `WORLD_TEST PASS`. KOREKSI 2026-11-09 11:19 WIB (screenshot ke-4): (1) BENTUK: lurus aja, nggak usah 3 segmen — bilah balik 1 segmen, blade_bend 0.05, gust 0.3, sway 0.06; (2) WARNA NGIKUT TANAH BAWAHNYA: INSTANCE_CUSTOM.rgb = warna tanah titik itu (dari `_ground_color`), shader pakai itu buat gradasi (ujung 1.5x lebih terang, pangkal = warna tanah) — hapus uniform color_top/color_bottom artikel; (3) BAWAH TERLALU BESAR: lebar bilah 0.09 → 0.06 + blade_width 0.7 biar runcing; (4) MASIH KURANG RAPET: 12000 → 20000 helai; (5) ANGIN KEKENCENGAN: lihat poin angin di bawah; (6) BURUNG DIHAPUS (tidak ada burung): `birds.ogg` + kode burung dicabut. Commit `2c3a26f`, `WORLD_TEST PASS`. Belum dites ulang di tablet setelah fix ini.**
- **Repo asli shader dipakai (`08c74be`, 2026-11-09, `WORLD_TEST PASS`):** Bagus mengirim repo sumbernya langsung: https://github.com/gameidea-studio/3d-grass-shader (MIT, file `godot-4-grass.gdshader`, 71 baris). Ternyata repo itu versi AWAL penulisnya — fragment-nya cuma satu warna datar, tanpa taper/gradasi seperti artikel. Jadi shader sekarang = repo itu sebagai basis, dengan adaptasi minta Bagus: warna ngikut tanah bawahnya (INSTANCE_CUSTOM), angin diskala `wind_amount` (sinkron suara), arah angin world→model biar serentak, interaksi kamera. Dua bug kecil repo diperbaiki: arah dorong interaksi pakai w=1.0 (ikut translasi) dan konversi arah angin pakai sumbu yang keliru (vec4(dir.x, dir.y, 0, 0) + .xy buat bidang XZ). Taper pindah ke geometri bilah (3 baris: lebar 0.06 → 0.04 → 0.015, tetap lurus — barisnya buat lancip, bukan melengkung). Nilai angin repo dilunakkan: wind_strength 1.0 → 0.35, wind_vertical_strength 0.5 → 0.05. **Koreksi 2026-11-09 12:00 WIB: bilah 0.06 x 0.6 kekecilan + ketinggian + kurang rapet — fix `e3fd438`: bilah dilebarin & dipendekin jadi 0.12 x 0.4 (baris 0.12 → 0.08 → 0.03), jumlah 20000 → 30000 helai, `WORLD_TEST PASS`.** Belum dites di tablet setelah fix ini.
- Sentuhan: `emulate_mouse_from_touch` MATI (bug multi-touch hero-game 2026-11-08) — joystick/tombol/kamera menangani InputEventScreenTouch langsung. Node yang dibuat di kode TIDAK bernama otomatis (namanya `@Nama@N`) — beri `.name` eksplisit kalau dicari pakai `$Nama`.
- Tes: `godot --headless --path . -- --world-test` harus `WORLD_TEST PASS` sebelum push (cek pohon, rumput, air, tanah, tebasan, pendaratan pemain).

## Starter & gameplay

- Starter minimal: jangan tambah aset pihak ketiga, plugin, atau sistem baru tanpa perintah Bagus.
- Scene utama: `scenes/main.tscn` (`scripts/main.gd` membangun dunia starter di kode: langit, matahari, tanah, rintangan, kamera, HUD).
- Gerak prosedural/fisika: cari dan ikuti tutorial/referensi yang sudah terbukti dulu, jangan ngarang dari nol. Tunjukkan referensinya (nama + link + arsitekturnya) dan tunggu persetujuan Bagus sebelum membangun.
- Jangan tambah file animasi tanpa perintah Bagus.
- Verifikasi dengan headless check lokal dulu, lalu minta Bagus mengetes di tabletnya — tes di tablet adalah vonisnya, bukan klaim dari check lokal.

## Android

- Godot 4.4, GL Compatibility, export arm64 saja (`com.lightofkirana.game`, v0.1.0).
- Target perangkat Bagus: tablet itel VistaTab 30GT (Helio G99, Mali-G57).
