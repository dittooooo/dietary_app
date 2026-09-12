import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../config/api_config.dart';
import '../services/auth_service.dart';
import '../services/token_storage.dart';
import '../views/auth/login_page.dart';

/// 網路請求客戶端，負責與後端 API 進行通訊。
/// 封裝了 GET、POST、PUT、DELETE、POST Multipart 等常用 HTTP 方法，並自動處理 Token 驗證與刷新機制。
class ApiClient {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  static final http.Client _defaultHttpClient = http.Client();

  final http.Client _httpClient;
  final TokenStore _tokenStore;
  static Future<bool>? _refreshInFlight;

  /// 預設建構元
  ApiClient({http.Client? httpClient, TokenStore? tokenStore}) : _httpClient = httpClient ?? _defaultHttpClient, _tokenStore = tokenStore ?? const SecureTokenStorage();

  /// 解析檔案名稱，取得檔案類型。
  MediaType _resolveMediaType(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.png')) return MediaType('image', 'png');
    if (lower.endsWith('.webp')) return MediaType('image', 'webp');
    if (lower.endsWith('.gif')) return MediaType('image', 'gif');
    return MediaType('image', 'jpeg');
  }

  /// 根據路徑決定使用基礎URL或server基礎URL。若路徑以 http:// 或 https:// 開頭，則直接使用該路徑。
  Uri _resolveUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) { return Uri.parse(path); }
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final base = normalizedPath.startsWith('/dietary-agent/') ? ApiConfig.serverBaseUrl : ApiConfig.baseUrl;
    return Uri.parse('$base$normalizedPath');
  }

  /// 封裝 POST 請求，增加Token驗證功能。
  Future<http.Response> post(
    String path,
    Map<String, dynamic> body, { Map<String, String>? headers, }) async {
      final url = _resolveUrl(path);
      return _sendWithRefresh(
        path: path,
        send: (resolvedHeaders) => _httpClient.post( url, headers: resolvedHeaders, body: jsonEncode(body),),
        headers: headers,
        contentType: 'application/json',
      );
  }

  /// 封裝 GET 請求，增加 Token 驗證功能。
  Future<http.Response> get(String path, {Map<String, String>? headers}) async {
    final url = _resolveUrl(path);
    return _sendWithRefresh(
      path: path,
      send: (resolvedHeaders) => _httpClient.get(url, headers: resolvedHeaders),
      headers: headers,
      contentType: 'application/json',
    );
  }

  /// 封裝 PUT 請求，增加 Token 驗證功能。
  Future<http.Response> put(String path, Map<String, dynamic> body, { Map<String, String>? headers, }) async {
    final url = _resolveUrl(path);
    return _sendWithRefresh(
      path: path,
      send: (resolvedHeaders) => _httpClient.put( url, headers: resolvedHeaders, body: jsonEncode(body),),
      headers: headers,
      contentType: 'application/json',
    );
  }

  /// 封裝 multipart/form-data 請求，增加 Token 驗證功能。
  Future<http.Response> multipart( String path, List<int> fileBytes, String filename, { Map<String, String>? headers, }) async {
    final url = _resolveUrl(path);
    return _sendWithRefresh(
      path: path,
      send: (resolvedHeaders) async {
        final request = http.MultipartRequest('POST', url);
        request.headers.addAll(resolvedHeaders);
        request.files.add( http.MultipartFile.fromBytes( 'file', fileBytes, filename: filename, contentType: _resolveMediaType(filename),), );
        final streamedResponse = await _httpClient.send(request);
        return http.Response.fromStream(streamedResponse);
      },
      headers: headers,
    );
  }

  /// 封裝 DELETE 請求，增加 Token 驗證功能。
  Future<http.Response> delete( String path, { Map<String, String>? headers, }) async {
    final url = _resolveUrl(path);
    return _sendWithRefresh(
      path: path,
      send: (resolvedHeaders) =>  _httpClient.delete(url, headers: resolvedHeaders),
      headers: headers,
      contentType: 'application/json',
    );
  }

  /// 封裝請求並自動處理 Token 刷新機制。
  Future<http.Response> _sendWithRefresh({
    required String path, required Future<http.Response> Function(Map<String, String>) send,
    Map<String, String>? headers, String? contentType,
  }) async {
    var resolvedHeaders = <String, String>{...?headers};
    if (contentType != null) { resolvedHeaders['Content-Type'] = contentType; }

    if (!_isPublicEndpoint(path)) { await _attachLatestAccessToken(resolvedHeaders);} //如果不是公開端點，則附加 Token

    var response = await send(resolvedHeaders);
    _logResponse(path, response);

    if (_shouldAttemptRefresh(path, response.statusCode)) {
      final refreshed = await _refreshAccessToken();
      if (refreshed) {
        resolvedHeaders = <String, String>{...?headers};
        if (contentType != null) { resolvedHeaders['Content-Type'] = contentType; }
        if (!_isPublicEndpoint(path)) { await _attachLatestAccessToken(resolvedHeaders, force: true); } // 刷新成功後必須覆蓋原本的 Authorization，避免重試仍使用過期 Token。
        response = await send(resolvedHeaders);
        _logResponse('$path (retried)', response);
      }
    }
    _checkResponse(response);
    return response;
  }

  /// 判斷是否為公開端點（不需要 Token）。
  /// 邏輯：公開端點是路徑開頭為 /api/v1/auth/login、/api/v1/auth/register 或 /api/v1/auth/refresh 的端點。
  bool _isPublicEndpoint(String path) {
    const publicPaths = <String>{'/login', '/register', '/refresh'};
    return publicPaths.contains(path);
  }

  /// 附加 Token。
  /// 邏輯：若不為公開端點且 Authorization 已存在且長度大於 10，則不附加。直接從 SecureTokenStorage 中讀取 Token 並附加。
  Future<void> _attachLatestAccessToken( Map<String, String> headers, { bool force = false, }) async {
    final existingAuth = headers['Authorization'];
    if (!force && existingAuth != null && existingAuth.startsWith('Bearer ') && existingAuth.length > 10) { return; }

    final token = await _tokenStore.readAccessToken();

    if (token != null && token.isNotEmpty) { headers['Authorization'] = 'Bearer $token'; }
  }

  /// 判斷是否需要刷新 Token。
  /// 邏輯：若狀態碼為 401 或 403 且路徑不是 /login、/register 或 /refresh，則需要刷新。
  bool _shouldAttemptRefresh(String path, int statusCode) {
    if (statusCode != 401 && statusCode != 403) { return false; }

    const excludedPaths = <String>{'/login', '/register', '/refresh'};
    return !excludedPaths.contains(path);
  }

  /// 刷新 Access Token。
  /// 邏輯：若已有正在執行的刷新操作，則等待該操作完成。若無，則執行刷新操作並等待完成。
  Future<bool> _refreshAccessToken() async {
    final existingRefresh = _refreshInFlight;
    if (existingRefresh != null) { return existingRefresh; }

    final refreshFuture = _performRefreshAccessToken();
    _refreshInFlight = refreshFuture;
    return refreshFuture.whenComplete(() {
      if (identical(_refreshInFlight, refreshFuture)) {  _refreshInFlight = null; }
    });
  }

  /// 實際執行刷新Token操作。
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
            final newRefreshToken = decoded['refreshToken']?.toString() ?? refreshToken;

            if (accessToken.isNotEmpty) { await _tokenStore.writeAuthTokens(
                accessToken: accessToken,
                refreshToken: newRefreshToken,
                tokenType: decoded['tokenType']?.toString() ?? 'Bearer',
                accessTokenExpiresInSeconds: _asInt( decoded['accessTokenExpiresInSeconds'],),
                refreshTokenExpiresInSeconds: _asInt( decoded['refreshTokenExpiresInSeconds'],),
              );

              return true;
            }
          }
        }
      } catch (_) {}
    }
    return false;
  }

  /// 記錄 API 請求與回應。
  void _logResponse(String path, http.Response response) {
    debugPrint('API $path -> ${response.statusCode}');
  }

  /// 檢查回應並處理 401/403 狀態碼。
  /// 邏輯：若狀態碼為 401 或 403，則檢查路徑。若路徑包含 :3000、:3001、/companion/ 或 /maf/，則不處理（由對話流程自行處理）。否則，取得當前 Context，檢查是否已mounted。若已mounted，則顯示登入失敗/權限不足/登入已失效的 AlertDialog。
  void _checkResponse(http.Response response) {
    if (response.statusCode == 401 || response.statusCode == 403) {
      final requestUrlStr = response.request?.url.toString() ?? '';
      // MAF/Companion 的對話錯誤由對話流程自行處理，不觸發全域登出彈窗
      if (requestUrlStr.contains(':3000') || requestUrlStr.contains(':3001') ||
          requestUrlStr.contains('/companion/') || requestUrlStr.contains('/maf/')) {
        return;
      }

      final context = navigatorKey.currentContext;
      if (context == null) { return; }
      final requestUrl = response.request?.url.path ?? '';
      final isLogin = requestUrl.contains('/login');

      Future.delayed(Duration.zero, () async {
        if (response.statusCode == 401 && !isLogin) { await AuthService().clearSession(); }

        if (!context.mounted) { return; }

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: Text(isLogin ? '登入失敗' : (response.statusCode == 403 ? '權限不足' : '登入已失效'),),
            content: Text(isLogin ? '帳號或密碼錯誤，請重新確認。' : (response.statusCode == 403 ? '你目前沒有權限執行這個操作。' : '登入狀態已過期，請重新登入。'),),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  if (!isLogin) {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (context) => const LoginPage()),
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

  /// 輔助方法，將傳入值安全轉換為 int。
  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? 0;
  }
}
