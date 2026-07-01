import 'package:flutter/foundation.dart';

import '../models/media_item.dart';
import '../models/movie_details.dart';
import '../models/movie_filters.dart';
import '../services/concurrency.dart';
import '../services/filter_store.dart';
import '../services/ignore_store.dart';
import '../services/tmdb_api.dart';
import '../services/trakt_api.dart';
import 'auth_controller.dart';

enum BrowseState { loading, ready, error }

/// Backs the Movies browse page. Loads movie releases starting four weeks
/// before today and extends into the future one month at a time, deduping and
/// hiding anything the user has ignored.
class BrowseController extends ChangeNotifier {
  final TmdbApi _tmdb;
  final TraktApi _trakt;
  final IgnoreStore _ignore;
  final FilterStore _filterStore;

  BrowseController({
    required AuthController auth,
    TmdbApi? tmdb,
    TraktApi? trakt,
    IgnoreStore? ignore,
    FilterStore? filterStore,
  })  : _tmdb = tmdb ?? TmdbApi(),
        _trakt = trakt ?? TraktApi(auth),
        _ignore = ignore ?? IgnoreStore(),
        _filterStore = filterStore ?? FilterStore();

  MovieFilters _filters = const MovieFilters();
  MovieFilters get filters => _filters;

  BrowseState _state = BrowseState.loading;
  BrowseState get state => _state;

  String? _error;
  String? get error => _error;

  bool _loadingMore = false;
  bool get loadingMore => _loadingMore;

  final List<MediaItem> _items = [];
  List<MediaItem> get items => List.unmodifiable(_items);

  // --- Search state ---
  String _query = '';
  String get query => _query;

  bool _searching = false;
  bool get searching => _searching;

  List<MediaItem> _results = const [];
  List<MediaItem> get results => List.unmodifiable(_results);

  final Set<int> _seenIds = {};
  final Set<int> _busyIds = {};

  /// TMDB ids of items already on the user's Trakt watchlist, used to show
  /// discovered movies in their correct watchlist state.
  Set<int> _watchlistTmdbIds = {};

  /// TMDB ids of movies the user has already watched, hidden from the list.
  Set<int> _watchedTmdbIds = {};

  late DateTime _cursor;

  bool isBusy(MediaItem item) =>
      item.ids.tmdb != null && _busyIds.contains(item.ids.tmdb);

  /// Window start: 4 weeks before today, normalized to midnight.
  DateTime get _startDate {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 28));
  }

  Future<void> init() async {
    _filters = await _filterStore.load();
    await _ignore.load();
    await _loadTraktState();
    _cursor = _startDate;
    await _loadWindow(initial: true);
  }

  /// Reloads from the start window.
  Future<void> refresh() async {
    await _ignore.load();
    await _loadTraktState();
    await _restart();
  }

  /// Applies new filters, persists them, and reloads from the start window.
  Future<void> applyFilters(MovieFilters filters) async {
    _filters = filters;
    _filterStore.save(filters);
    await _restart();
  }

  /// Clears loaded results and reloads the first window with current filters.
  Future<void> _restart() async {
    _items.clear();
    _seenIds.clear();
    _state = BrowseState.loading;
    notifyListeners();
    _cursor = _startDate;
    await _loadWindow(initial: true);
  }

  /// Best-effort fetch of the user's watchlist and watched-movie ids. Failures
  /// just leave the previous state (items show as not-on-list / not-watched).
  Future<void> _loadTraktState() async {
    try {
      final watchlist = await _trakt.watchlist();
      _watchlistTmdbIds =
          watchlist.map((e) => e.ids.tmdb).whereType<int>().toSet();
    } catch (_) {
      // Leave whatever we had.
    }
    try {
      _watchedTmdbIds = await _trakt.watchedMovieTmdbIds();
    } catch (_) {
      // Leave whatever we had.
    }
  }

  /// Advances one month into the future and appends the results.
  Future<void> loadMore() async {
    if (_loadingMore || _state == BrowseState.loading) return;
    await _loadWindow();
  }

  Future<void> _loadWindow({bool initial = false}) async {
    if (initial) {
      _state = BrowseState.loading;
    } else {
      _loadingMore = true;
    }
    notifyListeners();

    final from = _cursor;
    final to = DateTime(from.year, from.month + 1, from.day);

    try {
      final results =
          await _tmdb.discoverMovies(from: from, to: to, filters: _filters);
      for (final movie in results) {
        final id = movie.ids.tmdb;
        if (id == null ||
            _seenIds.contains(id) ||
            _ignore.contains(id) ||
            _watchedTmdbIds.contains(id)) {
          continue;
        }
        if (!_passesObscureFilter(movie)) continue;
        movie.onWatchlist = _watchlistTmdbIds.contains(id);
        _seenIds.add(id);
        _items.add(movie);
      }
      _items.sort((a, b) => (a.releaseDate ?? from).compareTo(b.releaseDate ?? from));
      _cursor = to;
      _state = BrowseState.ready;
    } catch (e) {
      _error = e.toString();
      if (initial) _state = BrowseState.error;
    } finally {
      _loadingMore = false;
      notifyListeners();
    }
  }

  /// "Hide obscure" is client-side so it only affects already-released movies;
  /// unreleased movies (which have no votes yet) always pass.
  bool _passesObscureFilter(MediaItem movie) {
    if (!_filters.hideObscure) return true;
    if (!movie.isReleased) return true;
    return (movie.voteCount ?? 0) >= MovieFilters.obscureVoteThreshold;
  }

  /// Fetches full TMDB details for the detail dialog.
  Future<MovieDetails> movieDetails(MediaItem item) {
    final id = item.ids.tmdb;
    if (id == null) {
      throw StateError('“${item.title}” has no TMDB id');
    }
    return _tmdb.movieDetails(id);
  }

  /// Marks [item] watched on Trakt and drops it from the browse list.
  Future<void> markWatched(MediaItem item) async {
    final id = item.ids.tmdb;
    if (id != null) {
      _busyIds.add(id);
      notifyListeners();
    }
    try {
      await _trakt.markWatched(item);
      _items.remove(item);
      if (id != null) {
        _watchlistTmdbIds.remove(id);
        _watchedTmdbIds.add(id); // keep it hidden from future windows
      }
    } finally {
      if (id != null) _busyIds.remove(id);
      notifyListeners();
    }
  }

  /// Hides [item] locally and persists the choice so it stays hidden.
  Future<void> ignore(MediaItem item) async {
    final id = item.ids.tmdb;
    _items.remove(item);
    notifyListeners();
    if (id != null) await _ignore.add(id);
  }

  /// Adds or removes [item] from the Trakt watchlist. Rethrows on error.
  Future<void> toggleWatchlist(MediaItem item) async {
    final id = item.ids.tmdb;
    if (id != null) {
      _busyIds.add(id);
      notifyListeners();
    }
    try {
      if (item.onWatchlist) {
        await _trakt.removeFromWatchlist(item);
        item.onWatchlist = false;
        if (id != null) _watchlistTmdbIds.remove(id);
      } else {
        await _trakt.addToWatchlist(item);
        item.onWatchlist = true;
        if (id != null) _watchlistTmdbIds.add(id);
      }
    } finally {
      if (id != null) _busyIds.remove(id);
      notifyListeners();
    }
  }

  /// Searches Trakt for movies. Empty queries clear the results. Results are
  /// flagged with their watchlist/watched state for correct rendering.
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
      final results = await _trakt.searchMovies(trimmed);
      await pooledForEach(results, _tmdb.enrich);
      for (final r in results) {
        final id = r.ids.tmdb;
        r.onWatchlist = id != null && _watchlistTmdbIds.contains(id);
        r.watched = id != null && _watchedTmdbIds.contains(id);
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
}
