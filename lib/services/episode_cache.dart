import 'dart:async';

import '../models/media_item.dart';
import '../models/watchlist_show.dart';
import 'prefs_cache.dart';

/// Process-wide, persistent cache of a show season's episode list from TMDB
/// (episode number, title, still, air date, overview), keyed by TMDB id +
/// season number. This is what lets the show detail dialog list the remaining
/// episodes without re-hitting TMDB every time it opens — across tabs and app
/// restarts. Watched *progress* is never cached here (it comes live from Trakt);
/// only the stable episode metadata is.
///
/// Loaded from disk once, written back debounced. Best-effort: any failure just
/// behaves like a miss and the caller falls back to the network.
class EpisodeCache {
  EpisodeCache._();
  static final EpisodeCache instance = EpisodeCache._();

  static const _store = PrefsCache('tmdb_season_episodes_cache');

  // A finished season's episodes never change, so it's cached for a long time;
  // a still-airing season keeps firming up (new stills, air dates) so it's
  // refreshed far more often. "Finished" = its latest episode aired a while ago.
  static const _airingTtl = Duration(hours: 12);
  static const _finishedTtl = Duration(days: 30);
  static const _finishedAfter = Duration(days: 30);
  static const _maxEntries = 1500;

  final Map<String, Map<String, dynamic>> _entries = {};
  bool _loaded = false;
  Future<void>? _loading;
  Timer? _flush;

  String _key(int tmdbId, int season) => '$tmdbId:$season';

  Future<void> _ensureLoaded() =>
      _loaded ? Future.value() : (_loading ??= _load());

  Future<void> _load() async {
    final data = (await _store.read())?.data;
    if (data is Map) {
      data.forEach((k, v) {
        if (v is Map) _entries[k as String] = Map<String, dynamic>.from(v);
      });
    }
    _loaded = true;
  }

  /// Returns the cached episode list for a season if present and still fresh,
  /// otherwise null (a miss — the caller should fetch).
  Future<List<TmdbEpisode>?> get(int tmdbId, int season) async {
    await _ensureLoaded();
    final e = _entries[_key(tmdbId, season)];
    if (e == null) return null;
    final at = DateTime.tryParse(e['at'] as String? ?? '');
    if (at == null) return null;
    final eps = _decode(e['eps']);
    if (DateTime.now().difference(at) >= _ttlFor(eps)) return null;
    return eps;
  }

  /// Stores a freshly-fetched season episode list for reuse.
  Future<void> put(int tmdbId, int season, List<TmdbEpisode> eps) async {
    if (eps.isEmpty) return; // don't cache an empty/failed fetch
    await _ensureLoaded();
    _entries[_key(tmdbId, season)] = {
      'eps': [for (final ep in eps) _encode(ep)],
      'at': DateTime.now().toIso8601String(),
    };
    _scheduleFlush();
  }

  /// A season whose most recent episode aired more than [_finishedAfter] ago is
  /// treated as done (long TTL); anything still airing gets the short TTL.
  Duration _ttlFor(List<TmdbEpisode> eps) {
    DateTime? latest;
    for (final ep in eps) {
      final d = ep.airDate;
      if (d != null && (latest == null || d.isAfter(latest))) latest = d;
    }
    if (latest == null) return _airingTtl;
    return DateTime.now().difference(latest) > _finishedAfter
        ? _finishedTtl
        : _airingTtl;
  }

  static Map<String, dynamic> _encode(TmdbEpisode ep) => {
        'n': ep.number,
        if (ep.name != null) 't': ep.name,
        if (ep.stillPath != null) 's': ep.stillPath,
        if (ep.airDate != null) 'a': ep.airDate!.toIso8601String(),
        if (ep.overview != null) 'o': ep.overview,
      };

  static List<TmdbEpisode> _decode(Object? raw) => [
        for (final e in (raw as List?) ?? const [])
          if (e is Map)
            TmdbEpisode(
              number: e['n'] as int? ?? 0,
              name: e['t'] as String?,
              stillPath: e['s'] as String?,
              airDate: parseIsoOrNull(e['a']),
              overview: e['o'] as String?,
            ),
      ];

  void _scheduleFlush() {
    _flush?.cancel();
    _flush = Timer(const Duration(milliseconds: 500), _persist);
  }

  Future<void> _persist() async {
    _prune();
    await _store.write(_entries);
  }

  /// Evicts the oldest entries when the cache outgrows its cap (localStorage is
  /// small on the iOS PWA).
  void _prune() {
    if (_entries.length <= _maxEntries) return;
    final keys = _entries.keys.toList()
      ..sort((a, b) => (_entries[a]!['at'] as String? ?? '')
          .compareTo(_entries[b]!['at'] as String? ?? ''));
    for (final k in keys.take(_entries.length - _maxEntries)) {
      _entries.remove(k);
    }
  }

  Future<void> clear() async {
    _flush?.cancel();
    _entries.clear();
    _loaded = true; // nothing left to load after an explicit clear
    await _store.clear();
  }
}
