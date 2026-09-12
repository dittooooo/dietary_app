import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 抽象介面，定義了 Token 的儲存與讀取方法。
abstract class TokenStore {
  /// 讀取 AccessToken。
  Future<String?> readAccessToken();
  
  /// 讀取 RefreshToken。
  Future<String?> readRefreshToken();

  /// 寫入 Token。 
  Future<void> writeAuthTokens({
    required String accessToken,
    required String refreshToken,
    String tokenType = 'Bearer',
    int? accessTokenExpiresInSeconds,
    int? refreshTokenExpiresInSeconds,
  });

  /// 清除 Token。
  Future<void> clear();
}

/// 將驗證密鑰儲存在 Android Keystore / iOS Keychain 中。
class SecureTokenStorage implements TokenStore {
  /// 儲存 AccessToken 的 Key。
  static const String _accessTokenKey = 'jwt_token';
  /// 儲存 RefreshToken 的 Key。
  static const String _refreshTokenKey = 'refresh_token';
  /// 儲存 TokenType 的 Key。
  static const String _tokenTypeKey = 'token_type';
  /// AccessToken 過期時間的 Key。
  static const String _accessTokenExpiresKey = 'access_token_expires_in_seconds';
  /// RefreshToken 過期時間的 Key。
  static const String _refreshTokenExpiresKey = 'refresh_token_expires_in_seconds';

  /// 儲存 Token 的工具。
  final FlutterSecureStorage _storage;

  /// 建構子。
  const SecureTokenStorage({ FlutterSecureStorage storage = const FlutterSecureStorage(), }) : _storage = storage;

  /// 實作 TokenStore 介面，讀取 AccessToken。
  @override
  Future<String?> readAccessToken() => _storage.read(key: _accessTokenKey);

  /// 實作 TokenStore 介面，讀取 RefreshToken。
  @override
  Future<String?> readRefreshToken() => _storage.read(key: _refreshTokenKey);

  /// 實作 TokenStore 介面，寫入 Token。
  @override
  Future<void> writeAuthTokens({
    required String accessToken, required String refreshToken, String tokenType = 'Bearer',
    int? accessTokenExpiresInSeconds, int? refreshTokenExpiresInSeconds,
  }) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
    if (refreshToken.isEmpty) { await _storage.delete(key: _refreshTokenKey);}
    else { await _storage.write(key: _refreshTokenKey, value: refreshToken);}
    await _storage.write(key: _tokenTypeKey, value: tokenType);

    if (accessTokenExpiresInSeconds != null) {
      await _storage.write( key: _accessTokenExpiresKey, value: '$accessTokenExpiresInSeconds' );
    }
    if (refreshTokenExpiresInSeconds != null) {
      await _storage.write( key: _refreshTokenExpiresKey, value: '$refreshTokenExpiresInSeconds' );
    }
  } 

  /// 實作 TokenStore 介面，清除 Token。
  @override
  Future<void> clear() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _tokenTypeKey);
    await _storage.delete(key: _accessTokenExpiresKey);
    await _storage.delete(key: _refreshTokenExpiresKey);
  }

}
