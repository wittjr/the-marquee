/// OAuth tokens returned by Trakt's `/oauth/token` endpoint.
class TraktTokens {
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;

  const TraktTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  /// Treat as expired a minute early to avoid edge-of-window failures.
  bool get isExpired =>
      DateTime.now().isAfter(expiresAt.subtract(const Duration(minutes: 1)));

  factory TraktTokens.fromJson(Map<String, dynamic> json) {
    final createdAt = json['created_at'] != null
        ? DateTime.fromMillisecondsSinceEpoch(
            (json['created_at'] as int) * 1000)
        : DateTime.now();
    final expiresIn = json['expires_in'] as int? ?? 7776000; // 90 days
    return TraktTokens(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      expiresAt: createdAt.add(Duration(seconds: expiresIn)),
    );
  }

  Map<String, dynamic> toStorageJson() => {
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'expires_at': expiresAt.toIso8601String(),
      };

  factory TraktTokens.fromStorageJson(Map<String, dynamic> json) => TraktTokens(
        accessToken: json['access_token'] as String,
        refreshToken: json['refresh_token'] as String,
        expiresAt: DateTime.parse(json['expires_at'] as String),
      );
}
