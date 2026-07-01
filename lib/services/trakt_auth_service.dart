import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/trakt_tokens.dart';

/// Drives Trakt's OAuth 2.0 authorization-code flow from inside the app.
///
/// Trakt does not support PKCE, so the client secret is bundled and used for
/// the code/refresh exchanges. The redirect uses a custom URL scheme that must
/// be registered both in the app (Info.plist / AndroidManifest) and in the
/// Trakt application settings.
class TraktAuthService {
  final http.Client _client;

  TraktAuthService([http.Client? client]) : _client = client ?? http.Client();

  /// Redirect URI for the OAuth flow. On native this is the custom URL scheme;
  /// on web it must be an http(s) page on the app's own origin (auth.html).
  String get _redirectUri =>
      kIsWeb ? '${Uri.base.origin}/auth.html' : AppConfig.redirectUri;

  /// When no client secret is bundled, the secret-bearing OAuth calls are
  /// routed through the serverless proxy instead of straight to Trakt.
  bool get _useProxy => AppConfig.traktClientSecret.isEmpty;

  String get _proxyUrl {
    if (AppConfig.authProxyUrl.isNotEmpty) return AppConfig.authProxyUrl;
    if (kIsWeb) return '${Uri.base.origin}/.netlify/functions/trakt-auth';
    throw const TraktAuthException(
        'No client secret and no AUTH_PROXY_URL configured.');
  }

  /// Opens the system browser for Trakt sign-in and returns fresh tokens.
  Future<TraktTokens> signIn() async {
    final authUrl = Uri.parse('${AppConfig.traktSiteBase}/oauth/authorize')
        .replace(queryParameters: {
      'response_type': 'code',
      'client_id': AppConfig.traktClientId,
      'redirect_uri': _redirectUri,
    });

    final result = await FlutterWebAuth2.authenticate(
      url: authUrl.toString(),
      callbackUrlScheme: AppConfig.redirectScheme,
    );

    final code = Uri.parse(result).queryParameters['code'];
    if (code == null) {
      throw const TraktAuthException('No authorization code returned by Trakt.');
    }
    return _exchange({
      'code': code,
      'grant_type': 'authorization_code',
      'redirect_uri': _redirectUri,
    });
  }

  /// Exchanges a refresh token for a new access token.
  Future<TraktTokens> refresh(String refreshToken) => _exchange({
        'refresh_token': refreshToken,
        'grant_type': 'refresh_token',
        'redirect_uri': _redirectUri,
      });

  /// Best-effort revocation of an access token on the server.
  Future<void> revoke(String accessToken) async {
    if (_useProxy) {
      await _client.post(
        Uri.parse(_proxyUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'revoke', 'token': accessToken}),
      );
      return;
    }
    await _client.post(
      Uri.parse('${AppConfig.traktApiBase}/oauth/revoke'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'token': accessToken,
        'client_id': AppConfig.traktClientId,
        'client_secret': AppConfig.traktClientSecret,
      }),
    );
  }

  Future<TraktTokens> _exchange(Map<String, String> extra) async {
    // Via the proxy the function injects the client id + secret; directly we
    // include them ourselves.
    final Uri url = _useProxy
        ? Uri.parse(_proxyUrl)
        : Uri.parse('${AppConfig.traktApiBase}/oauth/token');
    final Map<String, dynamic> payload = _useProxy
        ? {...extra}
        : {
            'client_id': AppConfig.traktClientId,
            'client_secret': AppConfig.traktClientSecret,
            ...extra,
          };

    final res = await _client.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (res.statusCode != 200) {
      throw TraktAuthException(
          'Token exchange failed (${res.statusCode}): ${res.body}');
    }
    return TraktTokens.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }
}

class TraktAuthException implements Exception {
  final String message;
  const TraktAuthException(this.message);
  @override
  String toString() => 'TraktAuthException: $message';
}
