import 'dart:convert';

/// A snapshot of Trakt's `X-Ratelimit` response header, sent on every API call.
///
/// The header is a JSON object, e.g.
/// `{"name":"AUTHED_API_GET_LIMIT","period":300,"limit":1000,"remaining":875,
///   "until":"2020-10-10T00:24:00Z"}` — where [remaining] is the live call
/// budget and [until] is when the window resets.
class TraktRateLimit {
  /// The rate-limit bucket this snapshot describes, e.g.
  /// `AUTHED_API_GET_LIMIT`. `estimate` marks a locally-counted value rather
  /// than one Trakt reported.
  final String name;

  /// Total calls allowed in the current window.
  final int limit;

  /// Calls left before throttling kicks in.
  final int remaining;

  /// Length of the rate-limit window, in seconds.
  final int period;

  /// When the current window resets (UTC).
  final DateTime until;

  const TraktRateLimit({
    required this.name,
    required this.limit,
    required this.remaining,
    required this.period,
    required this.until,
  });

  /// Whether this snapshot describes the GET-request budget (the one the app's
  /// browsing exhausts), as opposed to a write bucket like `AUTHED_API_POST_LIMIT`.
  bool get isGetBucket => name.toUpperCase().contains('GET');

  /// Parses the raw `X-Ratelimit` header value, or null if absent/malformed.
  static TraktRateLimit? parse(String? header) {
    if (header == null || header.isEmpty) return null;
    try {
      final m = jsonDecode(header) as Map<String, dynamic>;
      final until = DateTime.tryParse(m['until'] as String? ?? '');
      if (until == null) return null;
      return TraktRateLimit(
        name: m['name'] as String? ?? '',
        limit: m['limit'] as int? ?? 0,
        remaining: m['remaining'] as int? ?? 0,
        period: m['period'] as int? ?? 0,
        until: until,
      );
    } catch (_) {
      return null;
    }
  }

  /// Time left until the window resets, clamped to zero once it's elapsed.
  Duration get timeToReset {
    final d = until.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }
}
