import 'package:flutter/foundation.dart';

import '../models/media_item.dart';
import '../services/concurrency.dart';
import '../services/prefs_cache.dart';
import '../services/tmdb_api.dart';
import '../services/trakt_api.dart';
import 'auth_controller.dart';

enum WatchlistLoadState { loading, ready, error }

/// Backs the Watchlist tab: the user's *entire* movie watchlist (no date
/// window, unlike the home dashboard), enriched with TMDB metadata and sorted
/// by release date, oldest first.
class WatchlistMoviesController extends ChangeNotifier {
  final TraktApi _trakt;
  final TmdbApi _tmdb;

  WatchlistMoviesController({
    required AuthController auth,
    TraktApi? trakt,
    TmdbApi? tmdb,
  })  : _trakt = trakt ?? TraktApi(auth),
        _tmdb = tmdb ?? TmdbApi();

  /// Persisted snapshot of the last-built list, for an instant cold-start
  /// render while a fresh copy loads in the background.
  static const _snapshotStore = PrefsCache('watchlist_movies_snapshot_v1');

  WatchlistLoadState _state = WatchlistLoadState.loading;
  WatchlistLoadState get state => _state;

  String? _error;
  String? get error => _error;

  List<MediaItem> _movies = const [];
  List<MediaItem> get movies => _movies;

  bool get isEmpty => _movies.isEmpty;

  /// True while a background refresh runs over already-visible cached data.
  bool _refreshing = false;
  bool get isRefreshing => _refreshing;

  bool _loading = false;
  bool _restored = false;

  /// Loads the full watchlist, keeps the movies, enriches them, and sorts them
  /// oldest release first. Re-entrant calls are ignored (the page reloads on
  /// tab selection). Existing results stay on screen while refreshing; the
  /// spinner only shows on the first load.
  Future<void> load() async {
    if (_loading) return;
    _loading = true;

    // On the first load, paint the persisted snapshot immediately, then refresh
    // in the background (stale-while-revalidate).
    if (!_restored) {
      _restored = true;
      if (_movies.isEmpty && await _restoreSnapshot()) {
        _state = WatchlistLoadState.ready;
      }
    }
    if (_movies.isEmpty) {
      _state = WatchlistLoadState.loading;
    } else {
      _refreshing = true;
    }
    notifyListeners();

    try {
      final items = await _trakt.watchlist();
      final movies = items.where((e) => e.isMovie).toList();
      // Bounded concurrency; per-item enrichment failures are swallowed inside.
      await pooledForEach(movies, _tmdb.enrich);
      movies.sort(_byReleaseAscending);
      _movies = movies;
      _state = WatchlistLoadState.ready;
      _error = null;
      await _saveSnapshot();
    } catch (e) {
      _error = e.toString();
      if (_movies.isEmpty) _state = WatchlistLoadState.error;
    } finally {
      _loading = false;
      _refreshing = false;
      notifyListeners();
    }
  }

  /// Rehydrates the list from the persisted snapshot. Returns true when it
  /// restored something. Never throws.
  Future<bool> _restoreSnapshot() async {
    final data = (await _snapshotStore.read())?.data;
    if (data is! List) return false;
    try {
      _movies = data
          .map((e) => MediaItem.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
      return _movies.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _saveSnapshot() =>
      _snapshotStore.write(_movies.map((e) => e.toJson()).toList());

  /// Clears the persisted snapshot (e.g. on sign-out).
  static Future<void> clearSnapshot() => _snapshotStore.clear();

  /// Oldest release first; movies with no known release date sink to the bottom,
  /// ordered by title.
  int _byReleaseAscending(MediaItem a, MediaItem b) {
    final da = a.releaseDate;
    final db = b.releaseDate;
    if (da == null && db == null) {
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    }
    if (da == null) return 1;
    if (db == null) return -1;
    return da.compareTo(db);
  }

  // --- Per-item mutations ---

  final Set<int> _busyIds = {};

  bool isBusy(MediaItem item) =>
      item.ids.trakt != null && _busyIds.contains(item.ids.trakt);

  /// Marks [item] watched on Trakt and drops it from the list.
  Future<void> markWatched(MediaItem item) =>
      _mutate(item, () => _trakt.markWatched(item));

  /// Removes [item] from the Trakt watchlist and from the list.
  Future<void> removeFromWatchlist(MediaItem item) =>
      _mutate(item, () => _trakt.removeFromWatchlist(item));

  Future<void> _mutate(MediaItem item, Future<void> Function() action) async {
    final id = item.ids.trakt;
    if (id != null) {
      _busyIds.add(id);
      notifyListeners();
    }
    try {
      await action();
      _movies = List.of(_movies)..remove(item);
    } finally {
      if (id != null) _busyIds.remove(id);
      notifyListeners();
    }
  }
}
