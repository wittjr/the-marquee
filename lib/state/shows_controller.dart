import 'package:flutter/foundation.dart';

import '../models/media_item.dart';
import '../models/watchlist_show.dart';
import '../services/concurrency.dart';
import '../services/prefs_cache.dart';
import '../services/show_enricher.dart';
import '../services/tmdb_api.dart';
import '../services/trakt_api.dart';
import 'auth_controller.dart';

enum ShowsState { loading, ready, error }

/// Backs the TV Shows tab: searches Trakt for shows to add to the watchlist,
/// and displays the "Watch Later" list as resumable next-episode cards.
class ShowsController extends ChangeNotifier {
  final TraktApi _trakt;
  final TmdbApi _tmdb;
  late final ShowEnricher _enricher = ShowEnricher(_trakt, _tmdb);

  ShowsController({
    required AuthController auth,
    TraktApi? trakt,
    TmdbApi? tmdb,
  })  : _trakt = trakt ?? TraktApi(auth),
        _tmdb = tmdb ?? TmdbApi();

  static const _watchLaterListName = 'Watch Later';

  /// Persisted snapshot of the built Watch Later list, for an instant render on
  /// tab (re)selection while a fresh copy loads in the background.
  static const _snapshotStore = PrefsCache('watch_later_snapshot_v1');

  ShowsState _state = ShowsState.loading;
  ShowsState get state => _state;

  String? _error;
  String? get error => _error;

  /// True while a background refresh runs over already-visible cached data.
  bool _refreshing = false;
  bool get isRefreshing => _refreshing;

  int? _watchLaterListId;

  List<WatchlistShow> _watchLaterShows = const [];
  List<WatchlistShow> get watchLaterShows => _watchLaterShows;

  /// Trakt ids of shows currently on the user's watchlist, used to render
  /// search results in the correct "on list" state.
  Set<int> _watchlistShowIds = {};

  /// Trakt ids of shows the user has watched, used to flag search results.
  Set<int> _watchedShowIds = {};

  // --- Search state ---
  String _query = '';
  String get query => _query;

  bool _searching = false;
  bool get searching => _searching;

  List<MediaItem> _results = const [];
  List<MediaItem> get results => _results;

  final Set<int> _busyIds = {};
  bool isBusy(MediaItem item) =>
      item.ids.trakt != null && _busyIds.contains(item.ids.trakt);
  bool isShowBusy(WatchlistShow ws) =>
      ws.show.ids.trakt != null && _busyIds.contains(ws.show.ids.trakt);

  bool _isLoading = false;
  bool _restored = false;

  /// Loads the watchlist show ids (for search-result state) and the "Watch
  /// Later" list, enriched with progress + next episode. Re-entrant calls
  /// (e.g. reselecting the tab while a load runs) are ignored.
  ///
  /// On the first load the persisted snapshot is painted immediately and the
  /// network refresh runs in the background (stale-while-revalidate), so
  /// (re)selecting the tab shows the list instantly instead of a blank spinner
  /// while the expensive per-show progress calls run.
  Future<void> load() async {
    if (_isLoading) return;
    _isLoading = true;

    if (!_restored) {
      _restored = true;
      if (_watchLaterShows.isEmpty && await _restoreSnapshot()) {
        _state = ShowsState.ready;
      }
    }
    if (_watchLaterShows.isEmpty) {
      _state = ShowsState.loading;
    } else {
      _refreshing = true; // refreshing over already-visible data
    }
    _error = null;
    notifyListeners();

    try {
      final watchlist = await _trakt.watchlist();
      _watchlistShowIds = watchlist
          .where((e) => e.isShow)
          .map((e) => e.ids.trakt)
          .whereType<int>()
          .toSet();

      // Watched-show ids for the search "Watched" badge. Best-effort.
      try {
        final watched = await _trakt.watchedShows();
        _watchedShowIds =
            watched.map((s) => s.show.ids.trakt).whereType<int>().toSet();
      } catch (_) {
        // Leave whatever we had; search just won't flag watched shows.
      }

      _watchLaterListId = await _trakt.findListId(_watchLaterListName);
      final shows = _watchLaterListId != null
          ? await _trakt.listShows(_watchLaterListId!)
          : <MediaItem>[];

      // Posters/overview from TMDB, then progress + next episode (bounded).
      await pooledForEach(shows, _tmdb.enrich);
      final built = await pooledMap(shows, _enricher.buildShow);
      built.sort((a, b) =>
          a.show.title.toLowerCase().compareTo(b.show.title.toLowerCase()));
      _watchLaterShows = built;

      _state = ShowsState.ready;
      await _saveSnapshot();
    } catch (e) {
      _error = e.toString();
      // Keep showing cached shows if we have any; only surface the error when
      // there's nothing on screen to fall back to.
      if (_watchLaterShows.isEmpty) _state = ShowsState.error;
    } finally {
      _isLoading = false;
      _refreshing = false;
    }
    notifyListeners();
  }

  /// Rehydrates the Watch Later list from the persisted snapshot. Returns true
  /// when it restored something. Never throws.
  Future<bool> _restoreSnapshot() async {
    final data = (await _snapshotStore.read())?.data;
    if (data is! List) return false;
    try {
      _watchLaterShows = data
          .map((e) => WatchlistShow.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
      return _watchLaterShows.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _saveSnapshot() =>
      _snapshotStore.write(_watchLaterShows.map((e) => e.toJson()).toList());

  /// Clears the persisted snapshot (e.g. on sign-out).
  static Future<void> clearSnapshot() => _snapshotStore.clear();

  /// Runs a show search. Empty queries clear the results.
  Future<void> search(String query) async {
    _query = query;
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      _results = const [];
      _searching = false;
      notifyListeners();
      return;
    }

    _searching = true;
    notifyListeners();
    try {
      final results = await _trakt.searchShows(trimmed);
      await pooledForEach(results, _tmdb.enrich);
      for (final r in results) {
        r.onWatchlist =
            r.ids.trakt != null && _watchlistShowIds.contains(r.ids.trakt);
        r.watched =
            r.ids.trakt != null && _watchedShowIds.contains(r.ids.trakt);
      }
      // Guard against an out-of-order response for a stale query.
      if (_query == query) _results = results;
    } catch (_) {
      if (_query == query) _results = const [];
    } finally {
      _searching = false;
      notifyListeners();
    }
  }

  /// Clears the search query and results.
  void clearSearch() {
    _query = '';
    _results = const [];
    _searching = false;
    notifyListeners();
  }

  /// Adds or removes a search result from the watchlist.
  Future<void> toggleWatchlist(MediaItem item) async {
    final id = item.ids.trakt;
    if (id != null) {
      _busyIds.add(id);
      notifyListeners();
    }
    try {
      if (item.onWatchlist) {
        await _trakt.removeFromWatchlist(item);
        item.onWatchlist = false;
        if (id != null) _watchlistShowIds.remove(id);
      } else {
        await _trakt.addToWatchlist(item);
        item.onWatchlist = true;
        if (id != null) _watchlistShowIds.add(id);
      }
    } finally {
      if (id != null) _busyIds.remove(id);
      notifyListeners();
    }
  }

  /// Clears the show's watch history and removes it from the watchlist and the
  /// Watch Later list, then drops it from this tab.
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
      _watchLaterShows = List.of(_watchLaterShows)..remove(ws);
      if (id != null) _watchlistShowIds.remove(id);
    } finally {
      if (id != null) _busyIds.remove(id);
      notifyListeners();
    }
  }

  /// Marks the Watch Later show's next episode watched, then moves it off the
  /// Watch Later list and onto the watchlist (so it resumes on the home page).
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
      if (_watchLaterListId != null) {
        await _trakt.removeShowFromList(_watchLaterListId!, ws.show);
      }
      await _trakt.addToWatchlist(ws.show);
      _watchLaterShows = List.of(_watchLaterShows)..remove(ws);
    } finally {
      if (id != null) _busyIds.remove(id);
      notifyListeners();
    }
  }
}
