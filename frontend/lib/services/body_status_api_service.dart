import 'dart:convert';

import '../core/api_client.dart';
import '../models/body_status_models.dart';
import 'token_storage.dart';

class BodyStatusApiService {
  final ApiClient _client;

  /// 預設建構元
  BodyStatusApiService({ApiClient? client}) : _client = client ?? ApiClient();

  /// 取得體型狀態
  Future<BodyStatusModel> getBodyStatus() async {
    final token = await _token();
    if (token == null) { throw BodyStatusApiException('尚未登入'); }

    final response = await _client.get( 
      '/body-status', 
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BodyStatusApiException('取得體型狀態失敗 (${response.statusCode})');
    }
    return BodyStatusModel.fromJson(_decodeMap(response.body));
  }

  /// 每日結算
  Future<SettlementResponse> settleDailyScores() async {
    final token = await _token();
    if (token == null) { throw BodyStatusApiException('尚未登入'); }

    final response = await _client.post(
      '/body-status/settle',
      const {},
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BodyStatusApiException('每日結算失敗 (${response.statusCode})');
    }
    return SettlementResponse.fromJson(_decodeMap(response.body));
  }

  /// 取得 Token
  Future<String?> _token() async {
    return const SecureTokenStorage().readAccessToken();
  }

  /// 解碼 API 回傳的 JSON 字串
  Map<String, dynamic> _decodeMap(String body) {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      final data = decoded['data'];
      return data is Map<String, dynamic> ? data : decoded;
    }
    throw BodyStatusApiException('API 回傳格式不正確');
  }
}

/// 體型狀態 API 錯誤
class BodyStatusApiException implements Exception {
  final String message;
  BodyStatusApiException(this.message);

  @override
  String toString() => message;
}
