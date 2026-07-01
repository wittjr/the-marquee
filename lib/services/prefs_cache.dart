import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A tiny best-effort JSON cache over [SharedPreferences] (which is
/// `localStorage` on web / the iOS PWA). Every entry is wrapped with the time it
/// was written so callers can reason about staleness. Nothing here ever throws
/// or hangs: a storage failure just behaves like a cache miss, so the app falls
/// back to the network.
class PrefsCache {
  final String key;
  const PrefsCache(this.key);

  static Future<SharedPreferences> _prefs() =>
      SharedPreferences.getInstance().timeout(const Duration(seconds: 5));

  /// Reads the cached payload plus when it was written, or null on a miss.
  Future<CacheEntry?> read() async {
    try {
      final raw = (await _prefs()).getString(key);
      if (raw == null) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final at = DateTime.tryParse(map['at'] as String? ?? '');
      if (at == null || !map.containsKey('data')) return null;
      return CacheEntry(map['data'], at);
    } catch (_) {
      return null;
    }
  }

  /// Writes [data] (any JSON-encodable value) stamped with the current time.
  Future<void> write(Object? data) async {
    try {
      final payload =
          jsonEncode({'at': DateTime.now().toIso8601String(), 'data': data});
      await (await _prefs()).setString(key, payload);
    } catch (_) {
      // Best-effort; the app keeps working from memory / the network.
    }
  }

  Future<void> clear() async {
    try {
      await (await _prefs()).remove(key);
    } catch (_) {
      // Ignore.
    }
  }
}

/// A decoded cache payload and the time it was stored.
class CacheEntry {
  final dynamic data;
  final DateTime at;
  const CacheEntry(this.data, this.at);

  bool isFresh(Duration ttl) => DateTime.now().difference(at) < ttl;
}
