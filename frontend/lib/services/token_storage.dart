import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class TokenStore {
  Future<String?> readAccessToken();

  Future<String?> readRefreshToken();

  Future<void> writeAuthTokens({
    required String accessToken,
    required String refreshToken,
    String tokenType = 'Bearer',
    int? accessTokenExpiresInSeconds,
    int? refreshTokenExpiresInSeconds,
  });

  Future<void> clear();
}

/// Stores authentication secrets in Android Keystore / iOS Keychain.
class SecureTokenStorage implements TokenStore {
  static const String accessTokenKey = 'jwt_token';
  static const String refreshTokenKey = 'refresh_token';
  static const String tokenTypeKey = 'token_type';
  static const String accessTokenExpiresKey = 'access_token_expires_in_seconds';
  static const String refreshTokenExpiresKey =
      'refresh_token_expires_in_seconds';

  final FlutterSecureStorage _storage;

  const SecureTokenStorage({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  @override
  Future<String?> readAccessToken() => _storage.read(key: accessTokenKey);

  @override
  Future<String?> readRefreshToken() => _storage.read(key: refreshTokenKey);

  Future<String?> readTokenType() => _storage.read(key: tokenTypeKey);

  @override
  Future<void> writeAuthTokens({
    required String accessToken,
    required String refreshToken,
    String tokenType = 'Bearer',
    int? accessTokenExpiresInSeconds,
    int? refreshTokenExpiresInSeconds,
  }) async {
    await _storage.write(key: accessTokenKey, value: accessToken);
    if (refreshToken.isEmpty) {
      await _storage.delete(key: refreshTokenKey);
    } else {
      await _storage.write(key: refreshTokenKey, value: refreshToken);
    }
    await _storage.write(key: tokenTypeKey, value: tokenType);

    if (accessTokenExpiresInSeconds != null) {
      await _storage.write(
        key: accessTokenExpiresKey,
        value: '$accessTokenExpiresInSeconds',
      );
    }
    if (refreshTokenExpiresInSeconds != null) {
      await _storage.write(
        key: refreshTokenExpiresKey,
        value: '$refreshTokenExpiresInSeconds',
      );
    }
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: accessTokenKey);
    await _storage.delete(key: refreshTokenKey);
    await _storage.delete(key: tokenTypeKey);
    await _storage.delete(key: accessTokenExpiresKey);
    await _storage.delete(key: refreshTokenExpiresKey);
  }

  /// Migrates tokens created by older builds from SharedPreferences once.
  Future<void> migrateLegacyTokens() async {
    final prefs = await SharedPreferences.getInstance();
    final secureAccessToken = await readAccessToken();
    final secureRefreshToken = await readRefreshToken();

    final legacyAccessToken = prefs.getString(accessTokenKey);
    final legacyRefreshToken = prefs.getString(refreshTokenKey);
    final legacyTokenType = prefs.getString(tokenTypeKey) ?? 'Bearer';
    final legacyAccessExpiry = prefs.getInt(accessTokenExpiresKey);
    final legacyRefreshExpiry = prefs.getInt(refreshTokenExpiresKey);

    if ((secureAccessToken == null || secureAccessToken.isEmpty) &&
        legacyAccessToken != null &&
        legacyAccessToken.isNotEmpty) {
      await writeAuthTokens(
        accessToken: legacyAccessToken,
        refreshToken: legacyRefreshToken ?? secureRefreshToken ?? '',
        tokenType: legacyTokenType,
        accessTokenExpiresInSeconds: legacyAccessExpiry,
        refreshTokenExpiresInSeconds: legacyRefreshExpiry,
      );
    } else if ((secureRefreshToken == null || secureRefreshToken.isEmpty) &&
        legacyRefreshToken != null &&
        legacyRefreshToken.isNotEmpty) {
      await _storage.write(key: refreshTokenKey, value: legacyRefreshToken);
    }

    // Remove secrets from the old unencrypted store, whether or not migration
    // was needed. The next app start will use only secure storage.
    await prefs.remove(accessTokenKey);
    await prefs.remove(refreshTokenKey);
    await prefs.remove(tokenTypeKey);
    await prefs.remove(accessTokenExpiresKey);
    await prefs.remove(refreshTokenExpiresKey);
  }
}
