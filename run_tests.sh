#!/usr/bin/env bash
set -euo pipefail

GODOT="${GODOT:-godot}"

# Verify godot is available
if ! command -v "$GODOT" &>/dev/null; then
  echo "Error: '$GODOT' not found. Set the GODOT env var to your Godot binary." >&2
  exit 1
fi

cd "$(dirname "$0")"

"$GODOT" --headless -s addons/gut/gut_cmdln.gd \
  -gdir=res://test/unit/ \
  -gprefix=test_ \
  -gexit
