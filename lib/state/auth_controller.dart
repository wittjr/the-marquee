import 'package:flutter/foundation.dart';

import '../models/trakt_tokens.dart';
import '../services/enrichment_cache.dart';
import '../services/token_store.dart';
import '../services/trakt_api.dart';
import '../services/trakt_auth_service.dart';
import 'library_controller.dart';
import 'show_watchlist_controller.dart';
import 'watchlist_movies_controller.dart';

enum AuthStatus { unknown, signedOut, signedIn }

/// Single source of truth for authentication. Holds the current tokens, hands
/// out a guaranteed-valid access token (refreshing transparently), and exposes
/// sign-in / sign-out for the UI.
class AuthController extends ChangeNotifier {
  final TraktAuthService _authService;
  final TokenStore _store;

  AuthController({TraktAuthService? authService, TokenStore? store})
      : _authService = authService ?? TraktAuthService(),
        _store = store ?? TokenStore();

  AuthStatus _status = AuthStatus.unknown;
  AuthStatus get status => _status;

  TraktTokens? _tokens;
  String? _username;
  String? get username => _username;

  String? _error;
  String? get error => _error;

  bool _busy = false;
  bool get busy => _busy;

  /// Loads any persisted session on startup.
  Future<void> bootstrap() async {
    _tokens = await _store.readTokens();
    _username = await _store.readUsername();
    _setStatus(_tokens != null ? AuthStatus.signedIn : AuthStatus.signedOut);
  }

  Future<void> signIn() async {
    _setBusy(true);
    _error = null;
    try {
      final tokens = await _authService.signIn();
      _tokens = tokens;
      await _store.writeTokens(tokens);
      _setStatus(AuthStatus.signedIn);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    } finally {
      _setBusy(false);
    }
  }

  Future<void> signOut() async {
    final token = _tokens?.accessToken;
    _tokens = null;
    _username = null;
    // Drop every cached trace of this account: in-memory lists, the persisted
    // home / watchlist snapshots, and the shared TMDB enrichment cache.
    TraktApi.clearCaches();
    await Future.wait([
      LibraryController.clearSnapshot(),
      WatchlistMoviesController.clearSnapshot(),
      ShowWatchlistController.clearSnapshot(),
      EnrichmentCache.instance.clear(),
    ]);
    await _store.clear();
    _setStatus(AuthStatus.signedOut);
    if (token != null) {
      // Fire-and-forget; local sign-out already happened.
      _authService.revoke(token).ignore();
    }
  }

  /// Returns a valid access token, refreshing if the current one is expired.
  /// Throws if there is no session.
  Future<String> validAccessToken() async {
    final tokens = _tokens;
    if (tokens == null) {
      throw StateError('Not signed in');
    }
    if (!tokens.isExpired) return tokens.accessToken;

    final refreshed = await _authService.refresh(tokens.refreshToken);
    _tokens = refreshed;
    await _store.writeTokens(refreshed);
    return refreshed.accessToken;
  }

  /// Records the resolved username (from Trakt settings) for later API calls.
  Future<void> setUsername(String username) async {
    if (_username == username) return;
    _username = username;
    await _store.writeUsername(username);
    notifyListeners();
  }

  void _setStatus(AuthStatus status) {
    _status = status;
    notifyListeners();
  }

  void _setBusy(bool value) {
    _busy = value;
    notifyListeners();
  }
}
