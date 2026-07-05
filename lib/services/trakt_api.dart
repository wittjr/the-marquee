import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/media_item.dart';
import '../models/trakt_ids.dart';
import '../models/trakt_profile.dart';
import '../models/watchlist_show.dart';
import '../state/auth_controller.dart';

/// Authenticated client for the Trakt REST API. Pulls a valid access token from
/// [AuthController] on each call (which refreshes transparently when needed).
class TraktApi {
  final AuthController _auth;
  final http.Client _client;

  TraktApi(this._auth, [http.Client? client])
      : _client = client ?? http.Client();

  // --- Short-lived shared cache for the two membership-list endpoints, so
  // switching tabs (each with its own controller/TraktApi) doesn't refetch
  // them. Static so it's shared across instances; invalidated on writes. The
  // expensive per-show progress calls are deliberately NOT cached.
  static const _cacheTtl = Duration(seconds: 90);
  static List<MediaItem>? _watchlistCache;
  static DateTime? _watchlistCacheAt;
  static List<WatchedShow>? _watchedShowsCache;
  static DateTime? _watchedShowsCacheAt;

  static bool _fresh(DateTime? at) =>
      at != null && DateTime.now().difference(at) < _cacheTtl;

  static List<MediaItem>? get _cachedWatchlist =>
      _fresh(_watchlistCacheAt) ? _watchlistCache : null;
  static List<WatchedShow>? get _cachedWatchedShows =>
      _fresh(_watchedShowsCacheAt) ? _watchedShowsCache : null;

  static void _invalidateWatchlist() {
    _watchlistCache = null;
    _watchlistCacheAt = null;
  }

  static void _invalidateWatchedShows() {
    _watchedShowsCache = null;
    _watchedShowsCacheAt = null;
  }

  /// Clears all cached membership lists (e.g. on sign-out).
  static void clearCaches() {
    _invalidateWatchlist();
    _invalidateWatchedShows();
  }

  Future<Map<String, String>> _headers() async => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${await _auth.validAccessToken()}',
        'trakt-api-version': AppConfig.traktApiVersion,
        'trakt-api-key': AppConfig.traktClientId,
      };

  /// The signed-in user's full watchlist (movies + shows). The Trakt watchlist
  /// is paginated, so we page through all results rather than returning only
  /// the first page. Cached briefly (see [_cacheTtl]) and shared across pages
  /// so switching tabs doesn't refetch it; invalidated on watchlist writes.
  Future<List<MediaItem>> watchlist() async {
    final cached = _cachedWatchlist;
    if (cached != null) return cached;

    final items = <MediaItem>[];
    var page = 1;
    var pageCount = 1;

    do {
      final uri = Uri.parse('${AppConfig.traktApiBase}/sync/watchlist')
          .replace(queryParameters: {'page': '$page', 'limit': '100'});
      final res = await _client.get(uri, headers: await _headers());
      if (res.statusCode != 200) {
        throw TraktApiException('watchlist', res.statusCode, res.body);
      }

      final list = jsonDecode(res.body) as List<dynamic>;
      items.addAll(list.map((e) =>
          MediaItem.fromTraktEntry(e as Map<String, dynamic>)
            ..onWatchlist = true));

      // Header is absent if the endpoint returned everything unpaginated.
      pageCount =
          int.tryParse(res.headers['x-pagination-page-count'] ?? '1') ?? 1;
      page++;
    } while (page <= pageCount);

    _watchlistCache = items;
    _watchlistCacheAt = DateTime.now();
    return items;
  }

  /// TMDB ids of every movie the user has watched (full watched set, not the
  /// paginated history). Used to hide watched movies from the browse list.
  Future<Set<int>> watchedMovieTmdbIds() async {
    final res = await _client.get(
      Uri.parse('${AppConfig.traktApiBase}/sync/watched/movies'),
      headers: await _headers(),
    );
    if (res.statusCode != 200) {
      throw TraktApiException('watched', res.statusCode, res.body);
    }
    final list = jsonDecode(res.body) as List<dynamic>;
    final ids = <int>{};
    for (final e in list) {
      final movie = (e as Map<String, dynamic>)['movie'] as Map<String, dynamic>?;
      final tmdb = (movie?['ids'] as Map<String, dynamic>?)?['tmdb'] as int?;
      if (tmdb != null) ids.add(tmdb);
    }
    return ids;
  }

  /// Watched progress for a show, including the next episode to watch.
  Future<ShowProgress> showProgress(MediaItem show) async {
    final id = show.ids.trakt ?? show.ids.slug;
    if (id == null) return const ShowProgress();

    final uri = Uri.parse('${AppConfig.traktApiBase}/shows/$id/progress/watched')
        .replace(queryParameters: {'hidden': 'false', 'specials': 'false'});
    final res = await _client.get(uri, headers: await _headers());
    if (res.statusCode != 200) {
      throw TraktApiException('progress', res.statusCode, res.body);
    }

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final next = json['next_episode'] as Map<String, dynamic>?;
    return ShowProgress(
      completed: json['completed'] as int? ?? 0,
      aired: json['aired'] as int? ?? 0,
      lastWatchedAt:
          DateTime.tryParse(json['last_watched_at'] as String? ?? ''),
      nextEpisode: next == null
          ? null
          : RawNextEpisode(
              season: next['season'] as int? ?? 0,
              number: next['number'] as int? ?? 0,
              title: next['title'] as String?,
              traktId: (next['ids'] as Map<String, dynamic>?)?['trakt'] as int?,
            ),
    );
  }

  /// Per-season watched progress from the same `progress/watched` endpoint as
  /// [showProgress], but keeping the full season/episode breakdown so callers
  /// can list the episodes still left to watch. Excludes specials.
  Future<List<SeasonProgress>> seasonProgress(MediaItem show) async {
    final id = show.ids.trakt ?? show.ids.slug;
    if (id == null) return const [];

    final uri = Uri.parse('${AppConfig.traktApiBase}/shows/$id/progress/watched')
        .replace(queryParameters: {'hidden': 'false', 'specials': 'false'});
    final res = await _client.get(uri, headers: await _headers());
    if (res.statusCode != 200) {
      throw TraktApiException('progress', res.statusCode, res.body);
    }

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final seasons = (json['seasons'] as List<dynamic>?) ?? const [];
    return [
      for (final s in seasons.cast<Map<String, dynamic>>())
        if ((s['number'] as int? ?? 0) != 0)
          SeasonProgress(
            number: s['number'] as int? ?? 0,
            aired: s['aired'] as int? ?? 0,
            completed: s['completed'] as int? ?? 0,
            watchedNumbers: {
              for (final e in (s['episodes'] as List<dynamic>? ?? const [])
                  .cast<Map<String, dynamic>>())
                if (e['completed'] == true) e['number'] as int? ?? 0,
            },
          ),
    ];
  }

  /// Marks a show's episode watched by show id + season/number (works whether
  /// or not we have the episode's own Trakt id).
  Future<void> markEpisodeWatched(
      MediaItem show, int season, int number) async {
    final showId = show.ids.trakt ?? show.ids.slug;
    if (showId == null) {
      throw TraktApiException('history', 0, 'Show "${show.title}" has no id');
    }
    final res = await _client.post(
      Uri.parse('${AppConfig.traktApiBase}/sync/history'),
      headers: await _headers(),
      body: jsonEncode({
        'shows': [
          {
            'ids': show.ids.trakt != null
                ? {'trakt': show.ids.trakt}
                : {'slug': show.ids.slug},
            'seasons': [
              {
                'number': season,
                'episodes': [
                  {
                    'number': number,
                    'watched_at': DateTime.now().toUtc().toIso8601String(),
                  }
                ]
              }
            ]
          }
        ]
      }),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw TraktApiException('history', res.statusCode, res.body);
    }
    _invalidateWatchedShows();
  }

  /// Every show the user has watched, each with when it was last watched plus
  /// watched/aired episode counts (so callers can tell which are in progress
  /// without a per-show request). Cached briefly and shared across pages;
  /// invalidated when watch history changes.
  Future<List<WatchedShow>> watchedShows() async {
    final cached = _cachedWatchedShows;
    if (cached != null) return cached;

    // This endpoint is paginated (100/page). We must page through every page —
    // otherwise watched shows beyond the first 100 silently vanish from the
    // library (an in-progress show that's slipped past page 1 would never be
    // discovered). extended=full gives each show's aired_episodes; combined
    // with the row-level `plays` count it lets callers cheaply pre-filter to
    // in-progress shows (see [WatchedShow.inProgress]) without a per-show
    // progress call. Note: this endpoint no longer returns a per-season watched
    // breakdown, so `plays` is the only watched-volume signal here.
    final shows = <WatchedShow>[];
    var page = 1;
    var pageCount = 1;
    do {
      final uri = Uri.parse('${AppConfig.traktApiBase}/users/me/watched/shows')
          .replace(queryParameters: {
        'extended': 'full',
        'page': '$page',
        'limit': '100',
      });
      final res = await _client.get(uri, headers: await _headers());
      if (res.statusCode != 200) {
        throw TraktApiException('watched-shows', res.statusCode, res.body);
      }
      pageCount =
          int.tryParse(res.headers['x-pagination-page-count'] ?? '') ?? 1;

      for (final row in jsonDecode(res.body) as List<dynamic>) {
        final map = row as Map<String, dynamic>;
        final show = map['show'] as Map<String, dynamic>?;
        if (show == null) continue;

        shows.add(WatchedShow(
          MediaItem(
            type: MediaType.show,
            title: show['title'] as String? ?? 'Untitled',
            year: show['year'] as int?,
            ids: TraktIds.fromJson(
                show['ids'] as Map<String, dynamic>? ?? const {}),
          ),
          DateTime.tryParse(map['last_watched_at'] as String? ?? ''),
          plays: map['plays'] as int? ?? 0,
          airedEpisodes: show['aired_episodes'] as int? ?? 0,
        ));
      }
      page++;
    } while (page <= pageCount);

    _watchedShowsCache = shows;
    _watchedShowsCacheAt = DateTime.now();
    return shows;
  }

  /// Finds one of the user's personal lists by (case-insensitive) name and
  /// returns its Trakt id, or null if no list with that name exists.
  Future<int?> findListId(String name) async {
    final res = await _client.get(
      Uri.parse('${AppConfig.traktApiBase}/users/me/lists'),
      headers: await _headers(),
    );
    if (res.statusCode != 200) {
      throw TraktApiException('lists', res.statusCode, res.body);
    }
    final list = jsonDecode(res.body) as List<dynamic>;
    for (final e in list) {
      final m = e as Map<String, dynamic>;
      if ((m['name'] as String?)?.toLowerCase() == name.toLowerCase()) {
        return (m['ids'] as Map<String, dynamic>?)?['trakt'] as int?;
      }
    }
    return null;
  }

  /// Every show on the given personal list.
  Future<List<MediaItem>> listShows(int listId) async {
    final res = await _client.get(
      Uri.parse('${AppConfig.traktApiBase}/users/me/lists/$listId/items/shows'),
      headers: await _headers(),
    );
    if (res.statusCode != 200) {
      throw TraktApiException('list-items', res.statusCode, res.body);
    }
    final list = jsonDecode(res.body) as List<dynamic>;
    return list
        .where((e) => (e as Map<String, dynamic>)['show'] != null)
        .map((e) => MediaItem.fromTraktEntry(e as Map<String, dynamic>))
        .toList();
  }

  /// Trakt ids of every show on the given personal list.
  Future<Set<int>> listShowTraktIds(int listId) async {
    final shows = await listShows(listId);
    return shows.map((s) => s.ids.trakt).whereType<int>().toSet();
  }

  /// Searches Trakt for shows matching [query], best matches first.
  Future<List<MediaItem>> searchShows(String query) =>
      _search('show', query);

  /// Searches Trakt for movies matching [query], best matches first.
  Future<List<MediaItem>> searchMovies(String query) =>
      _search('movie', query);

  /// The most-watched shows on Trakt right now. Each entry wraps the show in a
  /// `show` key (alongside a `watchers` count), which [MediaItem.fromTraktEntry]
  /// already unwraps.
  Future<List<MediaItem>> trendingShows({int limit = 30}) =>
      _showList('trending', limit);

  /// The most-anticipated upcoming shows on Trakt. Entries wrap the show in a
  /// `show` key (alongside a `list_count`).
  Future<List<MediaItem>> anticipatedShows({int limit = 30}) =>
      _showList('anticipated', limit);

  /// Fetches a Trakt show discovery list ('trending' or 'anticipated').
  Future<List<MediaItem>> _showList(String kind, int limit) async {
    final uri = Uri.parse('${AppConfig.traktApiBase}/shows/$kind')
        .replace(queryParameters: {'limit': '$limit'});
    final res = await _client.get(uri, headers: await _headers());
    if (res.statusCode != 200) {
      throw TraktApiException('shows-$kind', res.statusCode, res.body);
    }
    final list = jsonDecode(res.body) as List<dynamic>;
    return list
        .where((e) => (e as Map<String, dynamic>)['show'] != null)
        .map((e) => MediaItem.fromTraktEntry(e as Map<String, dynamic>))
        .toList();
  }

  /// Searches a single Trakt media [type] ('show' or 'movie') for [query].
  Future<List<MediaItem>> _search(String type, String query) async {
    final uri = Uri.parse('${AppConfig.traktApiBase}/search/$type')
        .replace(queryParameters: {'query': query, 'limit': '30'});
    final res = await _client.get(uri, headers: await _headers());
    if (res.statusCode != 200) {
      throw TraktApiException('search', res.statusCode, res.body);
    }
    final list = jsonDecode(res.body) as List<dynamic>;
    return list
        .where((e) => (e as Map<String, dynamic>)[type] != null)
        .map((e) => MediaItem.fromTraktEntry(e as Map<String, dynamic>))
        .toList();
  }

  /// Adds a show to the given personal list.
  Future<void> addShowToList(int listId, MediaItem show) =>
      _listItems('add', listId, show);

  /// Removes a show from the given personal list. A no-op on Trakt's side if
  /// the show isn't on the list.
  Future<void> removeShowFromList(int listId, MediaItem show) =>
      _listItems('remove', listId, show);

  /// Adds or removes a show on a personal list. [op] is 'add' or 'remove'.
  Future<void> _listItems(String op, int listId, MediaItem show) async {
    final ids = <String, dynamic>{};
    if (show.ids.trakt != null) {
      ids['trakt'] = show.ids.trakt;
    } else if (show.ids.slug != null) {
      ids['slug'] = show.ids.slug;
    } else {
      throw TraktApiException('list-$op', 0, 'Show "${show.title}" has no id');
    }
    final path = op == 'remove'
        ? '/users/me/lists/$listId/items/remove'
        : '/users/me/lists/$listId/items';
    final res = await _client.post(
      Uri.parse('${AppConfig.traktApiBase}$path'),
      headers: await _headers(),
      body: jsonEncode({
        'shows': [
          {'ids': ids}
        ]
      }),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw TraktApiException('list-$op', res.statusCode, res.body);
    }
  }

  /// Removes all of a show's episodes from the user's watch history (clearing
  /// its watched progress).
  Future<void> removeShowFromHistory(MediaItem show) =>
      _sync('/sync/history/remove', show);

  /// Marks an item watched (adds it to the user's Trakt history).
  Future<void> markWatched(MediaItem item) => _sync(
        '/sync/history',
        item,
        watchedAt: DateTime.now().toUtc().toIso8601String(),
      );

  /// Adds an item to the user's watchlist.
  Future<void> addToWatchlist(MediaItem item) =>
      _sync('/sync/watchlist', item);

  /// Removes an item from the user's watchlist.
  Future<void> removeFromWatchlist(MediaItem item) =>
      _sync('/sync/watchlist/remove', item);

  /// Posts a single item to a Trakt `/sync/*` endpoint, keyed by the best
  /// available id and nested under `movies` or `shows` per its type.
  Future<void> _sync(String path, MediaItem item, {String? watchedAt}) async {
    final ids = <String, dynamic>{};
    if (item.ids.trakt != null) {
      ids['trakt'] = item.ids.trakt;
    } else if (item.ids.imdb != null) {
      ids['imdb'] = item.ids.imdb;
    } else if (item.ids.tmdb != null) {
      ids['tmdb'] = item.ids.tmdb;
    } else {
      throw TraktApiException(path, 0, 'Item "${item.title}" has no usable id');
    }

    final entry = <String, dynamic>{'ids': ids};
    if (watchedAt != null) entry['watched_at'] = watchedAt;
    final body = item.isMovie ? {'movies': [entry]} : {'shows': [entry]};

    final res = await _client.post(
      Uri.parse('${AppConfig.traktApiBase}$path'),
      headers: await _headers(),
      body: jsonEncode(body),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw TraktApiException(path, res.statusCode, res.body);
    }
    // Keep the shared caches in sync with the write we just made.
    if (path.startsWith('/sync/watchlist')) _invalidateWatchlist();
    if (path.startsWith('/sync/history')) {
      _invalidateWatchedShows();
      _invalidateWatchlist(); // watched movies are hidden from the watchlist view
    }
  }

  /// User settings — used to resolve and cache the account username.
  Future<String> fetchUsername() async {
    final json = await _getSettings();
    return (json['user'] as Map<String, dynamic>)['username'] as String;
  }

  /// The signed-in user's full profile.
  Future<TraktUser> userProfile() async =>
      TraktUser.fromSettings(await _getSettings());

  Future<Map<String, dynamic>> _getSettings() async {
    final res = await _client.get(
      Uri.parse('${AppConfig.traktApiBase}/users/settings'),
      headers: await _headers(),
    );
    if (res.statusCode != 200) {
      throw TraktApiException('settings', res.statusCode, res.body);
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// The user's Plex connection status. Best-effort: any failure (including a
  /// non-200, meaning not connected) yields a "not connected" status rather
  /// than throwing. The response shape is parsed defensively.
  Future<PlexStatus> plexStatus() async {
    try {
      final res = await _client.get(
        Uri.parse('${AppConfig.traktApiBase}/users/settings/plex'),
        headers: await _headers(),
      );
      if (res.statusCode != 200) return const PlexStatus(connected: false);

      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) {
        return PlexStatus(connected: decoded != null);
      }
      // Details may be nested under a "plex" key or sit at the top level.
      final node = (decoded['plex'] as Map<String, dynamic>?) ?? decoded;
      return PlexStatus(
        connected: (node['connected'] as bool?) ?? node.isNotEmpty,
        username: (node['username'] ?? node['user'] ?? node['title']) as String?,
        connectedAt:
            DateTime.tryParse(node['connected_at'] as String? ?? ''),
      );
    } catch (_) {
      return const PlexStatus(connected: false);
    }
  }

  /// Aggregate watch statistics for the signed-in user.
  Future<TraktStats> userStats() async {
    final res = await _client.get(
      Uri.parse('${AppConfig.traktApiBase}/users/me/stats'),
      headers: await _headers(),
    );
    if (res.statusCode != 200) {
      throw TraktApiException('stats', res.statusCode, res.body);
    }
    return TraktStats.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Recent watch history (movies + episodes), most recent first.
  Future<List<HistoryItem>> history({int limit = 40}) async {
    final uri = Uri.parse('${AppConfig.traktApiBase}/sync/history')
        .replace(queryParameters: {'limit': '$limit'});
    final res = await _client.get(uri, headers: await _headers());
    if (res.statusCode != 200) {
      throw TraktApiException('history', res.statusCode, res.body);
    }
    final list = jsonDecode(res.body) as List<dynamic>;
    return list
        .map((e) => HistoryItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

class TraktApiException implements Exception {
  final String endpoint;
  final int statusCode;
  final String body;
  const TraktApiException(this.endpoint, this.statusCode, this.body);
  @override
  String toString() =>
      'TraktApiException($endpoint): HTTP $statusCode — $body';
}
