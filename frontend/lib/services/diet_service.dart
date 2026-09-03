import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../core/api_client.dart';
import '../utils/friendly_error_message.dart';
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

  String _errorMessage(String action, int _statusCode, String _body) {
    if (action.toLowerCase().contains('companion')) {
      return FriendlyErrorMessage.companion;
    }
    return FriendlyErrorMessage.dietRecord;
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

  Future<List<dynamic>> getMyCustomDishes() async {
    final token = await _token();
    if (token == null) return [];

    try {
      final response = await _client.get(
        '/diet-records/custom-dishes',
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        return _unwrapListResponse(response.body);
      }
    } catch (e) {
      print('Load custom dishes failed: $e');
    }
    return [];
  }

  /// 依特定日期 (YYYY-MM-DD) 取得歷史飲食紀錄明細（含後端 API 與前端日期備用過濾）
  Future<List<dynamic>> getDietRecordsByDate(String dateStr) async {
    final targetDate = dateStr.trim();
    if (targetDate.isEmpty) return [];

    final token = await _token();
    if (token == null) return [];

    try {
      // 1. 發送 GET 請求向後端查詢單日紀錄 (?date=YYYY-MM-DD)
      final response = await _client.get(
        '/diet-records?date=$targetDate',
        headers: {'Authorization': 'Bearer $token'},
      );

      List<dynamic> rawList = [];
      if (response.statusCode == 200) {
        rawList = _unwrapListResponse(response.body);
      } else {
        // 2. 若帶參查詢失敗，改為撈取全量紀錄再由前端自行篩選
        rawList = await getMyDietRecords();
      }

      // 3. 對撈出的紀錄進行餐期標記處理與目標日期二次過濾
      final List<dynamic> result = [];
      for (var record in rawList) {
        if (record is Map) {
          var processedRecord = Map<String, dynamic>.from(record);
          final desc = (processedRecord['description'] ?? '').toString();
          if (desc.startsWith('[MealType:OTHER]')) {
            processedRecord['mealType'] = 'OTHER';
            processedRecord['description'] = desc.replaceFirst('[MealType:OTHER]', '');
          }

          // 正規化日期格式並進行比對
          final rawDate = processedRecord['date'] ??
              processedRecord['mealDate'] ??
              processedRecord['createdAt'];
          final normDate = _normalizeRecordDate(rawDate);

          if (normDate.isEmpty || normDate.startsWith(targetDate) || normDate == targetDate) {
            result.add(processedRecord);
          }
        }
      }

      return result;
    } catch (e) {
      print('Load diet records by date failed: $e');
      return [];
    }
  }

  int _parseAmount(dynamic amt) {
    if (amt is int) return amt;
    if (amt is double) return amt.toInt();
    if (amt == null) return 1;
    final digits = amt.toString().replaceAll(RegExp(r'[^\d]'), '');
    return int.tryParse(digits) ?? 1;
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
        final decoded = _decodeObject(response.body);
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

  /// 新增飲食紀錄 (3 大核心必填欄位: dishName, mealType, amount)
  Future<Map<String, dynamic>> createDietRecord({
    required String dishName,
    required String mealType,
    required dynamic amount,
    String description = '',
    String nutrition = '',
    DateTime? mealDate,
    bool fetchNutritionIfMissing = true,
    String? type,
  }) async {
    final token = await _token();
    if (token == null) {
      return {'success': false, 'message': '請重新登入。'};
    }

    Map<String, double?> parsedNutrition = _parseNutrition(nutrition);
    if (fetchNutritionIfMissing && parsedNutrition['calories'] == null) {
      final fetchedNut = await fetchDishNutrition(dishName);
      if (fetchedNut['calories'] != null) {
        parsedNutrition = fetchedNut;
      }
    }

    final int intAmount = _parseAmount(amount);

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
          'amount': intAmount,
          if (parsedNutrition['calories'] != null) 'calories': parsedNutrition['calories'],
          if (parsedNutrition['protein'] != null) 'protein': parsedNutrition['protein'],
          if (parsedNutrition['fat'] != null) 'fat': parsedNutrition['fat'],
          if (parsedNutrition['carbohydrates'] != null) 'carbohydrates': parsedNutrition['carbohydrates'],
          if (mealDate != null) 'date': _formatDate(mealDate),
          if (type != null && type.trim().isNotEmpty) 'type': type.trim(),
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
      return {'success': false, 'message': FriendlyErrorMessage.dietRecord};
    }
  }

  Future<Map<String, dynamic>> uploadDietPhoto(
    int recordId,
    List<int> fileBytes,
    String filename,
  ) async {
    final token = await _token();
    if (token == null) {
      return {'success': false, 'message': '請重新登入。'};
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
      return {'success': false, 'message': FriendlyErrorMessage.upload};
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
    dynamic amount = 1,
    double? calories,
    double? protein,
    double? fat,
    double? carbohydrates,
  }) async {
    final token = await _token();
    if (token == null) {
      return {'success': false, 'message': '請重新登入。'};
    }

    final int intAmount = _parseAmount(amount);

    try {
      final response = await _client.put(
        '/diet-records/$id',
        {
          'amount': intAmount,
          if (calories != null) 'calories': calories,
          if (protein != null) 'protein': protein,
          if (fat != null) 'fat': fat,
          if (carbohydrates != null) 'carbohydrates': carbohydrates,
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
      return {'success': false, 'message': FriendlyErrorMessage.dietRecord};
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
          'message': FriendlyErrorMessage.companion,
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
      return {'success': false, 'message': FriendlyErrorMessage.companion};
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

  /// 發送使用者訊息至 Companion Agent (Port 3000 /companion/ask)
  ///
  /// [userPrompt]：使用者輸入的最新對話內容。
  /// [tempStory]：前端快取的最近最多 3 則歷史對話，供後端無狀態微服務作為 LLM 推理上下文。
  Future<Map<String, dynamic>> sendCompanionUserPrompt(
    String userPrompt, {
    List<Map<String, String>> tempStory = const [],
  }) async {
    final normalizedPrompt = userPrompt.trim();
    if (normalizedPrompt.isEmpty) {
      return {'success': false, 'message': '請先輸入想和精靈說的內容。'};
    }

    final token = await _token();
    final candidateUrls = ApiConfig.companionCandidateBaseUrls;

    for (final baseUrl in candidateUrls) {
      try {
        final response = await _client.post(
          '$baseUrl/companion/ask',
          {
            'user_prompt': normalizedPrompt,
            'temp_story': tempStory, // 打包近 3 則歷史對話傳送至無狀態後端
          },
          headers: {
            if (token != null) 'Authorization': 'Bearer $token',
          },
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final List<dynamic> rawMealItems = data['meal_items'] ?? [];

          // 1. 將 Companion 一維平坦陣列 (1D) 按餐期 (meal_period) 自動進行 Group By 轉換
          final Map<String, List<Map<String, dynamic>>> groupedMap = {};
          for (var item in rawMealItems) {
            if (item is Map) {
              final period = item['meal_period']?.toString().trim() ?? '其他';
              if (!groupedMap.containsKey(period)) {
                groupedMap[period] = [];
              }
              groupedMap[period]!.add({
                'name': item['name']?.toString() ?? '',
                'quantity': int.tryParse(item['quantity']?.toString() ?? '1') ?? 1,
                'unit': item['unit']?.toString() ?? '',
              });
            }
          }

          // 2. 組裝成前端 UI 彈窗現行相容的 meal_records 兩層巢狀陣列
          final List<Map<String, dynamic>> mealRecords = groupedMap.entries.map((entry) {
            return {
              'meal_period': entry.key,
              'meal_items': entry.value,
            };
          }).toList();

          return {
            'success': data['success'] ?? true,
            'companion_reply': data['companion_reply'] ?? '',
            'intent_category': data['intent_category'] ?? 'general',
            'query_date': data['query_date'],
            'meal_records': mealRecords,      // ✅ 前端 UI 現行彈窗立即可用之分組陣列
            'dietary_agent_error': data['dietary_agent_error'],
            'data': data,
          };
        }
        
        // 若 Http Status 非 200 但能連通，保留錯誤訊息
        return {
          'success': false,
          'message': FriendlyErrorMessage.companion,
        };
      } catch (e) {
        // 連線拒絕 (SocketException) 或逾時，自動切換至下一個候選 URL (如 10.0.2.2 或 127.0.0.1)
        continue;
      }
    }

    return {'success': false, 'message': FriendlyErrorMessage.companion};
  }
}

