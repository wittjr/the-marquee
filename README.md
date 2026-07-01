# The Marquee

A Flutter app to track movies and TV shows you want to watch, backed by
[Trakt.tv](https://trakt.tv) for authentication and list/progress tracking, and
[TMDB](https://www.themoviedb.org) for posters, overviews and release dates.

## Status

- ✅ Trakt OAuth sign-in (in-app authorization-code flow)
- ✅ Home page: your Trakt watchlist (movies **and** shows), enriched with TMDB
  metadata and sorted by release date

## Architecture

```
lib/
  config/app_config.dart      # endpoints + compile-time secrets
  models/                     # MediaItem (movie|show), TraktIds, TraktTokens
  services/
    trakt_auth_service.dart   # OAuth code/refresh/revoke exchanges
    token_store.dart          # tokens in the keychain (flutter_secure_storage)
    trakt_api.dart            # authenticated Trakt REST calls
    tmdb_api.dart             # read-only TMDB enrichment
  state/
    auth_controller.dart      # session state, hands out valid access tokens
    library_controller.dart   # loads + enriches + sorts the watchlist
  ui/                         # app shell, login page, home page, media card
```

State management is `provider` + `ChangeNotifier`. Trakt is the source of truth
for lists; TMDB only enriches (matched via each item's `ids.tmdb`).

## Setup

### 1. Secrets

Secrets are injected at build time and never committed. Copy the example and
fill in your credentials:

```bash
cp config/dev.example.json config/dev.json   # already gitignored
```

`config/dev.json` needs:

- `TRAKT_ID` / `TRAKT_SECRET` — from your Trakt app at
  <https://trakt.tv/oauth/applications>
- `TMDB_READ_TOKEN` — the TMDB API **Read Access Token (v4 auth)**

### 2. Register the OAuth redirect URI ⚠️

In your Trakt application settings, add this to the **Redirect URI** list:

```
themarquee://oauth/callback
```

This must match `AppConfig.redirectScheme` / `AppConfig.redirectUri`. Without it,
Trakt rejects the sign-in. (The scheme is already registered in the iOS,
Android, and macOS native projects.)

## Running

### Desktop / mobile (no Apple Developer account needed)

```bash
flutter run --dart-define-from-file=config/dev.json
```

macOS desktop and Android run with free local signing.

Tip: add a VS Code launch config with
`"toolArgs": ["--dart-define-from-file=config/dev.json"]` so you don't pass it
each time.

### Web (local dev)

The app runs in the browser — both Trakt and TMDB allow cross-origin (CORS)
requests, so no proxy is needed for data calls. The OAuth redirect uses an
http(s) callback page (`web/auth.html`) instead of the native custom scheme.

Run on a **fixed port** so the redirect URI stays stable:

```bash
flutter run -d chrome --web-port=8080 --dart-define-from-file=config/dev.json
```

Register this redirect URI in your Trakt app settings
(<https://trakt.tv/oauth/applications>), in addition to the native one:

```
http://localhost:8080/auth.html
```

Locally we use `config/dev.json`, which **includes** the client secret, so the
token exchange goes straight to Trakt (fine on your machine).

## Deploying to Netlify (with serverless proxies)

For a hosted build, **no secrets ship in the JS**. The production config
(`config/web.json`) contains only the public Trakt client id, and the
token-bearing calls route through two Netlify functions that hold the secrets in
env vars:

- `netlify/functions/trakt-auth.mjs` — Trakt OAuth (token exchange / refresh /
  revoke), at `/.netlify/functions/trakt-auth`.
- `netlify/functions/tmdb.mjs` — TMDB API pass-through, at `/api/tmdb/*`.

The app picks proxy-vs-direct automatically: when a secret/token is absent from
the build, it uses the same-origin proxy; otherwise it calls the API directly
(native + local web). TMDB **images** (`image.tmdb.org`) are always direct — they
need no token.

### One-time setup

```bash
npm i -g netlify-cli && netlify login && netlify link

cp config/web.example.json config/web.json   # fill in TRAKT_ID (public)

netlify env:set TRAKT_ID <your-client-id>
netlify env:set TRAKT_SECRET <your-client-secret>
netlify env:set TMDB_READ_TOKEN <your-tmdb-v4-read-token>
```

Then register the deployed redirect URI in your Trakt app settings:

```
https://<your-site>.netlify.app/auth.html
```

### Deploy

```bash
./scripts/deploy.sh
```

(which runs `flutter build web --dart-define-from-file=config/web.json` then
`netlify deploy --prod`). `netlify.toml` also supports git-based deploys —
Netlify installs Flutter and builds, injecting only the public `TRAKT_ID`.

## Tests

```bash
flutter test
```
