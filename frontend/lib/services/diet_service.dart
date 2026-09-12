import 'dart:convert';

import '../config/api_config.dart';
import '../core/api_client.dart';
import '../utils/friendly_error_message.dart';
import 'token_storage.dart';

class DietService {
  final ApiClient _client = ApiClient();

  /// 建立飲食紀錄
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
      case '其他':
      case 'OTHER':
        return 'OTHER';
      default:
        return mealType.trim().toUpperCase();
    }
  }

  /// 解析營養素
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
      'carbohydrates': parseVal( r'(?:碳水化合物|碳水|carbs|carbohydrates)\D*(\d+(?:\.\d+)?)'),
    };
  }

  /// 格式化日期
  String _formatDate(DateTime? mealDate) {
    if (mealDate == null) return '';
    final month = mealDate.month.toString().padLeft(2, '0');
    final day = mealDate.day.toString().padLeft(2, '0');
    return '${mealDate.year}-$month-$day';
  }

  /// 取得 Token
  Future<String?> _token() async {
    return const SecureTokenStorage().readAccessToken();
  }

  /// 錯誤訊息
  String _errorMessage(String action, int statusCode, String body) {
    if (action.toLowerCase().contains('companion')) { return FriendlyErrorMessage.companion;}
    return FriendlyErrorMessage.dietRecord;
  }

  /// 解碼 JSON
  Map<String, dynamic> _decodeObject(String body) {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) { return decoded; }
    return {};
  }

  /// 解碼 JSON 並回傳 List
  List<dynamic> _unwrapListResponse(String body) {
    final decoded = jsonDecode(body);
    if (decoded is List) return decoded;
    if (decoded is Map<String, dynamic>) {
      final data = decoded['data'];
      if (data is List) return data;
    }
    return [];
  }

  /// 取得我的飲食紀錄
  Future<List<dynamic>> getMyDietRecords() async {
    final token = await _token();
    if (token == null) return [];

    try {
      final response = await _client.get(
        '/diet-records',
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) { return _unwrapListResponse(response.body); }
      return [];
    } catch (_) { return []; }
  }

  Future<List<dynamic>> getMyCustomDishes() async {
    final token = await _token();
    if (token == null) return [];

    try {
      final response = await _client.get(
        '/diet-records/custom-dishes',
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) { return _unwrapListResponse(response.body); }
    } catch (_) {}
    return [];
  }

  /// 依特定日期 (YYYY-MM-DD) 取得歷史飲食紀錄明細。
  Future<List<dynamic>> getDietRecordsByDate(String dateStr) async {
    final targetDate = dateStr.trim();
    if (targetDate.isEmpty) return [];

    final token = await _token();
    if (token == null) return [];

    try {
      final response = await _client.get( // 1. 發送 GET 請求向後端查詢單日紀錄 (?date=YYYY-MM-DD)
        '/diet-records?date=$targetDate',
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode != 200) return [];
      final rawList = _unwrapListResponse(response.body);

      // 對後端回傳資料進行目標日期二次驗證，缺少日期的紀錄不顯示。
      final List<dynamic> result = [];
      for (var record in rawList) {
        if (record is Map) {
          var processedRecord = Map<String, dynamic>.from(record);

          // 正規化日期格式並進行比對
          final rawDate = processedRecord['mealDate'];
          final normDate = _normalizeRecordDate(rawDate);

          if (normDate == targetDate) { result.add(processedRecord); }
        }
      }
      return result;
    } catch (_) { return [];
    }
  }

  /// 解析份數
  int _parseAmount(dynamic amt) {
    if (amt is int) return amt;
    if (amt is double) return amt.toInt();
    if (amt == null) return 1;
    final digits = amt.toString().replaceAll(RegExp(r'[^\d]'), '');
    return int.tryParse(digits) ?? 1;
  }

  /// 取得食物營養資訊
  Future<Map<String, double?>> fetchDishNutrition(String dishName) async {
    final token = await _token();
    if (token == null || dishName.trim().isEmpty) {
      return { 'calories': null,'protein': null,'fat': null,'carbohydrates': null,};
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
              final double? amt = double.tryParse((n['amount_per_serving'] ?? '').toString(),);
              
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
          return { 'calories': calories,'protein': protein,'fat': fat,'carbohydrates': carbs,};
        }
      }
    } catch (_) {}
    return { 'calories': null,'protein': null,'fat': null,'carbohydrates': null,};
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
    String? type
  }) async {
    final token = await _token();
    if (token == null) { return {'success': false, 'message': '請重新登入。'}; }

    /// 解析營養資訊字符串 "X卡 Y克 X克 X克" 成 Map
    Map<String, double?> parsedNutrition = _parseNutrition(nutrition);
    /// 標記營養資訊是否來自後端
    bool fetchedFromAgent = false;

    // 若未傳入營養資訊且允許自動補全，向後端 Agent 查詢單份營養數值 (1份的熱量與三大營養素)
    if (fetchNutritionIfMissing && parsedNutrition['calories'] == null) {
      final fetchedNut = await fetchDishNutrition(dishName);
      if (fetchedNut['calories'] != null) {
        parsedNutrition = fetchedNut;
        fetchedFromAgent = true;
      }
    }
    final int intAmount = _parseAmount(amount);

    // 當輸入份量大於 1，且營養數值來自 Agent 查詢 (1份標準量) 或傳入字串未預先換算時，
    // 將熱量與三大營養素乘以份量 (intAmount)，避免後端少算營養價值
    if (intAmount > 1 && (fetchedFromAgent || nutrition.trim().isEmpty)) {
      parsedNutrition = {
        'calories': parsedNutrition['calories'] != null ? parsedNutrition['calories']! * intAmount : null,
        'protein': parsedNutrition['protein'] != null ? parsedNutrition['protein']! * intAmount : null,
        'fat': parsedNutrition['fat'] != null ? parsedNutrition['fat']! * intAmount : null,
        'carbohydrates': parsedNutrition['carbohydrates'] != null ? parsedNutrition['carbohydrates']! * intAmount : null,
      };
    }

    try {
      final response = await _client.post(
        '/diet-records',
        {
          'dishName': dishName,
          'mealType': _mealTypeForApi(mealType),
          'description': description,
          'amount': intAmount,
          if (parsedNutrition['calories'] != null) 'calories': parsedNutrition['calories'],
          if (parsedNutrition['protein'] != null) 'protein': parsedNutrition['protein'],
          if (parsedNutrition['fat'] != null) 'fat': parsedNutrition['fat'],
          if (parsedNutrition['carbohydrates'] != null) 'carbohydrates': parsedNutrition['carbohydrates'],
          if (mealDate != null) 'mealDate': _formatDate(mealDate),
          if (type != null && type.trim().isNotEmpty) 'type': type.trim(),
        },
        headers: {'Authorization': 'Bearer $token'},
      );

      final data = _decodeObject(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) { return {'success': true, 'data': data['data'] ?? data};}

      final serverMessage =
          data['message']?.toString().trim() ??
          data['error']?.toString().trim();
      return {
        'success': false,
        'message': serverMessage?.isNotEmpty == true
            ? serverMessage
            : _errorMessage(
                'Create diet record',
                response.statusCode,
                response.body,
              ),
      };
    } catch (e) { return {'success': false, 'message': FriendlyErrorMessage.dietRecord};}
  }

  /// 上傳飲食紀錄照片
  Future<Map<String, dynamic>> uploadDietPhoto(int recordId, List<int> fileBytes, String filename,) async {
    final token = await _token();
    if (token == null) { return {'success': false, 'message': '請重新登入。'};}

    try {
      final response = await _client.multipart(
        '/diet-records/$recordId/photo',
        fileBytes,
        filename,
        headers: {'Authorization': 'Bearer $token'},
      );

      final data = _decodeObject(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) { return {'success': true, 'data': data['data'] ?? data};}

      return {
        'success': false,
        'message': _errorMessage( 'Upload diet photo', response.statusCode, response.body),
      };
    } catch (e) { return {'success': false, 'message': FriendlyErrorMessage.upload};}
  }

  /// 刪除飲食紀錄
  Future<bool> deleteDietRecord(int id) async {
    final token = await _token();
    if (token == null) return false;

    try {
      final response = await _client.delete(
        '/diet-records/$id',
        headers: {'Authorization': 'Bearer $token'},
      );
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (_) { return false;}
  }

  /// 更新飲食紀錄
  Future<Map<String, dynamic>> updateDietRecord( int id, { dynamic amount = 1, double? calories, double? protein, double? fat, double? carbohydrates,}) async {
    final token = await _token();
    if (token == null) { return {'success': false, 'message': '請重新登入。'};}

    final int intAmount = _parseAmount(amount);

    try {
      final requestBody = <String, dynamic>{'amount': intAmount};
      if (calories != null) { requestBody['calories'] = calories; }
      if (protein != null) { requestBody['protein'] = protein; }
      if (fat != null) { requestBody['fat'] = fat; }
      if (carbohydrates != null) { requestBody['carbohydrates'] = carbohydrates; }
      final response = await _client.put( '/diet-records/$id', requestBody, headers: {'Authorization': 'Bearer $token'},
      );

      final data = _decodeObject(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, 'data': data['data'] ?? data};
      }

      return {
        'success': false,
        'message': _errorMessage('Update diet record', response.statusCode, response.body,),
      };
    } catch (e) { return {'success': false, 'message': FriendlyErrorMessage.dietRecord};}
  }

  /// 整理日期格式
  String _normalizeRecordDate(dynamic value) {
    if (value == null) return '';
    final text = value.toString();
    if (text.contains('T')) { return text.split('T').first;}
    return text;
  }

  /// 發送使用者訊息至 MAF Workflow (Port 3001 /maf/ask)
  ///
  /// [userPrompt]：使用者輸入的最新對話內容。
  /// [tempStory]：前端快取的最近最多 10 組來回歷史對話，供後端無狀態微服務作為 LLM 推理上下文。
  Future<Map<String, dynamic>> sendMafUserPrompt(
    String userPrompt, { List<Map<String, String>> tempStory = const [],
  }) async {
    final normalizedPrompt = userPrompt.trim();
    if (normalizedPrompt.isEmpty) { return {'success': false, 'message': '請先輸入想和精靈說的內容。'};}

    final token = await _token();
    final candidateUrls = ApiConfig.mafCandidateBaseUrls;

    for (final baseUrl in candidateUrls) {
      try {
        final response = await _client.post(
          '$baseUrl/maf/ask',
          { 'user_prompt': normalizedPrompt, 'temp_story': tempStory },
          headers: {if (token != null) 'Authorization': 'Bearer $token'},
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final List<dynamic> rawMealItems = data['meal_items'] ?? [];

          // 1. 將 Companion 一維平坦陣列 (1D) 按餐期 (meal_period) 自動進行 Group By 轉換
          final Map<String, List<Map<String, dynamic>>> groupedMap = {};
          for (var item in rawMealItems) {
            if (item is Map) {
              final period = item['meal_period']?.toString().trim() ?? '其他';
              if (!groupedMap.containsKey(period)) { groupedMap[period] = [];}
              groupedMap[period]!.add({
                'name': item['name']?.toString() ?? '',
                'quantity': int.tryParse(item['quantity']?.toString() ?? '1') ?? 1,
                'unit': item['unit']?.toString() ?? '',
              });
            }
          }

          // 2. 組裝成前端 UI 彈窗現行相容的 meal_records 兩層巢狀陣列
          final List<Map<String, dynamic>> mealRecords = groupedMap.entries.map(
            (entry) { return {'meal_period': entry.key, 'meal_items': entry.value};},
          ).toList();

          return {
            'success': data['success'] ?? true,
            'status': data['status'] ?? 'COMPLETED',
            'confirmation_id': data['confirmation_id'],
            'companion_reply': data['companion_reply'] ?? '',
            'intent_category': data['intent_category'] ?? 'general',
            'query_date': data['query_date'],
            'meal_records': mealRecords, // 前端 UI 現行彈窗立即可用之分組陣列
            'dietary_agent_error': data['dietary_agent_error'],
            'data': data,
          };
        }
        // 若 Http Status 非 200 但能連通，保留錯誤訊息
        return {'success': false, 'message': FriendlyErrorMessage.companion};
      } catch (e) { continue;}
    }
    return {'success': false, 'message': FriendlyErrorMessage.companion};
  }

  /// 將前端確認/修改後的飲食草稿交回 MAF Workflow。
  Future<Map<String, dynamic>> confirmMafMealRecord(
    String confirmationId, List<Map<String, dynamic>> mealItems,
  ) async {
    if (confirmationId.trim().isEmpty || mealItems.isEmpty) {
      return {'success': false, 'message': FriendlyErrorMessage.dietRecord};
    }

    final token = await _token();
    if (token == null) { return {'success': false, 'message': '請重新登入。'}; }

    for (final baseUrl in ApiConfig.mafCandidateBaseUrls) {
      try {
        final response = await _client.post(
          '$baseUrl/maf/confirm',
          {'confirmation_id': confirmationId, 'meal_items': mealItems},
          headers: {'Authorization': 'Bearer $token'},
        );
        final data = _decodeObject(response.body);
        if (response.statusCode == 200) { return data; }
        final serverMessage = data['error_message']?.toString().trim() ?? data['message']?.toString().trim();
        return {
          'success': false,
          'message': serverMessage?.isNotEmpty == true ? serverMessage : FriendlyErrorMessage.dietRecord,
        };
      } catch (_) { continue; }
    }
    return {'success': false, 'message': FriendlyErrorMessage.dietRecord};
  }
}
