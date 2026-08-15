#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "A full Xcode installation must be selected before building the app." >&2
  echo "After installing Xcode, select it with: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "XcodeGen is required. Install it with: brew install xcodegen" >&2
  exit 1
fi

if [[ ! -f Config.plist ]]; then
  cp Config.plist.template Config.plist
  echo "Created local Config.plist from the public template."
fi

xcodegen generate
echo "Generated 扶摇.xcodeproj. Add local credentials to Config.plist, environment variables, or Keychain before running the app."
