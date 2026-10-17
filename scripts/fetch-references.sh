#!/usr/bin/env bash
# Clones the open-source projects this app draws ideas from into ./references
# (git-ignored). They are for reading only - see docs/REFERENCES.md for licenses.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p references
repos=(
  xtool-org/xtool
  StanfordSpezi/SpeziHealthKit
  rudrankriyam/Foundation-Models-Framework-Example
  jamesrochabrun/SwiftAnthropic
  yuhonas/free-exercise-db
  karimknaebel/Iron
  RyanCwynar/gym
  BlakeB88/Training_app
  madebysan/aura-health
  wger-project/wger
  twostraws/swift-agent-skills
)
for r in "${repos[@]}"; do
  dir="references/$(basename "$r")"
  if [ -d "$dir" ]; then
    echo "Updating $r"; git -C "$dir" pull --ff-only --quiet
  else
    echo "Cloning $r"; git clone --depth 1 --quiet "https://github.com/$r" "$dir"
  fi
done
echo "Done. References are in ./references"
