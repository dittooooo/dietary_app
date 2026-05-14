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

  // 獲取個人資料 (串接後端並更新本地緩衝)
  Future<Map<String, dynamic>> getUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    
    if (token == null) return {'success': false, 'message': '未登入'};

    try {
      final response = await _client.get('/user/profile', headers: {
        'Authorization': 'Bearer $token',
      });

      final Map<String, dynamic> data = _decodeBody(response.body);

      if (response.statusCode == 200 && (data['success'] == true || data.containsKey('nickname'))) {
        // 更新本地快取
        final userData = data['data'] ?? data;
        await prefs.setString('user_email', userData['email'] ?? '');
        await prefs.setString('user_nickname', userData['nickname'] ?? '');
        await prefs.setString('user_pet_type', userData['petType'] ?? '');
        // 額外儲存更多資訊以便編輯時使用
        await prefs.setString('user_gender', userData['gender'] ?? '男');
        return {'success': true, 'data': userData};
      }
      
      return {'success': false, ...data};
    } catch (e) {
      final cachedNickname = prefs.getString('user_nickname');
      if (cachedNickname != null) {
        return {
          'success': true, 
          'data': {
            'nickname': cachedNickname,
            'petType': prefs.getString('user_pet_type'),
          },
          'isOffline': true
        };
      }
      return {'success': false, 'message': '連線失敗'};
    }
  }

  // 更新個人資料 (Onboarding)
  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> profileData) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    
    if (token == null) return {'success': false, 'message': '未登入'};

    final response = await _client.post(
      '/user/onboarding', 
      profileData,
      headers: {'Authorization': 'Bearer $token'},
    );

    final Map<String, dynamic> data = _decodeBody(response.body);

    if (response.statusCode == 200) {
      // 更新本地快取
      if (data['success'] == true) {
        await prefs.setString('user_nickname', profileData['nickname']);
      }
      return {'success': true, ...data};
    }

    return {'success': false, ...data};
  }

  // 登出：清除所有本地資料
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  // 私有工具：儲存 Token (強化過濾機制)
  Future<void> _saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    // 移除可能存在的空白與多餘引號 (部分後端回傳純字串時會帶引號)
    String cleanToken = token.trim();
    if (cleanToken.startsWith('"') && cleanToken.endsWith('"')) {
      cleanToken = cleanToken.substring(1, cleanToken.length - 1);
    }
    await prefs.setString('jwt_token', cleanToken);
  }

  // 私有工具：安全解析 JSON
  Map<String, dynamic> _decodeBody(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      return {}; 
    } catch (_) {
      return {}; 
    }
  }
}