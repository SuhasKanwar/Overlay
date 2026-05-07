#!/usr/bin/env bash
set -euo pipefail

APP_NAME="overlay"
DISPLAY_NAME="Overlay"
BIN_NAME="overlay"

MODE="user"
PREFIX="${PREFIX:-}"

usage() {
  cat <<EOF
Usage: ./install.sh [--user|--system] [--prefix PATH]

Installs the Electron app by copying this project to an install directory,
installing npm dependencies there, and registering a launcher.

Defaults:
  --user   Install under ~/.local (no sudo)

Options:
  --system Install under /opt and register launcher under /usr/local (requires sudo)
  --prefix Override installation prefix (advanced)
EOF
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: Missing required command: $1" >&2
    exit 1
  }
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

need_cmd node
need_cmd npm
need_cmd rsync

if [[ ! -f "$REPO_DIR/package.json" ]]; then
  echo "ERROR: package.json not found in $REPO_DIR" >&2
  exit 1
fi

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
    echo "System install requested; re-running with sudo..."
    exec sudo -E bash "$0" --system --prefix "$PREFIX"
  fi

  BIN_DIR="/usr/local/bin"
  DESKTOP_DIR="/usr/share/applications"
else
  BIN_DIR="$HOME/.local/bin"
  DESKTOP_DIR="$HOME/.local/share/applications"
fi

mkdir -p "$INSTALL_DIR" "$BIN_DIR" "$DESKTOP_DIR"

echo "Installing to: $INSTALL_DIR"

rsync -a --delete \
  --exclude ".git" \
  --exclude "node_modules" \
  --exclude "dist" \
  --exclude "out" \
  --exclude "release" \
  --exclude "*.log" \
  "$REPO_DIR/" "$INSTALL_DIR/"

cd "$INSTALL_DIR"
if [[ -f package-lock.json ]]; then
  npm ci
else
  npm install
fi

LAUNCHER_PATH="$BIN_DIR/$BIN_NAME"
cat > "$LAUNCHER_PATH" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Resolve install dir relative to this script if possible.
# Fallback to the default user path.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The installer writes an absolute APP_DIR into this file.
APP_DIR="__APP_DIR__"

if [[ ! -d "$APP_DIR" ]]; then
  echo "ERROR: App directory not found: $APP_DIR" >&2
  exit 1
fi

cd "$APP_DIR"
exec "./node_modules/.bin/electron" . --disable-gpu
EOF

if command -v sed >/dev/null 2>&1; then
  sed -i "s|__APP_DIR__|$INSTALL_DIR|g" "$LAUNCHER_PATH"
else
  # Shouldn't happen on most Linux distros
  perl -pi -e "s|__APP_DIR__|$INSTALL_DIR|g" "$LAUNCHER_PATH"
fi

chmod 0755 "$LAUNCHER_PATH"

DESKTOP_FILE="$DESKTOP_DIR/${APP_NAME}.desktop"
cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=$DISPLAY_NAME
Comment=Overlay desktop app
Exec=$LAUNCHER_PATH
Terminal=false
Categories=Utility;
StartupNotify=true
EOF

chmod 0644 "$DESKTOP_FILE"

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
fi

echo "OK: Installed launcher: $LAUNCHER_PATH"
echo "OK: Installed desktop entry: $DESKTOP_FILE"

if [[ "$MODE" == "user" ]]; then
  echo "Note: ensure ~/.local/bin is on your PATH (restart your shell or log out/in)."
fi

echo "Run: $BIN_NAME"