import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_client.dart';
import '../utils/profile_value_mapper.dart';

class AuthService {
  static const String accessTokenKey = 'jwt_token';
  static const String refreshTokenKey = 'refresh_token';
  static const String tokenTypeKey = 'token_type';
  static const String needsOnboardingKey = 'needs_onboarding';
  static const String accessTokenExpiresKey = 'access_token_expires_in_seconds';
  static const String refreshTokenExpiresKey = 'refresh_token_expires_in_seconds';

  final ApiClient _client = ApiClient();

  Future<Map<String, dynamic>> login(String email, String password) async {
    final response = await _client.post('/login', {
      'email': email,
      'password': password,
    });

    final data = _decodeBody(response.body);
    return _handleAuthResponse(response.statusCode, data);
  }

  Future<Map<String, dynamic>> register(String email, String password) async {
    final response = await _client.post('/register', {
      'email': email,
      'password': password,
    });

    final data = _decodeBody(response.body);
    return _handleAuthResponse(response.statusCode, data);
  }

  Future<Map<String, dynamic>> refreshAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString(refreshTokenKey);

    if (refreshToken == null || refreshToken.isEmpty) {
      return {
        'success': false,
        'message': 'No refresh token found.',
      };
    }

    final response = await _client.post('/refresh', {
      'refreshToken': refreshToken,
    });

    final data = _decodeBody(response.body);
    return _handleAuthResponse(
      response.statusCode,
      data,
      preserveOnboardingState: true,
    );
  }

  Future<Map<String, dynamic>> getUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(accessTokenKey);

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

      if (response.statusCode == 200 &&
          userData is Map<String, dynamic> &&
          userData.isNotEmpty) {
        await _cacheUserProfile(userData);
        await prefs.setBool(needsOnboardingKey, false);
        return {'success': true, 'data': userData};
      }

      return {'success': false, ...data};
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
    final token = prefs.getString(accessTokenKey);

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

  Map<String, dynamic> _normalizeProfilePayload(Map<String, dynamic> profileData) {
    final normalized = Map<String, dynamic>.from(profileData);

    final healthConditions = normalized['healthConditions'];
    if (healthConditions is Iterable) {
      normalized['healthConditions'] =
          ProfileValueMapper.healthConditionsToApi(healthConditions);
    }

    final dietGoal = normalized['dietGoal'];
    if (dietGoal is Iterable) {
      normalized['dietGoal'] = ProfileValueMapper.firstDietGoalToApi(
        dietGoal.map((item) => item.toString()),
      );
    } else {
      normalized['dietGoal'] =
          ProfileValueMapper.dietGoalToApi(dietGoal?.toString());
    }

    normalized['petType'] =
        ProfileValueMapper.petTypeToApi(normalized['petType']?.toString());

    return normalized;
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await _clearSession(prefs);
  }

  Future<bool> isAdmin() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('user_role');
    return role == 'ROLE_ADMIN';
  }

  Future<Map<String, dynamic>> uploadAvatar(
    List<int> fileBytes,
    String filename,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(accessTokenKey);

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
    } catch (e) {
      return {'success': false, 'message': '上傳頭像失敗: $e'};
    }
  }

  Future<String?> getAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(accessTokenKey);
  }

  Future<bool> getNeedsOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(needsOnboardingKey) ?? false;
  }

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await _clearSession(prefs);
  }

  Future<Map<String, dynamic>> _handleAuthResponse(
    int statusCode,
    Map<String, dynamic> data, {
    bool preserveOnboardingState = false,
  }) async {
    if (statusCode != 200) {
      return {'success': false, ...data};
    }

    final accessToken = data['accessToken']?.toString() ?? '';
    final refreshToken = data['refreshToken']?.toString() ?? '';

    if (accessToken.isEmpty || refreshToken.isEmpty) {
      return {
        'success': false,
        'message': data['message'] ?? 'Auth response is missing tokens.',
      };
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(accessTokenKey, accessToken);
    await prefs.setString(refreshTokenKey, refreshToken);
    await prefs.setString(tokenTypeKey, data['tokenType']?.toString() ?? 'Bearer');

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

    await prefs.setInt(
      accessTokenExpiresKey,
      _asInt(data['accessTokenExpiresInSeconds']),
    );
    await prefs.setInt(
      refreshTokenExpiresKey,
      _asInt(data['refreshTokenExpiresInSeconds']),
    );

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
    final email = userData['email']?.toString() ??
        userData['user']?['email']?.toString();
    final nickname = userData['nickname']?.toString();
    final petType = userData['petType']?.toString();
    final gender = userData['gender']?.toString();
    final role = userData['user']?['role']?.toString() ??
        userData['role']?.toString();
    final dietGoal = userData['dietGoal']?.toString() ??
        userData['diet_goal']?.toString();
    final age = _asInt(userData['age']);
    final height = _asDouble(userData['height']);
    final weight = _asDouble(userData['weight']);
    final healthConditions = userData['healthConditions'];

    if (email != null && email.isNotEmpty) {
      await prefs.setString('user_email', email);
    }
    if (nickname != null) {
      await prefs.setString('user_nickname', nickname);
    }
    if (petType != null) {
      await prefs.setString(
        'user_pet_type',
        ProfileValueMapper.petTypeToDisplay(petType),
      );
      await prefs.setString('user_pet_type_raw', ProfileValueMapper.petTypeToApi(petType));
    }
    if (gender != null) {
      await prefs.setString('user_gender', gender);
    }
    if (role != null) {
      await prefs.setString('user_role', role);
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
    await prefs.remove(accessTokenKey);
    await prefs.remove(refreshTokenKey);
    await prefs.remove(tokenTypeKey);
    await prefs.remove(needsOnboardingKey);
    await prefs.remove(accessTokenExpiresKey);
    await prefs.remove(refreshTokenExpiresKey);
    await prefs.remove('user_role');
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
