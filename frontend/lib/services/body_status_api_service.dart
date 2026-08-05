import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_client.dart';
import '../models/body_status_models.dart';

class BodyStatusApiService {
  final ApiClient _client;

  BodyStatusApiService({ApiClient? client}) : _client = client ?? ApiClient();

  Future<BodyStatusModel> getBodyStatus() async {
    final token = await _token();
    if (token == null) {
      throw BodyStatusApiException('尚未登入');
    }

    final response = await _client.get(
      '/body-status',
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BodyStatusApiException('取得體型狀態失敗 (${response.statusCode})');
    }

    return BodyStatusModel.fromJson(_decodeMap(response.body));
  }

  Future<SettlementResponse> settleDailyScores() async {
    final token = await _token();
    if (token == null) {
      throw BodyStatusApiException('尚未登入');
    }

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

  Future<String?> _token() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt_token');
  }

  Map<String, dynamic> _decodeMap(String body) {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      final data = decoded['data'];
      return data is Map<String, dynamic> ? data : decoded;
    }
    throw BodyStatusApiException('API 回傳格式不正確');
  }
}

class BodyStatusApiException implements Exception {
  final String message;

  BodyStatusApiException(this.message);

  @override
  String toString() => message;
}
