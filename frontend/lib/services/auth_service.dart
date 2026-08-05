//處理登入與註冊的具體業務，包含解析後端回傳的 JSON 以及存儲 JWT Token。
import 'dart:convert'; // 匯入 dart:convert 套件或模組
import 'package:shared_preferences/shared_preferences.dart'; // 匯入 shared_preferences.dart 套件或模組
import '../core/api_client.dart'; // 匯入 api_client.dart 套件或模組

class AuthService { // 定義 AuthService 類別，封裝相關功能或資料
  final ApiClient _client = ApiClient(); // 宣告唯讀的 API 請求客戶端物件實例

  // 登入邏輯
  Future<Map<String, dynamic>> login(String email, String password) async { // 處理使用者登入驗證，傳入帳號密碼並發送登入請求
    final response = await _client.post('/login', { // 宣告類別屬性或方法內部的區域變數
      'email': email, // 執行相對應的程式邏輯運算或欄位宣告設定
      'password': password, // 執行相對應的程式邏輯運算或欄位宣告設定
    }); // 程式碼區塊或結構結束

    final Map<String, dynamic> responseData = _decodeBody(response.body); // 宣告類別屬性或方法內部的區域變數

    if (response.statusCode == 200) { // 執行相對應的程式邏輯運算或欄位宣告設定
      // 如果回傳的是純字串 Token (如你的 login_page 邏輯)
      if (responseData.isEmpty) { // 執行相對應的程式邏輯運算或欄位宣告設定
        await _saveToken(response.body); // 執行相對應的程式邏輯運算或欄位宣告設定
        return {'success': true}; // 回傳方法執行結果或計算完成的數據
      } // 程式碼區塊或結構結束
      
      // 如果回傳的是 JSON 報錯袋
      return {'success': false, ...responseData}; // 回傳方法執行結果或計算完成的數據
    } // 程式碼區塊或結構結束
    
    return {'success': false, ...responseData}; // 回傳方法執行結果或計算完成的數據
  } // 程式碼區塊或結構結束

  // 註冊邏輯
  Future<Map<String, dynamic>> register(String email, String password) async { // 處理使用者帳號註冊，傳入帳號密碼並發送註冊請求
    final response = await _client.post('/register', { // 宣告類別屬性或方法內部的區域變數
      'email': email, // 執行相對應的程式邏輯運算或欄位宣告設定
      'password': password, // 執行相對應的程式邏輯運算或欄位宣告設定
    }); // 程式碼區塊或結構結束

    final Map<String, dynamic> data = _decodeBody(response.body); // 宣告類別屬性或方法內部的區域變數

    if (response.statusCode == 200 && data['success'] == true) { // 執行相對應的程式邏輯運算或欄位宣告設定
      await _saveToken(data['token']); // 執行相對應的程式邏輯運算或欄位宣告設定
      return {'success': true}; // 回傳方法執行結果或計算完成的數據
    } // 程式碼區塊或結構結束

    return {'success': false, ...data}; // 回傳方法執行結果或計算完成的數據
  } // 程式碼區塊或結構結束

  // 獲取個人資料 (串接後端並更新本地緩衝)
  Future<Map<String, dynamic>> getUserProfile() async { // 獲取當前登入使用者的詳細個人檔案與設定資料
    final prefs = await SharedPreferences.getInstance(); // 獲取本地存儲 SharedPreferences 的單例實例
    final token = prefs.getString('jwt_token'); // 宣告類別屬性或方法內部的區域變數
    
    if (token == null) return {'success': false, 'message': '未登入'}; // 回傳方法執行結果或計算完成的數據

    try { // 執行相對應的程式邏輯運算或欄位宣告設定
      final response = await _client.get('/user/profile', headers: { // 宣告類別屬性或方法內部的區域變數
        'Authorization': 'Bearer $token', // 執行相對應的程式邏輯運算或欄位宣告設定
      }); // 程式碼區塊或結構結束

      final Map<String, dynamic> data = _decodeBody(response.body); // 宣告類別屬性或方法內部的區域變數

      if (response.statusCode == 200 && (data['success'] == true || data.containsKey('nickname'))) { // 執行相對應的程式邏輯運算或欄位宣告設定
        // 更新本地快取
        final userData = data['data'] ?? data; // 宣告類別屬性或方法內部的區域變數
        final String? email = userData['email'] ?? userData['user']?['email']; // 宣告類別屬性或方法內部的區域變數
        if (email != null && email.isNotEmpty) { // 執行相對應的程式邏輯運算或欄位宣告設定
          await prefs.setString('user_email', email); // 執行相對應的程式邏輯運算或欄位宣告設定
        } // 程式碼區塊或結構結束
        await prefs.setString('user_nickname', userData['nickname'] ?? ''); // 執行相對應的程式邏輯運算或欄位宣告設定
        await prefs.setString('user_pet_type', userData['petType'] ?? ''); // 執行相對應的程式邏輯運算或欄位宣告設定
        // 額外儲存更多資訊以便編輯時使用
        await prefs.setString('user_gender', userData['gender'] ?? '男'); // 執行相對應的程式邏輯運算或欄位宣告設定

        final String? role = userData['user']?['role'] ?? userData['role']; // 宣告類別屬性或方法內部的區域變數
        if (role != null) { // 執行相對應的程式邏輯運算或欄位宣告設定
          await prefs.setString('user_role', role); // 執行相對應的程式邏輯運算或欄位宣告設定
        } // 程式碼區塊或結構結束
        return {'success': true, 'data': userData}; // 回傳方法執行結果或計算完成的數據
      } // 程式碼區塊或結構結束
      
      return {'success': false, ...data}; // 回傳方法執行結果或計算完成的數據
    } catch (e) { // 執行相對應的程式邏輯運算或欄位宣告設定
      final cachedNickname = prefs.getString('user_nickname'); // 宣告類別屬性或方法內部的區域變數
      if (cachedNickname != null) { // 執行相對應的程式邏輯運算或欄位宣告設定
        return { // 回傳方法執行結果或計算完成的數據
          'success': true,  // 執行相對應的程式邏輯運算或欄位宣告設定
          'data': { // 執行相對應的程式邏輯運算或欄位宣告設定
            'nickname': cachedNickname, // 執行相對應的程式邏輯運算或欄位宣告設定
            'petType': prefs.getString('user_pet_type'), // 執行相對應的程式邏輯運算或欄位宣告設定
          }, // 程式碼區塊或結構結束
          'isOffline': true // 執行相對應的程式邏輯運算或欄位宣告設定
        }; // 執行相對應的程式邏輯運算或欄位宣告設定
      } // 程式碼區塊或結構結束
      return {'success': false, 'message': '連線失敗'}; // 回傳方法執行結果或計算完成的數據
    } // 程式碼區塊或結構結束
  } // 程式碼區塊或結構結束

  // 更新個人資料 (Onboarding)
  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> profileData) async { // 更新使用者的個人檔案資訊（Onboarding/基本設定資料）
    final prefs = await SharedPreferences.getInstance(); // 獲取本地存儲 SharedPreferences 的單例實例
    final token = prefs.getString('jwt_token'); // 宣告類別屬性或方法內部的區域變數
    
    if (token == null) return {'success': false, 'message': '未登入'}; // 回傳方法執行結果或計算完成的數據

    final response = await _client.post( // 宣告類別屬性或方法內部的區域變數
      '/user/onboarding',  // 執行相對應的程式邏輯運算或欄位宣告設定
      profileData, // 執行相對應的程式邏輯運算或欄位宣告設定
      headers: {'Authorization': 'Bearer $token'}, // 執行相對應的程式邏輯運算或欄位宣告設定
    ); // 程式碼區塊或結構結束

    final Map<String, dynamic> data = _decodeBody(response.body); // 宣告類別屬性或方法內部的區域變數

    if (response.statusCode == 200) { // 執行相對應的程式邏輯運算或欄位宣告設定
      // 更新本地快取
      if (data['success'] == true) { // 執行相對應的程式邏輯運算或欄位宣告設定
        await prefs.setString('user_nickname', profileData['nickname']); // 執行相對應的程式邏輯運算或欄位宣告設定
      } // 程式碼區塊或結構結束
      return {'success': true, ...data}; // 回傳方法執行結果或計算完成的數據
    } // 程式碼區塊或結構結束

    return {'success': false, ...data}; // 回傳方法執行結果或計算完成的數據
  } // 程式碼區塊或結構結束

  // 登出：清除所有本地資料
  Future<void> logout() async { // 執行登出操作，清除本地存儲的 JWT Token 與快取設定
    final prefs = await SharedPreferences.getInstance(); // 獲取本地存儲 SharedPreferences 的單例實例
    await prefs.clear(); // 執行相對應的程式邏輯運算或欄位宣告設定
  } // 程式碼區塊或結構結束

  // 統一檢查是否為管理員
  Future<bool> isAdmin() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('user_role');
    return role == 'ROLE_ADMIN';
  }

  // 上傳頭像到後端
  Future<Map<String, dynamic>> uploadAvatar(List<int> fileBytes, String filename) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    
    if (token == null) return {'success': false, 'message': '未登入'};

    try {
      final response = await _client.multipart(
        '/user/avatar',
        fileBytes,
        filename,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        return {'success': true, 'avatarUrl': response.body};
      }
      return {'success': false, 'message': '上傳失敗，請檢查檔案格式與網路後再試'};
    } catch (e) {
      return {'success': false, 'message': '連線失敗: $e'};
    }
  }

  // 私有工具：儲存 Token (強化過濾機制)
  Future<void> _saveToken(String token) async { // 私有方法：安全清理並儲存 JWT Token 到本地持久化快取
    final prefs = await SharedPreferences.getInstance(); // 獲取本地存儲 SharedPreferences 的單例實例
    // 移除可能存在的空白與多餘引號 (部分後端回傳純字串時會帶引號)
    String cleanToken = token.trim(); // 宣告類別屬性或方法內部的區域變數
    if (cleanToken.startsWith('"') && cleanToken.endsWith('"')) { // 執行相對應的程式邏輯運算或欄位宣告設定
      cleanToken = cleanToken.substring(1, cleanToken.length - 1); // 執行相對應的程式邏輯運算或欄位宣告設定
    } // 程式碼區塊或結構結束
    await prefs.setString('jwt_token', cleanToken); // 執行相對應的程式邏輯運算或欄位宣告設定
  } // 程式碼區塊或結構結束

  // 私有工具：安全解析 JSON
  Map<String, dynamic> _decodeBody(String body) { // 私有方法：安全將 API 回傳的 body 字串解析為 Map 鍵值對
    try { // 執行相對應的程式邏輯運算或欄位宣告設定
      final decoded = jsonDecode(body); // 將 JSON 字串反序列化解析為 Map 結構資料
      if (decoded is Map<String, dynamic>) return decoded; // 回傳方法執行結果或計算完成的數據
      return {};  // 回傳方法執行結果或計算完成的數據
    } catch (_) { // 執行相對應的程式邏輯運算或欄位宣告設定
      return {};  // 回傳方法執行結果或計算完成的數據
    } // 程式碼區塊或結構結束
  } // 程式碼區塊或結構結束
} // 程式碼區塊或結構結束
