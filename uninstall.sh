#!/usr/bin/env bash
# Menghapus DeskWidgets. Menanyakan dulu apakah data pengguna ikut dihapus.
set -euo pipefail

APP_NAME="DeskWidgets"
DEST="$HOME/Applications/$APP_NAME.app"
DATA_DIR="$HOME/Library/Application Support/$APP_NAME"

step() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    step "Menghentikan $APP_NAME"
    pkill -x "$APP_NAME" || true
    sleep 1
fi

if [ -x "$DEST/Contents/MacOS/$APP_NAME" ]; then
    step "Mencabut item login"
    "$DEST/Contents/MacOS/$APP_NAME" --unregister-login || true
fi

if [ -d "$DEST" ]; then
    step "Menghapus $DEST"
    rm -rf "$DEST"
else
    step "$DEST tidak ditemukan, dilewati"
fi

if [ -d "$DATA_DIR" ]; then
    answer="n"
    if [ -r /dev/tty ]; then
        printf 'Hapus juga data pengguna di "%s"? [y/N] ' "$DATA_DIR" > /dev/tty
        read -r answer < /dev/tty || answer="n"
    fi
    case "$answer" in
        [yY]*) rm -rf "$DATA_DIR"; step "Data dihapus" ;;
        *) step "Data dipertahankan" ;;
    esac
fi

step "Selesai."
