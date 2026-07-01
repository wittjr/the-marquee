import 'package:shared_preferences/shared_preferences.dart';

/// Persists the set of TMDB movie ids the user has chosen to ignore, so they
/// stay hidden from the browse page across sessions. Local-only, not synced to
/// Trakt.
class IgnoreStore {
  static const _key = 'ignored_movie_ids';

  Set<int> _ids = {};

  /// Loads the persisted ids. Call once before reading. Never throws or hangs:
  /// on any failure the ignore list simply starts empty so browsing still works.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 5));
      _ids = (prefs.getStringList(_key) ?? [])
          .map(int.tryParse)
          .whereType<int>()
          .toSet();
    } catch (_) {
      _ids = {};
    }
  }

  bool contains(int tmdbId) => _ids.contains(tmdbId);

  Future<void> add(int tmdbId) async {
    if (!_ids.add(tmdbId)) return;
    await _persist();
  }

  Future<void> remove(int tmdbId) async {
    if (!_ids.remove(tmdbId)) return;
    await _persist();
  }

  /// Best-effort persistence. The in-memory set is already updated by the
  /// caller, so a storage failure only means the choice won't survive a
  /// restart — it never breaks the ignore action itself.
  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 5));
      await prefs.setStringList(_key, _ids.map((e) => e.toString()).toList());
    } catch (_) {
      // Ignore — keeps working in-memory for this session.
    }
  }
}
