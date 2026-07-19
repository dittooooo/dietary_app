import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_client.dart';

class DietService {
  final ApiClient _client = ApiClient();

  // 取得當前使用者的歷史飲食紀錄
  Future<List<dynamic>> getMyDietRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token == null) return [];

    try {
      final response = await _client.get(
        '/diet-records',
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) {
          return data;
        } else if (data is Map && data.containsKey('data')) {
          return data['data'] ?? [];
        }
        return [];
      }
      return [];
    } catch (e) {
      print('取得飲食紀錄失敗: $e');
      return [];
    }
  }

  // 新增飲食紀錄
  Future<Map<String, dynamic>> createDietRecord({
    required String dishName,
    required String mealType,
    required String description,
    String nutrition = '',
    DateTime? mealDate,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token == null) return {'success': false, 'message': '未登入'};

    // 解析各個雙精度浮點數欄位
    double? parseVal(String pattern) {
      final regExp = RegExp(pattern + r':\s*(\d+(?:\.\d+)?)', caseSensitive: false);
      final match = regExp.firstMatch(nutrition);
      if (match != null) {
        return double.tryParse(match.group(1) ?? '');
      }
      return null;
    }

    final calories = parseVal(r'(?:熱量|calories|kcal)');
    final protein = parseVal(r'(?:蛋白質|protein)');
    final fat = parseVal(r'(?:脂肪|fat)');
    final carbohydrates = parseVal(r'(?:碳水化合物|碳水|carbs|carbohydrates)');

    final String? formattedDate = mealDate != null 
        ? "${mealDate.year}-${mealDate.month.toString().padLeft(2, '0')}-${mealDate.day.toString().padLeft(2, '0')}" 
        : null;

    try {
      final response = await _client.post(
        '/diet-records',
        {
          'dishName': dishName,
          'mealType': mealType,
          'description': description,
          'calories': calories,
          'protein': protein,
          'fat': fat,
          'carbohydrates': carbohydrates,
          'mealDate': formattedDate,
        },
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        return {'success': true, 'data': data};
      }
      return {'success': false, 'message': '新增失敗，請檢查網路連線或稍後再試'};
    } catch (e) {
      return {'success': false, 'message': '連線失敗: $e'};
    }
  }

  // 上傳飲食紀錄照片
  Future<Map<String, dynamic>> uploadDietPhoto(int recordId, List<int> fileBytes, String filename) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token == null) return {'success': false, 'message': '未登入'};

    try {
      final response = await _client.multipart(
        '/diet-records/$recordId/photo',
        fileBytes,
        filename,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        return {'success': true, 'data': data};
      }
      return {'success': false, 'message': '照片上傳失敗，請稍後再試'};
    } catch (e) {
      return {'success': false, 'message': '照片上傳連線失敗: $e'};
    }
  }

  // 刪除飲食紀錄
  Future<bool> deleteDietRecord(int id) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token == null) return false;

    try {
      final response = await _client.delete(
        '/diet-records/$id',
        headers: {'Authorization': 'Bearer $token'},
      );
      return response.statusCode == 200;
    } catch (e) {
      print('刪除飲食紀錄失敗: $e');
      return false;
    }
  }

  // 修改飲食紀錄
  Future<Map<String, dynamic>> updateDietRecord(int id, {
    required String dishName,
    required String mealType,
    required String description,
    String nutrition = '',
    DateTime? mealDate,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token == null) return {'success': false, 'message': '未登入'};

    // 解析字串以傳送後端 Spring Boot 期待的各個雙精度浮點數欄位
    double? parseVal(String pattern) {
      final regExp = RegExp(pattern + r':\s*(\d+(?:\.\d+)?)', caseSensitive: false);
      final match = regExp.firstMatch(nutrition);
      if (match != null) {
        return double.tryParse(match.group(1) ?? '');
      }
      return null;
    }

    final calories = parseVal(r'(?:熱量|calories|kcal)');
    final protein = parseVal(r'(?:蛋白質|protein)');
    final fat = parseVal(r'(?:脂肪|fat)');
    final carbohydrates = parseVal(r'(?:碳水化合物|碳水|carbs|carbohydrates)');

    final String? formattedDate = mealDate != null 
        ? "${mealDate.year}-${mealDate.month.toString().padLeft(2, '0')}-${mealDate.day.toString().padLeft(2, '0')}" 
        : null;

    try {
      final response = await _client.put(
        '/diet-records/$id',
        {
          'dishName': dishName,
          'mealType': mealType,
          'description': description,
          'calories': calories,
          'protein': protein,
          'fat': fat,
          'carbohydrates': carbohydrates,
          'mealDate': formattedDate,
        },
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        return {'success': true, 'data': data};
      }
      return {'success': false, 'message': '修改失敗，請稍後再試'};
    } catch (e) {
      return {'success': false, 'message': '修改連線失敗: $e'};
    }
  }

  // 智能小精靈與週報告分析
  Future<Map<String, dynamic>> askWeeklyAnalysis(String question) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token == null) return {'success': false, 'message': '未登入'};

    try {
      final response = await _client.post(
        '/dietary/ask-weekly-analysis',
        {
          'question': question,
          'questionType': 'WEEKLY_ANALYSIS',
          'dishNames': ['general'],
        },
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        return {'success': true, 'data': data};
      }
      return {'success': false, 'message': '智能分析讀取失敗，請確認資料後再試'};
    } catch (e) {
      return {'success': false, 'message': '智能分析連線失敗: $e'};
    }
  }
}
