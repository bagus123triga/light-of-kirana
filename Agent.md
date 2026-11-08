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

## Starter & gameplay

- Starter minimal: jangan tambah aset pihak ketiga, plugin, atau sistem baru tanpa perintah Bagus.
- Scene utama: `scenes/main.tscn` (`scripts/main.gd` membangun dunia starter di kode: langit, matahari, tanah, rintangan, kamera, HUD).
- Gerak prosedural/fisika: cari dan ikuti tutorial/referensi yang sudah terbukti dulu, jangan ngarang dari nol. Tunjukkan referensinya (nama + link + arsitekturnya) dan tunggu persetujuan Bagus sebelum membangun.
- Jangan tambah file animasi tanpa perintah Bagus.
- Verifikasi dengan headless check lokal dulu, lalu minta Bagus mengetes di tabletnya — tes di tablet adalah vonisnya, bukan klaim dari check lokal.

## Android

- Godot 4.4, GL Compatibility, export arm64 saja (`com.lightofkirana.game`, v0.1.0).
- Target perangkat Bagus: tablet itel VistaTab 30GT (Helio G99, Mali-G57).
