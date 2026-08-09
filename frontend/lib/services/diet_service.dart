import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_client.dart';
import '../utils/profile_value_mapper.dart';

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
        return mealType.trim().toUpperCase();
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
      'carbohydrates': parseVal(
        r'(?:碳水化合物|碳水|carbs|carbohydrates)\D*(\d+(?:\.\d+)?)',
      ),
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

  Future<SharedPreferences> _prefs() async {
    return SharedPreferences.getInstance();
  }

  String _errorMessage(String action, int statusCode, String body) {
    final detail = body.trim().isEmpty ? '無伺服器回應內容' : body;
    return '$action失敗 ($statusCode): $detail';
  }

  Map<String, dynamic> _decodeObject(String body) {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return {};
  }

  List<dynamic> _unwrapListResponse(String body) {
    final decoded = jsonDecode(body);
    if (decoded is List) return decoded;
    if (decoded is Map<String, dynamic>) {
      final data = decoded['data'];
      if (data is List) return data;
    }
    return [];
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
        final rawList = _unwrapListResponse(response.body);
        return rawList.map((record) {
          if (record is Map) {
            final desc = (record['description'] ?? '').toString();
            if (desc.startsWith('[MealType:OTHER]')) {
              final newRecord = Map<String, dynamic>.from(record);
              newRecord['mealType'] = 'OTHER';
              newRecord['description'] = desc.replaceFirst(
                '[MealType:OTHER]',
                '',
              );
              return newRecord;
            }
          }
          return record;
        }).toList();
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

    String apiMealType = _mealTypeForApi(mealType);
    String apiDescription = description;
    if (mealType == '其他' || mealType.trim().toUpperCase() == 'OTHER') {
      apiMealType = 'DINNER';
      apiDescription = '[MealType:OTHER]$description';
    }

    try {
      final response = await _client.post(
        '/diet-records',
        {
          'dishName': dishName,
          'mealType': apiMealType,
          'description': apiDescription,
          'nutrition': nutrition,
          'calories': parsedNutrition['calories'],
          'protein': parsedNutrition['protein'],
          'fat': parsedNutrition['fat'],
          'carbohydrates': parsedNutrition['carbohydrates'],
          if (mealDate != null) 'date': _formatDate(mealDate),
        },
        headers: {'Authorization': 'Bearer $token'},
      );

      final data = _decodeObject(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        final recordData = data['data'] ?? data;
        if (recordData is Map) {
          final desc = (recordData['description'] ?? '').toString();
          if (desc.startsWith('[MealType:OTHER]')) {
            final newRecord = Map<String, dynamic>.from(recordData);
            newRecord['mealType'] = 'OTHER';
            newRecord['description'] = desc.replaceFirst(
              '[MealType:OTHER]',
              '',
            );
            return {'success': true, 'data': newRecord};
          }
        }
        return {'success': true, 'data': recordData};
      }

      return {
        'success': false,
        'message': _errorMessage(
          'Create diet record',
          response.statusCode,
          response.body,
        ),
      };
    } catch (e) {
      return {'success': false, 'message': 'Create diet record failed: $e'};
    }
  }

  Future<Map<String, dynamic>> uploadDietPhoto(
    int recordId,
    List<int> fileBytes,
    String filename,
  ) async {
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

      final data = _decodeObject(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, 'data': data['data'] ?? data};
      }

      return {
        'success': false,
        'message': _errorMessage(
          'Upload diet photo',
          response.statusCode,
          response.body,
        ),
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

    String apiMealType = _mealTypeForApi(mealType);
    String apiDescription = description;
    if (mealType == '其他' || mealType.trim().toUpperCase() == 'OTHER') {
      apiMealType = 'DINNER';
      apiDescription = '[MealType:OTHER]$description';
    }

    try {
      final response = await _client.put(
        '/diet-records/$id',
        {
          'dishName': dishName,
          'mealType': apiMealType,
          'description': apiDescription,
          'nutrition': nutrition,
          'calories': parsedNutrition['calories'],
          'protein': parsedNutrition['protein'],
          'fat': parsedNutrition['fat'],
          'carbohydrates': parsedNutrition['carbohydrates'],
          if (mealDate != null) 'date': _formatDate(mealDate),
        },
        headers: {'Authorization': 'Bearer $token'},
      );

      final data = _decodeObject(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        final recordData = data['data'] ?? data;
        if (recordData is Map) {
          final desc = (recordData['description'] ?? '').toString();
          if (desc.startsWith('[MealType:OTHER]')) {
            final newRecord = Map<String, dynamic>.from(recordData);
            newRecord['mealType'] = 'OTHER';
            newRecord['description'] = desc.replaceFirst(
              '[MealType:OTHER]',
              '',
            );
            return {'success': true, 'data': newRecord};
          }
        }
        return {'success': true, 'data': recordData};
      }

      return {
        'success': false,
        'message': _errorMessage(
          'Update diet record',
          response.statusCode,
          response.body,
        ),
      };
    } catch (e) {
      return {'success': false, 'message': 'Update diet record failed: $e'};
    }
  }

  Future<Map<String, dynamic>> askWeeklyAnalysis(String question) async {
    final token = await _token();
    if (token == null) {
      return {'success': false, 'message': '請重新登入。'};
    }

    try {
      final prefs = await _prefs();
      final payload = await _buildAskPayload(question);
      final response = await _client.post(
        '/dietary-agent/ask',
        payload,
        headers: {'Authorization': 'Bearer $token'},
      );

      final decoded = _decodeObject(response.body);
      if (response.statusCode != 200) {
        return {
          'success': false,
          'message': _errorMessage('飲食分析', response.statusCode, response.body),
        };
      }

      return {
        'success': decoded['success'] != false,
        'data': _normalizeAskResponse(
          payload: payload,
          partnerData: decoded['data'],
          goalDisplay:
              prefs.getString('user_diet_goal') ??
              ProfileValueMapper.defaultDietGoalDisplay,
        ),
      };
    } catch (e) {
      return {'success': false, 'message': '飲食分析失敗: $e'};
    }
  }

  Future<Map<String, dynamic>> _buildAskPayload(String question) async {
    final prefs = await _prefs();
    final normalizedQuestion = question.trim();
    final dishNames = _extractDishNames(normalizedQuestion);

    String questionType = 'unknown';
    if (normalizedQuestion.contains('比較') ||
        normalizedQuestion.contains('和') ||
        dishNames.length > 1) {
      questionType = 'dish_comparison';
    } else if (dishNames.isNotEmpty && dishNames.first != 'general') {
      questionType = 'single_dish';
    }

    final Map<String, dynamic> payload = {
      'question': normalizedQuestion,
      'question_type': questionType,
      'dish_names': dishNames,
      'user_profile': {
        'height_cm': prefs.getDouble('user_height'),
        'weight_kg': prefs.getDouble('user_weight'),
        'gender': prefs.getString('user_gender'),
        'age': prefs.getInt('user_age'),
      }..removeWhere((key, value) => value == null),
    };

    final healthConditions =
        prefs.getStringList('user_health_conditions_raw') ?? const [];
    payload['health_condition'] = {
      'has_chronic_disease':
          healthConditions.isNotEmpty && !healthConditions.contains('NONE'),
      'chronic_diseases': healthConditions.isEmpty
          ? ['NONE']
          : healthConditions,
    };

    final records = await _buildWeeklyDietRecords();
    if (records.isNotEmpty) {
      payload['weekly_diet_records'] = records;
    }

    return payload;
  }

  Future<List<Map<String, dynamic>>> _buildWeeklyDietRecords() async {
    final records = await getMyDietRecords();
    return records.take(7).map((record) {
      final rawDate =
          record['date'] ?? record['mealDate'] ?? record['createdAt'];
      return {
        'date': _normalizeRecordDate(rawDate),
        'meal': _mealTypeForApi(
          '${record['mealType'] ?? record['meal'] ?? ''}',
        ),
        'dish_name': record['dishName'] ?? record['dish_name'] ?? '',
        'note': record['description'] ?? record['note'] ?? '',
      }..removeWhere((key, value) => value == null || value == '');
    }).toList();
  }

  String _normalizeRecordDate(dynamic value) {
    if (value == null) return '';
    final text = value.toString();
    if (text.contains('T')) {
      return text.split('T').first;
    }
    return text;
  }

  List<String> _extractDishNames(String question) {
    final cleaned = question.trim();
    if (cleaned.isEmpty) return ['general'];

    final candidates = cleaned
        .split(RegExp(r'[,，、\n]'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();

    if (candidates.isEmpty) {
      return ['general'];
    }

    if (candidates.length == 1) {
      return [candidates.first];
    }

    return candidates;
  }

  Map<String, dynamic> _normalizeAskResponse({
    required Map<String, dynamic> payload,
    required dynamic partnerData,
    required String goalDisplay,
  }) {
    final responseMap = partnerData is Map<String, dynamic>
        ? Map<String, dynamic>.from(partnerData)
        : {};
    final profile = Map<String, dynamic>.from(
      payload['user_profile'] is Map<String, dynamic>
          ? payload['user_profile'] as Map<String, dynamic>
          : const <String, dynamic>{},
    );
    profile['goal'] = goalDisplay;

    return {
      'user_profile': profile,
      'health_condition': payload['health_condition'] ?? const {},
      'weekly_diet_records': payload['weekly_diet_records'] ?? const [],
      'partner_response': partnerData,
      if (responseMap['answer'] != null) 'answer': responseMap['answer'],
      if (responseMap['message'] != null) 'message': responseMap['message'],
    };
  }
}
