//負責所有網路請求的共通邏輯
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

class ApiClient {
  // 統一處理 POST 請求
  Future<http.Response> post(String path, Map<String, dynamic> body) async {
    final url = Uri.parse('${ApiConfig.baseUrl}$path');
    
    // 這裡可以統一印出 Log，方便除錯
    print('🚀 發送請求至: $url');
    print('📦 請求內容: $body');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      return response;
    } catch (e) {
      print('❌ 網路連線異常: $e');
      rethrow; // 將錯誤丟給上層 Service 處理
    }
  }
}