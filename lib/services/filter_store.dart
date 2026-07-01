import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/movie_filters.dart';

/// Persists the user's Movies-page filters so they survive view switches and
/// app restarts. Never throws — a storage failure just yields default filters.
class FilterStore {
  static const _key = 'movie_filters';

  Future<MovieFilters> load() async {
    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 5));
      final raw = prefs.getString(_key);
      if (raw == null) return const MovieFilters();
      return MovieFilters.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const MovieFilters();
    }
  }

  Future<void> save(MovieFilters filters) async {
    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 5));
      await prefs.setString(_key, jsonEncode(filters.toJson()));
    } catch (_) {
      // Best-effort; in-memory filters still apply this session.
    }
  }
}
