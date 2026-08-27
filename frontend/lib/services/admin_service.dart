import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_client.dart';

class AdminService {
  final ApiClient _client = ApiClient();

  Future<String?> _token() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt_token');
  }

  Map<String, dynamic> _decodeMap(String body) {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return {};
  }

  dynamic _unwrapData(String body) {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic> && decoded.containsKey('data')) {
      return decoded['data'];
    }
    return decoded;
  }

  Future<List<dynamic>> listUsers({String? keyword}) async {
    final token = await _token();
    if (token == null) return [];

    try {
      final path = keyword != null && keyword.isNotEmpty
          ? '/admin/users?keyword=${Uri.encodeComponent(keyword)}'
          : '/admin/users';

      final response = await _client.get(
        path,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = _unwrapData(response.body);
        return data is List ? data : [];
      }
      return [];
    } catch (e) {
      print('Load users failed: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> getUserDetail(int id) async {
    final token = await _token();
    if (token == null) return null;

    try {
      final response = await _client.get(
        '/admin/users/$id',
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = _unwrapData(response.body);
        return data is Map<String, dynamic> ? data : null;
      }
      return null;
    } catch (e) {
      print('Load user detail failed: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>> createUser(Map<String, dynamic> userData) async {
    final token = await _token();
    if (token == null) {
      return {'success': false, 'message': 'Please sign in again.'};
    }

    try {
      final response = await _client.post(
        '/admin/users',
        userData,
        headers: {'Authorization': 'Bearer $token'},
      );

      final data = _decodeMap(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, 'data': data['data'] ?? data};
      }
      return {'success': false, ...data};
    } catch (e) {
      return {'success': false, 'message': 'Create user failed: $e'};
    }
  }

  Future<Map<String, dynamic>> updateUser(
    int id,
    Map<String, dynamic> userData,
  ) async {
    final token = await _token();
    if (token == null) {
      return {'success': false, 'message': 'Please sign in again.'};
    }

    try {
      final response = await _client.put(
        '/admin/users/$id',
        userData,
        headers: {'Authorization': 'Bearer $token'},
      );

      final data = _decodeMap(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'data': data['data'] ?? data};
      }
      return {'success': false, ...data};
    } catch (e) {
      return {'success': false, 'message': 'Update user failed: $e'};
    }
  }

  Future<Map<String, dynamic>> updateUserStatus(int id, bool enabled) async {
    final token = await _token();
    if (token == null) {
      return {'success': false, 'message': '請重新登入'};
    }

    try {
      final response = await _client.put(
        '/admin/users/$id/status',
        {'enabled': enabled},
        headers: {'Authorization': 'Bearer $token'},
      );

      final data = _decodeMap(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'data': data['data'] ?? data};
      }

      return {
        'success': false,
        ...data,
        'message': data['message'] ?? data['error'] ?? '更新狀態失敗 (${response.statusCode})',
      };
    } catch (e) {
      return {'success': false, 'message': '更新使用者狀態失敗，請稍後再試'};
    }
  }

  Future<List<dynamic>> listRestaurants({String? name}) async {
    return [];
  }

  Future<Map<String, dynamic>> createRestaurant(Map<String, dynamic> data) async {
    return {
      'success': false,
      'message': 'Restaurant management has been removed from the frontend.',
    };
  }

  Future<Map<String, dynamic>> updateRestaurant(
    int id,
    Map<String, dynamic> data,
  ) async {
    return {
      'success': false,
      'message': 'Restaurant management has been removed from the frontend.',
    };
  }

  Future<bool> deleteRestaurant(int id) async {
    return false;
  }

  Future<List<dynamic>> listMenuItems({String? dishName}) async {
    return [];
  }

  Future<Map<String, dynamic>> createMenuItem(Map<String, dynamic> data) async {
    return {
      'success': false,
      'message': 'Menu management has been removed from the frontend.',
    };
  }

  Future<Map<String, dynamic>> updateMenuItem(
    int id,
    Map<String, dynamic> data,
  ) async {
    return {
      'success': false,
      'message': 'Menu management has been removed from the frontend.',
    };
  }

  Future<bool> deleteMenuItem(int id) async {
    return false;
  }

  Future<List<dynamic>> listDietRecords({
    int? userId,
    String? nickname,
    String? dishName,
    String? mealType,
  }) async {
    final token = await _token();
    if (token == null) return [];

    try {
      final params = <String>[];
      if (userId != null) {
        params.add('userId=$userId');
      }
      if (nickname != null && nickname.isNotEmpty) {
        params.add('nickname=${Uri.encodeComponent(nickname)}');
      }
      if (dishName != null && dishName.isNotEmpty) {
        params.add('dishName=${Uri.encodeComponent(dishName)}');
      }
      if (mealType != null && mealType.isNotEmpty) {
        params.add('mealType=${Uri.encodeComponent(mealType)}');
      }

      final queryString = params.isNotEmpty ? '?${params.join('&')}' : '';
      final response = await _client.get(
        '/admin/diet-records$queryString',
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = _unwrapData(response.body);
        return data is List ? data : [];
      }
      return [];
    } catch (e) {
      print('Load admin diet records failed: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> updateDietRecord(
    int id,
    Map<String, dynamic> data,
  ) async {
    final token = await _token();
    if (token == null) {
      return {'success': false, 'message': 'Please sign in again.'};
    }

    try {
      final response = await _client.put(
        '/admin/diet-records/$id',
        data,
        headers: {'Authorization': 'Bearer $token'},
      );

      final decoded = _decodeMap(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'data': decoded['data'] ?? decoded};
      }
      return {
        'success': false,
        ...decoded,
        'message': decoded['message'] ?? decoded['error'] ?? '更新失敗 (${response.statusCode})',
      };
    } catch (e) {
      return {'success': false, 'message': 'Update diet record failed: $e'};
    }
  }

  Future<bool> deleteDietRecord(int id) async {
    final token = await _token();
    if (token == null) return false;

    try {
      final response = await _client.delete(
        '/admin/diet-records/$id',
        headers: {'Authorization': 'Bearer $token'},
      );
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (e) {
      print('Delete diet record failed: $e');
      return false;
    }
  }

  Future<Map<String, double?>> fetchDishNutrition(String dishName) async {
    final token = await _token();
    if (token == null || dishName.trim().isEmpty) {
      return {'calories': null, 'protein': null, 'fat': null, 'carbohydrates': null};
    }
    try {
      final response = await _client.post(
        '/dietary-agent/dish-nutrition',
        {'dish_name': dishName.trim()},
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        final decoded = _decodeMap(response.body);
        final dishNut = decoded['data']?['dish_nutrition'] ?? decoded['dish_nutrition'];
        if (dishNut != null && dishNut['nutrients'] is List) {
          final List nutrients = dishNut['nutrients'];
          double? calories;
          double? protein;
          double? fat;
          double? carbs;

          for (final n in nutrients) {
            if (n is Map) {
              final String name = (n['name'] ?? '').toString();
              final double? amt = double.tryParse((n['amount_per_serving'] ?? '').toString());
              if (amt != null) {
                if (name.contains('熱量') || name.contains('calories') || name.contains('kcal')) {
                  calories = amt;
                } else if (name.contains('蛋白質') || name.contains('protein')) {
                  protein = amt;
                } else if (name.contains('脂肪') || name.contains('fat')) {
                  fat = amt;
                } else if (name.contains('碳水') || name.contains('carbohydrate')) {
                  carbs = amt;
                }
              }
            }
          }
          return {
            'calories': calories,
            'protein': protein,
            'fat': fat,
            'carbohydrates': carbs,
          };
        }
      }
    } catch (e) {
      print('Fetch dish nutrition error: $e');
    }
    return {'calories': null, 'protein': null, 'fat': null, 'carbohydrates': null};
  }

  Future<Map<String, dynamic>> createDietRecord(
    int userId,
    Map<String, dynamic> data,
  ) async {
    final token = await _token();
    if (token == null) {
      return {'success': false, 'message': 'Please sign in again.'};
    }

    try {
      final response = await _client.post(
        '/admin/diet-records?userId=$userId',
        data,
        headers: {'Authorization': 'Bearer $token'},
      );

      final decoded = _decodeMap(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, 'data': decoded['data'] ?? decoded};
      }
      return {
        'success': false,
        ...decoded,
        'message': decoded['message'] ?? decoded['error'] ?? '新增失敗 (${response.statusCode})',
      };
    } catch (e) {
      return {'success': false, 'message': 'Create diet record failed: $e'};
    }
  }

  Future<List<dynamic>> listProblemFeedback() async {
    final token = await _token();
    if (token == null) return [];

    try {
      final response = await _client.get(
        '/admin/problem-feedback',
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = _unwrapData(response.body);
        return data is List ? data : [];
      }
      return [];
    } catch (e) {
      print('Load problem feedback failed: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> replyProblemFeedback(
    int id,
    String adminReply,
  ) async {
    final token = await _token();
    if (token == null) {
      return {'success': false, 'message': '請重新登入'};
    }

    try {
      final response = await _client.put(
        '/admin/problem-feedback/$id/reply',
        {'adminReply': adminReply.trim()},
        headers: {'Authorization': 'Bearer $token'},
      );

      final data = _decodeMap(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {'success': true, 'data': data['data'] ?? data};
      }
      return {
        'success': false,
        ...data,
        'message': data['message'] ?? data['error'] ?? '回覆失敗 (${response.statusCode})',
      };
    } catch (e) {
      return {'success': false, 'message': '回覆失敗，請稍後再試'};
    }
  }
}
