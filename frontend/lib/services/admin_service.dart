import 'dart:convert';

import '../core/api_client.dart';
import 'token_storage.dart';

class AdminService {
  /// 預設建構元
  final ApiClient _client = ApiClient();

  /// 取得 Token。
  Future<String?> _token() async {
    return const SecureTokenStorage().readAccessToken();
  }

  /// 將 JSON 字串解碼為 Map。
  Map<String, dynamic> _decodeMap(String body) {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) { return decoded; }
    return {};
  }

  /// 將 JSON 字串解碼並取得 data 欄位。
  dynamic _unwrapData(String body) {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic> && decoded.containsKey('data')) { return decoded['data']; }
    return decoded;
  }

  /// 列出問題回報。
  Future<List<dynamic>> listProblemFeedback() async {
    final token = await _token();
    if (token == null) return [];
    try {
      final response = await _client.get('/admin/problem-feedback', headers: {'Authorization': 'Bearer $token'});
      if (response.statusCode == 200) { final data = _unwrapData(response.body); return data is List ? data : [];}
      return [];
    } catch (_) { return []; }
  }

  /// 回覆問題回報。
  Future<Map<String, dynamic>> replyProblemFeedback( int id, String adminReply, ) async {
    final token = await _token();
    if (token == null) { return {'success': false, 'message': '請重新登入'}; }

    try {
      final response = await _client.put(
        '/admin/problem-feedback/$id/reply',
        {'adminReply': adminReply.trim()},
        headers: {'Authorization': 'Bearer $token'},
      );

      final data = _decodeMap(response.body);
      if (response.statusCode == 200 && data['success'] == true) {  return {'success': true, 'data': data['data'] ?? data};}
      return {
        'success': false,
        ...data,
        'message': data['message'] ?? data['error'] ?? '回覆失敗 (${response.statusCode})',
      };
    } catch (e) {
      return {'success': false, 'message': '回覆失敗，請稍後再試'};
    }
  }
}
