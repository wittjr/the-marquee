#!/usr/bin/env bash
#
# Build the Flutter web app (without any secrets in the bundle) and deploy it to
# Netlify along with the serverless OAuth + TMDB proxy functions.
#
# Prereqs (one-time):
#   - npm i -g netlify-cli && netlify login && netlify link
#   - config/web.json exists (cp config/web.example.json config/web.json; fill TRAKT_ID)
#   - Netlify env vars set:
#       netlify env:set TRAKT_ID <client-id>
#       netlify env:set TRAKT_SECRET <client-secret>
#       netlify env:set TMDB_READ_TOKEN <tmdb-v4-read-token>
#   - Trakt redirect URI registered: https://<your-site>.netlify.app/auth.html

set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -f config/web.json ]; then
  echo "error: config/web.json not found." >&2
  echo "  cp config/web.example.json config/web.json   # then fill in TRAKT_ID" >&2
  exit 1
fi

echo "==> Building Flutter web (release, no bundled secrets)…"
flutter build web --release --dart-define-from-file=config/web.json

# --no-build: we already built locally; this skips the netlify.toml build
# command (which is meant only for Netlify's CI, not your machine).
echo "==> Deploying to Netlify (production)…"
netlify deploy --prod --no-build --dir=build/web

echo "==> Done."
echo "    Reminder: TRAKT_ID, TRAKT_SECRET and TMDB_READ_TOKEN must be set as"
echo "    Netlify env vars for the proxy functions to work."
