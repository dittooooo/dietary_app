import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../config/api_config.dart';
import '../services/auth_service.dart';
import '../services/token_storage.dart';
import '../views/auth/login_page.dart';

class ApiClient {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
  static final http.Client _defaultHttpClient = http.Client();

  final http.Client _httpClient;
  final TokenStore _tokenStore;
  Future<bool>? _refreshInFlight;

  ApiClient({http.Client? httpClient, TokenStore? tokenStore})
    : _httpClient = httpClient ?? _defaultHttpClient,
      _tokenStore = tokenStore ?? const SecureTokenStorage();

  /// Keeps the in-memory token aligned with secure storage after an
  /// account switch. Without this, a request made immediately after login or
  /// registration can still be authenticated as the previous account.
  static void setLatestAccessToken(String token) {
    _latestAccessToken = token;
  }

  static void clearLatestAccessToken() {
    _latestAccessToken = null;
  }

  MediaType _resolveMediaType(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.png')) return MediaType('image', 'png');
    if (lower.endsWith('.webp')) return MediaType('image', 'webp');
    if (lower.endsWith('.gif')) return MediaType('image', 'gif');
    return MediaType('image', 'jpeg');
  }

  Uri _resolveUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Uri.parse(path);
    }
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final base = normalizedPath.startsWith('/dietary-agent/')
        ? ApiConfig.serverBaseUrl
        : ApiConfig.baseUrl;
    return Uri.parse('$base$normalizedPath');
  }

  Future<http.Response> post(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
  }) async {
    final url = _resolveUrl(path);
    return _sendWithRefresh(
      path: path,
      send: (resolvedHeaders) => _httpClient.post(
        url,
        headers: resolvedHeaders,
        body: jsonEncode(body),
      ),
      headers: headers,
      contentType: 'application/json',
    );
  }

  Future<http.Response> get(String path, {Map<String, String>? headers}) async {
    final url = _resolveUrl(path);
    return _sendWithRefresh(
      path: path,
      send: (resolvedHeaders) => _httpClient.get(url, headers: resolvedHeaders),
      headers: headers,
      contentType: 'application/json',
    );
  }

  Future<http.Response> put(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
  }) async {
    final url = _resolveUrl(path);
    return _sendWithRefresh(
      path: path,
      send: (resolvedHeaders) => _httpClient.put(
        url,
        headers: resolvedHeaders,
        body: jsonEncode(body),
      ),
      headers: headers,
      contentType: 'application/json',
    );
  }

  Future<http.Response> multipart(
    String path,
    List<int> fileBytes,
    String filename, {
    Map<String, String>? headers,
  }) async {
    final url = _resolveUrl(path);
    return _sendWithRefresh(
      path: path,
      send: (resolvedHeaders) async {
        final request = http.MultipartRequest('POST', url);
        request.headers.addAll(resolvedHeaders);
        request.files.add(
          http.MultipartFile.fromBytes(
            'file',
            fileBytes,
            filename: filename,
            contentType: _resolveMediaType(filename),
          ),
        );
        final streamedResponse = await _httpClient.send(request);
        return http.Response.fromStream(streamedResponse);
      },
      headers: headers,
    );
  }

  Future<http.Response> delete(
    String path, {
    Map<String, String>? headers,
  }) async {
    final url = _resolveUrl(path);
    return _sendWithRefresh(
      path: path,
      send: (resolvedHeaders) =>
          _httpClient.delete(url, headers: resolvedHeaders),
      headers: headers,
      contentType: 'application/json',
    );
  }

  Future<http.Response> _sendWithRefresh({
    required String path,
    required Future<http.Response> Function(Map<String, String>) send,
    Map<String, String>? headers,
    String? contentType,
  }) async {
    var resolvedHeaders = <String, String>{
      if (contentType != null) 'Content-Type': contentType,
      ...?headers,
    };

    if (!_isPublicEndpoint(path)) {
      await _attachLatestAccessToken(resolvedHeaders);
    }

    var response = await send(resolvedHeaders);
    _logResponse(path, response);

    if (_shouldAttemptRefresh(path, response.statusCode)) {
      final refreshed = await _refreshAccessToken();
      if (refreshed) {
        resolvedHeaders = <String, String>{
          if (contentType != null) 'Content-Type': contentType,
          ...?headers,
        };
        if (!_isPublicEndpoint(path)) {
          // 刷新成功後必須覆蓋原本的 Authorization，避免重試仍使用過期 Token。
          await _attachLatestAccessToken(resolvedHeaders, force: true);
        }
        response = await send(resolvedHeaders);
        _logResponse('$path (retried)', response);
      }
    }

    _checkResponse(response);
    return response;
  }

  bool _isPublicEndpoint(String path) {
    const publicPaths = <String>{'/login', '/register', '/refresh'};
    return publicPaths.contains(path);
  }

  Future<void> _attachLatestAccessToken(
    Map<String, String> headers, {
    bool force = false,
  }) async {
    final existingAuth = headers['Authorization'];
    if (!force &&
        existingAuth != null &&
        existingAuth.startsWith('Bearer ') &&
        existingAuth.length > 10) {
      return;
    }

    // SecureTokenStorage is the source of truth for the signed-in account.
    // Do not prefer the process-wide cache here: it can belong to a previous
    // user after logout/login or registration within the same app process.
    String? token;
    try {
      token = await _tokenStore.readAccessToken();
      if (token != null && token.isNotEmpty) {
        _latestAccessToken = token;
      }
    } catch (_) {}
    token ??= _latestAccessToken;

    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
  }

  bool _shouldAttemptRefresh(String path, int statusCode) {
    if (statusCode != 401 && statusCode != 403) {
      return false;
    }

    const excludedPaths = <String>{'/login', '/register', '/refresh'};
    return !excludedPaths.contains(path);
  }

  Future<bool> _refreshAccessToken() async {
    final existingRefresh = _refreshInFlight;
    if (existingRefresh != null) {
      return existingRefresh;
    }

    final refreshFuture = _performRefreshAccessToken();
    _refreshInFlight = refreshFuture;
    return refreshFuture.whenComplete(() {
      if (identical(_refreshInFlight, refreshFuture)) {
        _refreshInFlight = null;
      }
    });
  }

  Future<bool> _performRefreshAccessToken() async {
    final refreshToken = await _tokenStore.readRefreshToken();

    if (refreshToken != null && refreshToken.isNotEmpty) {
      try {
        final response = await _httpClient.post(
          Uri.parse('${ApiConfig.baseUrl}/refresh'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'refreshToken': refreshToken}),
        );

        if (response.statusCode == 200) {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) {
            final accessToken = decoded['accessToken']?.toString() ?? '';
            final newRefreshToken =
                decoded['refreshToken']?.toString() ?? refreshToken;

            if (accessToken.isNotEmpty) {
              await _tokenStore.writeAuthTokens(
                accessToken: accessToken,
                refreshToken: newRefreshToken,
                tokenType: decoded['tokenType']?.toString() ?? 'Bearer',
                accessTokenExpiresInSeconds: _asInt(
                  decoded['accessTokenExpiresInSeconds'],
                ),
                refreshTokenExpiresInSeconds: _asInt(
                  decoded['refreshTokenExpiresInSeconds'],
                ),
              );

              _latestAccessToken = accessToken;
              return true;
            }
          }
        }
      } catch (_) {}
    }

    return false;
  }

  void _logResponse(String path, http.Response response) {
    debugPrint('API $path -> ${response.statusCode}');
  }

  void _checkResponse(http.Response response) {
    if (response.statusCode == 401 || response.statusCode == 403) {
      final requestUrlStr = response.request?.url.toString() ?? '';
      // MAF/Companion 的對話錯誤由對話流程自行處理，不觸發全域登出彈窗
      if (requestUrlStr.contains(':3000') ||
          requestUrlStr.contains(':3001') ||
          requestUrlStr.contains('/companion/') ||
          requestUrlStr.contains('/maf/')) {
        return;
      }

      final context = navigatorKey.currentContext;
      if (context == null) {
        return;
      }

      final requestUrl = response.request?.url.path ?? '';
      final isLogin = requestUrl.contains('/login');

      Future.delayed(Duration.zero, () async {
        if (response.statusCode == 401 && !isLogin) {
          await AuthService().clearSession();
        }

        if (!context.mounted) {
          return;
        }

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: Text(
              isLogin
                  ? '登入失敗'
                  : (response.statusCode == 403 ? '權限不足' : '登入已失效'),
            ),
            content: Text(
              isLogin
                  ? '帳號或密碼錯誤，請重新確認。'
                  : (response.statusCode == 403
                        ? '你目前沒有權限執行這個操作。'
                        : '登入狀態已過期，請重新登入。'),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  if (!isLogin) {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(
                        builder: (context) => const LoginPage(),
                      ),
                      (route) => false,
                    );
                  }
                },
                child: const Text('確定'),
              ),
            ],
          ),
        );
      });
    }
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? 0;
  }
}

String? _latestAccessToken;
