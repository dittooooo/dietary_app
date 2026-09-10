import 'dart:convert';

import '../core/api_client.dart';
import 'token_storage.dart';

class AdminService {
  final ApiClient _client = ApiClient();

  Future<String?> _token() async {
    return const SecureTokenStorage().readAccessToken();
  }

  Map<String, dynamic> _decodeMap(String body) {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return {};
  }

  dynamic _unwrapData(String body) {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic> && decoded.containsKey('data')) {
      return decoded['data'];
    }
    return decoded;
  }

  Future<List<dynamic>> listUsers({String? keyword}) async {
    final token = await _token();
    if (token == null) return [];

    try {
      final path = keyword != null && keyword.isNotEmpty
          ? '/admin/users?keyword=${Uri.encodeComponent(keyword)}'
          : '/admin/users';

      final response = await _client.get(
        path,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = _unwrapData(response.body);
        return data is List ? data : [];
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>?> getUserDetail(int id) async {
    final token = await _token();
    if (token == null) return null;

    try {
      final response = await _client.get(
        '/admin/users/$id',
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = _unwrapData(response.body);
        return data is Map<String, dynamic> ? data : null;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> createUser(Map<String, dynamic> userData) async {
    final token = await _token();
    if (token == null) {
      return {'success': false, 'message': 'Please sign in again.'};
    }

    try {
      final response = await _client.post(
        '/admin/users',
        userData,
        headers: {'Authorization': 'Bearer $token'},
      );

      final data = _decodeMap(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, 'data': data['data'] ?? data};
      }
      return {'success': false, ...data};
    } catch (_) {
      return {'success': false, 'message': '建立使用者失敗，請稍後再試'};
    }
  }

  Future<Map<String, dynamic>> updateUser(
    int id,
    Map<String, dynamic> userData,
  ) async {
    final token = await _token();
    if (token == null) {
      return {'success': false, 'message': 'Please sign in again.'};
    }

    try {
      final response = await _client.put(
        '/admin/users/$id',
        userData,
        headers: {'Authorization': 'Bearer $token'},
      );

      final data = _decodeMap(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'data': data['data'] ?? data};
      }
      return {'success': false, ...data};
    } catch (_) {
      return {'success': false, 'message': '更新使用者失敗，請稍後再試'};
    }
  }

  Future<Map<String, dynamic>> updateUserStatus(int id, bool enabled) async {
    final token = await _token();
    if (token == null) {
      return {'success': false, 'message': '請重新登入'};
    }

    try {
      final response = await _client.put(
        '/admin/users/$id/status',
        {'enabled': enabled},
        headers: {'Authorization': 'Bearer $token'},
      );

      final data = _decodeMap(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'data': data['data'] ?? data};
      }

      return {
        'success': false,
        ...data,
        'message':
            data['message'] ??
            data['error'] ??
            '更新狀態失敗 (${response.statusCode})',
      };
    } catch (e) {
      return {'success': false, 'message': '更新使用者狀態失敗，請稍後再試'};
    }
  }

  // --- 管理者餐廳、菜單與飲食紀錄 API (已廢棄且後端已無對應 Controller，特此清理) ---

  Future<List<dynamic>> listProblemFeedback() async {
    final token = await _token();
    if (token == null) return [];

    try {
      final response = await _client.get(
        '/admin/problem-feedback',
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = _unwrapData(response.body);
        return data is List ? data : [];
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>> replyProblemFeedback(
    int id,
    String adminReply,
  ) async {
    final token = await _token();
    if (token == null) {
      return {'success': false, 'message': '請重新登入'};
    }

    try {
      final response = await _client.put(
        '/admin/problem-feedback/$id/reply',
        {'adminReply': adminReply.trim()},
        headers: {'Authorization': 'Bearer $token'},
      );

      final data = _decodeMap(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {'success': true, 'data': data['data'] ?? data};
      }
      return {
        'success': false,
        ...data,
        'message':
            data['message'] ?? data['error'] ?? '回覆失敗 (${response.statusCode})',
      };
    } catch (e) {
      return {'success': false, 'message': '回覆失敗，請稍後再試'};
    }
  }
}
