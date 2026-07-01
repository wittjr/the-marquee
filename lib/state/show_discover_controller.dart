import 'package:flutter/foundation.dart';

import '../models/media_item.dart';
import '../services/concurrency.dart';
import '../services/tmdb_api.dart';
import '../services/trakt_api.dart';
import 'auth_controller.dart';

enum ShowDiscoverState { loading, ready, error }

/// Backs the TV segment of the Discover tab: searches Trakt for shows to add to
/// the watchlist, and — when there's no active search — shows Trending and
/// Coming Soon (most-anticipated) discovery rows. Watchlist membership is
/// tracked so cards render in the correct "on list" state.
class ShowDiscoverController extends ChangeNotifier {
  final TraktApi _trakt;
  final TmdbApi _tmdb;

  ShowDiscoverController({
    required AuthController auth,
    TraktApi? trakt,
    TmdbApi? tmdb,
  })  : _trakt = trakt ?? TraktApi(auth),
        _tmdb = tmdb ?? TmdbApi();

  ShowDiscoverState _state = ShowDiscoverState.loading;
  ShowDiscoverState get state => _state;

  String? _error;
  String? get error => _error;

  List<MediaItem> _trending = const [];
  List<MediaItem> get trending => _trending;

  List<MediaItem> _anticipated = const [];
  List<MediaItem> get anticipated => _anticipated;

  /// Trakt ids of shows on the user's watchlist, for search/discovery card state.
  Set<int> _watchlistShowIds = {};

  /// Trakt ids of shows the user has watched, to flag discovery cards.
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

  bool _isLoading = false;

  /// Loads watchlist/watched membership (for card state) and the Trending +
  /// Coming Soon discovery rows. Re-entrant calls are ignored. Keeps any
  /// already-loaded rows visible if a refresh fails.
  Future<void> load() async {
    if (_isLoading) return;
    _isLoading = true;
    if (_trending.isEmpty && _anticipated.isEmpty) {
      _state = ShowDiscoverState.loading;
    }
    _error = null;
    notifyListeners();

    try {
      await _refreshMembership();

      final trending = await _trakt.trendingShows();
      final anticipated = await _trakt.anticipatedShows();
      await pooledForEach([...trending, ...anticipated], _tmdb.enrich);
      _flag(trending);
      _flag(anticipated);
      _trending = trending;
      _anticipated = anticipated;

      _state = ShowDiscoverState.ready;
    } catch (e) {
      _error = e.toString();
      if (_trending.isEmpty && _anticipated.isEmpty) {
        _state = ShowDiscoverState.error;
      }
    } finally {
      _isLoading = false;
    }
    notifyListeners();
  }

  /// Refreshes the watchlist/watched id sets used for card state. Best-effort:
  /// leaves whatever we had on failure so cards just miss a badge.
  Future<void> _refreshMembership() async {
    final watchlist = await _trakt.watchlist();
    _watchlistShowIds = watchlist
        .where((e) => e.isShow)
        .map((e) => e.ids.trakt)
        .whereType<int>()
        .toSet();
    try {
      final watched = await _trakt.watchedShows();
      _watchedShowIds =
          watched.map((s) => s.show.ids.trakt).whereType<int>().toSet();
    } catch (_) {
      // Leave the previous set; discovery cards just won't flag watched shows.
    }
  }

  /// Stamps watchlist/watched state onto a batch of shows.
  void _flag(List<MediaItem> shows) {
    for (final s in shows) {
      s.onWatchlist =
          s.ids.trakt != null && _watchlistShowIds.contains(s.ids.trakt);
      s.watched = s.ids.trakt != null && _watchedShowIds.contains(s.ids.trakt);
    }
  }

  /// Runs a show search. Empty queries clear the results (revealing the
  /// discovery rows again).
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
      _flag(results);
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

  /// Adds or removes a show from the watchlist, updating every visible copy
  /// (search results and both discovery rows may hold the same show).
  Future<void> toggleWatchlist(MediaItem item) async {
    final id = item.ids.trakt;
    if (id != null) {
      _busyIds.add(id);
      notifyListeners();
    }
    try {
      if (item.onWatchlist) {
        await _trakt.removeFromWatchlist(item);
        if (id != null) _watchlistShowIds.remove(id);
      } else {
        await _trakt.addToWatchlist(item);
        if (id != null) _watchlistShowIds.add(id);
      }
      if (id != null) _syncFlag(id);
    } finally {
      if (id != null) _busyIds.remove(id);
      notifyListeners();
    }
  }

  /// Reflects the current watchlist membership of [traktId] onto every visible
  /// copy of that show.
  void _syncFlag(int traktId) {
    final onList = _watchlistShowIds.contains(traktId);
    for (final list in [_results, _trending, _anticipated]) {
      for (final s in list) {
        if (s.ids.trakt == traktId) s.onWatchlist = onList;
      }
    }
  }
}
