#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_FILE="$ROOT_DIR/SkillSync.xcodeproj/project.pbxproj"

source "$ROOT_DIR/scripts/version_utils.sh"
load_version_config

if [[ ! -f "$PROJECT_FILE" ]]; then
  echo "Missing project file: $PROJECT_FILE" >&2
  exit 1
fi

export VERSION BUILD_NUMBER PROJECT_FILE

python3 <<'PY'
import os
import pathlib
import re
import sys

project_path = pathlib.Path(os.environ["PROJECT_FILE"])
version = os.environ["VERSION"]
build_number = os.environ["BUILD_NUMBER"]
text = project_path.read_text()

text, version_count = re.subn(r"MARKETING_VERSION = [^;]+;", f"MARKETING_VERSION = {version};", text)
text, build_count = re.subn(r"CURRENT_PROJECT_VERSION = [^;]+;", f"CURRENT_PROJECT_VERSION = {build_number};", text)

if version_count == 0 or build_count == 0:
    sys.stderr.write("Failed to update MARKETING_VERSION or CURRENT_PROJECT_VERSION in project.pbxproj\n")
    sys.exit(1)

project_path.write_text(text)
PY

echo "Synced version metadata: $VERSION ($BUILD_NUMBER)"
