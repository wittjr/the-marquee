import 'package:flutter/foundation.dart' show kIsWeb;

/// Static configuration for the app.
///
/// Secrets (Trakt client id/secret, TMDB token) are injected at build time via
/// `--dart-define-from-file=config/dev.json`. They are never committed.
class AppConfig {
  AppConfig._();

  // --- Secrets (compile-time) ---
  static const String traktClientId = String.fromEnvironment('TRAKT_ID');
  static const String traktClientSecret = String.fromEnvironment('TRAKT_SECRET');
  static const String tmdbReadToken = String.fromEnvironment('TMDB_READ_TOKEN');

  /// Optional URL of the serverless OAuth proxy (Netlify function). When the
  /// client secret is omitted from the build, the app routes token exchange
  /// through this instead. On web it defaults to a same-origin function path,
  /// so this only needs setting for a non-web build without a bundled secret.
  static const String authProxyUrl = String.fromEnvironment('AUTH_PROXY_URL');

  /// Optional base URL of the serverless TMDB proxy. When the TMDB token is
  /// omitted from the build, TMDB calls route through this (the proxy injects
  /// the token). On web it defaults to a same-origin path.
  static const String tmdbProxyUrl = String.fromEnvironment('TMDB_PROXY_URL');

  // --- OAuth redirect ---
  // The scheme below must be registered as a redirect URI in your Trakt app
  // settings at https://trakt.tv/oauth/applications
  static const String redirectScheme = 'themarquee';
  static const String redirectUri = '$redirectScheme://oauth/callback';

  // --- Endpoints ---
  static const String traktApiBase = 'https://api.trakt.tv';
  static const String traktSiteBase = 'https://trakt.tv';
  static const String tmdbApiBase = 'https://api.themoviedb.org/3';
  static const String tmdbImageBase = 'https://image.tmdb.org/t/p';

  static const String traktApiVersion = '2';

  /// The client needs a client id, plus a way to do the secret-bearing token
  /// exchange: either a bundled secret, an explicit proxy URL, or (on web) the
  /// default same-origin proxy function.
  static bool get isConfigured =>
      traktClientId.isNotEmpty &&
      (traktClientSecret.isNotEmpty || authProxyUrl.isNotEmpty || kIsWeb);
}
