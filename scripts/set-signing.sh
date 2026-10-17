#!/usr/bin/env bash
# Usage: scripts/set-signing.sh <TEAM_ID> <bundle.id>
# Example: scripts/set-signing.sh AB12CD34EF com.yourname.workoutapp
# Find your Team ID at https://developer.apple.com/account -> Membership details.
set -euo pipefail
if [ $# -ne 2 ]; then
  echo "Usage: $0 <TEAM_ID> <bundle.id>" >&2
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
else
  echo "Now run: xcodegen generate"
fi
