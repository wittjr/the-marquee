import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/media_item.dart';
import '../models/movie_details.dart';
import '../models/movie_filters.dart';
import '../models/show_details.dart';
import '../models/trakt_ids.dart';
import '../models/watchlist_show.dart';
import 'enrichment_cache.dart';
import 'episode_cache.dart';

/// Read-only TMDB client used to enrich Trakt items with posters, overviews,
/// genres, runtime and a meaningful release date.
///
/// When a TMDB token is bundled it talks to TMDB directly with a bearer header;
/// when it isn't (production web), it routes through a same-origin serverless
/// proxy that injects the token server-side. Image URLs are always direct (the
/// TMDB image CDN needs no token).
class TmdbApi {
  final http.Client _client;

  TmdbApi([http.Client? client]) : _client = client ?? http.Client();

  /// Route through the proxy when no token is bundled in the client.
  bool get _useProxy => AppConfig.tmdbReadToken.isEmpty;

  /// API base, with a `/3`-style path layout in both modes (proxy strips the
  /// `/api/tmdb` prefix and forwards to `api.themoviedb.org/3`).
  String get _base {
    if (!_useProxy) return AppConfig.tmdbApiBase;
    if (AppConfig.tmdbProxyUrl.isNotEmpty) return AppConfig.tmdbProxyUrl;
    if (kIsWeb) return '${Uri.base.origin}/api/tmdb';
    throw StateError('No TMDB token and no TMDB_PROXY_URL configured.');
  }

  Map<String, String> get _headers => _useProxy
      ? const {'Content-Type': 'application/json'}
      : {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${AppConfig.tmdbReadToken}',
        };

  /// Discovers US theatrical/limited movie releases between [from] and [to]
  /// (inclusive), ordered by release date. Pages through results up to
  /// [maxPages] so a month-sized window is fully covered.
  Future<List<MediaItem>> discoverMovies({
    required DateTime from,
    required DateTime to,
    MovieFilters filters = const MovieFilters(),
    int maxPages = 5,
  }) async {
    final results = <MediaItem>[];
    var page = 1;
    var totalPages = 1;

    while (page <= totalPages && page <= maxPages) {
      final params = <String, String>{
        'language': 'en-US',
        'region': 'US',
        'sort_by': 'release_date.asc',
        'certification_country': 'US',
        'include_adult': 'false',
        'include_video': 'false',
        'with_release_type': '2|3', // limited + theatrical
        'with_original_language': 'en',
        'release_date.gte': _ymd(from),
        'release_date.lte': _ymd(to),
        'page': '$page',
      };
      if (filters.genreIds.isNotEmpty) {
        params['with_genres'] = filters.genreIds.join('|'); // OR
      }
      if (filters.excludedGenreIds.isNotEmpty) {
        // Excludes any movie matching one of these genres.
        params['without_genres'] = filters.excludedGenreIds.join('|');
      }
      if (filters.minRuntime > 0) {
        params['with_runtime.gte'] = '${filters.minRuntime}';
      }
      if (filters.maxRuntime < MovieFilters.maxRuntimeCap) {
        params['with_runtime.lte'] = '${filters.maxRuntime}';
      }

      final uri = Uri.parse('$_base/discover/movie')
          .replace(queryParameters: params);

      final res = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        throw Exception('TMDB discover failed (${res.statusCode})');
      }

      final json = jsonDecode(res.body) as Map<String, dynamic>;
      totalPages = json['total_pages'] as int? ?? 1;
      final list = json['results'] as List<dynamic>? ?? const [];
      for (final r in list) {
        results.add(_movieFromDiscover(r as Map<String, dynamic>));
      }
      page++;
    }
    return results;
  }

  /// Metadata for a single episode (title, still image, air date). Returns null
  /// on any failure so it never breaks show loading.
  Future<TmdbEpisode?> episodeDetails(
      int showTmdbId, int season, int number) async {
    try {
      final uri = Uri.parse(
              '$_base/tv/$showTmdbId/season/$season/episode/$number')
          .replace(queryParameters: {'language': 'en-US'});
      final res = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return null;
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      return TmdbEpisode(
        name: j['name'] as String?,
        stillPath: j['still_path'] as String?,
        airDate: _parseDate(j['air_date'] as String?),
        overview: j['overview'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  /// All episodes of a season (number, title, still, air date). Served from the
  /// persistent [EpisodeCache] when fresh, so re-opening the detail dialog costs
  /// no network. Returns an empty list on any failure so it never breaks the
  /// detail view.
  Future<List<TmdbEpisode>> seasonEpisodes(int showTmdbId, int season) async {
    final cached = await EpisodeCache.instance.get(showTmdbId, season);
    if (cached != null) return cached;
    try {
      final uri = Uri.parse('$_base/tv/$showTmdbId/season/$season')
          .replace(queryParameters: {'language': 'en-US'});
      final res = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return const [];
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final eps = (j['episodes'] as List<dynamic>?) ?? const [];
      final list = [
        for (final e in eps.cast<Map<String, dynamic>>())
          TmdbEpisode(
            number: e['episode_number'] as int? ?? 0,
            name: e['name'] as String?,
            stillPath: e['still_path'] as String?,
            airDate: _parseDate(e['air_date'] as String?),
            overview: e['overview'] as String?,
          ),
      ];
      await EpisodeCache.instance.put(showTmdbId, season, list);
      return list;
    } catch (_) {
      return const [];
    }
  }

  /// Full details for the movie detail dialog: overview, cast, runtime,
  /// genres, certification, etc.
  Future<MovieDetails> movieDetails(int tmdbId) async {
    final uri = Uri.parse('$_base/movie/$tmdbId').replace(
      queryParameters: {
        'language': 'en-US',
        'append_to_response': 'credits,release_dates',
      },
    );
    final res = await _client
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw Exception('TMDB movie details failed (${res.statusCode})');
    }
    return MovieDetails.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Full details for the show detail dialog: overview, cast, creators, genres,
  /// season/episode counts, status, etc.
  Future<ShowDetails> showDetails(int tmdbId) async {
    final uri = Uri.parse('$_base/tv/$tmdbId').replace(
      queryParameters: {
        'language': 'en-US',
        'append_to_response': 'credits',
      },
    );
    final res = await _client
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw Exception('TMDB show details failed (${res.statusCode})');
    }
    return ShowDetails.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  MediaItem _movieFromDiscover(Map<String, dynamic> r) {
    final releaseDate = _parseDate(r['release_date'] as String?);
    return MediaItem(
      type: MediaType.movie,
      title: r['title'] as String? ?? 'Untitled',
      ids: TraktIds(tmdb: r['id'] as int?),
      year: releaseDate?.year,
      overview: r['overview'] as String?,
      posterPath: r['poster_path'] as String?,
      releaseDate: releaseDate,
      voteCount: r['vote_count'] as int?,
    );
  }

  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Enriches [item] in place. Silently no-ops if the item lacks a TMDB id or
  /// the lookup fails, so one bad item never breaks the whole list.
  Future<void> enrich(MediaItem item) async {
    final tmdbId = item.ids.tmdb;
    if (tmdbId == null) return;

    // Reuse enrichment cached from any tab/session before hitting the network.
    if (await EnrichmentCache.instance.applyIfFresh(item)) return;

    try {
      if (item.isMovie) {
        await _enrichMovie(item, tmdbId);
      } else {
        await _enrichShow(item, tmdbId);
      }
      await EnrichmentCache.instance.store(item);
    } catch (_) {
      // Leave the item with whatever Trakt data it already has.
    }
  }

  Future<void> _enrichMovie(MediaItem item, int id) async {
    final res = await _client.get(
      Uri.parse(
          '$_base/movie/$id?append_to_response=release_dates'),
      headers: _headers,
    );
    if (res.statusCode != 200) return;
    final json = jsonDecode(res.body) as Map<String, dynamic>;

    _applyCommon(item, json);
    item.runtime = json['runtime'] as int?;
    item.releaseDate = _bestMovieReleaseDate(json) ??
        _parseDate(json['release_date'] as String?);
  }

  Future<void> _enrichShow(MediaItem item, int id) async {
    final res = await _client.get(
      Uri.parse('$_base/tv/$id'),
      headers: _headers,
    );
    if (res.statusCode != 200) return;
    final json = jsonDecode(res.body) as Map<String, dynamic>;

    _applyCommon(item, json);
    final runtimes = json['episode_run_time'] as List<dynamic>?;
    item.runtime =
        (runtimes != null && runtimes.isNotEmpty) ? runtimes.first as int? : null;

    // Sort shows by their most recently aired episode; fall back to the first
    // air date for shows that haven't aired yet.
    final lastEp = json['last_episode_to_air'] as Map<String, dynamic>?;
    item.releaseDate = _parseDate(lastEp?['air_date'] as String?) ??
        _parseDate(json['first_air_date'] as String?) ??
        _parseDate(
            (json['next_episode_to_air'] as Map<String, dynamic>?)?['air_date']
                as String?);
    item.status = json['status'] as String?;
  }

  void _applyCommon(MediaItem item, Map<String, dynamic> json) {
    item.overview = json['overview'] as String?;
    item.posterPath = json['poster_path'] as String?;
    final genres = json['genres'] as List<dynamic>?;
    item.genres = genres
            ?.map((g) => (g as Map<String, dynamic>)['name'] as String)
            .toList() ??
        const [];
  }

  /// Mirrors the PWA's preference: US theatrical, then limited, then digital.
  DateTime? _bestMovieReleaseDate(Map<String, dynamic> json) {
    final results =
        (json['release_dates'] as Map<String, dynamic>?)?['results']
            as List<dynamic>?;
    if (results == null) return null;

    final us = results.firstWhere(
      (r) => (r as Map<String, dynamic>)['iso_3166_1'] == 'US',
      orElse: () => null,
    );
    if (us == null) return null;

    final dates = (us as Map<String, dynamic>)['release_dates'] as List<dynamic>;
    DateTime? byType(int type) {
      for (final d in dates) {
        if ((d as Map<String, dynamic>)['type'] == type) {
          return _parseDate(d['release_date'] as String?);
        }
      }
      return null;
    }

    return byType(3) ?? byType(2) ?? byType(4);
  }

  DateTime? _parseDate(String? value) {
    if (value == null || value.isEmpty) return null;
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return null;
    // TMDB release dates are calendar dates: the release_dates endpoint wraps
    // them in a midnight-UTC timestamp (e.g. "2026-07-01T00:00:00.000Z"). Keep
    // the date exactly as written and represent it as local midnight, so
    // "released yet?" checks compare against the user's own day rather than a
    // UTC instant (which would flip a next-day release to "released" for anyone
    // behind UTC). The getters read components in the parsed value's own zone,
    // so this preserves 7/1 as 7/1 without shifting it across timezones.
    return DateTime(parsed.year, parsed.month, parsed.day);
  }
}
