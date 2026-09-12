import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../controllers/dog_state_controller.dart';
import '../core/api_client.dart';
import 'token_storage.dart';
import '../utils/friendly_error_message.dart';
import '../utils/profile_value_mapper.dart';

class AuthService {
  static const String needsOnboardingKey = 'needs_onboarding';

  final ApiClient _client = ApiClient();
  final TokenStore _tokenStorage = const SecureTokenStorage();

  /// 處理登入操作。
  Future<Map<String, dynamic>> login(String email, String password) async {
    final response = await _client.post('/login', { 'email': email, 'password': password, });

    final data = _decodeBody(response.body);
    return _handleAuthResponse( response.statusCode, data, rawBody: response.body, );
  }

  /// 處理註冊操作。
  Future<Map<String, dynamic>> register(String email, String password) async {
    final response = await _client.post('/register', { 'email': email, 'password': password, });

    final data = _decodeBody(response.body);
    return _handleAuthResponse( response.statusCode, data, rawBody: response.body, );
  }

  /// 取得使用者個人資料。
  Future<Map<String, dynamic>> getUserProfile() async { 
    final prefs = await SharedPreferences.getInstance();
    final token = await _tokenStorage.readAccessToken();

    if (token == null || token.isEmpty) { return {'success': false, 'message': '未登入'}; }

    try {
      final response = await _client.get('/user/profile',headers: {'Authorization': 'Bearer $token'});
      final data = _decodeBody(response.body);
      final userData = data['data'] is Map<String, dynamic> ? data['data'] as Map<String, dynamic> : data;

      if (response.statusCode == 200 && userData.isNotEmpty) {
        await _cacheUserProfile(userData);
        await prefs.setBool(needsOnboardingKey, false);
        return {'success': true, 'data': userData};
      }
      return {'success': false, 'statusCode': response.statusCode, ...data};
    } catch (e) {
      final cachedNickname = prefs.getString('user_nickname');
      if (cachedNickname != null && cachedNickname.isNotEmpty) {
        return {
          'success': true,
          'data': { 'nickname': cachedNickname, 'petType': prefs.getString('user_pet_type'), },
          'isOffline': true, 
        };
      }
      return {'success': false, 'message': '取得使用者資料失敗'};
    }
  }

  /// 更新使用者個人資料。
  Future<Map<String, dynamic>> updateProfile( Map<String, dynamic> profileData,) async {
    final prefs = await SharedPreferences.getInstance();
    final token = await _tokenStorage.readAccessToken();

    if (token == null || token.isEmpty) { return {'success': false, 'message': '未登入'}; }
    final normalizedProfile = _normalizeProfilePayload(profileData);
    final response = await _client.post( '/user/onboarding',normalizedProfile,headers: {'Authorization': 'Bearer $token'},);

    final data = _decodeBody(response.body);

    if (response.statusCode == 200 && data['success'] == true) {
      final profile = data['data'] is Map<String, dynamic> ? data['data'] as Map<String, dynamic> : normalizedProfile;
      await _cacheUserProfile(profile);
      await prefs.setBool(needsOnboardingKey, false);
      return {'success': true, ...data};
    }
    return {'success': false, ...data};
  }

  /// 處理個人資料格式標準化
  Map<String, dynamic> _normalizeProfilePayload(Map<String, dynamic> profileData) {
    final normalized = Map<String, dynamic>.from(profileData);

    normalized['gender'] = ProfileValueMapper.genderToApi( normalized['gender']?.toString());// 性別轉譯

    // 生日 resolution (若無傳入 birthDate，根據年齡推算西元 YYYY-01-01)
    if (normalized['birthDate'] == null || normalized['birthDate'].toString().isEmpty) {
      final age = int.tryParse(normalized['age']?.toString() ?? '') ?? 20;
      final year = DateTime.now().year - age;
      normalized['birthDate'] = '$year-01-01';
    }

    // 疾病條件轉譯
    final rawHealth = normalized['healthConditions'];
    if (rawHealth is Iterable) {
      normalized['healthConditions'] = ProfileValueMapper.healthConditionsToApi( rawHealth,);
    } else if (rawHealth is String && rawHealth.isNotEmpty) {
      final list = rawHealth.split(RegExp(r'[,\s]+')).where((e) => e.isNotEmpty);
      normalized['healthConditions'] = ProfileValueMapper.healthConditionsToApi(list, );
    } else { normalized['healthConditions'] = ['NONE']; }

    // 健康目標轉譯
    final rawGoal = normalized['dietGoal'];
    if (rawGoal is Iterable) {
      normalized['dietGoal'] = ProfileValueMapper.firstDietGoalToApi(rawGoal.map((item) => item.toString()), );
    } else {
      normalized['dietGoal'] = ProfileValueMapper.dietGoalToApi(rawGoal?.toString(), );
    }

    // 寵物類型轉譯
    normalized['petType'] = ProfileValueMapper.petTypeToApi(normalized['petType']?.toString(), );
    return normalized;
  }

  /// 使用者刪除帳號
  Future<Map<String, dynamic>> deleteAccount() async {
    final prefs = await SharedPreferences.getInstance();
    final token = await _tokenStorage.readAccessToken();

    if (token == null || token.isEmpty) { return {'success': false, 'message': '未登入'}; }

    try {
      final response = await _client.delete('/user/account', headers: {'Authorization': 'Bearer $token'});
      final data = _decodeBody(response.body);

      if (response.statusCode == 200) {
        await _clearSession(prefs);
        return {'success': true, 'message': data['message'] ?? '帳號已註銷'};
      }
      return {'success': false, 'message': data['message'] ?? '註銷失敗'};
    } catch (_) { return {'success': false, 'message': '連線失敗，請稍後再試'}; }
  }

  /// 使用者登出
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await _clearSession(prefs);
  }

  /// 判斷是否為管理員
  Future<bool> isAdmin() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('user_role')?.trim().toUpperCase();
    return role == 'ROLE_ADMIN';
  }

  /// 使用者上傳頭像
  Future<Map<String, dynamic>> uploadAvatar(List<int> fileBytes, String filename,) async {
    final prefs = await SharedPreferences.getInstance();
    final token = await _tokenStorage.readAccessToken();
    if (token == null || token.isEmpty) { return {'success': false, 'message': '未登入'}; }

    try {
      final response = await _client.multipart('/user/avatar', fileBytes, filename, headers: {'Authorization': 'Bearer $token'});
      final data = _decodeBody(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        final avatarUrl = data['data']?.toString();
        if (avatarUrl != null && avatarUrl.isNotEmpty) { await prefs.setString('user_avatar_url', avatarUrl);}
        return {'success': true, 'avatarUrl': avatarUrl};
      }

      return {'success': false, ...data};
    } catch (_) { return {'success': false, 'message': '上傳頭像失敗，請稍後再試'}; }
  }

  /// 使用者回報問題 
  Future<Map<String, dynamic>> submitProblemFeedback(String content) async {
    final token = await _tokenStorage.readAccessToken();
    final trimmedContent = content.trim();

    if (token == null || token.isEmpty) { return {'success': false, 'message': '請重新登入。'}; }
    if (trimmedContent.isEmpty) { return {'success': false, 'message': '請輸入問題內容。'}; }

    try {
      final response = await _client.post('/user/problem-feedback', {'content': trimmedContent}, headers: {'Authorization': 'Bearer $token'},);
      final data = _decodeBody(response.body);
      if (response.statusCode == 200 && data['success'] == true) { return {'success': true, ...data}; }

      return {'success': false, 'message': FriendlyErrorMessage.generic};
    } catch (e) { return {'success': false, 'message': FriendlyErrorMessage.generic};}
  }

  /// 上傳問題回報照片 (管理員專用) 
  Future<Map<String, dynamic>> uploadProblemFeedbackPhoto(int feedbackId,List<int> fileBytes, String filename,) async {
    final token = await _tokenStorage.readAccessToken();
    if (token == null || token.isEmpty) { return {'success': false, 'message': '請重新登入。'}; }

    try {
      final response = await _client.multipart('/user/problem-feedback/$feedbackId/photo', fileBytes, filename, headers: {'Authorization': 'Bearer $token'},);
      final data = _decodeBody(response.body);

      if (response.statusCode == 200 && data['success'] == true) { return {'success': true, 'data': data['data'] ?? data}; }

      return {'success': false, 'message': FriendlyErrorMessage.upload};
    } catch (_) { return {'success': false, 'message': FriendlyErrorMessage.upload}; }
  }

  /// 列出所有問題回報 (管理員專用)
  Future<List<dynamic>> listMyProblemFeedback() async {
    final token = await _tokenStorage.readAccessToken();
    if (token == null || token.isEmpty) { return []; }

    try {
      final response = await _client.get( '/user/problem-feedback', headers: {'Authorization': 'Bearer $token'});
      final data = _decodeBody(response.body);
      final feedbackList = data['data'];

      if (response.statusCode == 200 && feedbackList is List) { return feedbackList; }
      return [];
    } catch (_) { return []; }
  }

  /// 取得 token 
  Future<String?> getAccessToken() async {
    return _tokenStorage.readAccessToken();
  }

  /// 非同步清除快取請求
  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await _clearSession(prefs);
  }

  /// 處理認證回應，成功時更新快取與 Token，失敗時回傳錯誤訊息。
  Future<Map<String, dynamic>> _handleAuthResponse( int statusCode, Map<String, dynamic> data, { bool preserveOnboardingState = false, String? rawBody,}) async {
    if (statusCode != 200) {return {'success': false, ...data}; }
    var accessToken = data['accessToken']?.toString() ?? '';
    if (accessToken.isEmpty && data['token'] != null) { accessToken = data['token'].toString(); }
    
    if (accessToken.isEmpty && rawBody != null) {
      final trimmed = rawBody.trim();
      if (!trimmed.startsWith('{') && trimmed.split('.').length == 3) { accessToken = trimmed; }
    }

    final refreshToken = data['refreshToken']?.toString() ?? '';
    if (accessToken.isEmpty) {
      return {
        'success': false,
        'message': data['message'] ?? 'Auth response is missing access token.',
      };
    }

    final prefs = await SharedPreferences.getInstance();
    await _tokenStorage.writeAuthTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      tokenType: data['tokenType']?.toString() ?? 'Bearer',
      accessTokenExpiresInSeconds: _asInt(data['accessTokenExpiresInSeconds']),
      refreshTokenExpiresInSeconds: _asInt( data['refreshTokenExpiresInSeconds']),
    );
    final role = data['role']?.toString();
    if (role != null && role.isNotEmpty) { await prefs.setString('user_role', role); }
    else { await prefs.remove('user_role'); }

    final needsOnboarding = preserveOnboardingState ? (prefs.getBool(needsOnboardingKey) ?? false) : (data['needsOnboarding'] == true);
    await prefs.setBool(needsOnboardingKey, needsOnboarding);

    return {
      'success': true,
      'message': data['message'],
      'needsOnboarding': needsOnboarding,
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'role': role,
      'tokenType': data['tokenType'] ?? 'Bearer',
    };
  }

  /// 非同步快取使用者設定檔。 必須在成功登入後立即呼叫，以確保使用者資料的可用性。 
  /// 該方法會將使用者資料儲存到 SharedPreferences 中，供其他模組存取。
  Future<void> _cacheUserProfile(Map<String, dynamic> userData) async {
    final prefs = await SharedPreferences.getInstance();
    final email = userData['email']?.toString() ?? userData['user']?['email']?.toString();
    final nickname = userData['nickname']?.toString();
    final petType = userData['petType']?.toString();
    final gender = userData['gender']?.toString();
    final birthDate = userData['birthDate']?.toString();
    final role = userData['user']?['role']?.toString() ?? userData['role']?.toString();
    final avatarUrl = userData['avatarUrl']?.toString() ?? userData['user']?['avatarUrl']?.toString();
    final dietGoal = userData['dietGoal']?.toString();
    final age = _asInt(userData['age']);
    final height = _asDouble(userData['height']);
    final weight = _asDouble(userData['weight']);
    final healthConditions = userData['healthConditions'];

    final isAdmin = role == 'ROLE_ADMIN';
    if (email != null && email.isNotEmpty) { await prefs.setString('user_email', email); }
    if (nickname != null && nickname.isNotEmpty) {
      final finalNick = (isAdmin && nickname == '使用者') ? '系統管理員' : nickname;
      await prefs.setString('user_nickname', finalNick);
    } else if (isAdmin) { await prefs.setString('user_nickname', '系統管理員');}
    if (petType != null) {
      await prefs.setString('user_pet_type', ProfileValueMapper.petTypeToDisplay(petType));
      await prefs.setString('user_pet_type_raw', ProfileValueMapper.petTypeToApi(petType));
    }
    if (gender != null) { await prefs.setString('user_gender', gender);}
    if (birthDate != null && birthDate.isNotEmpty) { await prefs.setString('user_birth_date', birthDate);}
    if (role != null) { await prefs.setString('user_role', role);}
    if (avatarUrl != null && avatarUrl.trim().isNotEmpty) { await prefs.setString('user_avatar_url', avatarUrl.trim());}
    else { await prefs.remove('user_avatar_url');}
    if (dietGoal != null) {
      await prefs.setString('user_diet_goal', ProfileValueMapper.dietGoalToDisplay(dietGoal));
      await prefs.setString('user_diet_goal_raw', ProfileValueMapper.dietGoalToApi(dietGoal));
    }
    if (age > 0) { await prefs.setInt('user_age', age);}
    if (height > 0) { await prefs.setDouble('user_height', height);}
    if (weight > 0) { await prefs.setDouble('user_weight', weight);}
    if (healthConditions is List) {
      await prefs.setStringList('user_health_conditions_raw', ProfileValueMapper.healthConditionsToApi(healthConditions));
    }
  }

  /// 非同步清除快取
  Future<void> _clearSession(SharedPreferences prefs) async {
    DogStateController.instance.setBodyType(DogBodyType.normal);
    DogStateController.instance.setState(DogAnimationState.idle);
    await _tokenStorage.clear();
    await prefs.remove(needsOnboardingKey);
    await prefs.remove('user_role');
    await prefs.remove('user_email');
    await prefs.remove('user_nickname');
    await prefs.remove('user_avatar_url');
    await prefs.remove('user_password');
    await prefs.remove('dog_body_type');
    await prefs.remove('pending_body_transition_show');
    await prefs.remove('pending_old_body_type');
    await prefs.remove('pending_new_body_type');
  }

  /// 嘗試解析 JSON 格式的字串，若失敗則回傳空 Map。
  Map<String, dynamic> _decodeBody(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) { return decoded; }
      return {};
    } catch (_) { return {}; }
  }

  /// 嘗試將值轉換為整數，若失敗則回傳 0。
  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  /// 嘗試將值轉換為浮點數，若失敗則回傳 0。
  double _asDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}') ?? 0;
  }
}
