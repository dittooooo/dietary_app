import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../services/auth_service.dart';
import '../views/auth/login_page.dart';

class ApiClient {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  Uri _resolveUrl(String path) {
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
      send: (resolvedHeaders) => http.post(
        url,
        headers: resolvedHeaders,
        body: jsonEncode(body),
      ),
      headers: headers,
      contentType: 'application/json',
    );
  }

  Future<http.Response> get(
    String path, {
    Map<String, String>? headers,
  }) async {
    final url = _resolveUrl(path);
    return _sendWithRefresh(
      path: path,
      send: (resolvedHeaders) => http.get(url, headers: resolvedHeaders),
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
      send: (resolvedHeaders) => http.put(
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
          http.MultipartFile.fromBytes('file', fileBytes, filename: filename),
        );
        final streamedResponse = await request.send();
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
      send: (resolvedHeaders) => http.delete(url, headers: resolvedHeaders),
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

    _attachLatestAccessToken(resolvedHeaders);

    var response = await send(resolvedHeaders);
    _logResponse(path, response);

    if (_shouldAttemptRefresh(path, response.statusCode)) {
      final refreshed = await _refreshAccessToken();
      if (refreshed) {
        resolvedHeaders = <String, String>{
          if (contentType != null) 'Content-Type': contentType,
          ...?headers,
        };
        _attachLatestAccessToken(resolvedHeaders);
        response = await send(resolvedHeaders);
        _logResponse('$path (retried)', response);
      }
    }

    _checkResponse(response);
    return response;
  }

  void _attachLatestAccessToken(Map<String, String> headers) {
    final currentAuthorization = headers['Authorization'];
    if (currentAuthorization == null || !currentAuthorization.startsWith('Bearer ')) {
      return;
    }

    final latestToken = _latestAccessToken;
    if (latestToken == null || latestToken.isEmpty) {
      return;
    }

    headers['Authorization'] = 'Bearer $latestToken';
  }

  bool _shouldAttemptRefresh(String path, int statusCode) {
    if (statusCode != 401) {
      return false;
    }

    const excludedPaths = <String>{
      '/login',
      '/register',
      '/refresh',
    };
    return !excludedPaths.contains(path);
  }

  Future<bool> _refreshAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString(AuthService.refreshTokenKey);

    if (refreshToken != null && refreshToken.isNotEmpty) {
      try {
        final response = await http.post(
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
              await prefs.setString(AuthService.accessTokenKey, accessToken);
              await prefs.setString(AuthService.refreshTokenKey, newRefreshToken);
              await prefs.setString(
                AuthService.tokenTypeKey,
                decoded['tokenType']?.toString() ?? 'Bearer',
              );
              if (decoded.containsKey('accessTokenExpiresInSeconds')) {
                await prefs.setInt(
                  AuthService.accessTokenExpiresKey,
                  _asInt(decoded['accessTokenExpiresInSeconds']),
                );
              }
              if (decoded.containsKey('refreshTokenExpiresInSeconds')) {
                await prefs.setInt(
                  AuthService.refreshTokenExpiresKey,
                  _asInt(decoded['refreshTokenExpiresInSeconds']),
                );
              }

              _latestAccessToken = accessToken;
              return true;
            }
          }
        }
      } catch (_) {}
    }

    // 續命機制：如果 Refresh Token 失敗或過期（例如後端重啟導致 JWT Key 變更），嘗試以本地記住的帳密無感自動登入
    final email = prefs.getString('user_email');
    final password = prefs.getString('user_password');
    if (email != null && email.isNotEmpty && password != null && password.isNotEmpty) {
      debugPrint('ApiClient: Refresh token 失敗，嘗試進行靜默自動登入刷新會話...');
      try {
        final response = await http.post(
          Uri.parse('${ApiConfig.baseUrl}/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'password': password}),
        );
        if (response.statusCode == 200) {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) {
            final data = decoded['data'] is Map<String, dynamic> ? decoded['data'] : decoded;
            final accessToken = data['accessToken']?.toString() ?? '';
            final newRefreshToken = data['refreshToken']?.toString() ?? '';
            if (accessToken.isNotEmpty) {
              await prefs.setString(AuthService.accessTokenKey, accessToken);
              if (newRefreshToken.isNotEmpty) {
                await prefs.setString(AuthService.refreshTokenKey, newRefreshToken);
              }
              _latestAccessToken = accessToken;
              debugPrint('ApiClient: 靜默自動登入成功，會話已重新建立。');
              return true;
            }
          }
        }
      } catch (e) {
        debugPrint('ApiClient: 靜默自動登入過程異常: $e');
      }
    }

    return false;
  }

  void _logResponse(String path, http.Response response) {
    debugPrint('API $path -> ${response.statusCode}');
    debugPrint('API $path body -> ${response.body}');
  }

  void _checkResponse(http.Response response) {
    if (response.statusCode == 401 || response.statusCode == 403) {
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
