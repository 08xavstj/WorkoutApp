#!/usr/bin/env bash
# Usage: scripts/set-signing.sh <TEAM_ID> <bundle.id>
# Example: scripts/set-signing.sh AB12CD34EF com.yourname.workoutapp
# Find your Team ID at https://developer.apple.com/account -> Membership details.
set -euo pipefail
if [ $# -ne 2 ]; then
  echo "Usage: $0 <TEAM_ID> <bundle.id>" >&2
  exit 1
fi
if ! [[ "$1" =~ ^[A-Z0-9]{10}$ ]]; then
  echo "\"$1\" doesn't look like a Team ID. It's 10 letters/numbers, e.g. AB12CD34EF." >&2
  echo "Find it at https://developer.apple.com/account -> Membership details." >&2
  exit 1
fi
if [[ "$2" == com.example.* ]] || ! [[ "$2" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]]; then
  echo "\"$2\" can't be used. Pick your own reverse-domain ID, e.g. com.yourname.workoutapp." >&2
  exit 1
fi
cd "$(dirname "$0")/.."
cat > Config/Signing.local.xcconfig <<CONF
DEVELOPMENT_TEAM = $1
PRODUCT_BUNDLE_IDENTIFIER = $2
CONF
echo "Saved signing settings to Config/Signing.local.xcconfig"
if command -v xcodegen >/dev/null; then
  xcodegen generate
  echo "Done. If Xcode is open, quit it (Cmd-Q) and reopen WorkoutApp.xcodeproj."
else
  echo "Now run: xcodegen generate   (then reopen WorkoutApp.xcodeproj)"
fi
