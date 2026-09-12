import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_client.dart';
import 'token_storage.dart';
import '../utils/friendly_error_message.dart';
import '../utils/profile_value_mapper.dart';

class AuthService {
  static const String accessTokenKey = SecureTokenStorage.accessTokenKey;
  static const String refreshTokenKey = SecureTokenStorage.refreshTokenKey;
  static const String tokenTypeKey = SecureTokenStorage.tokenTypeKey;
  static const String needsOnboardingKey = 'needs_onboarding';
  static const String accessTokenExpiresKey =
      SecureTokenStorage.accessTokenExpiresKey;
  static const String refreshTokenExpiresKey =
      SecureTokenStorage.refreshTokenExpiresKey;

  final ApiClient _client = ApiClient();
  final TokenStore _tokenStorage = const SecureTokenStorage();

  static Future<void> migrateLegacyTokenStorage() {
    return const SecureTokenStorage().migrateLegacyTokens();
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    final response = await _client.post('/login', {
      'email': email,
      'password': password,
    });

    final data = _decodeBody(response.body);
    return _handleAuthResponse(
      response.statusCode,
      data,
      rawBody: response.body,
    );
  }

  Future<Map<String, dynamic>> register(String email, String password) async {
    final response = await _client.post('/register', {
      'email': email,
      'password': password,
    });

    final data = _decodeBody(response.body);
    return _handleAuthResponse(
      response.statusCode,
      data,
      rawBody: response.body,
    );
  }

  Future<Map<String, dynamic>> getUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final token = await _tokenStorage.readAccessToken();

    if (token == null || token.isEmpty) {
      return {'success': false, 'message': '未登入'};
    }

    try {
      final response = await _client.get(
        '/user/profile',
        headers: {'Authorization': 'Bearer $token'},
      );

      final data = _decodeBody(response.body);
      final userData = data['data'] is Map<String, dynamic>
          ? data['data'] as Map<String, dynamic>
          : data;

      // 註解說明：原先此處包含 `userData is Map<String, dynamic>`，但因上方已推導 userData 為 Map<String, dynamic> 型態，
      // 導致該型別檢查恆為 true (flutter analyze: unnecessary_type_check)，故已簡化保留 `userData.isNotEmpty`。
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
          'data': {
            'nickname': cachedNickname,
            'petType': prefs.getString('user_pet_type'),
          },
          'isOffline': true,
        };
      }
      return {'success': false, 'message': '取得使用者資料失敗'};
    }
  }

  Future<Map<String, dynamic>> updateProfile(
    Map<String, dynamic> profileData,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final token = await _tokenStorage.readAccessToken();

    if (token == null || token.isEmpty) {
      return {'success': false, 'message': '未登入'};
    }

    final normalizedProfile = _normalizeProfilePayload(profileData);
    final response = await _client.post(
      '/user/onboarding',
      normalizedProfile,
      headers: {'Authorization': 'Bearer $token'},
    );

    final data = _decodeBody(response.body);

    if (response.statusCode == 200 && data['success'] == true) {
      final profile = data['data'] is Map<String, dynamic>
          ? data['data'] as Map<String, dynamic>
          : normalizedProfile;
      await _cacheUserProfile(profile);
      await prefs.setBool(needsOnboardingKey, false);
      return {'success': true, ...data};
    }

    return {'success': false, ...data};
  }

  Map<String, dynamic> _normalizeProfilePayload(
    Map<String, dynamic> profileData,
  ) {
    final normalized = Map<String, dynamic>.from(profileData);

    // 性別轉譯
    normalized['gender'] = ProfileValueMapper.genderToApi(
      normalized['gender']?.toString(),
    );

    // 生日 resolution (若無傳入 birthDate，根據年齡推算西元 YYYY-01-01)
    if (normalized['birthDate'] == null ||
        normalized['birthDate'].toString().isEmpty) {
      if (normalized['birth_date'] != null &&
          normalized['birth_date'].toString().isNotEmpty) {
        normalized['birthDate'] = normalized['birth_date'];
      } else {
        final age = int.tryParse(normalized['age']?.toString() ?? '') ?? 20;
        final year = DateTime.now().year - age;
        normalized['birthDate'] = '$year-01-01';
      }
    }

    // 疾病條件轉譯
    final rawHealth =
        normalized['healthConditions'] ?? normalized['health_conditions'];
    if (rawHealth is Iterable) {
      normalized['healthConditions'] = ProfileValueMapper.healthConditionsToApi(
        rawHealth,
      );
    } else if (rawHealth is String && rawHealth.isNotEmpty) {
      final list = rawHealth
          .split(RegExp(r'[,\s]+'))
          .where((e) => e.isNotEmpty);
      normalized['healthConditions'] = ProfileValueMapper.healthConditionsToApi(
        list,
      );
    } else {
      normalized['healthConditions'] = ['NONE'];
    }

    // 健康目標轉譯
    final rawGoal = normalized['dietGoal'] ?? normalized['diet_goal'];
    if (rawGoal is Iterable) {
      normalized['dietGoal'] = ProfileValueMapper.firstDietGoalToApi(
        rawGoal.map((item) => item.toString()),
      );
    } else {
      normalized['dietGoal'] = ProfileValueMapper.dietGoalToApi(
        rawGoal?.toString(),
      );
    }

    // 寵物類型轉譯
    normalized['petType'] = ProfileValueMapper.petTypeToApi(
      normalized['petType']?.toString(),
    );

    return normalized;
  }

  Future<Map<String, dynamic>> deleteAccount() async {
    final prefs = await SharedPreferences.getInstance();
    final token = await _tokenStorage.readAccessToken();

    if (token == null || token.isEmpty) {
      return {'success': false, 'message': '未登入'};
    }

    try {
      final response = await _client.delete(
        '/user/account',
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = _decodeBody(response.body);

      if (response.statusCode == 200) {
        await _clearSession(prefs);
        return {'success': true, 'message': data['message'] ?? '帳號已註銷'};
      }

      return {'success': false, 'message': data['message'] ?? '註銷失敗'};
    } catch (_) {
      return {'success': false, 'message': '連線失敗，請稍後再試'};
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await _clearSession(prefs);
  }

  Future<bool> isAdmin() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('user_role')?.trim().toUpperCase();
    return role == 'ROLE_ADMIN';
  }

  Future<Map<String, dynamic>> uploadAvatar(
    List<int> fileBytes,
    String filename,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final token = await _tokenStorage.readAccessToken();

    if (token == null || token.isEmpty) {
      return {'success': false, 'message': '未登入'};
    }

    try {
      final response = await _client.multipart(
        '/user/avatar',
        fileBytes,
        filename,
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = _decodeBody(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        final avatarUrl = data['data']?.toString();
        if (avatarUrl != null && avatarUrl.isNotEmpty) {
          await prefs.setString('user_avatar_url', avatarUrl);
        }
        return {'success': true, 'avatarUrl': avatarUrl};
      }

      return {'success': false, ...data};
    } catch (_) {
      return {'success': false, 'message': '上傳頭像失敗，請稍後再試'};
    }
  }

  Future<Map<String, dynamic>> submitProblemFeedback(String content) async {
    final token = await _tokenStorage.readAccessToken();
    final trimmedContent = content.trim();

    if (token == null || token.isEmpty) {
      return {'success': false, 'message': '請重新登入。'};
    }
    if (trimmedContent.isEmpty) {
      return {'success': false, 'message': '請輸入問題內容。'};
    }

    try {
      final response = await _client.post(
        '/user/problem-feedback',
        {'content': trimmedContent},
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = _decodeBody(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return {'success': true, ...data};
      }

      return {'success': false, 'message': FriendlyErrorMessage.generic};
    } catch (e) {
      return {'success': false, 'message': FriendlyErrorMessage.generic};
    }
  }

  Future<Map<String, dynamic>> uploadProblemFeedbackPhoto(
    int feedbackId,
    List<int> fileBytes,
    String filename,
  ) async {
    final token = await _tokenStorage.readAccessToken();

    if (token == null || token.isEmpty) {
      return {'success': false, 'message': '請重新登入。'};
    }

    try {
      final response = await _client.multipart(
        '/user/problem-feedback/$feedbackId/photo',
        fileBytes,
        filename,
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = _decodeBody(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return {'success': true, 'data': data['data'] ?? data};
      }

      return {'success': false, 'message': FriendlyErrorMessage.upload};
    } catch (_) {
      return {'success': false, 'message': FriendlyErrorMessage.upload};
    }
  }

  Future<List<dynamic>> listMyProblemFeedback() async {
    final token = await _tokenStorage.readAccessToken();

    if (token == null || token.isEmpty) {
      return [];
    }

    try {
      final response = await _client.get(
        '/user/problem-feedback',
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = _decodeBody(response.body);
      final feedbackList = data['data'];

      if (response.statusCode == 200 && feedbackList is List) {
        return feedbackList;
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<String?> getAccessToken() async {
    return _tokenStorage.readAccessToken();
  }

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await _clearSession(prefs);
  }

  Future<Map<String, dynamic>> _handleAuthResponse(
    int statusCode,
    Map<String, dynamic> data, {
    bool preserveOnboardingState = false,
    String? rawBody,
  }) async {
    if (statusCode != 200) {
      return {'success': false, ...data};
    }

    var accessToken = data['accessToken']?.toString() ?? '';
    if (accessToken.isEmpty && data['token'] != null) {
      accessToken = data['token'].toString();
    }
    if (accessToken.isEmpty && rawBody != null) {
      final trimmed = rawBody.trim();
      if (!trimmed.startsWith('{') && trimmed.split('.').length == 3) {
        accessToken = trimmed;
      }
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
      refreshTokenExpiresInSeconds: _asInt(
        data['refreshTokenExpiresInSeconds'],
      ),
    );
    ApiClient.setLatestAccessToken(accessToken);

    final role = data['role']?.toString();
    if (role != null && role.isNotEmpty) {
      await prefs.setString('user_role', role);
    } else {
      await prefs.remove('user_role');
    }

    final needsOnboarding = preserveOnboardingState
        ? (prefs.getBool(needsOnboardingKey) ?? false)
        : (data['needsOnboarding'] == true);
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

  Future<void> _cacheUserProfile(Map<String, dynamic> userData) async {
    final prefs = await SharedPreferences.getInstance();
    final email =
        userData['email']?.toString() ?? userData['user']?['email']?.toString();
    final nickname = userData['nickname']?.toString();
    final petType = userData['petType']?.toString();
    final gender = userData['gender']?.toString();
    final birthDate =
        userData['birthDate']?.toString() ??
        userData['birth_date']?.toString() ??
        userData['birthday']?.toString();
    final role =
        userData['user']?['role']?.toString() ?? userData['role']?.toString();
    final avatarUrl =
        userData['avatarUrl']?.toString() ??
        userData['user']?['avatarUrl']?.toString();
    final dietGoal =
        userData['dietGoal']?.toString() ?? userData['diet_goal']?.toString();
    final age = _asInt(userData['age']);
    final height = _asDouble(userData['height']);
    final weight = _asDouble(userData['weight']);
    final healthConditions = userData['healthConditions'];

    final isAdmin = role == 'ROLE_ADMIN';
    if (email != null && email.isNotEmpty) {
      await prefs.setString('user_email', email);
    }
    if (nickname != null && nickname.isNotEmpty) {
      final finalNick = (isAdmin && nickname == '使用者') ? '系統管理員' : nickname;
      await prefs.setString('user_nickname', finalNick);
    } else if (isAdmin) {
      await prefs.setString('user_nickname', '系統管理員');
    }
    if (petType != null) {
      await prefs.setString(
        'user_pet_type',
        ProfileValueMapper.petTypeToDisplay(petType),
      );
      await prefs.setString(
        'user_pet_type_raw',
        ProfileValueMapper.petTypeToApi(petType),
      );
    }
    if (gender != null) {
      await prefs.setString('user_gender', gender);
    }
    if (birthDate != null && birthDate.isNotEmpty) {
      await prefs.setString('user_birth_date', birthDate);
    }
    if (role != null) {
      await prefs.setString('user_role', role);
    }
    if (avatarUrl != null && avatarUrl.trim().isNotEmpty) {
      await prefs.setString('user_avatar_url', avatarUrl.trim());
    } else {
      await prefs.remove('user_avatar_url');
    }
    if (dietGoal != null) {
      await prefs.setString(
        'user_diet_goal',
        ProfileValueMapper.dietGoalToDisplay(dietGoal),
      );
      await prefs.setString(
        'user_diet_goal_raw',
        ProfileValueMapper.dietGoalToApi(dietGoal),
      );
    }
    if (age > 0) {
      await prefs.setInt('user_age', age);
    }
    if (height > 0) {
      await prefs.setDouble('user_height', height);
    }
    if (weight > 0) {
      await prefs.setDouble('user_weight', weight);
    }
    if (healthConditions is List) {
      await prefs.setStringList(
        'user_health_conditions_raw',
        ProfileValueMapper.healthConditionsToApi(healthConditions),
      );
    }
  }

  Future<void> _clearSession(SharedPreferences prefs) async {
    ApiClient.clearLatestAccessToken();
    await _tokenStorage.clear();
    // Remove legacy unencrypted keys left by older app versions.
    await prefs.remove(accessTokenKey);
    await prefs.remove(refreshTokenKey);
    await prefs.remove(tokenTypeKey);
    await prefs.remove(needsOnboardingKey);
    await prefs.remove(accessTokenExpiresKey);
    await prefs.remove(refreshTokenExpiresKey);
    await prefs.remove('user_role');
    await prefs.remove('user_email');
    await prefs.remove('user_nickname');
    await prefs.remove('user_avatar_url');
    await prefs.remove('user_password');
  }

  Map<String, dynamic> _decodeBody(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return {};
    } catch (_) {
      return {};
    }
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  double _asDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}') ?? 0;
  }
}
