#!/usr/bin/env python3
"""Sync a TV Time export (activity_history.csv) into Trakt.

What it does:
  * Movies   -> marked watched at the TV Time `watched_at` time.
  * Episodes -> marked watched at the TV Time `watched_at` time.
  * Shows    -> the ones flagged is_watchlisted=true are added to the watchlist.

"Overwrite, don't add a new viewing": for every movie/episode we first DELETE
any existing Trakt history for that item, then add exactly one play at the
TV Time time. This makes the sync idempotent (safe to re-run) at the cost of
discarding rewatch history Trakt may already hold.

Auth: OAuth device flow using TRAKT_ID/TRAKT_SECRET from config/dev.json.
The resulting token is cached in scripts/.trakt_token.json.

Usage:
  python3 scripts/sync_tvtime_to_trakt.py                 # full sync
  python3 scripts/sync_tvtime_to_trakt.py --dry-run       # parse + report, no writes
  python3 scripts/sync_tvtime_to_trakt.py --only movies   # movies | episodes | shows
  python3 scripts/sync_tvtime_to_trakt.py --limit 50      # only first N watched items
"""

import argparse
import csv
import json
import os
import sys
import time
import urllib.error
import urllib.request

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG_PATH = os.path.join(REPO_ROOT, "config", "dev.json")
CSV_PATH = os.path.join(REPO_ROOT, "tv-time-export", "activity_history.csv")
TOKEN_PATH = os.path.join(REPO_ROOT, "scripts", ".trakt_token.json")

API_BASE = "https://api.trakt.tv"
BATCH_SIZE = 100          # items per sync request (smaller = fewer upstream timeouts)
REQUEST_PAUSE = 1.0       # seconds between write requests (Trakt rate limit)
MAX_RETRIES = 4           # retries for transient 5xx errors
NOT_FOUND_PATH = os.path.join(REPO_ROOT, "scripts", "trakt_not_found.json")
PRUNE_REPORT_PATH = os.path.join(REPO_ROOT, "scripts", "trakt_pruned.json")


# --------------------------------------------------------------------------- #
# HTTP helpers
# --------------------------------------------------------------------------- #
def _request(method, path, body=None, headers=None, retries=0):
    """Make a request. Retries 429 (rate limit) always; retries 5xx up to
    `retries` times with backoff (use only for idempotent calls like remove)."""
    url = API_BASE + path
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    req.add_header("User-Agent", "the-marquee-tvtime-sync/1.0")
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    attempt = 0
    while True:
        try:
            with urllib.request.urlopen(req) as resp:
                raw = resp.read().decode("utf-8")
                return resp.status, (json.loads(raw) if raw else None)
        except urllib.error.HTTPError as e:
            if e.code == 429:
                retry = int(e.headers.get("Retry-After", "2"))
                print(f"  rate limited, sleeping {retry}s...")
                time.sleep(retry)
                continue
            if e.code >= 500 and attempt < retries:
                attempt += 1
                wait = min(30, 5 * attempt)
                print(f"  {e.code} on {path}, retry {attempt}/{retries} in {wait}s...")
                time.sleep(wait)
                continue
            raw = e.read().decode("utf-8", "replace")
            return e.code, (json.loads(raw) if raw.strip().startswith("{") else raw)
        except urllib.error.URLError as e:
            if attempt < retries:
                attempt += 1
                wait = min(30, 5 * attempt)
                print(f"  network error ({e.reason}) on {path}, "
                      f"retry {attempt}/{retries} in {wait}s...")
                time.sleep(wait)
                continue
            return 0, str(e.reason)


def api_headers(client_id, token=None):
    h = {"trakt-api-version": "2", "trakt-api-key": client_id}
    if token:
        h["Authorization"] = "Bearer " + token
    return h


# --------------------------------------------------------------------------- #
# Auth (OAuth device flow + token cache)
# --------------------------------------------------------------------------- #
def load_config():
    with open(CONFIG_PATH) as f:
        cfg = json.load(f)
    if not cfg.get("TRAKT_ID") or not cfg.get("TRAKT_SECRET"):
        sys.exit("config/dev.json is missing TRAKT_ID / TRAKT_SECRET")
    return cfg["TRAKT_ID"], cfg["TRAKT_SECRET"]


def cached_token(client_id, client_secret):
    if not os.path.exists(TOKEN_PATH):
        return None
    with open(TOKEN_PATH) as f:
        tok = json.load(f)
    # refresh if within a day of expiry
    if tok.get("created_at", 0) + tok.get("expires_in", 0) - 86400 > time.time():
        return tok["access_token"]
    print("Token expired/expiring, refreshing...")
    status, data = _request("POST", "/oauth/token", {
        "refresh_token": tok["refresh_token"],
        "client_id": client_id,
        "client_secret": client_secret,
        "redirect_uri": "urn:ietf:wg:oauth:2.0:oob",
        "grant_type": "refresh_token",
    })
    if status == 200:
        _save_token(data)
        return data["access_token"]
    print("  refresh failed, falling back to device login")
    return None


def _save_token(data):
    data.setdefault("created_at", int(time.time()))
    with open(TOKEN_PATH, "w") as f:
        json.dump(data, f, indent=2)
    os.chmod(TOKEN_PATH, 0o600)


def device_login(client_id, client_secret):
    status, dev = _request("POST", "/oauth/device/code", {"client_id": client_id})
    if status != 200:
        sys.exit(f"Could not start device login: {status} {dev}")
    print("\n" + "=" * 60)
    print(f"  Go to:  {dev['verification_url']}")
    print(f"  Enter code:  {dev['user_code']}")
    print("=" * 60 + "\n")
    interval = dev.get("interval", 5)
    deadline = time.time() + dev.get("expires_in", 600)
    while time.time() < deadline:
        time.sleep(interval)
        status, data = _request("POST", "/oauth/device/token", {
            "code": dev["device_code"],
            "client_id": client_id,
            "client_secret": client_secret,
        })
        if status == 200:
            _save_token(data)
            print("Authorized.\n")
            return data["access_token"]
        if status == 400:        # pending
            print("  waiting for authorization...")
            continue
        if status == 429:        # slow down
            interval += 1
            continue
        sys.exit(f"Device login failed: {status} {data}")
    sys.exit("Device login timed out.")


def get_token(client_id, client_secret):
    return cached_token(client_id, client_secret) or device_login(client_id, client_secret)


# --------------------------------------------------------------------------- #
# CSV parsing
# --------------------------------------------------------------------------- #
def _to_int(v):
    try:
        return int(v)
    except (TypeError, ValueError):
        return None


def parse_csv(limit=None):
    with open(CSV_PATH, newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))

    # First pass: map show title -> show TVDB id so we can resolve each
    # episode's parent show (episode rows only carry the show *title*).
    show_tvdb_by_title = {}
    for row in rows:
        if row["type"] == "show" and row["tvdb_id"] and row["tvdb_id"] != "-1":
            show_tvdb_by_title.setdefault(row["title"], row["tvdb_id"])

    movies, episodes, watchlist_shows = [], [], []
    seen_show_tvdb = set()
    no_show_match = 0
    for row in rows:
        rtype = row["type"]
        if rtype == "movie":
            if row.get("is_watched") == "true" and row.get("watched_at"):
                imdb = row["imdb_id"]
                if imdb and imdb != "-1":
                    movies.append({"ids": {"imdb": imdb},
                                   "watched_at": row["watched_at"],
                                   "_title": row["title"]})
        elif rtype == "episode":
            if row.get("is_watched") == "true" and row.get("watched_at"):
                tvdb = row["tvdb_id"]
                if tvdb and tvdb != "-1":
                    show_tvdb = show_tvdb_by_title.get(row["title"])
                    if show_tvdb is None:
                        no_show_match += 1
                    episodes.append({
                        "ids": {"tvdb": int(tvdb)},
                        "watched_at": row["watched_at"],
                        "_title": f"{row['title']} S{row['season']}E{row['episode']}",
                        "_show_tvdb": show_tvdb,            # for fallback matching
                        "_season": _to_int(row["season"]),
                        "_number": _to_int(row["episode"]),
                    })
        elif rtype == "show":
            if row.get("is_watchlisted") == "true":
                tvdb = row["tvdb_id"]
                if tvdb and tvdb != "-1" and tvdb not in seen_show_tvdb:
                    seen_show_tvdb.add(tvdb)
                    watchlist_shows.append({"ids": {"tvdb": int(tvdb)},
                                            "_title": row["title"]})
    if no_show_match:
        print(f"Note: {no_show_match} episode rows have no matching show row "
              f"(season/episode fallback unavailable for those)")
    if limit:
        movies = movies[:limit]
        episodes = episodes[:limit]
    return movies, episodes, watchlist_shows


def chunks(seq, n):
    for i in range(0, len(seq), n):
        yield seq[i:i + n]


def _clean(item):
    """Strip our private _title keys before sending to the API."""
    return {k: v for k, v in item.items() if not k.startswith("_")}


def _norm(t):
    """Normalize a Trakt/ISO timestamp to minute precision for comparison.
    Trakt stores watched_at truncated to the minute (seconds always :00), so
    comparing finer than that would flag every CSV time with non-zero seconds
    as a mismatch."""
    return t[:16] if t else t   # 'YYYY-MM-DDTHH:MM' (drops seconds, millis, 'Z')


# --------------------------------------------------------------------------- #
# Sync operations
# --------------------------------------------------------------------------- #
def fetch_history_map(headers, kind, id_key):
    """Return {id -> set(normalized watched_at)} for the user's existing
    Trakt history. `kind` is 'movies' or 'episodes'; `id_key` the id we match on."""
    singular = kind[:-1]            # movies->movie, episodes->episode
    result = {}
    page = 1
    while True:
        status, data = _request(
            "GET", f"/sync/history/{kind}?page={page}&limit=1000", None, headers)
        if status != 200 or not data:
            if status != 200:
                print(f"  WARN: could not read existing {kind} history ({status})")
            break
        for it in data:
            ids = (it.get(singular) or {}).get("ids", {})
            key = ids.get(id_key)
            if key is None:
                continue
            result.setdefault(str(key), set()).add(_norm(it.get("watched_at")))
        if len(data) < 1000:
            break
        page += 1
        time.sleep(0.3)
    return result


def fetch_episode_history(headers):
    """Read existing episode history and index it two ways:
      by_tvdb     : episode TVDB id           -> set(watched_at)
      by_show_se  : (show_tvdb, season, num)  -> set(watched_at)
    The second index is the fallback for plays whose record carries no
    episode TVDB id (e.g. Trakt stored them under TMDB ids)."""
    by_tvdb, by_show_se = {}, {}
    page = 1
    while True:
        status, data = _request(
            "GET", f"/sync/history/episodes?page={page}&limit=1000", None, headers)
        if status != 200 or not data:
            if status != 200:
                print(f"  WARN: could not read existing episode history ({status})")
            break
        for it in data:
            ts = _norm(it.get("watched_at"))
            ep = it.get("episode") or {}
            ep_tvdb = (ep.get("ids") or {}).get("tvdb")
            if ep_tvdb is not None:
                by_tvdb.setdefault(str(ep_tvdb), set()).add(ts)
            show_tvdb = ((it.get("show") or {}).get("ids") or {}).get("tvdb")
            if show_tvdb is not None and ep.get("season") is not None \
                    and ep.get("number") is not None:
                by_show_se.setdefault(
                    (str(show_tvdb), ep["season"], ep["number"]), set()).add(ts)
        if len(data) < 1000:
            break
        page += 1
        time.sleep(0.3)
    return by_tvdb, by_show_se


def categorize(items, existing, id_key):
    """Split items into (new, overwrite, skipped) by comparing against Trakt.
      new       -> not on Trakt at all          : just add
      overwrite -> on Trakt at a different time  : remove then add
      skipped   -> already on Trakt at this time : leave alone
    """
    new, overwrite, skipped = [], [], 0
    for it in items:
        times = existing.get(str(it["ids"][id_key]))
        if times is None:
            new.append(it)
        elif _norm(it["watched_at"]) in times:
            skipped += 1
        else:
            overwrite.append(it)
    return new, overwrite, skipped


def categorize_episodes(items, by_tvdb, by_show_se):
    """Like categorize() but matches on episode TVDB id first, then falls back
    to (show_tvdb, season, number). Returns (new, overwrite, skipped, fb_hits)
    where fb_hits is how many were matched only via the fallback index."""
    new, overwrite, skipped, fb_hits = [], [], 0, 0
    for it in items:
        ts = _norm(it["watched_at"])
        times = by_tvdb.get(str(it["ids"]["tvdb"]))
        if times is None and it.get("_show_tvdb") is not None \
                and it.get("_season") is not None and it.get("_number") is not None:
            times = by_show_se.get((it["_show_tvdb"], it["_season"], it["_number"]))
            if times is not None:
                fb_hits += 1
        if times is None:
            new.append(it)
        elif ts in times:
            skipped += 1
        else:
            overwrite.append(it)
    return new, overwrite, skipped, fb_hits


# Items we attempted to add, checked against Trakt at the end to find anything
# that didn't actually land (definitive, instead of trusting the add response).
SUBMITTED = {"movies": [], "episodes": []}


def _add_payload(payload_key, batch):
    """Build an add payload. For episodes, prefer the show/season/episode-number
    form (with per-episode watched_at) so Trakt resolves by show id + season +
    number — this works even when the episode's TVDB id isn't in Trakt's DB.
    Episodes lacking a show TVDB id, and movies, are sent by ids."""
    if payload_key != "episodes":
        return {payload_key: [_clean(it) for it in batch]}
    shows = {}          # show_tvdb -> {season -> [ {number, watched_at} ]}
    ep_ids = []
    for it in batch:
        st, s, n = it.get("_show_tvdb"), it.get("_season"), it.get("_number")
        if st is not None and s is not None and n is not None:
            shows.setdefault(st, {}).setdefault(s, []).append(
                {"number": n, "watched_at": it["watched_at"]})
        else:
            ep_ids.append({"ids": it["ids"], "watched_at": it["watched_at"]})
    payload = {}
    if shows:
        payload["shows"] = [
            {"ids": {"tvdb": int(st)},
             "seasons": [{"number": s, "episodes": eps}
                         for s, eps in sorted(seasons.items())]}
            for st, seasons in shows.items()]
    if ep_ids:
        payload["episodes"] = ep_ids
    return payload


def _remove_payload(payload_key, batch):
    """Build a remove payload. For episodes, prefer the show/season/episode-number
    form (works even when Trakt's record lacks the episode TVDB id); fall back to
    episode ids. For movies, remove by ids."""
    if payload_key != "episodes":
        return {payload_key: [{"ids": it["ids"]} for it in batch]}
    shows = {}          # show_tvdb -> {season -> set(numbers)}
    ep_ids = []
    for it in batch:
        st, s, n = it.get("_show_tvdb"), it.get("_season"), it.get("_number")
        if st is not None and s is not None and n is not None:
            shows.setdefault(st, {}).setdefault(s, set()).add(n)
        else:
            ep_ids.append({"ids": it["ids"]})
    payload = {}
    if shows:
        payload["shows"] = [
            {"ids": {"tvdb": int(st)},
             "seasons": [{"number": s, "episodes": [{"number": n} for n in sorted(nums)]}
                         for s, nums in sorted(seasons.items())]}
            for st, seasons in shows.items()]
    if ep_ids:
        payload["episodes"] = ep_ids
    return payload


def _remove(headers, payload_key, batch):
    payload = _remove_payload(payload_key, batch)
    if not payload:
        return
    status, data = _request("POST", "/sync/history/remove", payload, headers,
                            retries=MAX_RETRIES)
    _report(status, data, "/sync/history/remove")
    time.sleep(REQUEST_PAUSE)


def _apply(headers, payload_key, items, remove_first):
    """Add `items` to history in batches. `remove_first` overwrites existing
    plays. On a 5xx/transient add failure we re-remove then re-add the batch, so
    a retry can never leave a duplicate play behind. Submitted items are recorded
    for the end-of-run verification pass."""
    for batch in chunks(items, BATCH_SIZE):
        attempt = 0
        while True:
            if remove_first or attempt > 0:
                _remove(headers, payload_key, batch)
            status, data = _request("POST", "/sync/history",
                                    _add_payload(payload_key, batch), headers)
            if status in (200, 201):
                _report(status, data, "/sync/history")
                SUBMITTED[payload_key].extend(batch)
                break
            if attempt >= MAX_RETRIES:
                _report(status, data, "/sync/history")
                print(f"  giving up on a {payload_key} batch of "
                      f"{len(batch)} after {attempt} retries")
                break
            attempt += 1
            wait = min(30, 5 * attempt)
            print(f"  add returned {status}; re-removing + retrying in "
                  f"{wait}s (attempt {attempt}/{MAX_RETRIES})")
            time.sleep(wait)
        time.sleep(REQUEST_PAUSE)


def verify_and_report(headers):
    """Re-read Trakt history and list any submitted item that didn't land.
    This is form-independent — it trusts the resulting state, not the add
    response — so it catches episodes Trakt silently failed to resolve."""
    if not SUBMITTED["movies"] and not SUBMITTED["episodes"]:
        return
    print("\nVerifying what actually landed on Trakt...")
    missing = []
    if SUBMITTED["movies"]:
        existing = fetch_history_map(headers, "movies", "imdb")
        for it in SUBMITTED["movies"]:
            if str(it["ids"]["imdb"]) not in existing:
                missing.append(it)
    if SUBMITTED["episodes"]:
        by_tvdb, by_show_se = fetch_episode_history(headers)
        for it in SUBMITTED["episodes"]:
            se_key = (it.get("_show_tvdb"), it.get("_season"), it.get("_number"))
            if str(it["ids"]["tvdb"]) not in by_tvdb and se_key not in by_show_se:
                missing.append(it)

    if not missing:
        print("  all submitted items confirmed on Trakt.")
        return
    report = [{"title": it.get("_title"), "ids": it["ids"],
               "watched_at": it["watched_at"]} for it in missing]
    with open(NOT_FOUND_PATH, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2, ensure_ascii=False)
    print(f"  {len(missing)} item(s) could NOT be added (not in Trakt's "
          f"database). Full list: {NOT_FOUND_PATH}")
    for x in report[:15]:
        print(f"    - {x['title']}  ids={x['ids']}")
    if len(report) > 15:
        print(f"    ... and {len(report) - 15} more (see file)")


def sync_history(headers, movies, episodes, dry_run):
    if not movies and not episodes:
        return
    print(f"\nWatched sync: comparing {len(movies)} movies, "
          f"{len(episodes)} episodes against Trakt history...")

    movie_plan = ep_plan = None
    if movies:
        existing = fetch_history_map(headers, "movies", "imdb")
        new, over, skip = categorize(movies, existing, "imdb")
        print(f"  movies:   {len(new)} new, {len(over)} overwrite, {skip} already correct")
        movie_plan = (new, over)
    if episodes:
        by_tvdb, by_show_se = fetch_episode_history(headers)
        new, over, skip, fb = categorize_episodes(episodes, by_tvdb, by_show_se)
        extra = f" (incl. {fb} matched via season/episode fallback)" if fb else ""
        print(f"  episodes: {len(new)} new, {len(over)} overwrite, "
              f"{skip} already correct{extra}")
        ep_plan = (new, over)

    if dry_run:
        print("  [dry-run] no changes written")
        return

    for label, plan in (("movies", movie_plan), ("episodes", ep_plan)):
        if not plan:
            continue
        new, over = plan
        if over:
            print(f"  {label}: overwriting {len(over)} (remove+re-add per batch)...")
            _apply(headers, label, over, remove_first=True)
        if new:
            print(f"  {label}: adding {len(new)} new...")
            _apply(headers, label, new, remove_first=False)

    verify_and_report(headers)


def fetch_episode_plays(headers, wanted):
    """For shows whose tvdb id is in `wanted`, return:
      plays  : {show_tvdb -> {(season, number): [normalized watched_at, ...]}}
      titles : {show_tvdb -> show title}
    The list length per episode is its play count (to detect duplicates)."""
    plays, titles = {}, {}
    page = 1
    while True:
        status, data = _request(
            "GET", f"/sync/history/episodes?page={page}&limit=1000", None, headers)
        if status != 200 or not data:
            if status != 200:
                print(f"  WARN: could not read episode history ({status})")
            break
        for h in data:
            st = ((h.get("show") or {}).get("ids") or {}).get("tvdb")
            if st is None or str(st) not in wanted:
                continue
            st = str(st)
            titles.setdefault(st, (h.get("show") or {}).get("title"))
            ep = h.get("episode") or {}
            if ep.get("season") is None or ep.get("number") is None:
                continue
            plays.setdefault(st, {}).setdefault(
                (ep["season"], ep["number"]), []).append(_norm(h.get("watched_at")))
        if len(data) < 1000:
            break
        page += 1
        time.sleep(0.3)
    return plays, titles


def sync_prune(headers, episodes, dry_run):
    """Reconcile Trakt episode history to exactly match the TV Time export, for
    every show that appears in the export:
      * remove episodes watched on Trakt but not in the CSV (extras)
      * collapse duplicates / fix times so each CSV episode has exactly one
        play at its CSV watched_at
      * add CSV episodes missing from Trakt
    Movies are intentionally left untouched."""
    desired = {}        # show_tvdb -> {(season, number): csv_item}
    for it in episodes:
        st, s, n = it.get("_show_tvdb"), it.get("_season"), it.get("_number")
        if st and s is not None and n is not None:
            desired.setdefault(st, {})[(s, n)] = it
    if not desired:
        print("\nPrune: no episodes with a resolvable show; nothing to do.")
        return

    print(f"\nPrune: reconciling {len(desired)} shows from the export...")
    plays, titles = fetch_episode_plays(headers, set(desired))

    extras, fixes, adds = [], [], []
    for st, eps in desired.items():
        trakt_eps = plays.get(st, {})
        for key, times in trakt_eps.items():
            if key not in eps:                       # on Trakt, not in CSV
                s, n = key
                extras.append({"ids": {}, "_show_tvdb": st, "_season": s,
                               "_number": n,
                               "_title": f"{titles.get(st, st)} S{s}E{n}"})
        for key, it in eps.items():
            times = trakt_eps.get(key)
            if times is None:                        # missing on Trakt
                adds.append(it)
            elif len(times) == 1 and times[0] == _norm(it["watched_at"]):
                continue                             # already exactly right
            else:                                    # duplicate or wrong time
                fixes.append(it)

    print(f"  extras to remove:           {len(extras)}")
    print(f"  episodes to fix (dupe/time):{len(fixes)}")
    print(f"  missing episodes to add:    {len(adds)}")
    _write_prune_report(extras)

    if dry_run:
        print("  [dry-run] no changes written")
        return

    if extras:
        print(f"  removing {len(extras)} extra episodes...")
        for batch in chunks(extras, BATCH_SIZE):
            _remove(headers, "episodes", batch)
    if fixes:
        print(f"  fixing {len(fixes)} episodes (remove+re-add)...")
        _apply(headers, "episodes", fixes, remove_first=True)
    if adds:
        print(f"  adding {len(adds)} missing episodes...")
        _apply(headers, "episodes", adds, remove_first=False)

    verify_and_report(headers)


def _write_prune_report(extras):
    if not extras:
        return
    report = [{"title": x["_title"], "show_tvdb": x["_show_tvdb"],
               "season": x["_season"], "number": x["_number"]} for x in extras]
    with open(PRUNE_REPORT_PATH, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2, ensure_ascii=False)
    by_show = {}
    for x in report:
        by_show[x["title"].rsplit(" S", 1)[0]] = by_show.get(
            x["title"].rsplit(" S", 1)[0], 0) + 1
    print(f"  extras report ({len(report)} episodes across {len(by_show)} shows): "
          f"{PRUNE_REPORT_PATH}")
    for show, c in sorted(by_show.items(), key=lambda kv: -kv[1])[:10]:
        print(f"    {c:4d}  {show}")


def sync_watchlist(headers, shows, dry_run):
    if not shows:
        return
    print(f"\nWatchlist sync: {len(shows)} shows")
    if dry_run:
        print("  [dry-run] skipping")
        return
    payload_shows = [{"ids": s["ids"]} for s in shows]
    for batch in chunks(payload_shows, BATCH_SIZE):
        status, data = _request("POST", "/sync/watchlist", {"shows": batch}, headers)
        _report(status, data, "/sync/watchlist")
        time.sleep(REQUEST_PAUSE)


def _report(status, data, path):
    if status == 420:
        print(f"  ERROR 420 on {path}: Trakt account limit exceeded — your "
              f"watchlist/list is full. Free accounts are capped (~100 items); "
              f"Trakt VIP removes the limit. Nothing was added in this batch.")
        return
    if status not in (200, 201):
        print(f"  ERROR {status} on {path}: {data}")
        return
    if not isinstance(data, dict):
        return
    added = data.get("added", {})
    deleted = data.get("deleted", {})
    updated = data.get("updated", {})
    existing = data.get("existing", {})
    not_found = data.get("not_found", {})
    nf_counts = {k: len(v) for k, v in not_found.items() if v}
    summary = []
    for label, d in (("added", added), ("deleted", deleted),
                     ("updated", updated), ("existing", existing)):
        if d:
            summary.append(f"{label}={d}")
    line = f"  {os.path.basename(path)}: " + ", ".join(summary)
    if nf_counts:
        line += f" | not_found={nf_counts}"
    print(line)


# --------------------------------------------------------------------------- #
def main():
    ap = argparse.ArgumentParser(description="Sync TV Time export to Trakt")
    ap.add_argument("--dry-run", action="store_true", help="parse + report, no writes")
    ap.add_argument("--only", choices=["movies", "episodes", "shows"],
                    help="sync only one category")
    ap.add_argument("--limit", type=int, help="cap watched items (for testing)")
    ap.add_argument("--skip-watchlist", action="store_true")
    ap.add_argument("--prune", action="store_true",
                    help="reconcile episode history to exactly match the export "
                         "(remove extras, collapse duplicates); episodes only")
    args = ap.parse_args()

    movies, episodes, shows = parse_csv(limit=args.limit)
    print(f"Parsed: {len(movies)} movies, {len(episodes)} episodes, "
          f"{len(shows)} watchlist shows")

    if args.only == "movies":
        episodes, shows = [], []
    elif args.only == "episodes":
        movies, shows = [], []
    elif args.only == "shows":
        movies, episodes = [], []
    if args.skip_watchlist:
        shows = []

    client_id, client_secret = load_config()
    # Auth is needed even for --dry-run, since the plan is computed by
    # reading your existing Trakt history (read-only; nothing is written).
    token = get_token(client_id, client_secret)
    headers = api_headers(client_id, token)

    if args.prune:
        sync_prune(headers, episodes, args.dry_run)
    else:
        sync_history(headers, movies, episodes, args.dry_run)
        sync_watchlist(headers, shows, args.dry_run)
    print("\nDone.")


if __name__ == "__main__":
    main()
