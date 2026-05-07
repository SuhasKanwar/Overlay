#!/usr/bin/env bash
set -euo pipefail

APP_NAME="overlay"
BIN_NAME="overlay"

MODE="user"
PREFIX="${PREFIX:-}"

usage() {
  cat <<EOF
Usage: ./uninstall.sh [--user|--system] [--prefix PATH]

Removes the installed app directory, launcher, and desktop entry created by install.sh.

Defaults:
  --user   Remove from ~/.local

Options:
  --system Remove from /opt and system locations (requires sudo)
  --prefix Override installation prefix (advanced)
EOF
}

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)
      MODE="user";
      shift
      ;;
    --system)
      MODE="system";
      shift
      ;;
    --prefix)
      PREFIX="${2:-}";
      if [[ -z "$PREFIX" ]]; then
        echo "ERROR: --prefix requires a path" >&2
        exit 1
      fi
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$PREFIX" ]]; then
  if [[ "$MODE" == "system" ]]; then
    PREFIX="/opt/${APP_NAME}"
  else
    PREFIX="$HOME/.local/share/${APP_NAME}"
  fi
fi

INSTALL_DIR="$PREFIX/app"

if [[ "$MODE" == "system" ]]; then
  if [[ $EUID -ne 0 ]]; then
    echo "System uninstall requested; re-running with sudo..."
    exec sudo -E bash "$0" --system --prefix "$PREFIX"
  fi

  BIN_DIR="/usr/local/bin"
  DESKTOP_DIR="/usr/share/applications"
else
  BIN_DIR="$HOME/.local/bin"
  DESKTOP_DIR="$HOME/.local/share/applications"
fi

LAUNCHER_PATH="$BIN_DIR/$BIN_NAME"
DESKTOP_FILE="$DESKTOP_DIR/${APP_NAME}.desktop"

rm -f "$LAUNCHER_PATH" || true
rm -f "$DESKTOP_FILE" || true
rm -rf "$PREFIX" || true

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
fi

echo "OK: Removed launcher: $LAUNCHER_PATH"
echo "OK: Removed desktop entry: $DESKTOP_FILE"
echo "OK: Removed install prefix: $PREFIX"