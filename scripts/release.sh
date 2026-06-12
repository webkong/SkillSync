#!/usr/bin/env bash
set -euo pipefail

APP_DISPLAY_NAME="SkillSync"
BUNDLE_ID="com.skillsync.app"
SCHEME="SkillSync"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MACOS_DIR="$ROOT_DIR/macos"
RUST_DIR="$ROOT_DIR/skills-core"
DIST_DIR="$ROOT_DIR/dist"
RELEASE_DIR="$DIST_DIR/release"

source "$ROOT_DIR/scripts/version_utils.sh"
load_version_config

GITHUB_RELEASE_REPO="${GITHUB_RELEASE_REPO:-webkong/SkillSync}"
RELEASE_TAG="${RELEASE_TAG:-v$VERSION}"
RELEASE_NOTES_FILE="${RELEASE_NOTES_FILE:-$ROOT_DIR/docs/releases/$RELEASE_TAG.md}"

CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}"
KEYCHAIN_ARGS=()

ZIP_PATH="$RELEASE_DIR/$APP_DISPLAY_NAME-$VERSION.zip"
PKG_PATH="$RELEASE_DIR/$APP_DISPLAY_NAME-$VERSION-Installer.pkg"
PKG_ALIAS_PATH="$RELEASE_DIR/$APP_DISPLAY_NAME-Installer.pkg"

# ─── Helpers ──────────────────────────────────────────────────────────────────

usage() {
  cat <<EOF
Usage: $0 <command>

Commands:
  build-rust      Build Rust core (aarch64-apple-darwin release)
  build-app       Build Xcode release .app
  build-zip       Build .app and create zip
  build-pkg       Build .app and create PKG installer
  build-all       build-rust + build-app + build-zip

Environment:
  VERSION=x.y.z           Override scripts/version.env
  BUILD_NUMBER=NNNNN      Override scripts/version.env
  CODE_SIGN_IDENTITY=...  Codesign identity (default: ad-hoc)
  DEVELOPMENT_TEAM=...    Team ID for Xcode signing
  GITHUB_TOKEN=...        Required for push-release when gh not installed
  RELEASE_TAG=vX.Y.Z
  RELEASE_NOTES_FILE=docs/releases/vX.Y.Z.md
  SKIP_RUST_BUILD=1       Skip cargo build before Xcode build
EOF
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_release_notes() {
  if [[ ! -f "$RELEASE_NOTES_FILE" ]]; then
    echo "Missing release notes file: $RELEASE_NOTES_FILE" >&2
    echo "Create docs/releases/$RELEASE_TAG.md before releasing." >&2
    exit 1
  fi
}

# ─── Build Rust ───────────────────────────────────────────────────────────────

build_rust() {
  require_command cargo
  echo "▶ Building Rust core (aarch64-apple-darwin)..."
  export PATH="$HOME/.cargo/bin:$PATH"
  export OPENSSL_DIR=/opt/homebrew/opt/openssl
  export PKG_CONFIG_SYSROOT_DIR=/
  export PKG_CONFIG_PATH=/opt/homebrew/opt/openssl/lib/pkgconfig
  cd "$RUST_DIR"
  cargo build --release --target aarch64-apple-darwin
  echo "✓ Rust core built"
}

# ─── Build Xcode App ──────────────────────────────────────────────────────────

build_app() {
  if [[ "${SKIP_RUST_BUILD:-0}" != "1" ]]; then
    build_rust
  fi

  require_command xcodebuild

  echo "▶ Building Xcode app (v$VERSION / $BUILD_NUMBER)..."
  mkdir -p "$RELEASE_DIR"
  rm -rf "$RELEASE_DIR/$APP_DISPLAY_NAME.app"
  local derived_data_path
  derived_data_path="$(mktemp -d "$DIST_DIR/xcode-build.XXXXXX")"

  local xcode_sign_args=()
  if [[ -n "$CODE_SIGN_IDENTITY" && "$CODE_SIGN_IDENTITY" != "-" ]]; then
    xcode_sign_args+=("CODE_SIGN_IDENTITY=$CODE_SIGN_IDENTITY")
    xcode_sign_args+=("CODE_SIGN_STYLE=Manual")
  fi
  if [[ -n "$DEVELOPMENT_TEAM" ]]; then
    xcode_sign_args+=("DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM")
  fi

  xcodebuild \
    -project SkillSync.xcodeproj \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$derived_data_path" \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    "${xcode_sign_args[@]}" \
    build

  local built_app
  built_app="$(find "$derived_data_path/Build/Products/Release" -name "*.app" -maxdepth 1 | head -1)"
  if [[ -z "$built_app" ]]; then
    echo "App not found after build" >&2; exit 1
  fi

  cp -R "$built_app" "$RELEASE_DIR/"
  rm -rf "$derived_data_path"
  echo "✓ Built: $RELEASE_DIR/$APP_DISPLAY_NAME.app"
}

# ─── ZIP ──────────────────────────────────────────────────────────────────────

build_zip() {
  build_app

  cd "$RELEASE_DIR"
  rm -f "$ZIP_PATH"
  zip -qr "$ZIP_PATH" "$APP_DISPLAY_NAME.app"
  echo "✓ ZIP: $ZIP_PATH"
}

# ─── PKG ──────────────────────────────────────────────────────────────────────

build_pkg() {
  require_command pkgbuild

  build_app

  local work_dir; work_dir="$(mktemp -d)"
  local root_dir="$work_dir/root"
  local scripts_dir="$work_dir/scripts"
  mkdir -p "$root_dir/Applications" "$scripts_dir"
  cp -R "$RELEASE_DIR/$APP_DISPLAY_NAME.app" "$root_dir/Applications/"

  cat >"$scripts_dir/preinstall" <<PREINSTALL
#!/bin/bash
APP_PROCESS="$APP_DISPLAY_NAME"
if /usr/bin/pgrep -x "\$APP_PROCESS" >/dev/null 2>&1; then
  /usr/bin/pkill -x "\$APP_PROCESS" 2>/dev/null || true
  /bin/sleep 0.5
fi
exit 0
PREINSTALL

  cat >"$scripts_dir/postinstall" <<POSTINSTALL
#!/bin/bash
set -euo pipefail
APP_PATH="/Applications/$APP_DISPLAY_NAME.app"

console_user() { /usr/bin/stat -f "%Su" /dev/console 2>/dev/null || true; }
run_as_user() {
  local user uid
  user="\$(console_user)"
  [[ -n "\$user" && "\$user" != "root" ]] || return 1
  uid="\$(/usr/bin/id -u "\$user")" || return 1
  /bin/launchctl asuser "\$uid" /usr/bin/sudo -u "\$user" "\$@"
}

if [[ -d "\$APP_PATH" ]]; then
  /usr/bin/xattr -dr com.apple.quarantine "\$APP_PATH" 2>/dev/null || true
fi

[[ -d "\$APP_PATH" ]] && run_as_user /usr/bin/open "\$APP_PATH" >/dev/null 2>&1 || true
exit 0
POSTINSTALL

  chmod 755 "$scripts_dir/preinstall" "$scripts_dir/postinstall"
  rm -f "$PKG_PATH" "$PKG_ALIAS_PATH"

  pkgbuild --analyze --root "$root_dir" "$work_dir/component.plist" >/dev/null 2>&1 || true
  if [[ -f "$work_dir/component.plist" ]]; then
    /usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" "$work_dir/component.plist" 2>/dev/null || true
  fi

  local component_args=()
  [[ -f "$work_dir/component.plist" ]] && component_args=(--component-plist "$work_dir/component.plist")

  pkgbuild \
    --root "$root_dir" \
    --scripts "$scripts_dir" \
    --identifier "$BUNDLE_ID.pkg" \
    --version "$VERSION" \
    --install-location "/" \
    "${component_args[@]}" \
    "$PKG_PATH"

  cp -f "$PKG_PATH" "$PKG_ALIAS_PATH"
  rm -rf "$work_dir"
  echo "✓ PKG: $PKG_PATH"
  echo "✓ PKG alias: $PKG_ALIAS_PATH"
}

# ─── Build All ────────────────────────────────────────────────────────────────

build_all() {
  build_rust
  build_app
  build_zip
  echo -e "${GREEN}All builds complete!${NC}"
}

# ─── Main ─────────────────────────────────────────────────────────────────────

case "${1:-}" in
  build-rust)    build_rust ;;
  build-app)     build_app ;;
  build-zip)     build_zip ;;
  build-pkg)     build_pkg ;;
  build-all)     build_rust && build_app && build_zip ;;
  *)             usage; exit 1 ;;
esac
