import 'package:flutter/foundation.dart';

import '../models/calendar_entry.dart';
import '../models/media_item.dart';
import '../models/watchlist_show.dart';
import '../services/concurrency.dart';
import '../services/prefs_cache.dart';
import '../services/show_enricher.dart';
import '../services/tmdb_api.dart';
import '../services/trakt_api.dart';
import 'auth_controller.dart';

enum LoadState { idle, loading, ready, error }

/// Loads the watchlist from Trakt and enriches it with TMDB metadata, then
/// exposes it sorted by release date for the home page.
class LibraryController extends ChangeNotifier {
  final TraktApi _trakt;
  final TmdbApi _tmdb;
  final AuthController _auth;

  LibraryController({
    required AuthController auth,
    TraktApi? trakt,
    TmdbApi? tmdb,
  })  : _auth = auth,
        _trakt = trakt ?? TraktApi(auth),
        _tmdb = tmdb ?? TmdbApi();

  late final ShowEnricher _enricher = ShowEnricher(_trakt, _tmdb);

  /// Name of the personal Trakt list used to park shows the user has stopped
  /// watching. Shows on it are hidden from the home page.
  static const _watchLaterListName = 'Watch Later';

  /// Persisted snapshot of the last-built home view, for an instant render on a
  /// cold start (the network refresh then runs in the background).
  static const _snapshotStore = PrefsCache('home_snapshot_v1');

  LoadState _state = LoadState.idle;
  LoadState get state => _state;

  /// True while a background refresh is running over already-rendered cached
  /// data, so the UI can show a subtle indicator without blocking interaction.
  bool _refreshing = false;
  bool get isRefreshing => _refreshing;

  /// Trakt id of the "Watch Later" list, and the trakt ids of shows on it.
  int? _watchLaterListId;
  Set<int> _watchLaterShowIds = const {};

  String? _error;
  String? get error => _error;

  List<MediaItem> _items = const [];
  List<MediaItem> get items => _items;

  /// Movies not yet released, soonest first (ascending).
  List<MediaItem> get upcomingMovies =>
      _items.where((e) => e.isMovie && !e.isReleased).toList()
        ..sort((a, b) => -_byRecent(a, b));

  /// Released movies, most recent first (descending).
  List<MediaItem> get movies =>
      _items.where((e) => e.isMovie && e.isReleased).toList(growable: false);

  /// Shows watched recently, or aired within the last month; most recent first.
  List<WatchlistShow> _recentShows = const [];
  List<WatchlistShow> get recentShows => _recentShows;

  /// In-progress shows not watched in a while; most recently watched first.
  List<WatchlistShow> _staleShows = const [];
  List<WatchlistShow> get staleShows => _staleShows;

  /// Shows with no episodes watched; alphabetical.
  List<WatchlistShow> _notStartedShows = const [];
  List<WatchlistShow> get notStartedShows => _notStartedShows;

  /// Upcoming episodes of the user's shows, from Trakt's personalized calendar;
  /// soonest air date first. Populated best-effort, independent of the watchlist
  /// sections above.
  ///
  /// An entry whose episode has already aired is dropped once its show appears
  /// under "Recently Watched / Just Released" — the freshly-aired episode now
  /// surfaces there as the show's next episode, so keeping it here would be a
  /// duplicate. (Entries can be past-dated between refreshes via the persisted
  /// snapshot.)
  List<CalendarEntry> _upcomingEpisodes = const [];
  List<CalendarEntry> get upcomingEpisodes {
    final now = DateTime.now();
    final recentIds = _recentShows
        .map((ws) => ws.show.ids.trakt)
        .whereType<int>()
        .toSet();
    return _upcomingEpisodes
        .where((e) =>
            e.airsAt.isAfter(now) || !recentIds.contains(e.show.ids.trakt))
        .toList(growable: false);
  }

  /// The full set of shows behind the three sections above, kept so a per-item
  /// mutation (marking an episode watched, stopping a show) can re-bucket the
  /// sections in place without waiting for the next network reload.
  List<WatchlistShow> _allShows = const [];

  bool get isEmpty =>
      _items.isEmpty &&
      _recentShows.isEmpty &&
      _staleShows.isEmpty &&
      _notStartedShows.isEmpty &&
      _upcomingEpisodes.isEmpty;

  Future<void> load() async {
    // On the first load, paint the persisted snapshot immediately and refresh
    // in the background (stale-while-revalidate); a cold PWA open then shows
    // data instantly. Pull-to-refresh / retry calls skip straight to a fetch.
    if (_state == LoadState.idle && await _restoreSnapshot()) {
      _state = LoadState.ready;
      _refreshing = true;
    } else if (_state == LoadState.ready) {
      _refreshing = true; // refreshing over already-visible data
    } else {
      _state = LoadState.loading;
    }
    _error = null;
    notifyListeners();

    try {
      // Resolve username once for display, non-fatal if it fails.
      _trakt.fetchUsername().then(_auth.setUsername).ignore();

      final items = await _trakt.watchlist();
      // Enrich with bounded concurrency; failures per-item swallowed in enrich.
      await pooledForEach(items, _tmdb.enrich);

      // Resolve the "Watch Later" list so its shows can be excluded below and
      // "Stop Watching" can add to it. Best-effort: failures leave it empty.
      await _loadWatchLater();

      _items = items.where((e) => e.isMovie).where(_isVisible).toList()
        ..sort(_byRecent);

      final watchlistShows = await pooledMap(
          items.where((e) => e.isShow), _enricher.buildShow);

      // Merge in-progress shows from Trakt's "up next" progress endpoint that
      // aren't on the watchlist (best-effort; ignored if the call fails).
      final extraShows = await _loadInProgressNotOnWatchlist(watchlistShows);

      _allShows = [...watchlistShows, ...extraShows];
      _splitShows(_allShows);

      // Upcoming episodes from Trakt's personalized calendar (best-effort).
      _upcomingEpisodes = await _loadUpcomingEpisodes();

      _state = LoadState.ready;
      await _saveSnapshot();
    } catch (e) {
      _error = e.toString();
      // Keep showing cached data if we have any; only surface the error when
      // there's nothing on screen to fall back to.
      if (isEmpty) _state = LoadState.error;
    } finally {
      _refreshing = false;
      notifyListeners();
    }
  }

  /// Rehydrates the home view from the persisted snapshot. Returns true when it
  /// restored something renderable. Never throws.
  Future<bool> _restoreSnapshot() async {
    final data = (await _snapshotStore.read())?.data;
    if (data is! Map) return false;
    try {
      _items = _mediaFrom(data['movies']);
      _recentShows = _showsFrom(data['recent']);
      _staleShows = _showsFrom(data['stale']);
      _notStartedShows = _showsFrom(data['notStarted']);
      _upcomingEpisodes = _calendarFrom(data['upcoming']);
      _allShows = [..._recentShows, ..._staleShows, ..._notStartedShows];
      return !isEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _saveSnapshot() => _snapshotStore.write({
        'movies': _items.map((e) => e.toJson()).toList(),
        'recent': _recentShows.map((e) => e.toJson()).toList(),
        'stale': _staleShows.map((e) => e.toJson()).toList(),
        'notStarted': _notStartedShows.map((e) => e.toJson()).toList(),
        'upcoming': _upcomingEpisodes.map((e) => e.toJson()).toList(),
      });

  static List<MediaItem> _mediaFrom(Object? raw) => ((raw as List?) ?? const [])
      .map((e) => MediaItem.fromJson((e as Map).cast<String, dynamic>()))
      .toList();

  static List<WatchlistShow> _showsFrom(Object? raw) =>
      ((raw as List?) ?? const [])
          .map((e) => WatchlistShow.fromJson((e as Map).cast<String, dynamic>()))
          .toList();

  static List<CalendarEntry> _calendarFrom(Object? raw) =>
      ((raw as List?) ?? const [])
          .map((e) => CalendarEntry.fromJson((e as Map).cast<String, dynamic>()))
          .toList();

  /// Clears the persisted home snapshot (e.g. on sign-out).
  static Future<void> clearSnapshot() => _snapshotStore.clear();

  /// Loads the "Watch Later" list id and the trakt ids of shows on it.
  /// Best-effort: any failure (including the list not existing) leaves it empty.
  Future<void> _loadWatchLater() async {
    try {
      final id = await _trakt.findListId(_watchLaterListName);
      _watchLaterListId = id;
      _watchLaterShowIds =
          id != null ? await _trakt.listShowTraktIds(id) : const {};
    } catch (_) {
      _watchLaterListId = null;
      _watchLaterShowIds = const {};
    }
  }

  /// Fetches the user's watched shows and keeps those not already on the
  /// watchlist that are still in progress (have aired episodes left to watch).
  /// Only in-progress shows get a per-show progress call, so a large history of
  /// finished shows doesn't fan out into hundreds of requests. Best-effort:
  /// returns empty on failure.
  Future<List<WatchlistShow>> _loadInProgressNotOnWatchlist(
      List<WatchlistShow> watchlistShows) async {
    try {
      final watched = await _trakt.watchedShows();
      final known = watchlistShows
          .map((ws) => ws.show.ids.trakt)
          .whereType<int>()
          .toSet();
      final inProgress = watched
          .where((s) =>
              s.show.ids.trakt != null &&
              !known.contains(s.show.ids.trakt) &&
              s.inProgress)
          .map((s) => s.show)
          .toList();

      // Enrich with TMDB (posters + most-recent-aired-episode date) before
      // building, mirroring the watchlist path. Without this these shows carry a
      // null releaseDate, which breaks recency sorting and, more importantly,
      // the "abandoned > a year" drop in [_splitShows] — a show last watched
      // over a year ago whose new season aired recently would be dropped from
      // Up Next because airedInWindow can't see the (missing) release date.
      await pooledForEach(inProgress, _tmdb.enrich);

      final built = await pooledMap(inProgress, _enricher.buildShow);
      // Only keep shows with something left to watch.
      return built.where((ws) => ws.nextEpisode != null).toList();
    } catch (_) {
      return const [];
    }
  }

  /// How far ahead the upcoming-episodes calendar looks.
  static const _calendarWindowDays = 30;

  /// Fetches the user's upcoming episodes from Trakt's calendar, keeping only
  /// the soonest episode per show (to save vertical space), and enriches each
  /// show with a TMDB poster. Best-effort: returns empty on failure so a
  /// calendar hiccup never blocks the rest of the page.
  Future<List<CalendarEntry>> _loadUpcomingEpisodes() async {
    try {
      final entries =
          await _trakt.upcomingEpisodes(days: _calendarWindowDays);
      // Entries arrive sorted soonest-first, so the first one seen for a show is
      // its next episode; keep that and drop the rest. Shows with no trakt id
      // (shouldn't happen from the calendar) are kept as-is.
      final soonestByShow = <int, CalendarEntry>{};
      final next = <CalendarEntry>[];
      for (final e in entries) {
        final id = e.show.ids.trakt;
        if (id == null) {
          next.add(e);
        } else if (!soonestByShow.containsKey(id)) {
          soonestByShow[id] = e;
          next.add(e);
        }
      }
      await pooledForEach(next.map((e) => e.show), _tmdb.enrich);
      return next;
    } catch (_) {
      return const [];
    }
  }

  /// How long since the last watch before an in-progress show drops from
  /// "Recently Watched" into the "Not watched in a while" section.
  static const _staleAfter = Duration(days: 30);

  /// Splits shows into three sections: "Recently Watched / Just Released" (has
  /// views recently OR aired/premiered in the last six months), "Not watched in
  /// a while" (has views but not in [_staleAfter], with episodes left, and with
  /// some watch or airing activity in the last year), and "Not Started"
  /// (the rest, A–Z). A just-released show you haven't started is treated as
  /// recently-released. Upcoming shows that haven't premiered yet are excluded
  /// entirely — there's nothing to watch, so they only live on the Watchlist
  /// tab. In-progress shows abandoned for over six months (no watch activity
  /// and no new episode) are likewise dropped from Up Next; they remain under
  /// "Continue Watching" on the Watchlist → TV page.
  void _splitShows(List<WatchlistShow> shows) {
    final now = DateTime.now();
    // "Just released" content — a freshly aired next episode or a newly
    // premiered show you haven't started — stays in the Recently Watched /
    // Just Released section for six months, matching the movie window on the
    // Up Next page (see [_isVisible]). Independent of both [staleCutoff] (how
    // recently *you* watched) and [abandonedCutoff] below.
    final justReleasedCutoff = DateTime(now.year, now.month - 6, now.day);
    // An in-progress show you've watched stays in "Not watched in a while" for
    // up to a year of inactivity; with no watch activity AND no newly-aired
    // episode within that window it drops off Up Next entirely (it stays under
    // Continue Watching on the Watchlist → TV page).
    final abandonedCutoff = DateTime(now.year - 1, now.month, now.day);
    final staleCutoff = now.subtract(_staleAfter);

    final recent = <WatchlistShow>[];
    final stale = <WatchlistShow>[];
    final notStarted = <WatchlistShow>[];
    for (final ws in shows) {
      // Hide shows the user has parked on the "Watch Later" list.
      final traktId = ws.show.ids.trakt;
      if (traktId != null && _watchLaterShowIds.contains(traktId)) continue;
      // Hide shows you're fully caught up on: watched, with no aired episodes
      // left to watch. Trakt's aired−watched count (remainingReleased) is the
      // source of truth here rather than a resolved next episode — otherwise a
      // failed/missing TMDB next-episode lookup would make an in-progress show
      // vanish entirely instead of staying put.
      if (ws.hasViews && ws.remainingReleased == 0) continue;

      // A next episode that aired in the recent past is fresh content to watch,
      // so the show is "just released" even if it's been a while since you
      // watched. A *future* air date isn't watchable yet, so it doesn't count.
      final nextAir = ws.nextEpisode?.airDate;
      final freshEpisode = nextAir != null &&
          nextAir.isAfter(justReleasedCutoff) &&
          !nextAir.isAfter(now);

      if (ws.hasViews) {
        final lastWatched = ws.lastWatchedAt;
        final watchedRecently =
            lastWatched != null && !lastWatched.isBefore(staleCutoff);
        if (watchedRecently || freshEpisode) {
          recent.add(ws);
        } else {
          // "Not watched in a while" is bounded to a year: a show with no watch
          // activity AND no newly-aired episode in that window is dropped from
          // Up Next entirely. It still lives under "Continue Watching" on the
          // Watchlist → TV page, so it isn't lost — it just stops nagging.
          // [releaseDate] is the most recently aired episode, so it catches new
          // episodes even when you're several episodes behind (an old next
          // episode air date).
          final airedInWindow = ws.releaseDate != null &&
              ws.releaseDate!.isAfter(abandonedCutoff);
          final watchedInWindow =
              lastWatched != null && lastWatched.isAfter(abandonedCutoff);
          if (airedInWindow || watchedInWindow) {
            stale.add(ws);
          }
        }
      } else {
        // No episodes watched yet. "Just released" is bounded to the recent
        // past so a future premiere date doesn't qualify.
        final releasedRecently = ws.releaseDate != null &&
            ws.releaseDate!.isAfter(justReleasedCutoff) &&
            !ws.releaseDate!.isAfter(now);
        if (freshEpisode || releasedRecently) {
          recent.add(ws);
        } else if (_notYetAired(ws, now)) {
          // Upcoming show that hasn't premiered — nothing to watch yet.
          continue;
        } else {
          notStarted.add(ws);
        }
      }
    }

    recent.sort(_byRecency);
    stale.sort(_byRecency);
    notStarted.sort((a, b) =>
        a.show.title.toLowerCase().compareTo(b.show.title.toLowerCase()));

    _recentShows = recent;
    _staleShows = stale;
    _notStartedShows = notStarted;
  }

  /// True when an unstarted show has nothing available to watch yet: its next
  /// (first) episode airs in the future, or — with no episode data — its
  /// premiere date is still ahead. Shows with unknown dates are treated as
  /// available (they fall through to "Not Started").
  bool _notYetAired(WatchlistShow ws, DateTime now) {
    final nextAir = ws.nextEpisode?.airDate;
    if (nextAir != null) return nextAir.isAfter(now);
    final release = ws.releaseDate;
    return release != null && release.isAfter(now);
  }

  /// Latest activity for sorting: the most recent of last-watched, next-episode
  /// air date, and latest aired episode. Most recent first; undated shows sink
  /// to the bottom by title.
  int _byRecency(WatchlistShow a, WatchlistShow b) {
    final da = _recencyOf(a);
    final db = _recencyOf(b);
    if (da == null && db == null) return a.show.title.compareTo(b.show.title);
    if (da == null) return 1;
    if (db == null) return -1;
    return db.compareTo(da);
  }

  DateTime? _recencyOf(WatchlistShow ws) {
    DateTime? latest;
    for (final d in [ws.lastWatchedAt, ws.nextEpisode?.airDate, ws.releaseDate]) {
      if (d != null && (latest == null || d.isAfter(latest))) latest = d;
    }
    return latest;
  }

  /// Movies are limited to a window from six months ago through one month ahead
  /// (i.e. recently released or releasing soon); shows are always shown.
  bool _isVisible(MediaItem item) {
    if (item.isShow) return true;
    final date = item.releaseDate;
    if (date == null) return false;
    final now = DateTime.now();
    final upperCutoff = DateTime(now.year, now.month + 1, now.day);
    final lowerCutoff = DateTime(now.year, now.month - 6, now.day);
    return !date.isAfter(upperCutoff) && !date.isBefore(lowerCutoff);
  }

  /// Most recent first (movie release date / latest aired episode); undated
  /// items sink to the bottom, ordered by title.
  int _byRecent(MediaItem a, MediaItem b) {
    final da = a.releaseDate;
    final db = b.releaseDate;
    if (da == null && db == null) return a.title.compareTo(b.title);
    if (da == null) return 1;
    if (db == null) return -1;
    return db.compareTo(da);
  }

  /// The already-aired episodes still left to watch for [ws], next first.
  /// Fetched on demand (for the detail dialog), not preloaded.
  Future<List<NextEpisode>> remainingEpisodes(WatchlistShow ws) =>
      _enricher.remainingEpisodes(ws.show);

  // --- Per-item watchlist / watched mutations ---

  final Set<int> _busyIds = {};

  bool isBusy(MediaItem item) =>
      item.ids.trakt != null && _busyIds.contains(item.ids.trakt);

  bool isShowBusy(WatchlistShow ws) =>
      ws.show.ids.trakt != null && _busyIds.contains(ws.show.ids.trakt);

  /// Marks the show's next episode watched, then advances [ws] to the new next
  /// episode (or caught-up) and re-buckets the sections in place.
  Future<void> markNextEpisodeWatched(WatchlistShow ws) async {
    final ep = ws.nextEpisode;
    if (ep == null) return;

    final busyId = ws.show.ids.trakt;
    if (busyId != null) {
      _busyIds.add(busyId);
      notifyListeners();
    }
    try {
      await _trakt.markEpisodeWatched(ws.show, ep.season, ep.number);
      ws.hasViews = true;
      ws.lastWatchedAt = DateTime.now();

      final progress = await _trakt.showProgress(ws.show);
      if (progress.lastWatchedAt != null) {
        ws.lastWatchedAt = progress.lastWatchedAt;
      }
      ws.remainingReleased = progress.remainingReleased;
      ws.nextEpisode = progress.nextEpisode != null
          ? await _enricher.buildNextEpisode(ws.show, progress.nextEpisode!,
              assumeAired: progress.remainingReleased > 0)
          : null;
      _splitShows(_allShows);
      await _saveSnapshot();
    } finally {
      if (busyId != null) _busyIds.remove(busyId);
      notifyListeners();
    }
  }

  /// Adds [ws] to the "Watch Later" list, removes it from the watchlist, and
  /// removes it from the home view, so its episodes stop appearing in the show
  /// sections.
  Future<void> stopWatching(WatchlistShow ws) async {
    final listId = _watchLaterListId;
    if (listId == null) {
      throw StateError('No "$_watchLaterListName" list found on Trakt');
    }
    final busyId = ws.show.ids.trakt;
    if (busyId != null) {
      _busyIds.add(busyId);
      notifyListeners();
    }
    try {
      await _trakt.addShowToList(listId, ws.show);
      if (ws.show.onWatchlist) {
        await _trakt.removeFromWatchlist(ws.show);
      }
      if (busyId != null) {
        _watchLaterShowIds = {..._watchLaterShowIds, busyId};
      }
      _allShows = List.of(_allShows)..remove(ws);
      _splitShows(_allShows);
    } finally {
      if (busyId != null) _busyIds.remove(busyId);
      notifyListeners();
    }
  }

  /// Clears the show's watch history and removes it from both the watchlist and
  /// the "Watch Later" list, then drops it from the home view entirely.
  Future<void> removeFromHistory(WatchlistShow ws) async {
    final busyId = ws.show.ids.trakt;
    if (busyId != null) {
      _busyIds.add(busyId);
      notifyListeners();
    }
    try {
      await _trakt.removeShowFromHistory(ws.show);
      if (ws.show.onWatchlist) {
        await _trakt.removeFromWatchlist(ws.show);
      }
      final listId = _watchLaterListId;
      if (listId != null) {
        await _trakt.removeShowFromList(listId, ws.show);
        if (busyId != null) {
          _watchLaterShowIds = {..._watchLaterShowIds}..remove(busyId);
        }
      }
      _allShows = List.of(_allShows)..remove(ws);
      _splitShows(_allShows);
    } finally {
      if (busyId != null) _busyIds.remove(busyId);
      notifyListeners();
    }
  }

  /// Marks [item] watched on Trakt and drops it from the home list.
  Future<void> markWatched(MediaItem item) =>
      _mutate(item, () => _trakt.markWatched(item));

  /// Removes [item] from the Trakt watchlist and from the home list.
  Future<void> removeFromWatchlist(MediaItem item) =>
      _mutate(item, () => _trakt.removeFromWatchlist(item));

  /// Runs a sync action with per-item busy state, then removes the item from
  /// the list (both actions take it off the watchlist view). Rethrows on error
  /// so the UI can surface it.
  Future<void> _mutate(MediaItem item, Future<void> Function() action) async {
    final id = item.ids.trakt;
    if (id != null) {
      _busyIds.add(id);
      notifyListeners();
    }
    try {
      await action();
      _items = List.of(_items)..remove(item);
    } finally {
      if (id != null) _busyIds.remove(id);
      notifyListeners();
    }
  }
}
