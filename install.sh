#!/usr/bin/env bash
# Pemasang DeskWidgets. Tanpa sudo. Aman dijalankan ulang (memperbarui).
#
#   curl -fsSL https://raw.githubusercontent.com/KeiRey/mac-widget/main/install.sh | bash
#   ... | bash -s -- --version 1.0.0 --no-launch
#   ... | bash -s -- --uninstall
#
# Untuk fork, set env DESKWIDGETS_REPO=pemilik/repo (di sisi `bash`, setelah pipe).
set -euo pipefail

REPO="${DESKWIDGETS_REPO:-KeiRey/mac-widget}"
APP_NAME="DeskWidgets"
DEST_DIR="$HOME/Applications"
DEST="$DEST_DIR/$APP_NAME.app"
DATA_DIR="$HOME/Library/Application Support/$APP_NAME"

VERSION=""
LAUNCH=1
UNINSTALL=0

step() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31mGagal:\033[0m %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --version)   [ $# -ge 2 ] || fail "--version membutuhkan nilai, mis. --version 1.0.0"; VERSION="$2"; shift 2 ;;
        --no-launch) LAUNCH=0; shift ;;
        --uninstall) UNINSTALL=1; shift ;;
        -h|--help)   sed -n '2,9p' "$0" 2>/dev/null | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)           fail "Opsi tidak dikenal: $1" ;;
    esac
done

stop_app() {
    if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
        step "Menghentikan $APP_NAME yang sedang berjalan"
        pkill -x "$APP_NAME" || true
        for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x "$APP_NAME" >/dev/null 2>&1 || break; sleep 0.3; done
    fi
}

if [ "$UNINSTALL" = 1 ]; then
    stop_app
    if [ -x "$DEST/Contents/MacOS/$APP_NAME" ]; then
        step "Mencabut item login"
        "$DEST/Contents/MacOS/$APP_NAME" --unregister-login || true
    fi
    step "Menghapus $DEST"
    rm -rf "$DEST"
    if [ -d "$DATA_DIR" ]; then
        answer="n"
        if [ -r /dev/tty ]; then
            printf 'Hapus juga data pengguna di "%s"? [y/N] ' "$DATA_DIR" > /dev/tty
            read -r answer < /dev/tty || answer="n"
        fi
        case "$answer" in [yY]*) rm -rf "$DATA_DIR"; step "Data dihapus" ;; *) step "Data dipertahankan" ;; esac
    fi
    step "Selesai."
    exit 0
fi

# 1. Cek sistem
[ "$(uname -s)" = "Darwin" ] || fail "DeskWidgets hanya untuk macOS."
MACOS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
[ "$MACOS_MAJOR" -ge 13 ] || fail "Dibutuhkan macOS 13 (Ventura) atau lebih baru. Versi Anda: $(sw_vers -productVersion)."
case "$(uname -m)" in arm64|x86_64) ;; *) fail "Arsitektur tidak didukung: $(uname -m)" ;; esac

# 2. Tentukan versi
if [ -z "$VERSION" ]; then
    step "Mencari rilis terbaru"
    TAG="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
        | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n1)"
    [ -n "$TAG" ] || fail "Tidak bisa membaca rilis terbaru dari github.com/$REPO."
else
    TAG="v${VERSION#v}"
fi
ASSET="$APP_NAME-$TAG-macos-universal.zip"
BASE="https://github.com/$REPO/releases/download/$TAG"

# 3. Unduh
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
step "Mengunduh $ASSET"
curl -fsSL -o "$TMP/$ASSET" "$BASE/$ASSET" || fail "Unduhan gagal. Pastikan versi $TAG ada di github.com/$REPO/releases."
curl -fsSL -o "$TMP/$ASSET.sha256" "$BASE/$ASSET.sha256" || fail "File checksum tidak ditemukan."

# 4. Verifikasi checksum
step "Memverifikasi checksum SHA-256"
EXPECTED="$(awk '{print $1}' "$TMP/$ASSET.sha256")"
ACTUAL="$(shasum -a 256 "$TMP/$ASSET" | awk '{print $1}')"
[ -n "$EXPECTED" ] && [ "$EXPECTED" = "$ACTUAL" ] || fail "Checksum tidak cocok (diharapkan $EXPECTED, didapat $ACTUAL). Instalasi dibatalkan."

# 5-6. Hentikan lalu pasang
stop_app
step "Memasang ke $DEST"
mkdir -p "$DEST_DIR"
ditto -x -k "$TMP/$ASSET" "$TMP/extract"
[ -d "$TMP/extract/$APP_NAME.app" ] || fail "Arsip tidak berisi $APP_NAME.app."
rm -rf "$DEST"
mv "$TMP/extract/$APP_NAME.app" "$DEST"

# 7. Tanda tangan ad-hoc (wajib agar jalan di Apple Silicon)
if ! codesign --verify --deep --strict "$DEST" >/dev/null 2>&1; then
    step "Menandatangani ulang (ad-hoc)"
    codesign --force --deep -s - "$DEST"
fi

# 8. Karantina
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

step "Terpasang: $TAG"

# 9. Jalankan
if [ "$LAUNCH" = 1 ]; then
    step "Membuka $APP_NAME"
    open "$DEST"
fi
