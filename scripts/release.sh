#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RUST_DIR="$PROJECT_DIR/skills-core"
MACOS_DIR="$PROJECT_DIR/macos"
DERIVED_DATA="$PROJECT_DIR/DerivedData"

# Source version
source "$SCRIPT_DIR/version.env"
MARKETING_VERSION="$VERSION"
CURRENT_PROJECT_VERSION="$BUILD_NUMBER"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

usage() {
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  build-rust    Build Rust static library"
    echo "  build-app     Build macOS app via xcodebuild"
    echo "  build-zip     Package app into zip"
    echo "  build-all     Run build-rust + build-app + build-zip"
    echo ""
}

build_rust() {
    echo -e "${GREEN}Building Rust core...${NC}"
    cd "$RUST_DIR"
    OPENSSL_DIR=/opt/homebrew/opt/openssl@3 \
    PKG_CONFIG_SYSROOT_DIR=/ \
    PKG_CONFIG_PATH=/opt/homebrew/opt/openssl@3/lib/pkgconfig \
    cargo build --release --target aarch64-apple-darwin
    echo -e "${GREEN}Rust build complete${NC}"
}

build_app() {
    echo -e "${GREEN}Building macOS app...${NC}"
    cd "$PROJECT_DIR"
    xcodebuild \
        -project SkillsManager.xcodeproj \
        -scheme SkillsManager \
        -configuration Release \
        -derivedDataPath "$DERIVED_DATA" \
        MARKETING_VERSION="$MARKETING_VERSION" \
        CURRENT_PROJECT_VERSION="$CURRENT_PROJECT_VERSION" \
        build 2>&1
    echo -e "${GREEN}App build complete${NC}"
}

build_zip() {
    echo -e "${GREEN}Creating zip archive...${NC}"
    cd "$PROJECT_DIR"
    APP_PATH=$(find "$DERIVED_DATA/Build/Products/Release" -name "*.app" -maxdepth 1 | head -1)
    if [ -z "$APP_PATH" ]; then
        echo -e "${RED}App not found in DerivedData${NC}"
        exit 1
    fi
    
    ZIP_NAME="AgentSkillsManager-${VERSION}.zip"
    ditto -c -k --keepParent "$APP_PATH" "$ZIP_NAME"
    echo -e "${GREEN}Created $ZIP_NAME${NC}"
}

build_all() {
    build_rust
    build_app
    build_zip
    echo -e "${GREEN}All builds complete!${NC}"
}

# Main
if [ $# -eq 0 ]; then
    usage
    exit 1
fi

case "$1" in
    build-rust)   build_rust ;;
    build-app)    build_app ;;
    build-zip)    build_zip ;;
    build-all)    build_all ;;
    *)            usage; exit 1 ;;
esac
