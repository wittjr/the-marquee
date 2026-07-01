import 'dart:async';

import '../models/media_item.dart';
import 'prefs_cache.dart';

/// Process-wide, persistent cache of TMDB enrichment (poster, overview, genres,
/// runtime, release date) keyed by TMDB id + media type. This is what lets an
/// item enriched on one tab render fully on every other tab — and across app
/// restarts — without re-hitting TMDB. Loaded from disk once, written back
/// debounced so a burst of enrichments becomes a single write. Best-effort: any
/// failure just behaves like a miss and the caller falls back to the network.
class EnrichmentCache {
  EnrichmentCache._();
  static final EnrichmentCache instance = EnrichmentCache._();

  static const _store = PrefsCache('tmdb_enrichment_cache');
  // Movie metadata is essentially immutable; a show's "latest aired episode"
  // shifts weekly, so it's refreshed far more often.
  static const _movieTtl = Duration(days: 30);
  static const _showTtl = Duration(hours: 12);
  static const _maxEntries = 3000;

  final Map<String, Map<String, dynamic>> _entries = {};
  bool _loaded = false;
  Future<void>? _loading;
  Timer? _flush;

  String _key(MediaItem item) => '${item.isMovie ? 'm' : 's'}${item.ids.tmdb}';
  Duration _ttl(MediaItem item) => item.isMovie ? _movieTtl : _showTtl;

  Future<void> _ensureLoaded() => _loaded ? Future.value() : (_loading ??= _load());

  Future<void> _load() async {
    final data = (await _store.read())?.data;
    if (data is Map) {
      data.forEach((k, v) {
        if (v is Map) _entries[k as String] = Map<String, dynamic>.from(v);
      });
    }
    _loaded = true;
  }

  /// If a fresh entry exists for [item], copies its cached fields onto the item
  /// and returns true (the caller can skip the network); otherwise false.
  Future<bool> applyIfFresh(MediaItem item) async {
    if (item.ids.tmdb == null) return false;
    await _ensureLoaded();
    final e = _entries[_key(item)];
    if (e == null) return false;
    final at = DateTime.tryParse(e['at'] as String? ?? '');
    if (at == null || DateTime.now().difference(at) >= _ttl(item)) return false;
    item.overview = e['o'] as String? ?? item.overview;
    item.posterPath = e['p'] as String? ?? item.posterPath;
    final g = (e['g'] as List<dynamic>?)?.cast<String>();
    if (g != null) item.genres = g;
    item.runtime = e['r'] as int? ?? item.runtime;
    item.releaseDate = parseIsoOrNull(e['d']) ?? item.releaseDate;
    item.voteCount = e['v'] as int? ?? item.voteCount;
    return true;
  }

  /// Stores [item]'s freshly-fetched enrichment for reuse elsewhere.
  Future<void> store(MediaItem item) async {
    if (item.ids.tmdb == null) return;
    await _ensureLoaded();
    _entries[_key(item)] = {
      if (item.overview != null) 'o': item.overview,
      if (item.posterPath != null) 'p': item.posterPath,
      if (item.genres.isNotEmpty) 'g': item.genres,
      if (item.runtime != null) 'r': item.runtime,
      if (item.releaseDate != null) 'd': item.releaseDate!.toIso8601String(),
      if (item.voteCount != null) 'v': item.voteCount,
      'at': DateTime.now().toIso8601String(),
    };
    _scheduleFlush();
  }

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
