import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_client.dart';

class AdminService {
  final ApiClient _client = ApiClient();

  // 取得全系統使用者清單 (支援搜尋關鍵字)
  Future<List<dynamic>> listUsers({String? keyword}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
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
        final data = jsonDecode(response.body);
        if (data is List) {
          return data;
        }
        return [];
      }
      return [];
    } catch (e) {
      print('管理員取得使用者清單失敗: $e');
      return [];
    }
  }

  // 取得特定使用者詳情
  Future<Map<String, dynamic>?> getUserDetail(int id) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token == null) return null;

    try {
      final response = await _client.get(
        '/admin/users/$id',
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      print('管理員取得使用者詳情失敗: $e');
      return null;
    }
  }

  // 新增使用者
  Future<Map<String, dynamic>> createUser(Map<String, dynamic> userData) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token == null) return {'success': false, 'message': '未登入'};

    try {
      final response = await _client.post(
        '/admin/users',
        userData,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'message': '新增失敗 (${response.statusCode})'};
    } catch (e) {
      return {'success': false, 'message': '連線失敗: $e'};
    }
  }

  // 編輯使用者
  Future<Map<String, dynamic>> updateUser(int id, Map<String, dynamic> userData) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token == null) return {'success': false, 'message': '未登入'};

    try {
      final response = await _client.put(
        '/admin/users/$id',
        userData,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'message': '更新失敗 (${response.statusCode})'};
    } catch (e) {
      return {'success': false, 'message': '連線失敗: $e'};
    }
  }

  // 刪除使用者
  Future<bool> deleteUser(int id) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token == null) return false;

    try {
      final response = await _client.delete(
        '/admin/users/$id',
        headers: {'Authorization': 'Bearer $token'},
      );
      return response.statusCode == 200;
    } catch (e) {
      print('管理員刪除使用者失敗: $e');
      return false;
    }
  }

  // ===== 餐廳管理 API =====
  Future<List<dynamic>> listRestaurants({String? name}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token == null) return [];
    try {
      final path = name != null && name.isNotEmpty
          ? '/admin/restaurants?name=${Uri.encodeComponent(name)}'
          : '/admin/restaurants';
      final response = await _client.get(path, headers: {'Authorization': 'Bearer $token'});
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data is List ? data : [];
      }
      return [];
    } catch (e) {
      print('列出餐廳失敗: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> createRestaurant(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token == null) return {'success': false, 'message': '未登入'};
    try {
      final response = await _client.post('/admin/restaurants', data, headers: {'Authorization': 'Bearer $token'});
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'message': '新增餐廳失敗 (${response.statusCode})'};
    } catch (e) {
      return {'success': false, 'message': '新增餐廳連線失敗: $e'};
    }
  }

  Future<Map<String, dynamic>> updateRestaurant(int id, Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token == null) return {'success': false, 'message': '未登入'};
    try {
      final response = await _client.put('/admin/restaurants/$id', data, headers: {'Authorization': 'Bearer $token'});
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'message': '更新餐廳失敗 (${response.statusCode})'};
    } catch (e) {
      return {'success': false, 'message': '更新餐廳連線失敗: $e'};
    }
  }

  Future<bool> deleteRestaurant(int id) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token == null) return false;
    try {
      final response = await _client.delete('/admin/restaurants/$id', headers: {'Authorization': 'Bearer $token'});
      return response.statusCode == 200;
    } catch (e) {
      print('刪除餐廳失敗: $e');
      return false;
    }
  }

  // ===== 菜單管理 API =====
  Future<List<dynamic>> listMenuItems({String? dishName}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token == null) return [];
    try {
      final path = dishName != null && dishName.isNotEmpty
          ? '/admin/menus?dishName=${Uri.encodeComponent(dishName)}'
          : '/admin/menus';
      final response = await _client.get(path, headers: {'Authorization': 'Bearer $token'});
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data is List ? data : [];
      }
      return [];
    } catch (e) {
      print('列出菜單失敗: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> createMenuItem(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token == null) return {'success': false, 'message': '未登入'};
    try {
      final response = await _client.post('/admin/menus', data, headers: {'Authorization': 'Bearer $token'});
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'message': '新增菜單失敗 (${response.statusCode})'};
    } catch (e) {
      return {'success': false, 'message': '新增菜單連線失敗: $e'};
    }
  }

  Future<Map<String, dynamic>> updateMenuItem(int id, Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token == null) return {'success': false, 'message': '未登入'};
    try {
      final response = await _client.put('/admin/menus/$id', data, headers: {'Authorization': 'Bearer $token'});
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'message': '更新菜單失敗 (${response.statusCode})'};
    } catch (e) {
      return {'success': false, 'message': '更新菜單連線失敗: $e'};
    }
  }

  Future<bool> deleteMenuItem(int id) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token == null) return false;
    try {
      final response = await _client.delete('/admin/menus/$id', headers: {'Authorization': 'Bearer $token'});
      return response.statusCode == 200;
    } catch (e) {
      print('刪除菜單失敗: $e');
      return false;
    }
  }

  // ===== 飲食紀錄監控 API =====
  Future<List<dynamic>> listDietRecords({String? nickname, String? dishName, String? mealType}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token == null) return [];
    try {
      final List<String> params = [];
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
      final response = await _client.get('/admin/diet-records$queryString', headers: {'Authorization': 'Bearer $token'});
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data is List ? data : [];
      }
      return [];
    } catch (e) {
      print('列出飲食紀錄監控失敗: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> updateDietRecord(int id, Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token == null) return {'success': false, 'message': '未登入'};
    try {
      final response = await _client.put('/admin/diet-records/$id', data, headers: {'Authorization': 'Bearer $token'});
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'message': '更新飲食紀錄失敗 (${response.statusCode})'};
    } catch (e) {
      return {'success': false, 'message': '更新飲食紀錄連線失敗: $e'};
    }
  }

  Future<bool> deleteDietRecord(int id) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token == null) return false;
    try {
      final response = await _client.delete('/admin/diet-records/$id', headers: {'Authorization': 'Bearer $token'});
      return response.statusCode == 200;
    } catch (e) {
      print('刪除飲食紀錄失敗: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>> createDietRecord(int userId, Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token == null) return {'success': false, 'message': '未登入'};
    try {
      final response = await _client.post(
        '/admin/diet-records?userId=$userId',
        data,
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'message': '新增飲食紀錄失敗 (${response.statusCode})'};
    } catch (e) {
      return {'success': false, 'message': '新增飲食紀錄連線失敗: $e'};
    }
  }
}
