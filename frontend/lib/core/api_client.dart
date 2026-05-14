//負責所有網路請求的共通邏輯
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

class ApiClient {
  // 統一處理 POST 請求
  Future<http.Response> post(String path, Map<String, dynamic> body, {Map<String, String>? headers}) async {
    final url = Uri.parse('${ApiConfig.baseUrl}$path');
    
    print('🚀 發送 POST 請求至: $url');
    print('📦 請求內容: $body');

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          ...?headers,
        },
        body: jsonEncode(body),
      );
      return response;
    } catch (e) {
      print('❌ POST 網路連線異常: $e');
      rethrow;
    }
  }

  // 統一處理 GET 請求
  Future<http.Response> get(String path, {Map<String, String>? headers}) async {
    final url = Uri.parse('${ApiConfig.baseUrl}$path');
    print('🚀 GET 請求至: $url');

    try {
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          ...?headers,
        },
      );
      return response;
    } catch (e) {
      print('❌ GET 網路連線異常: $e');
      rethrow;
    }
  }
}