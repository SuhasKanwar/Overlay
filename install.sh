#!/usr/bin/env bash
set -euo pipefail

APP_NAME="overlay"
DISPLAY_NAME="Overlay"
BIN_NAME="overlay"

# GitHub repo used when this installer is run via curl/wget.
# Override with env vars if you fork.
REPO_SLUG="${REPO_SLUG:-SuhasKanwar/Overlay}"
REPO_REF="${REPO_REF:-main}"

MODE="user"
PREFIX="${PREFIX:-}"
START_AFTER_INSTALL="${START_AFTER_INSTALL:-1}"

usage() {
  cat <<EOF
Usage:
  ./install.sh [--user|--system] [--prefix PATH] [--no-start]

Remote install (recommended):
  curl -fsSL https://raw.githubusercontent.com/$REPO_SLUG/$REPO_REF/install.sh | bash

Installs the Electron app by copying this project to an install directory,
installing npm dependencies there, and registering a launcher.

Defaults:
  --user   Install under ~/.local (no sudo)

Options:
  --system Install under /opt and register launcher under /usr/local (requires sudo)
  --prefix Override installation prefix (advanced)
  --no-start Do not start the app/service after install

Env overrides:
  REPO_SLUG, REPO_REF, PREFIX, START_AFTER_INSTALL
EOF
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: Missing required command: $1" >&2
    exit 1
  }
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
    --no-start)
      START_AFTER_INSTALL="0"
      shift
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
need_cmd mkdir
need_cmd rm

copy_project() {
  local src_dir="$1"
  local dst_dir="$2"

  rm -rf "$dst_dir"
  mkdir -p "$dst_dir"

  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete \
      --exclude ".git" \
      --exclude "node_modules" \
      --exclude "dist" \
      --exclude "out" \
      --exclude "release" \
      --exclude "*.log" \
      "$src_dir/" "$dst_dir/"
    return
  fi

  # Fallback for minimal environments without rsync.
  need_cmd tar
  (
    cd "$src_dir"
    tar -cf - \
      --exclude=".git" \
      --exclude="node_modules" \
      --exclude="dist" \
      --exclude="out" \
      --exclude="release" \
      --exclude="*.log" \
      .
  ) | (
    cd "$dst_dir"
    tar -xf -
  )
}

BOOTSTRAP_DIR=""
REPO_DIR="$SCRIPT_DIR"

download_repo() {
  if have_cmd curl; then
    curl -fsSL "https://codeload.github.com/$REPO_SLUG/tar.gz/refs/heads/$REPO_REF" -o "$1"
    return
  fi
  if have_cmd wget; then
    wget -qO "$1" "https://codeload.github.com/$REPO_SLUG/tar.gz/refs/heads/$REPO_REF"
    return
  fi
  echo "ERROR: Need curl or wget to download $REPO_SLUG" >&2
  exit 1
}

ensure_repo_dir() {
  if [[ -f "$REPO_DIR/package.json" ]]; then
    return
  fi

  echo "Installer is not running from a repo checkout; bootstrapping from GitHub ($REPO_SLUG@$REPO_REF)..."
  need_cmd tar
  need_cmd mktemp

  BOOTSTRAP_DIR="$(mktemp -d)"
  local archive="$BOOTSTRAP_DIR/overlay.tar.gz"
  download_repo "$archive"

  tar -xzf "$archive" -C "$BOOTSTRAP_DIR"

  local extracted
  extracted="$(find "$BOOTSTRAP_DIR" -maxdepth 1 -type d -name "Overlay-*" -print -quit)"
  if [[ -z "${extracted:-}" || ! -f "$extracted/package.json" ]]; then
    echo "ERROR: Failed to unpack repository archive" >&2
    exit 1
  fi

  REPO_DIR="$extracted"
}

cleanup() {
  if [[ -n "${BOOTSTRAP_DIR:-}" && -d "${BOOTSTRAP_DIR:-}" ]]; then
    rm -rf "$BOOTSTRAP_DIR" || true
  fi
}
trap cleanup EXIT

ensure_repo_dir

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

copy_project "$REPO_DIR" "$INSTALL_DIR"

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

SERVICE_NAME="${APP_NAME}.service"
SERVICE_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$SERVICE_DIR/$SERVICE_NAME"

write_user_service() {
  mkdir -p "$SERVICE_DIR"
  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=$DISPLAY_NAME
After=graphical-session.target

[Service]
Type=simple
ExecStart=$LAUNCHER_PATH
Restart=on-failure
RestartSec=2

[Install]
WantedBy=default.target
EOF
}

start_user_service() {
  if ! command -v systemctl >/dev/null 2>&1; then
    echo "Note: systemctl not found; skipping auto-start service setup."
    return 0
  fi

  # Avoid failing hard on distros without user systemd.
  if ! systemctl --user show-environment >/dev/null 2>&1; then
    echo "Note: systemd user session not available; skipping auto-start service setup."
    return 0
  fi

  write_user_service
  systemctl --user daemon-reload
  systemctl --user enable --now "$SERVICE_NAME" >/dev/null 2>&1 || {
    echo "Note: Could not enable/start user service; you can still run: $BIN_NAME" >&2
    return 0
  }
  echo "OK: Enabled and started user service: $SERVICE_NAME"
}

echo "OK: Installed launcher: $LAUNCHER_PATH"
echo "OK: Installed desktop entry: $DESKTOP_FILE"

if [[ "$MODE" == "user" ]]; then
  echo "Note: ensure ~/.local/bin is on your PATH (restart your shell or log out/in)."
fi

if [[ "$MODE" == "user" && "$START_AFTER_INSTALL" == "1" ]]; then
  start_user_service
  echo "OK: App is now running (or can be started with: $BIN_NAME)"
else
  echo "Run: $BIN_NAME"
fi