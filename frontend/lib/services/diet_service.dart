import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_client.dart';

class DietService {
  final ApiClient _client = ApiClient();

  String _mealTypeForApi(String mealType) {
    switch (mealType.trim().toUpperCase()) {
      case '早餐':
      case 'BREAKFAST':
        return 'BREAKFAST';
      case '午餐':
      case 'LUNCH':
        return 'LUNCH';
      case '晚餐':
      case 'DINNER':
        return 'DINNER';
      default:
        return mealType;
    }
  }

  Map<String, double?> _parseNutrition(String nutrition) {
    double? parseVal(String pattern) {
      final regExp = RegExp(pattern, caseSensitive: false);
      final match = regExp.firstMatch(nutrition);
      if (match == null) return null;
      return double.tryParse(match.group(1) ?? '');
    }

    return {
      'calories': parseVal(r'(?:熱量|calories|kcal)\D*(\d+(?:\.\d+)?)'),
      'protein': parseVal(r'(?:蛋白質|protein)\D*(\d+(?:\.\d+)?)'),
      'fat': parseVal(r'(?:脂肪|fat)\D*(\d+(?:\.\d+)?)'),
      'carbohydrates': parseVal(r'(?:碳水化合物|碳水|carbs|carbohydrates)\D*(\d+(?:\.\d+)?)'),
    };
  }

  String _formatDate(DateTime? mealDate) {
    if (mealDate == null) return '';
    final month = mealDate.month.toString().padLeft(2, '0');
    final day = mealDate.day.toString().padLeft(2, '0');
    return '${mealDate.year}-$month-$day';
  }

  Future<String?> _token() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt_token');
  }

  String _errorMessage(String action, int statusCode, String body) {
    final detail = body.trim().isEmpty ? 'no response body' : body;
    return '$action failed ($statusCode): $detail';
  }

  Future<List<dynamic>> getMyDietRecords() async {
    final token = await _token();
    if (token == null) return [];

    try {
      final response = await _client.get(
        '/diet-records',
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) return data;
        if (data is Map && data.containsKey('data')) return data['data'] ?? [];
      }
      return [];
    } catch (e) {
      print('Load diet records failed: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> createDietRecord({
    required String dishName,
    required String mealType,
    required String description,
    String nutrition = '',
    DateTime? mealDate,
  }) async {
    final token = await _token();
    if (token == null) {
      return {'success': false, 'message': 'Please sign in again.'};
    }

    final parsedNutrition = _parseNutrition(nutrition);

    try {
      final response = await _client.post(
        '/diet-records',
        {
          'dishName': dishName,
          'mealType': _mealTypeForApi(mealType),
          'description': description,
          'nutrition': nutrition,
          'calories': parsedNutrition['calories'],
          'protein': parsedNutrition['protein'],
          'fat': parsedNutrition['fat'],
          'carbohydrates': parsedNutrition['carbohydrates'],
          if (mealDate != null) 'mealDate': _formatDate(mealDate),
        },
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return {'success': true, 'data': data};
      }

      return {
        'success': false,
        'message': _errorMessage('Create diet record', response.statusCode, response.body),
      };
    } catch (e) {
      return {'success': false, 'message': 'Create diet record failed: $e'};
    }
  }

  Future<Map<String, dynamic>> uploadDietPhoto(int recordId, List<int> fileBytes, String filename) async {
    final token = await _token();
    if (token == null) {
      return {'success': false, 'message': 'Please sign in again.'};
    }

    try {
      final response = await _client.multipart(
        '/diet-records/$recordId/photo',
        fileBytes,
        filename,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return {'success': true, 'data': data};
      }

      return {
        'success': false,
        'message': _errorMessage('Upload diet photo', response.statusCode, response.body),
      };
    } catch (e) {
      return {'success': false, 'message': 'Upload diet photo failed: $e'};
    }
  }

  Future<bool> deleteDietRecord(int id) async {
    final token = await _token();
    if (token == null) return false;

    try {
      final response = await _client.delete(
        '/diet-records/$id',
        headers: {'Authorization': 'Bearer $token'},
      );
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (e) {
      print('Delete diet record failed: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>> updateDietRecord(
    int id, {
    required String dishName,
    required String mealType,
    required String description,
    String nutrition = '',
    DateTime? mealDate,
  }) async {
    final token = await _token();
    if (token == null) {
      return {'success': false, 'message': 'Please sign in again.'};
    }

    final parsedNutrition = _parseNutrition(nutrition);

    try {
      final response = await _client.put(
        '/diet-records/$id',
        {
          'dishName': dishName,
          'mealType': _mealTypeForApi(mealType),
          'description': description,
          'nutrition': nutrition,
          'calories': parsedNutrition['calories'],
          'protein': parsedNutrition['protein'],
          'fat': parsedNutrition['fat'],
          'carbohydrates': parsedNutrition['carbohydrates'],
          if (mealDate != null) 'mealDate': _formatDate(mealDate),
        },
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return {'success': true, 'data': data};
      }

      return {
        'success': false,
        'message': _errorMessage('Update diet record', response.statusCode, response.body),
      };
    } catch (e) {
      return {'success': false, 'message': 'Update diet record failed: $e'};
    }
  }

  Future<Map<String, dynamic>> askWeeklyAnalysis(String question) async {
    final token = await _token();
    if (token == null) {
      return {'success': false, 'message': 'Please sign in again.'};
    }

    try {
      final normalizedQuestion = question.trim();
      final isSingleDish = _looksLikeSingleDish(normalizedQuestion);
      final response = await _client.post(
        '/dietary/ask-weekly-analysis',
        {
          'question': normalizedQuestion,
          'question_type': isSingleDish ? 'single_dish' : 'unknown',
          'dish_names': isSingleDish ? [normalizedQuestion] : ['general'],
        },
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {'success': true, 'data': data};
      }

      return {
        'success': false,
        'message': _errorMessage('Ask dietary analysis', response.statusCode, response.body),
      };
    } catch (e) {
      return {'success': false, 'message': 'Ask dietary analysis failed: $e'};
    }
  }
  bool _looksLikeSingleDish(String question) {
    if (question.isEmpty) return false;
    if (question.contains(RegExp(r'[?？,，、\s]'))) return false;
    if (question.toLowerCase().contains('vs')) return false;
    return question.length <= 12;
  }
}
