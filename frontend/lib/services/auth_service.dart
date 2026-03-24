//處理登入與註冊的具體業務，包含解析後端回傳的 JSON 以及存儲 JWT Token。
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_client.dart';

class AuthService {
  final ApiClient _client = ApiClient();

  // 登入邏輯
  Future<Map<String, dynamic>> login(String email, String password) async {
    final response = await _client.post('/login', {
      'email': email,
      'password': password,
    });

    final Map<String, dynamic> responseData = _decodeBody(response.body);

    if (response.statusCode == 200) {
      // 如果回傳的是純字串 Token (如你的 login_page 邏輯)
      if (responseData.isEmpty) {
        await _saveToken(response.body);
        return {'success': true};
      }
      
      // 如果回傳的是 JSON 報錯袋
      return {'success': false, ...responseData};
    }
    
    return {'success': false, ...responseData};
  }

  // 註冊邏輯
  Future<Map<String, dynamic>> register(String email, String password) async {
    final response = await _client.post('/register', {
      'email': email,
      'password': password,
    });

    final Map<String, dynamic> data = _decodeBody(response.body);

    if (response.statusCode == 200 && data['success'] == true) {
      await _saveToken(data['token']);
      return {'success': true};
    }

    return {'success': false, ...data};
  }

  // 私有工具：儲存 Token
  Future<void> _saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jwt_token', token);
  }

  // 私有工具：安全解析 JSON
  Map<String, dynamic> _decodeBody(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return {}; // 回傳空 Map 代表可能是純字串 Token
    }
  }
}