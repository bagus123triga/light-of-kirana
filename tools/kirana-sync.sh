#!/data/data/com.termux/files/usr/bin/bash
# kirana-sync.sh — clone/pull Light of Kirana lalu pindah ke Documents (Termux)
# Kenapa begini: git di Termux error kalau jalan di shared storage
# (/storage/emulated), jadi clone/pull di home dulu, baru disync ke
# Documents supaya bisa dibuka editor Godot.
# Pakai: bash kirana-sync.sh   (ulangi tiap mau update ke versi terbaru)
# Catatan: script ini menimpa isi Documents/light-of-kirana dengan versi
# GitHub. Kalau kamu edit sesuatu di Godot, kabarin Emilia dulu biar
# editannya dimasukin ke repo — kalau tidak, editan itu ketimpa.

REPO_URL="https://github.com/bagus123triga/light-of-kirana.git"
SRC="$HOME/light-of-kirana"
DST="$HOME/storage/shared/Documents/light-of-kirana"

# 1. Pastikan storage Termux sudah disetup.
if [ ! -d "$HOME/storage/shared" ]; then
  echo "Folder ~/storage/shared belum ada. Jalankan dulu:"
  echo "  termux-setup-storage"
  echo "Terus izinkan akses penyimpanan, lalu jalankan script ini lagi."
  exit 1
fi

# 2. Clone kalau belum ada, pull kalau sudah ada.
if [ -d "$SRC/.git" ]; then
  echo "Repo sudah ada di home, pull update..."
  (cd "$SRC" && git pull) || { echo "git pull gagal, cek koneksi."; exit 1; }
else
  echo "Clone repo ke home..."
  git clone "$REPO_URL" "$SRC" || { echo "git clone gagal, cek koneksi."; exit 1; }
fi

# 3. Backup copy lama di Documents (jaga-jaga kalau ada editan di Godot),
#    lalu sync yang terbaru. Cache .godot tidak ikut di-backup.
if [ -d "$DST" ] && [ -n "$(ls -A "$DST" 2>/dev/null)" ]; then
  BACKUP="${DST}-backup-$(date +%Y%m%d-%H%M%S)"
  cp -r "$DST" "$BACKUP" && rm -rf "$BACKUP/.godot" "$BACKUP/.git"
  echo "Backup copy lama: $BACKUP"
fi

# 4. Sync ke Documents. rsync (kalau ada) hanya copy file yang berubah
#    dan mempertahankan cache import Godot (.godot); kalau tidak ada,
#    hapus + copy ulang.
echo "Sync ke Documents..."
mkdir -p "$DST"
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete --exclude '.git' --exclude '.godot' "$SRC/" "$DST/"
else
  rm -rf "$DST" && mkdir -p "$DST" && cp -r "$SRC/." "$DST/" && rm -rf "$DST/.git"
fi

echo "Selesai! Project terbaru ada di: $DST"
echo "Buka dari editor Godot: Documents/light-of-kirana"
