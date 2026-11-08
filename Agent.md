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
