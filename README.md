# Light of Kirana

Light of Kirana is an open-world adventure set in a vast kingdom where the light is slowly fading. As Kirana, a young wanderer carrying the last spark of light, you explore forests, mountains, and ancient ruins — climb anything, swim across rivers, solve shrines, and battle creatures of darkness to bring the light back to the world.

Starter game Android, Godot 4.4, GL Compatibility.

Scene utama: `scenes/main.tscn` — dunia v1: tanah berbukit dari heightmap + noise (dicat rumput / tanah gundul / batu di lereng curam saja; batu ditekan 2026-11-09 karena kebanyakan batu abu-abu bikin bukit kelihatan putih), rumput MultiMesh + shader angin dari gameidea.org (ikutin artikelnya langkah demi langkah, bukan bikin sendiri), danau + air stylized dari godotlearning.com (paket CC0 di `water/`, ada busa pantai + ombak + pantulan), 24 pohon bisa ditebang (3 tebasan → roboh → kayu → tunggul → tumbuh lagi 60 dtk; logika tebang tetap hidup walau belum ada pemain), bebatuan, 1 matahari + langit + kabut, suara REKAMAN ASLI dari Mixkit (angin, air, burung, langkah rumput/tanah/batu, tebas, roboh, cipratan — lihat `assets/audio/`). **Mode kamera saja (tanpa pemain, minta Bagus 2026-11-09):** kamera bebas terbang tanpa tabrakan — joystick/WASD gerak (10 m/s, 25 kalau CEPAT/Shift), drag kanan lihat-lihat, NAIK/TURUN (tahan), Space/C juga bisa.

Tes dunia headless: `godot --headless --path . -- --world-test` (harus `WORLD_TEST PASS`).

## Jalankan di editor

Buka `project.godot` di Godot 4.4, tekan F5.

## Build APK (manual saja)

Actions > Android Build (Manual Only) > Run workflow > ketik `BUILD` > Run workflow. APK debug muncul di Artifacts `light-of-kirana-android-debug`, 7 hari.

Push ke `main` TIDAK menjalankan build.
