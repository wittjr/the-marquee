#!/usr/bin/env bash
#
# Run the Flutter web app locally for development.
#
# The --web-port is pinned to 8080 on purpose: the OAuth callback uses
# /auth.html on port 8080, so a random port would break Trakt login.
#
# Prereqs (one-time):
#   - config/dev.json exists (cp config/dev.example.json config/dev.json; fill TRAKT_ID)

set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -f config/dev.json ]; then
  echo "error: config/dev.json not found." >&2
  echo "  cp config/dev.example.json config/dev.json   # then fill in TRAKT_ID" >&2
  exit 1
fi

echo "==> Running Flutter web (Chrome, port 8080)…"
flutter run -d chrome --web-port=8080 --dart-define-from-file=config/dev.json
