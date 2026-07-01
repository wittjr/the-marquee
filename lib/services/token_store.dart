import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/trakt_tokens.dart';

/// Persists Trakt tokens in the platform keychain / keystore.
class TokenStore {
  static const _tokensKey = 'trakt_tokens';
  static const _usernameKey = 'trakt_username';

  final FlutterSecureStorage _storage;

  TokenStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage(
          // The macOS data-protection keychain requires the keychain-access-groups
          // entitlement and a signed build (error -34018 otherwise). We have no
          // signing certs in dev, so use the legacy file-based keychain instead.
          mOptions: MacOsOptions(usesDataProtectionKeychain: false),
        );

  Future<TraktTokens?> readTokens() async {
    final raw = await _storage.read(key: _tokensKey);
    if (raw == null) return null;
    return TraktTokens.fromStorageJson(
        jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> writeTokens(TraktTokens tokens) =>
      _storage.write(key: _tokensKey, value: jsonEncode(tokens.toStorageJson()));

  Future<String?> readUsername() => _storage.read(key: _usernameKey);

  Future<void> writeUsername(String username) =>
      _storage.write(key: _usernameKey, value: username);

  Future<void> clear() async {
    await _storage.delete(key: _tokensKey);
    await _storage.delete(key: _usernameKey);
  }
}
