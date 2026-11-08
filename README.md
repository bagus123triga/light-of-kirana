# Light of Kirana

Light of Kirana is an open-world adventure set in a vast kingdom where the light is slowly fading. As Kirana, a young wanderer carrying the last spark of light, you explore forests, mountains, and ancient ruins — climb anything, swim across rivers, solve shrines, and battle creatures of darkness to bring the light back to the world.

Starter game Android, Godot 4.4, GL Compatibility.

Scene utama: `scenes/main.tscn` — dunia v1: tanah berbukit dari heightmap + noise (dicat rumput / tanah gundul / batu di lereng), rumput MultiMesh + shader angin, danau + air stylized, 24 pohon bisa ditebang (3 tebasan → roboh → kayu → tunggul → tumbuh lagi 60 dtk), bebatuan, 1 matahari + langit + kabut, suara prosedural (angin, air, langkah per permukaan, tebasan, burung). Pemain kapsul sementara (model Kirana menyusul): WASD/panah + joystick kiri, Shift/LARI lari, Space/LOMPAT lompat, F/TEBAS tebas pohon di depan, drag kanan putar kamera. Mode terbang (tombol TERBANG pojok kanan atas / tombol V): kamera bebas terbang tanpa tabrakan buat ngecek dunia — joystick gerak, LOMPAT jadi NAIK, TEBAS jadi TURUN, LARI jadi cepat.

Tes dunia headless: `godot --headless --path . -- --world-test` (harus `WORLD_TEST PASS`).

## Jalankan di editor

Buka `project.godot` di Godot 4.4, tekan F5.

## Build APK (manual saja)

Actions > Android Build (Manual Only) > Run workflow > ketik `BUILD` > Run workflow. APK debug muncul di Artifacts `light-of-kirana-android-debug`, 7 hari.

Push ke `main` TIDAK menjalankan build.
