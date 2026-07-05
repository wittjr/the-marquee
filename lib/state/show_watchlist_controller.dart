import 'package:flutter/foundation.dart';

import '../models/watchlist_show.dart';
import '../services/concurrency.dart';
import '../services/prefs_cache.dart';
import '../services/show_enricher.dart';
import '../services/tmdb_api.dart';
import '../services/trakt_api.dart';
import 'auth_controller.dart';

enum ShowWatchlistState { loading, ready, error }

/// Backs the TV segment of the Watchlist tab: the user's *full* show watchlist
/// (watchlist entries plus shows parked on the "Watch Later" list), enriched
/// with watched progress and the next episode to watch.
///
/// The enriched shows are held in one master list ([_shows]); the New Episodes
/// and Recently Watched rows are computed views over it, so an in-place mutation
/// (marking an episode watched) re-buckets everything without a reload.
class ShowWatchlistController extends ChangeNotifier {
  final TraktApi _trakt;
  final TmdbApi _tmdb;
  late final ShowEnricher _enricher = ShowEnricher(_trakt, _tmdb);

  ShowWatchlistController({
    required AuthController auth,
    TraktApi? trakt,
    TmdbApi? tmdb,
  })  : _trakt = trakt ?? TraktApi(auth),
        _tmdb = tmdb ?? TmdbApi();

  static const _watchLaterListName = 'Watch Later';

  /// Persisted snapshot of the built list, for an instant render on tab
  /// (re)selection while a fresh copy loads in the background.
  static const _snapshotStore = PrefsCache('show_watchlist_snapshot_v1');

  ShowWatchlistState _state = ShowWatchlistState.loading;
  ShowWatchlistState get state => _state;

  String? _error;
  String? get error => _error;

  /// True while a background refresh runs over already-visible cached data.
  bool _refreshing = false;
  bool get isRefreshing => _refreshing;

  int? _watchLaterListId;

  /// The full watchlist, sorted alphabetically. Source of truth for the rows.
  List<WatchlistShow> _shows = const [];
  List<WatchlistShow> get allShows => _shows;

  bool get isEmpty => _shows.isEmpty;

  /// Shows that haven't premiered yet (no episodes aired), soonest premiere
  /// first — the next show to start comes first. Shows with no announced date
  /// yet sink to the bottom, ordered by title.
  List<WatchlistShow> get comingSoon {
    final out = _shows.where((ws) => ws.upcoming).toList();
    out.sort((a, b) {
      final da = a.releaseDate;
      final db = b.releaseDate;
      if (da == null && db == null) return _byTitle(a, b);
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    });
    return out;
  }

  /// Shows the user has started watching, most recently watched first.
  List<WatchlistShow> get continueWatching {
    final out = _shows.where((ws) => ws.hasViews).toList();
    out.sort((a, b) {
      final da = a.lastWatchedAt;
      final db = b.lastWatchedAt;
      if (da == null && db == null) return _byTitle(a, b);
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });
    return out;
  }

  /// Shows that have aired episodes but the user hasn't started; alphabetical
  /// (inherited from [_shows]).
  List<WatchlistShow> get notStarted =>
      _shows.where((ws) => !ws.hasViews && !ws.upcoming).toList();

  /// The already-aired episodes still left to watch for [ws], next first.
  /// Fetched on demand (for the detail dialog), not preloaded.
  Future<List<NextEpisode>> remainingEpisodes(WatchlistShow ws) =>
      _enricher.remainingEpisodes(ws.show);

  final Set<int> _busyIds = {};
  bool isShowBusy(WatchlistShow ws) =>
      ws.show.ids.trakt != null && _busyIds.contains(ws.show.ids.trakt);

  bool _isLoading = false;
  bool _restored = false;

  /// Loads the full show watchlist (watchlist entries + Watch Later shows),
  /// enriches each with progress and the next episode, and sorts alphabetically.
  /// Re-entrant calls are ignored. On the first load the persisted snapshot is
  /// painted immediately and the network refresh runs in the background.
  Future<void> load() async {
    if (_isLoading) return;
    _isLoading = true;

    if (!_restored) {
      _restored = true;
      if (_shows.isEmpty && await _restoreSnapshot()) {
        _state = ShowWatchlistState.ready;
      }
    }
    if (_shows.isEmpty) {
      _state = ShowWatchlistState.loading;
    } else {
      _refreshing = true; // refreshing over already-visible data
    }
    _error = null;
    notifyListeners();

    try {
      final watchlist = await _trakt.watchlist();
      final shows = watchlist.where((e) => e.isShow).toList();

      // Fold in shows parked on the "Watch Later" list, deduped by trakt id, so
      // the full watchlist includes shows you've set aside. Best-effort.
      _watchLaterListId = await _trakt.findListId(_watchLaterListName);
      if (_watchLaterListId != null) {
        final seen = shows.map((e) => e.ids.trakt).whereType<int>().toSet();
        final parked = await _trakt.listShows(_watchLaterListId!);
        for (final p in parked) {
          if (p.ids.trakt == null || !seen.contains(p.ids.trakt)) {
            shows.add(p);
          }
        }
      }

      // Posters/overview from TMDB, then progress + next episode (bounded).
      await pooledForEach(shows, _tmdb.enrich);
      final built = await pooledMap(shows, _enricher.buildShow);
      built.sort(_byTitle);
      _shows = built;

      _state = ShowWatchlistState.ready;
      await _saveSnapshot();
    } catch (e) {
      _error = e.toString();
      if (_shows.isEmpty) _state = ShowWatchlistState.error;
    } finally {
      _isLoading = false;
      _refreshing = false;
    }
    notifyListeners();
  }

  int _byTitle(WatchlistShow a, WatchlistShow b) =>
      a.show.title.toLowerCase().compareTo(b.show.title.toLowerCase());

  /// Rehydrates the list from the persisted snapshot. Returns true when it
  /// restored something. Never throws.
  Future<bool> _restoreSnapshot() async {
    final data = (await _snapshotStore.read())?.data;
    if (data is! List) return false;
    try {
      _shows = data
          .map((e) => WatchlistShow.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
      return _shows.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _saveSnapshot() =>
      _snapshotStore.write(_shows.map((e) => e.toJson()).toList());

  /// Clears the persisted snapshot (e.g. on sign-out).
  static Future<void> clearSnapshot() => _snapshotStore.clear();

  /// Marks the show's next episode watched and advances [ws] in place to the new
  /// next episode (or caught-up), re-bucketing the rows.
  Future<void> markNextEpisodeWatched(WatchlistShow ws) async {
    final ep = ws.nextEpisode;
    if (ep == null) return;

    final id = ws.show.ids.trakt;
    if (id != null) {
      _busyIds.add(id);
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
      await _saveSnapshot();
    } finally {
      if (id != null) _busyIds.remove(id);
      notifyListeners();
    }
  }

  /// Clears the show's watch history and removes it from both the watchlist and
  /// the "Watch Later" list, then drops it from this view.
  Future<void> removeFromHistory(WatchlistShow ws) async {
    final id = ws.show.ids.trakt;
    if (id != null) {
      _busyIds.add(id);
      notifyListeners();
    }
    try {
      await _trakt.removeShowFromHistory(ws.show);
      // Best-effort on both lists; Trakt no-ops if the show isn't a member.
      await _trakt.removeFromWatchlist(ws.show);
      if (_watchLaterListId != null) {
        await _trakt.removeShowFromList(_watchLaterListId!, ws.show);
      }
      _shows = List.of(_shows)..remove(ws);
      await _saveSnapshot();
    } finally {
      if (id != null) _busyIds.remove(id);
      notifyListeners();
    }
  }
}
