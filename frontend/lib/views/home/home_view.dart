import 'package:flutter/material.dart'; // 匯入 material.dart 元件庫或套件
import 'package:flutter/services.dart';
import 'dart:ui'; // 匯入 dart:ui 元件庫或套件
import 'dart:convert';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart'; // 匯入 shared_preferences.dart 元件庫或套件
import '../../controllers/dog_state_controller.dart';
import '../../services/auth_service.dart'; // 匯入 auth_service.dart 元件庫或套件
// import '../../services/admin_service.dart'; // 匯入 admin_service.dart 元件庫或套件
import '../../services/body_status_api_service.dart';
import '../../services/diet_service.dart'; // 匯入 diet_service.dart 元件庫或套件
import '../../utils/friendly_error_message.dart';
import '../../color/app_colors.dart'; // 匯入 app_colors.dart 元件庫或套件
import '../../widgets/body_transition_animation_dialog.dart';
import '../../widgets/dog_avatar.dart';
import '../../widgets/meal_record_card.dart';
import '../records/diary_page.dart';
import '../records/elf_feeding_page.dart';
import '../records/manual_record_page.dart'; // 匯入 elf_feeding_page.dart 元件庫或套件

class HomeView extends StatefulWidget { // 定義 HomeView 類別，繼承自 StatefulWidget
  final bool initialOpenChat; // 宣告類別成員或方法內部的區域變數
  const HomeView({super.key, this.initialOpenChat = false}); // 建立編譯期常數，優化 Flutter 渲染效能

  @override // 標記此方法為覆寫父類別之方法
  State<HomeView> createState() => _HomeViewState(); // 執行相對應的邏輯計算或設定屬性參數
} // 程式碼區塊或元件結構結束

class _HomeViewState extends State<HomeView> with TickerProviderStateMixin, WidgetsBindingObserver { // 定義 _HomeViewState 類別，繼承自 State
  static bool _hasCheckedBodyTransitionOnStartup = false;
  static const Set<String> _dietRecordRelatedIntents = {
    'daily_diet_report',
    'diet_analysis',
    'diet_record',
    'diet_record_query',
    'diet_question',
    'record_query',
    'weekly_analysis',
  };

  final TextEditingController _inputController = TextEditingController(); // 宣告類別成員或方法內部的區域變數
  final ScrollController _chatScrollController = ScrollController(); // 新增：對話滾動控制器
  final AuthService _authService = AuthService(); // 宣告類別成員或方法內部的區域變數
  final BodyStatusApiService _bodyStatusApi = BodyStatusApiService();
  final DogStateController _dogController = DogStateController.instance;
  
  late bool _isChatOpen; // 宣告類別成員或方法內部的區域變數
  late double _chatPanelX;  // 宣告類別成員或方法內部的區域變數
  String _userNickname = '使用者'; // 宣告類別成員或方法內部的區域變數
  String _petType = '米粒(Mili)'; // 宣告類別成員或方法內部的區域變數
  // String _dietGoal = '養生'; // 未使用，先註解
  
  List<Map<String, dynamic>> _messages = []; // UI 顯示的對話氣泡清單
  List<Map<String, String>> _tempStory = []; // 前端託管最近最多 3 則訊息 ([{role: 'user'|'assistant', content: '...'}])
  DateTime? _lastUpdateTime; // 最後互動時間戳，供 24h 閒置檢測比對

  String _stripEmojis(String text) {
    final regex = RegExp(
      r'[\u{1F300}-\u{1F5FF}\u{1F600}-\u{1F64F}\u{1F680}-\u{1F6FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}\u{1F900}-\u{1F9FF}\u{1F1E0}-\u{1F1FF}\u{1F004}\u{1F0CF}\u{1F170}-\u{1F19A}\u{1F201}-\u{1F251}\u{1fa00}-\u{1faff}]',
      unicode: true,
    );
    String result = text.replaceAll(regex, '');
    result = result.replaceAll(RegExp(r'[\u2700-\u27BF\u2600-\u26FF\u2300-\u23FF]'), '');
    return result.trim();
  }

  @override // 標記此方法為覆寫父類別之方法
  void initState() { // 初始化狀態生命週期方法，頁面建立時執行一次
    super.initState(); // 執行相對應的邏輯計算或設定屬性參數
    WidgetsBinding.instance.addObserver(this); // 註冊 WidgetsBindingObserver 監聽系統生命週期事件
    _isChatOpen = widget.initialOpenChat; // 執行相對應的邏輯計算或設定屬性參數
    _chatPanelX = widget.initialOpenChat ? 0.0 : 1.0; // 執行相對應的邏輯計算或設定屬性參數
    _dogController.setState(DogAnimationState.idle);
    _loadHomeData(); // 執行相對應的邏輯計算或設定屬性參數
    
    // 檢查並顯示飲食總結報告彈窗，並於初始化/Hot Restart時強制收起鍵盤
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      SystemChannels.textInput.invokeMethod('TextInput.hide');
      FocusManager.instance.primaryFocus?.unfocus();
      await _checkAndShowBodyTransitionOnStartup();
      if (!mounted) return;
      _checkAndShowDietSummaryDialog();
    });
  } // 程式碼區塊或元件結構結束
 
  @override // 標記此方法為覆寫父類別之方法
  void dispose() { // 銷毀狀態生命週期方法，釋放頁面資源與控制器
    WidgetsBinding.instance.removeObserver(this); // 移除 WidgetsBindingObserver 監聽器，防止 Memory Leak
    _inputController.dispose(); // 執行相對應的邏輯計算或設定屬性參數
    _chatScrollController.dispose(); // 新增：釋放對話滾動控制器資源
    super.dispose(); // 執行相對應的邏輯計算或設定屬性參數
  } // 程式碼區塊或元件結構結束

  /// 監聽 App 生命週期變化 (WidgetsBindingObserver)
  /// 當使用者切換 App 重新回到前景 (resumed) 時，自動觸發 24 小時閒置檢測
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _check24hIdleTimeout();
    }
  }

  /// 從 SharedPreferences 載入 temp_story 快取與最後更新時間
  Future<void> _loadTempStoryFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final String? storyJson = prefs.getString('temp_story');
    final int? lastTimeMs = prefs.getInt('last_update_time');

    if (lastTimeMs != null) {
      _lastUpdateTime = DateTime.fromMillisecondsSinceEpoch(lastTimeMs);
    }

    if (storyJson != null) {
      try {
        final List<dynamic> decoded = jsonDecode(storyJson);
        _tempStory = decoded.map((e) => Map<String, String>.from(e as Map)).toList();
      } catch (e) {
        debugPrint('載入 temp_story 快取失敗: $e');
        _tempStory = [];
      }
    }

    // 若有未過期歷史對話，還原至 UI 對話列表中
    if (_tempStory.isNotEmpty) {
      final loadedMessages = <Map<String, dynamic>>[];
      for (var item in _tempStory) {
        loadedMessages.add({
          'isElf': item['role'] == 'assistant',
          'text': item['content'] ?? '',
        });
      }
      setState(() {
        _messages = loadedMessages;
      });
    }

    _check24hIdleTimeout();
  }

  /// 檢查與最後互動時間的時差，若 >= 24 小時自動清空歷史快取
  Future<void> _check24hIdleTimeout() async {
    if (_lastUpdateTime != null) {
      final difference = DateTime.now().difference(_lastUpdateTime!);
      if (difference.inHours >= 24) {
        debugPrint('⏱️ 超過 24 小時未互動，自動清空歷史');
        await resetChat();
      }
    }
  }

  /// 清空對話歷史與 SharedPreferences 快取，重置為初始話題
  Future<void> resetChat() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('temp_story');
    await prefs.remove('last_update_time');

    setState(() {
      _messages = [
        {
          'isElf': true,
          'text': '嗨 $_userNickname！我是你的飲食夥伴精靈！無論想記錄餐點、詢問營養建議，或是隨意聊聊都歡迎跟我說喔！'
        },
      ];
      _tempStory.clear();
      _lastUpdateTime = DateTime.now();
    });
  }

  /// 將新對話推入 tempStory，維持最多 3 則訊息的滑動視窗 (Sliding Window)，並寫入 SharedPreferences
  void _appendTempStory(String role, String content) async {
    _tempStory.add({'role': role, 'content': content});
    if (_tempStory.length > 3) {
      _tempStory.removeAt(0); // 維持最多 3 則舊對話
    }
    _lastUpdateTime = DateTime.now();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('temp_story', jsonEncode(_tempStory));
    await prefs.setInt('last_update_time', _lastUpdateTime!.millisecondsSinceEpoch);
  }

  /// 內嵌於 home_view.dart 中的「🌱 開啟新話題」按鈕 UI
  Widget _buildNewTopicButton() {
    return TextButton.icon(
      onPressed: () {
        resetChat();
        _scrollToBottom();
      },
      icon: const Text('🌱', style: TextStyle(fontSize: 14)),
      label: const Text(
        '開啟新話題',
        style: TextStyle(
          color: Color(0xFF2E7D32),
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
      style: TextButton.styleFrom(
        backgroundColor: const Color(0xFFE8F5E9),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFA5D6A7)),
        ),
      ),
    );
  }

  Future<void> _loadHomeData() async { // 定義非同步方法（Future），執行耗時操作
    // 1. 先從本地快取讀取 (前端輔助，速度快)
    final prefs = await SharedPreferences.getInstance(); // 宣告類別成員或方法內部的區域變數
    final cachedRole = prefs.getString('user_role');
    final cachedEmail = prefs.getString('user_email') ?? '';
    final bool isCachedAdmin = cachedRole == 'ROLE_ADMIN' || cachedRole == 'ADMIN' || cachedEmail.trim().toLowerCase() == 'admin@gmail.com';
    String nick = prefs.getString('user_nickname') ?? (isCachedAdmin ? '系統管理員' : '使用者');
    if (isCachedAdmin && (nick == 'aaa' || nick == '使用者')) {
      nick = '系統管理員';
    }

    setState(() { // 更新狀態數據並通知 UI 重新渲染畫面
      _userNickname = prefs.getString('user_nickname') ?? '使用者'; // 執行相對應的邏輯計算或設定屬性參數
      _petType = '米粒(Mili)'; // 執行相對應的邏輯計算或設定屬性參數
      // _dietGoal = prefs.getString('user_diet_goal') ?? '養生'; // 未使用，先註解
      _messages = [ // 執行相對應的邏輯計算或設定屬性參數
        {
          'isElf': true, 
          'text': '嗨 $_userNickname！我是你的飲食夥伴精靈！無論想記錄餐點、詢問營養建議，或是隨意聊聊都歡迎跟我說喔！'
        }, // 執行相對應的邏輯計算或設定屬性參數
      ]; // 程式碼區塊或元件結構結束
    }); // 程式碼區塊或元件結構結束
    await _loadTempStoryFromStorage();
 
    // 2. 向後端請求最新資料 (後端為主，保持同步)
    await _syncBodyStatus(prefs);
    if (!mounted) return;

    final result = await _authService.getUserProfile(); // 宣告類別成員或方法內部的區域變數
    if (result['success'] == true) { // 執行相對應的邏輯計算或設定屬性參數
      final userData = result['data']; // 宣告類別成員或方法內部的區域變數
      final String g = userData['dietGoal'] ?? userData['diet_goal'] ?? '養生'; // 宣告類別成員或方法內部的區域變數
      await prefs.setString('user_diet_goal', g); // 執行相對應的邏輯計算或設定屬性參數

      final String? userRole = userData['user']?['role'] ?? userData['role'] ?? cachedRole;
      final String userEmail = userData['email'] ?? userData['user']?['email'] ?? cachedEmail;
      final bool isUserAdmin = userRole == 'ROLE_ADMIN' || userRole == 'ADMIN' || userEmail.trim().toLowerCase() == 'admin@gmail.com';
      
      String fetchedNick = userData['nickname'] ?? '';
      if (isUserAdmin && (fetchedNick.isEmpty || fetchedNick == 'aaa' || fetchedNick == '使用者')) {
        fetchedNick = '系統管理員';
      } else if (fetchedNick.isEmpty) {
        fetchedNick = _userNickname;
      }

      setState(() { // 更新狀態數據並通知 UI 重新渲染畫面
        _userNickname = userData['nickname'] ?? '使用者'; // 執行相對應的邏輯計算或設定屬性參數
        _petType = '米粒(Mili)'; // 執行相對應的邏輯計算或設定屬性參數
        // _dietGoal = g; // 未使用，先註解
        // 更新歡迎詞
        if (_messages.isNotEmpty && _messages[0]['isElf'] == true) { // 執行相對應的邏輯計算或設定屬性參數
          _messages[0]['text'] = '嗨 $_userNickname！我是你的飲食夥伴精靈！無論想記錄餐點、詢問營養建議，或是隨意聊聊都歡迎跟我說喔！'; // 執行相對應的邏輯計算或設定屬性參數
        } // 程式碼區塊或元件結構結束
      }); // 程式碼區塊或元件結構結束
      prefs.setString('user_nickname', _userNickname);
    } // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  DateTime? _getRecordDate(dynamic record) {
    if (record == null) return null;
    
    // 0. Try date first (from backend record_date field)
    final dateVal = record['date'];
    if (dateVal != null) {
      if (dateVal is String) {
        try {
          return DateTime.parse(dateVal);
        } catch (_) {}
      } else if (dateVal is List && dateVal.length >= 3) {
        try {
          return DateTime(
            int.parse(dateVal[0].toString()),
            int.parse(dateVal[1].toString()),
            int.parse(dateVal[2].toString()),
          );
        } catch (_) {}
      } else if (dateVal is Map) {
        try {
          final y = int.parse((dateVal['year'] ?? dateVal['yearValue']).toString());
          final m = int.parse((dateVal['month'] ?? dateVal['monthValue']).toString());
          final d = int.parse((dateVal['day'] ?? dateVal['dayOfMonth']).toString());
          return DateTime(y, m, d);
        } catch (_) {}
      }
    }
    
    // 1. Try mealDate second
    final mealDateVal = record['mealDate'];
    if (mealDateVal != null) {
      if (mealDateVal is String) {
        try {
          return DateTime.parse(mealDateVal);
        } catch (_) {}
      } else if (mealDateVal is List && mealDateVal.length >= 3) {
        try {
          return DateTime(
            int.parse(mealDateVal[0].toString()),
            int.parse(mealDateVal[1].toString()),
            int.parse(mealDateVal[2].toString()),
          );
        } catch (_) {}
      } else if (mealDateVal is Map) {
        try {
          final y = int.parse((mealDateVal['year'] ?? mealDateVal['yearValue']).toString());
          final m = int.parse((mealDateVal['month'] ?? mealDateVal['monthValue']).toString());
          final d = int.parse((mealDateVal['day'] ?? mealDateVal['dayOfMonth']).toString());
          return DateTime(y, m, d);
        } catch (_) {}
      }
    }
    
    // 2. Fallback to createdAt
    final createdAtVal = record['createdAt'];
    if (createdAtVal != null) {
      if (createdAtVal is String) {
        try {
          return DateTime.parse(createdAtVal);
        } catch (_) {}
      } else if (createdAtVal is List && createdAtVal.length >= 3) {
        try {
          final y = int.parse(createdAtVal[0].toString());
          final m = int.parse(createdAtVal[1].toString());
          final d = int.parse(createdAtVal[2].toString());
          final h = createdAtVal.length > 3 ? int.parse(createdAtVal[3].toString()) : 0;
          final min = createdAtVal.length > 4 ? int.parse(createdAtVal[4].toString()) : 0;
          final s = createdAtVal.length > 5 ? int.parse(createdAtVal[5].toString()) : 0;
          return DateTime(y, m, d, h, min, s);
        } catch (_) {}
      }
    }
    return null;
  }

  double _getCaloriesFromRecord(dynamic record) {
    if (record == null) return 0.0;
    
    final nutrition = record['nutrition'];
    if (nutrition != null) {
      if (nutrition is Map) {
        final calVal = nutrition['calories'];
        if (calVal != null) {
          final numMatch = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(calVal.toString());
          if (numMatch != null) {
            return double.tryParse(numMatch.group(1) ?? '') ?? 0.0;
          }
        }
      } else {
        final nutritionStr = nutrition.toString().trim();
        if (nutritionStr.isNotEmpty) {
          try {
            if (nutritionStr.startsWith('{') && nutritionStr.endsWith('}')) {
              final parsed = jsonDecode(nutritionStr);
              if (parsed is Map && parsed.containsKey('calories')) {
                final numMatch = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(parsed['calories'].toString());
                if (numMatch != null) {
                  return double.tryParse(numMatch.group(1) ?? '') ?? 0.0;
                }
              }
            }
          } catch (_) {}

          final numRegExp = RegExp(r'(\d+(?:\.\d+)?)\s*(?:kcal|千卡|卡)?', caseSensitive: false);
          final match = numRegExp.firstMatch(nutritionStr);
          if (match != null) {
            final val = double.tryParse(match.group(1) ?? '');
            if (val != null) return val;
          }
        }
      }
    }

    final dishName = record['dishName'] ?? '';
    final desc = record['description'] ?? '';
    final combined = '$dishName $desc';
    final kcalMatch = RegExp(r'(\d+(?:\.\d+)?)\s*(?:kcal|千卡|卡)', caseSensitive: false).firstMatch(combined);
    if (kcalMatch != null) {
      final val = double.tryParse(kcalMatch.group(1) ?? '');
      if (val != null) return val;
    }

    return dishName.toString().trim().isNotEmpty ? 400.0 : 0.0;
  }

  double _getNutrientFromRecord(dynamic record, String pattern) {
    if (record == null) return 0.0;
    final nutrition = record['nutrition'];
    if (nutrition == null) return 0.0;

    String englishKey = '';
    if (pattern.contains('蛋白質') || pattern.contains('protein')) {
      englishKey = 'protein';
    } else if (pattern.contains('脂肪') || pattern.contains('fat')) {
      englishKey = 'fat';
    } else if (pattern.contains('碳水') || pattern.contains('carbohydrate') || pattern.contains('carb')) {
      englishKey = 'carbohydrates';
    }

    if (nutrition is Map) {
      if (englishKey.isNotEmpty) {
        final val = nutrition[englishKey];
        if (val != null) {
          final numMatch = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(val.toString());
          if (numMatch != null) {
            return double.tryParse(numMatch.group(1) ?? '') ?? 0.0;
          }
        }
      }
    } else {
      final nutritionStr = nutrition.toString().trim();
      if (nutritionStr.isNotEmpty) {
        final regExp = RegExp(pattern + r':\s*(\d+(?:\.\d+)?)', caseSensitive: false);
        final match = regExp.firstMatch(nutritionStr);
        if (match != null) {
          return double.tryParse(match.group(1) ?? '') ?? 0.0;
        }
      }
    }
    return 0.0;
  }

  bool _isSameDate(DateTime date, DateTime targetDate) {
    return date.year == targetDate.year &&
        date.month == targetDate.month &&
        date.day == targetDate.day;
  }

  DateTime _dietReportDateForPrompt(String prompt) {
    final normalizedPrompt = prompt.trim().toLowerCase();
    final today = DateTime.now();
    if (normalizedPrompt.contains('前天')) {
      return today.subtract(const Duration(days: 2));
    }
    if (normalizedPrompt.contains('昨天') || normalizedPrompt.contains('昨日')) {
      return today.subtract(const Duration(days: 1));
    }
    return today;
  }

  bool _shouldShowDietReportForPrompt(String prompt, String intent) {
    final normalizedPrompt = prompt.trim().toLowerCase();
    final normalizedIntent = intent.trim().toLowerCase();

    final asksAboutDate = normalizedPrompt.contains('今天') ||
        normalizedPrompt.contains('今日') ||
        normalizedPrompt.contains('當天') ||
        normalizedPrompt.contains('這天') ||
        normalizedPrompt.contains('昨天') ||
        normalizedPrompt.contains('昨日') ||
        normalizedPrompt.contains('前天');
    final intentNeedsDietRecord =
        _dietRecordRelatedIntents.contains(normalizedIntent) ||
            normalizedIntent.contains('record') ||
            normalizedIntent.contains('analysis');
    if (!asksAboutDate && !intentNeedsDietRecord) return false;

    return normalizedPrompt.contains('吃') ||
        normalizedPrompt.contains('飲食') ||
        normalizedPrompt.contains('餐') ||
        normalizedPrompt.contains('紀錄') ||
        normalizedPrompt.contains('記錄') ||
        normalizedPrompt.contains('熱量') ||
        normalizedPrompt.contains('卡路里') ||
        normalizedPrompt.contains('蛋白質') ||
        normalizedPrompt.contains('脂肪') ||
        normalizedPrompt.contains('碳水') ||
        normalizedPrompt.contains('營養') ||
        normalizedPrompt.contains('夠不夠') ||
        normalizedPrompt.contains('過量') ||
        intentNeedsDietRecord;
  }

  Map<String, dynamic> _buildDietSummaryForDate(
    List<dynamic> records,
    DateTime targetDate,
  ) {
    double totalCalories = 0;
    double totalProtein = 0;
    double totalFat = 0;
    double totalCarbs = 0;
    final List<String> dishes = [];

    for (final record in records) {
      final rDate = _getRecordDate(record);
      if (rDate == null || !_isSameDate(rDate, targetDate)) continue;

      totalCalories += _getCaloriesFromRecord(record);
      totalProtein += _getNutrientFromRecord(record, r'(?:蛋白質|protein)');
      totalFat += _getNutrientFromRecord(record, r'(?:脂肪|fat)');
      totalCarbs += _getNutrientFromRecord(
        record,
        r'(?:碳水化合物|碳水|carbohydrate|carbs)',
      );

      final dishName = record['dishName'];
      if (dishName != null && dishName.toString().isNotEmpty) {
        dishes.add(dishName.toString());
      }
    }

    return {
      'calories': totalCalories,
      'protein': totalProtein,
      'fat': totalFat,
      'carbs': totalCarbs,
      'dishes': dishes,
    };
  }

  Future<void> _showDietReportFromCompanion(String prompt) async {
    try {
      final records = await DietService().getMyDietRecords();
      final reportDate = _dietReportDateForPrompt(prompt);
      final isToday = _isSameDate(reportDate, DateTime.now());
      final dateLabel = isToday ? '今天' : '${reportDate.month}/${reportDate.day}';
      final summary = _buildDietSummaryForDate(records, reportDate);

      if (!mounted) return;
      _showDietSummaryDialog(
        date: reportDate,
        calories: summary['calories'] as double,
        protein: summary['protein'] as double,
        fat: summary['fat'] as double,
        carbs: summary['carbs'] as double,
        dishes: List<String>.from(summary['dishes'] as List),
        emptyComment: '$dateLabel還沒有記錄任何飲食。先新增餐點後，我就能幫您一起看營養狀況。',
        filledCommentBuilder: (dishes, calories) =>
            '$dateLabel記錄了：${dishes.join('、')}。目前總熱量為 ${calories.toStringAsFixed(0)} kcal。',
      );
    } catch (e) {
      debugPrint('觸發飲食紀錄報告失敗: $e');
    }
  }

  void _checkAndShowDietSummaryDialog() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now();
    final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    
    // 檢查今天是否已經顯示過飲食總結彈窗（每天僅第一次開啟 app 時跳出）
    final lastShownDate = prefs.getString('last_shown_summary_date');
    if (lastShownDate == todayStr) {
      debugPrint('今日 ($todayStr) 已顯示過飲食總結彈窗，不再重複跳出。');
      return;
    }

    try {
      final records = await DietService().getMyDietRecords();
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      
      double totalCalories = 0;
      double totalProtein = 0;
      double totalFat = 0;
      double totalCarbs = 0;
      List<String> yesterdayDishes = [];

      for (var record in records) {
        final rDate = _getRecordDate(record);
        if (rDate == null) continue;
        if (rDate.year == yesterday.year &&
            rDate.month == yesterday.month &&
            rDate.day == yesterday.day) {
          
          totalCalories += _getCaloriesFromRecord(record);
          totalProtein += _getNutrientFromRecord(record, r'(?:蛋白質|protein)');
          totalFat += _getNutrientFromRecord(record, r'(?:脂肪|fat)');
          totalCarbs += _getNutrientFromRecord(record, r'(?:碳水化合物|碳水|carbohydrate|carbs)');
          
          if (record['dishName'] != null) {
            yesterdayDishes.add(record['dishName'].toString());
          }
        }
      }

      // 若為新用戶或完全沒有歷史紀錄，不跳出昨日總結彈窗
      if (records.isEmpty) {
        debugPrint('無任何飲食記錄（新用戶），不跳出昨日總結彈窗。');
        await prefs.setString('last_shown_summary_date', todayStr);
        return;
      }

      if (!mounted) return;
      debugPrint('=============================================');
      debugPrint('準備跳出昨日飲食總結彈窗！ Dishes: $yesterdayDishes');
      debugPrint('=============================================');
      
      // 紀錄今日已跳出飲食總結彈窗
      await prefs.setString('last_shown_summary_date', todayStr);

      Future.delayed(const Duration(milliseconds: 800), () {
        if (!mounted) return;
        _showDietSummaryDialog(
          date: yesterday,
          calories: totalCalories,
          protein: totalProtein,
          fat: totalFat,
          carbs: totalCarbs,
          dishes: yesterdayDishes,
        );
      });
    } catch (e) {
      debugPrint('取得昨日飲食總結失敗: $e');
    }
  }

  Future<void> _triggerYesterdaySummary() async {
    try {
      final records = await DietService().getMyDietRecords();
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      
      double totalCalories = 0;
      double totalProtein = 0;
      double totalFat = 0;
      double totalCarbs = 0;
      List<String> yesterdayDishes = [];

      for (var record in records) {
        final rDate = _getRecordDate(record);
        if (rDate == null) continue;
        if (rDate.year == yesterday.year &&
            rDate.month == yesterday.month &&
            rDate.day == yesterday.day) {
          totalCalories += _getCaloriesFromRecord(record);
          final dishName = record['dishName'];
          if (dishName != null && dishName.toString().isNotEmpty) {
            yesterdayDishes.add(dishName.toString());
          }
        }
      }

      if (!mounted) return;
      _showDietSummaryDialog(
        date: yesterday,
        calories: totalCalories,
        protein: totalProtein,
        fat: totalFat,
        carbs: totalCarbs,
        dishes: yesterdayDishes,
      );
    } catch (e) {
      debugPrint('觸發昨日飲食總結失敗: $e');
      if (mounted) {
        _showDietSummaryDialog(
          date: DateTime.now().subtract(const Duration(days: 1)),
          calories: 0,
          protein: 0,
          fat: 0,
          carbs: 0,
          dishes: [],
        );
      }
    }
  }

  void _showBodyStatusDialog() {
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    FocusManager.instance.primaryFocus?.unfocus();
    FocusScope.of(context).unfocus();

    // 觸發 3D 小精靈動態表演動畫
    _dogController.setState(DogAnimationState.response);
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) _dogController.setState(DogAnimationState.idle);
    });

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24.0),
          ),
          backgroundColor: AppColors.background,
          elevation: 10,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 標題
                const Text(
                  '小精靈的體態發生了變化......',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                
                const SizedBox(height: 12),
                
                // 小精靈 3D 動畫展示 (巨大化 3.2 Scale, 270px)
                Center(
                  child: SizedBox(
                    width: 320,
                    height: 270,
                    child: DogAvatar(
                      controller: _dogController,
                      scale: 3.2,
                      instanceId: 'body-status-dialog-dog',
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // 關閉按鈕 (1fe8ba9 風格)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.background,
                      padding: const EdgeInsets.symmetric(vertical: 12.0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      '太棒了，我知道了！',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showDietSummaryDialog({
    required DateTime date,
    required double calories,
    required double protein,
    required double fat,
    required double carbs,
    required List<String> dishes,
    String? emptyComment,
    String Function(List<String> dishes, double calories)? filledCommentBuilder,
  }) {
    final String dateStr = '${date.month}/${date.day}';
    final String comment = dishes.isEmpty
        ? emptyComment ?? '昨天沒有記錄任何飲食。記得補記錄，我才能為您做評估喔。'
        : filledCommentBuilder?.call(dishes, calories) ??
            '昨天記錄了：${dishes.join('、')}。總熱量為 ${calories.toStringAsFixed(0)} kcal。請繼續保持健康飲食！';

    SystemChannels.textInput.invokeMethod('TextInput.hide');
    FocusManager.instance.primaryFocus?.unfocus();
    FocusScope.of(context).unfocus();

    final double pCal = protein * 4;
    final double fCal = fat * 9;
    final double cCal = carbs * 4;
    final double macroTotalCal = pCal + fCal + cCal;

    int carbsPercent = 0;
    int proteinPercent = 0;
    int fatPercent = 0;

    if (macroTotalCal > 0) {
      carbsPercent = ((cCal / macroTotalCal) * 100).round();
      proteinPercent = ((pCal / macroTotalCal) * 100).round();
      fatPercent = 100 - carbsPercent - proteinPercent;
    }

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24.0),
          ),
          backgroundColor: AppColors.background,
          elevation: 10,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 標題與日期
                Text(
                  '$dateStr 飲食總結報告',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                
                const SizedBox(height: 10),
                
                // 小精靈 (巨大化 3.2 Scale, 完整無裁剪 270px)
                Center(
                  child: SizedBox(
                    width: 320,
                    height: 270,
                    child: DogAvatar(
                      controller: DogStateController.instance,
                      scale: 3.2,
                      instanceId: 'yesterday-summary-dialog-dog',
                    ),
                  ),
                ),

                const SizedBox(height: 0),

                // 1. 昨日熱量弧形表 (三區間: 偏低 / 適量 / 偏高)
                _buildCalorieArcGaugeCard(calories.round()),

                const SizedBox(height: 8),

                // 2. 昨日三大營養素比例柱狀圖
                _buildMacronutrientBarChartCard(
                  carbsPercent: carbsPercent,
                  proteinPercent: proteinPercent,
                  fatPercent: fatPercent,
                  todayCarbs: carbs,
                  todayProtein: protein,
                  todayFat: fat,
                ),

                const SizedBox(height: 8),
                
                // 精靈評語
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12.0),
                    border: Border.all(color: AppColors.primary.withOpacity(0.15)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          comment,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textPrimary.withOpacity(0.85),
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                
                // 按鈕區
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.background,
                    minimumSize: const Size(double.infinity, 44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.0),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    '太棒了，我知道了！',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /*
  Widget _buildSummaryRow(String label, String value, IconData icon, Color iconColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
          ],
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: iconColor,
          ),
        ),
      ],
    );
  }

  Widget _buildNutrientItem(String name, String value, Color color) {
    return Column(
      children: [
        Text(
          name,
          style: TextStyle(fontSize: 12, color: AppColors.textPrimary.withOpacity(0.5)),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
  */

  // 根據小精靈名稱獲取對應圖標
  Future<void> _syncBodyStatus(SharedPreferences prefs) async {
    try {
      final status = await _bodyStatusApi.getBodyStatus()
          .timeout(const Duration(seconds: 6));
      await prefs.setString('dog_body_type', status.bodyType);
      if (!mounted) return;
      _dogController.setBodyTypeFromBackend(status.bodyType);
    } catch (e) {
      debugPrint('首頁同步 BodyStatus 失敗: $e');
    }
  }

  Future<void> _checkAndShowBodyTransitionOnStartup() async {
    if (_hasCheckedBodyTransitionOnStartup) return;

    try {
      if (await _authService.isAdmin()) {
        debugPrint('管理者帳號略過首頁每日結算。');
        return;
      }

      _hasCheckedBodyTransitionOnStartup = true;
      final settlement = await _bodyStatusApi.settleDailyScores()
          .timeout(const Duration(seconds: 8));
      final oldBodyType = DogStateController.parseBodyType(settlement.oldBodyType);
      final newBodyType = DogStateController.parseBodyType(settlement.newBodyType);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('dog_body_type', settlement.bodyType);

      if (!settlement.bodyTypeChanged || oldBodyType == newBodyType) {
        _dogController.setBodyType(newBodyType);
        _dogController.setState(DogAnimationState.idle);
        return;
      }

      if (!mounted) return;
      _dogController.setBodyType(oldBodyType);
      _dogController.setState(DogAnimationState.idle);
      await showDialog(
        context: context,
        barrierDismissible: true,
        builder: (context) {
          return BodyTransitionAnimationDialog(
            oldBodyType: oldBodyType,
            newBodyType: newBodyType,
          );
        },
      );

      if (!mounted) return;
      _dogController.setBodyType(newBodyType);
      _dogController.setState(DogAnimationState.idle);
    } catch (e) {
      debugPrint('首頁啟動體態變化檢查失敗: $e');
    }
  }

  /*
  IconData _getPetIcon(String petType) { // 顯示預設的圖示元件（Icon）
    switch (petType) { // 執行相對應的邏輯計算或設定屬性參數
      case '奶油皮丘': return Icons.pets; // 回傳建構完成的元件或方法計算結果
      case '薄荷兔兔': return Icons.eco; // 回傳建構完成的元件或方法計算結果
      case '草莓狐狸': return Icons.star; // 回傳建構完成的元件或方法計算結果
      default: return Icons.pets; // 回傳建構完成的元件或方法計算結果
    } // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  // 獲取 3D 渲染的柴犬精靈圖片路徑
  String _getPetImagePath(String petType, String dietGoal) { // 宣告類別成員或方法內部的區域變數
    String path = 'assets/images/shiba_normal.png'; // 宣告類別成員或方法內部的區域變數
    if (petType == '奶油皮丘' || petType.isNotEmpty) { // 執行相對應的邏輯計算或設定屬性參數
      if (dietGoal.contains('減脂')) { // 執行相對應的邏輯計算或設定屬性參數
        path = 'assets/images/shiba_fat.png'; // 執行相對應的邏輯計算或設定屬性參數
      } else if (dietGoal.contains('增肌')) { // 執行相對應的邏輯計算或設定屬性參數
        path = 'assets/images/shiba_muscular.png'; // 執行相對應的邏輯計算或設定屬性參數
      } else if (dietGoal.contains('養生')) { // 執行相對應的邏輯計算或設定屬性參數
        path = 'assets/images/shiba_thin.png'; // 執行相對應的邏輯計算或設定屬性參數
      } // 程式碼區塊或元件結構結束
    } // 程式碼區塊或元件結構結束
    return path; // 回傳建構完成的元件或方法計算結果
  } // 程式碼區塊或元件結構結束
  */

  // 根據小精靈名稱獲取對應顏色
  Color _getPetColor(String petType) { // 設定顏色數值（Color）
    switch (petType) { // 執行相對應的邏輯計算或設定屬性參數
      case '奶油皮丘': return const Color(0xFFD4A373); // Muted orange (retro)
      case '薄荷兔兔': return const Color(0xFF8A9A5B); // Muted sage (retro)
      case '草莓狐狸': return const Color(0xFFB07D62); // Muted terracotta (retro)
      default: return AppColors.secondary; // 設定顏色數值（Color）
    } // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  void _toggleChat(bool open) { // 執行相對應的邏輯計算或設定屬性參數
    setState(() { // 更新狀態數據並通知 UI 重新渲染畫面
      _isChatOpen = open; // 執行相對應的邏輯計算或設定屬性參數
      _chatPanelX = open ? 0.0 : 1.0; // 執行相對應的邏輯計算或設定屬性參數
    }); // 程式碼區塊或元件結構結束
    if (open) {
      _scrollToBottom();
    }
  } // 程式碼區塊或元件結構結束

  void _scrollToBottom() { // 新增：自動滾動對話清單到底部
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showDogResponseThenIdle() {
    _dogController.setState(DogAnimationState.response);
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (!mounted || _dogController.state != DogAnimationState.response) return;
      _dogController.setState(DogAnimationState.idle);
    });
  }
  void _handleMessage(String text) { // 執行相對應的邏輯計算或設定屬性參數
    FocusScope.of(context).unfocus(); // 送出訊息後立刻收起軟鍵盤
    if (text.trim().isEmpty) return; // 執行相對應的邏輯計算或設定屬性參數

    // 複製一份當前歷史傳給後端
    final payloadHistory = List<Map<String, String>>.from(_tempStory);
    _appendTempStory('user', text);

    setState(() { // 更新狀態數據並通知 UI 重新渲染畫面
      _messages.add({'isElf': false, 'text': text}); // 執行相對應的邏輯計算或設定屬性參數
      _inputController.clear(); // 執行相對應的邏輯計算或設定屬性參數
      _isChatOpen = true; // 執行相對應的邏輯計算或設定屬性參數
      _chatPanelX = 0.0; // 執行相對應的邏輯計算或設定屬性參數
    }); // 程式碼區塊或元件結構結束
    _dogController.setState(DogAnimationState.thinking);
    _scrollToBottom(); // 新增：傳送訊息後自動滑到底部

    // 模擬回覆
    Future.delayed(const Duration(milliseconds: 500), () { // 建立編譯期常數，優化 Flutter 渲染效能
      setState(() { // 更新狀態數據並通知 UI 重新渲染畫面
        _messages.add({
          'isElf': true,
          'text': '米粒正在思考中....',
        });
      });
      _scrollToBottom(); // 新增：載入中提示滑到底部
      
      DietService().sendCompanionUserPrompt(text, tempStory: payloadHistory).then((res) {
        _showDogResponseThenIdle();
        setState(() {
          if (_messages.isNotEmpty && _messages.last['text'] == '米粒正在思考中....') {
            _messages.removeLast();
          }

          final reply = res['companion_reply'] ??
              (res['data'] is Map ? res['data']['companion_reply'] : null);

          if (res['success'] == true && reply != null && reply.toString().isNotEmpty) {
            final replyStr = reply.toString();
            // 取得 AI 助手識別的意圖類別 (intent_category) 與歷史查詢日期 (query_date)
            final intent = (res['intent_category'] ?? '').toString();
            final queryDate = res['query_date']?.toString();

            _messages.add({
              'isElf': true,
              'text': replyStr,
              'intentCategory': intent, // 存入意圖類別（如 meal_query）
              'queryDate': queryDate,   // 存入查詢日期（如 2026-06-19）
            });
            _appendTempStory('assistant', replyStr);

            // 判斷意圖若為 meal_record 且含草稿，自動觸發飲食紀錄確認彈窗
            final mealRecords = res['meal_records'] as List<dynamic>? ?? [];
            if (intent == 'meal_record' && mealRecords.isNotEmpty) {
              _showMealRecordDraftDialog(context, mealRecords, userPrompt: text);
            } else if (_shouldShowDietReportForPrompt(text, intent)) {
              Future.microtask(() => _showDietReportFromCompanion(text));
            }
          } else {
            _messages.add({
              'isElf': true,
              'text': FriendlyErrorMessage.companionReply(res['message']),
            });
          }
        });
        _scrollToBottom(); // 新增：智能評估分析完成後滑到底部
      }).catchError((e) {
        _showDogResponseThenIdle();
        setState(() {
          if (_messages.isNotEmpty && _messages.last['text'] == '米粒正在思考中....') {
            _messages.removeLast();
          }
          _messages.add({
            'isElf': true,
            'text': FriendlyErrorMessage.companionReply(e),
          });
        });
        _scrollToBottom(); // 新增：發生異常後滑到底部
      });
    });
  } // 程式碼區塊或元件結構結束

  @override // 標記此方法為覆寫父類別之方法
  Widget build(BuildContext context) { // 建立畫面的主要 build 方法，返回元件樹
    return GestureDetector( // 建立手勢偵測器（GestureDetector），用於監聽點擊、拖動等觸控事件
      onHorizontalDragUpdate: (details) { // 執行相對應的邏輯計算或設定屬性參數
        if (details.delta.dx < -5) _toggleChat(true); // 左滑開啟
        if (details.delta.dx > 5) _toggleChat(false); // 右滑關閉
      }, // 程式碼區塊或元件結構結束
      child: Scaffold( // 建立頁面的基礎 Scaffold 骨架，提供頁面基本版面佈局
        backgroundColor: AppColors.surface, // 設定顏色數值（Color）
        body: Stack( // 設定頁面的主要內容區域（body）
          children: [ // 執行相對應的邏輯計算或設定屬性參數
            // 1. 背景與標題 (毛玻璃效果)
            Positioned( // 建立絕對定位元件（Positioned），用於精確設定子元件在 Stack 中的位置
              top: 0, left: 0, right: 0, // 執行相對應的邏輯計算或設定屬性參數
              child: SafeArea( // 執行相對應的邏輯計算或設定屬性參數
                child: Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
                  height: 80, // 執行相對應的邏輯計算或設定屬性參數
                  alignment: Alignment.center, // 執行相對應的邏輯計算或設定屬性參數
                  child: const Text( // 建立文字顯示元件（Text）
                    "精靈助手", // 執行相對應的邏輯計算或設定屬性參數
                    style: TextStyle( // 設定文字字體大小、顏色與粗細等字型樣式（TextStyle）
                      fontSize: 22,  // 執行相對應的邏輯計算或設定屬性參數
                      fontWeight: FontWeight.bold,  // 執行相對應的邏輯計算或設定屬性參數
                      letterSpacing: 1.5, // 執行相對應的邏輯計算或設定屬性參數
                      color: AppColors.textPrimary // 設定顏色數值（Color）
                    ), // 執行相對應的邏輯計算或設定屬性參數
                  ), // 執行相對應的邏輯計算或設定屬性參數
                ), // 執行相對應的邏輯計算或設定屬性參數
              ), // 執行相對應的邏輯計算或設定屬性參數
            ), // 執行相對應的邏輯計算或設定屬性參數

            // 2. 中央大精靈
            Center( // 建立置中對齊元件（Center），將子元件居中顯示
              child: SingleChildScrollView(
                child: Builder(
                  builder: (context) {
                    final isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
                    final elfSize = isKeyboardVisible ? 160.0 : 280.0;
                    return Column( // 建立垂直排列元件（Column），縱向排列多個子元件
                      mainAxisSize: MainAxisSize.min, // 執行相對應的邏輯計算或設定屬性參數
                children: [ // 執行相對應的邏輯計算或設定屬性參數
                  GestureDetector( // 建立手勢偵測器（GestureDetector），用於監聽點擊、拖動等觸控事件
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _toggleChat(true), // 單擊：開啟對話對話框
                    child: Hero( // 建立跨頁面過渡動畫元件（Hero），點擊時呈現放大或縮小移動特效
                      tag: 'elf', // 執行相對應的邏輯計算或設定屬性參數
                              child: Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
                                width: elfSize, height: elfSize, // 執行相對應的邏輯計算或設定屬性參數
                                decoration: BoxDecoration( // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
                                  shape: BoxShape.circle, // 執行相對應的邏輯計算或設定屬性參數
                                  color: AppColors.background, // 設定顏色數值（Color）
                                  boxShadow: [ // 執行相對應的邏輯計算或設定屬性參數
                                    BoxShadow( // 設定容器的陰影效果，包括顏色、模糊半徑與偏移量
                                      color: _getPetColor(_petType).withOpacity(0.15),  // 設定顏色數值（Color）
                                      blurRadius: 15,  // 執行相對應的邏輯計算或設定屬性參數
                                      spreadRadius: 2, // 執行相對應的邏輯計算或設定屬性參數
                                    ) // 執行相對應的邏輯計算或設定屬性參數
                                  ], // 執行相對應的邏輯計算或設定屬性參數
                                ), // 執行相對應的邏輯計算或設定屬性參數
                                child: ClipRRect( // 建立圓角裁剪元件（ClipRRect），可將子元件裁切為圓角矩形
                                  borderRadius: BorderRadius.circular(elfSize / 2), // 設定容器的圓角弧度半徑大小
                                  child: Padding( // 建立間距容器（Padding），用於設定內部邊距
                                    padding: EdgeInsets.all(isKeyboardVisible ? 15.0 : 25.0), // 設定外邊距或內邊距的數值大小（EdgeInsets）
                                    child: AbsorbPointer(
                                      child: DogAvatar(
                                        controller: _dogController,
                                        scale: isKeyboardVisible ? 1.0 : 1.5,
                                        instanceId: 'home-main-dog',
                                      ),
                                    ),
                                  ), // 執行相對應的邏輯計算或設定屬性參數
                                ), // 執行相對應的邏輯計算或設定屬性參數
                              ), // 執行相對應的邏輯計算或設定屬性參數
                    ), // 執行相對應的邏輯計算或設定屬性參數
                  ), // 執行相對應的邏輯計算或設定屬性參數
                  if (!isKeyboardVisible) const SizedBox(height: 20), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
                  // 精靈說話框 (初始狀態)
                  if (!_isChatOpen && !isKeyboardVisible) ...[ // 執行相對應的邏輯計算或設定屬性參數
                    Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15), // 設定外邊距或內邊距的數值大小（EdgeInsets）
                      margin: const EdgeInsets.symmetric(horizontal: 20), // 設定外邊距或內邊距的數值大小（EdgeInsets）
                      decoration: BoxDecoration( // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
                        color: AppColors.background, // 設定顏色數值（Color）
                        borderRadius: BorderRadius.circular(20), // 設定容器的圓角弧度半徑大小
                        boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.1), blurRadius: 1.95)], // 設定容器的陰影效果，包括顏色、模糊半徑與偏移量
                      ), // 執行相對應的邏輯計算或設定屬性參數
                      child: Text( // 建立文字顯示元件（Text）
                        _stripEmojis(_messages.isNotEmpty ? _messages[0]['text'] : "載入中..."), // 執行相對應的邏輯計算或設定屬性參數
                        textAlign: TextAlign.left, // 執行相對應的邏輯計算或設定屬性參數
                        style: const TextStyle( // 設定文字字體大小、顏色與粗細等字型樣式（TextStyle）
                          fontSize: 15,  // 執行相對應的邏輯計算或設定屬性參數
                          fontWeight: FontWeight.normal, // 執行相對應的邏輯計算或設定屬性參數
                          height: 1.4,
                          color: AppColors.textPrimary // 設定顏色數值（Color）
                        ), // 執行相對應的邏輯計算或設定屬性參數
                      ), // 執行相對應的邏輯計算或設定屬性參數
                    ), // 執行相對應的邏輯計算或設定屬性參數
                    const SizedBox(height: 15), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
                  ], // 執行相對應的邏輯計算或設定屬性參數
                ], // 執行相對應的邏輯計算或設定屬性參數
              );
            }
          ),
        ),
      ), // 執行相對應的邏輯計算或設定屬性參數

            // 3. 底部輸入框
            Positioned( // 建立絕對定位元件（Positioned），用於精確設定子元件在 Stack 中的位置
              bottom: 20, left: 20, right: 20, // 執行相對應的邏輯計算或設定屬性參數
              child: Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
                padding: const EdgeInsets.symmetric(horizontal: 20), // 設定外邊距或內邊距的數值大小（EdgeInsets）
                decoration: BoxDecoration( // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
                  color: AppColors.background, // 設定顏色數值（Color）
                  borderRadius: BorderRadius.circular(30), // 設定容器的圓角弧度半徑大小
                  boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.05), blurRadius: 2.925, offset: const Offset(0, 0.975))], // 設定容器的陰影效果，包括顏色、模糊半徑與偏移量
                ), // 執行相對應的邏輯計算或設定屬性參數
                child: Row( // 建立水平排列元件（Row），橫向排列多個子元件
                  children: [ // 執行相對應的邏輯計算或設定屬性參數
                    Expanded( // 建立填充元件（Expanded），自動佔滿 Row 或 Column 的剩餘空間
                      child: TextField( // 建立文字輸入框元件（TextField）
                        controller: _inputController, // 執行相對應的邏輯計算或設定屬性參數
                        decoration: const InputDecoration( // 建立輸入框樣式裝飾（InputDecoration）
                          hintText: "輸入訊息...",  // 執行相對應的邏輯計算或設定屬性參數
                          border: InputBorder.none, // 執行相對應的邏輯計算或設定屬性參數
                          hintStyle: TextStyle(color: AppColors.textPrimary) // 設定文字字體大小、顏色與粗細等字型樣式（TextStyle）
                        ), // 執行相對應的邏輯計算或設定屬性參數
                        onSubmitted: _handleMessage, // 執行相對應的邏輯計算或設定屬性參數
                      ), // 執行相對應的邏輯計算或設定屬性參數
                    ), // 執行相對應的邏輯計算或設定屬性參數
                    IconButton( // 建立點擊圖示按鈕（IconButton）
                      icon: const Icon(Icons.send, color: AppColors.primary), // 設定顏色數值（Color）
                      onPressed: () => _handleMessage(_inputController.text), // 執行相對應的邏輯計算或設定屬性參數
                    ), // 執行相對應的邏輯計算或設定屬性參數
                  ], // 執行相對應的邏輯計算或設定屬性參數
                ), // 執行相對應的邏輯計算或設定屬性參數
              ), // 執行相對應的邏輯計算或設定屬性參數
            ), // 執行相對應的邏輯計算或設定屬性參數

            // 4. 右側滑出的對話面板
            IgnorePointer( // 執行相對應的邏輯計算或設定屬性參數
              ignoring: !_isChatOpen, // 執行相對應的邏輯計算或設定屬性參數
              child: AnimatedContainer( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
                duration: const Duration(milliseconds: 300), // 建立編譯期常數，優化 Flutter 渲染效能
                curve: Curves.easeOutCubic, // 執行相對應的邏輯計算或設定屬性參數
                transform: Matrix4.translationValues( // 執行相對應的邏輯計算或設定屬性參數
                  MediaQuery.of(context).size.width * _chatPanelX, 0, 0 // 執行相對應的邏輯計算或設定屬性參數
                ), // 執行相對應的邏輯計算或設定屬性參數
                child: _buildChatPanel(), // 執行相對應的邏輯計算或設定屬性參數
              ), // 執行相對應的邏輯計算或設定屬性參數
            ), // 執行相對應的邏輯計算或設定屬性參數
          ], // 執行相對應的邏輯計算或設定屬性參數
        ), // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Widget _buildChatPanel() { // 定義用於重複使用的 UI 封裝建構方法
    return Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
      width: MediaQuery.of(context).size.width, // 執行相對應的邏輯計算或設定屬性參數
      color: const Color(0xFFE7D9B1), // 設定顏色數值（Color）
      child: Column( // 建立垂直排列元件（Column），縱向排列多個子元件
        children: [ // 執行相對應的邏輯計算或設定屬性參數
          // 對話面板頭部
          Container(
            color: const Color(0xFFFCF8EC), // 頂部標題以上/狀態列使用奶油白
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
            child: Padding( // 建立間距容器（Padding），用於設定內部邊距
              padding: const EdgeInsets.all(16.0), // 設定外邊距或內邊距的數值大小（EdgeInsets）
              child: Row( // 建立水平排列元件（Row），橫向排列多個子元件
                children: [ // 執行相對應的邏輯計算或設定屬性參數
                  IconButton( // 建立點擊圖示按鈕（IconButton）
                    icon: const Icon(Icons.arrow_back_ios, color: AppColors.textPrimary), // 設定顏色數值（Color）
                    onPressed: () => _toggleChat(false), // 執行相對應的邏輯計算或設定屬性參數
                  ), // 執行相對應的邏輯計算或設定屬性參數
                  const Text("與精靈對話", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary)), // 建立文字顯示元件（Text）
                  const Spacer(),
                  _buildNewTopicButton(),
                ], // 執行相對應的邏輯計算或設定屬性參數
              ), // 執行相對應的邏輯計算或設定屬性參數
            ), // 執行相對應的邏輯計算或設定屬性參數
          ),
          Expanded( // 建立填充元件（Expanded），自動佔滿 Row 或 Column 的剩餘空間
            child: GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              behavior: HitTestBehavior.opaque,
              child: ListView.builder( // 建立滾動清單元件（ListView），支援多個子元件滾動瀏覽
                controller: _chatScrollController, // 新增：連結滾動控制器
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 127), // 新增：底部預留 127 像素，防止文字被小精靈 3D 模型遮擋
                itemCount: _messages.length, // 執行相對應的邏輯計算或設定屬性參數
                itemBuilder: (context, index) { // 執行相對應的邏輯計算或設定屬性參數
                  final msg = _messages[index]; // 宣告類別成員或方法內部的區域變數
                  if (msg['type'] == 'restaurant') { // 執行相對應的邏輯計算或設定屬性參數
                    return _buildRestaurantCard(msg['text']); // 回傳建構完成的元件或方法計算結果
                  } else if (msg['type'] == 'nutrient') { // 執行相對應的邏輯計算或設定屬性參數
                    return _buildNutrientCard(); // 回傳建構完成的元件或方法計算結果
                  } // 程式碼區塊或元件結構結束
                  return _buildChatMessage(
                    msg['isElf'],
                    msg['text'],
                    options: msg['options'],
                    intentCategory: msg['intentCategory'],
                    queryDate: msg['queryDate'],
                  );
                }, // 程式碼區塊或元件結構結束
              ), // 執行相對應的邏輯計算或設定屬性參數
            ),
          ),
            SafeArea(
              top: false,
              child: Stack( // 建立層疊佈局元件（Stack），可將多個子元件重疊顯示
                clipBehavior: Clip.none, // 執行相對應的邏輯計算或設定屬性參數
                children: [ // 執行相對應的邏輯計算或設定屬性參數
                  Positioned( // 建立絕對定位元件（Positioned），用於精確設定子元件在 Stack 中的位置
                    top: -130, // 執行相對應的邏輯計算或設定屬性參數
                  left: 0, // 執行相對應的邏輯計算或設定屬性參數
                  right: 0, // 執行相對應的邏輯計算或設定屬性參數
                  child: Center( // 建立置中對齊元件（Center），將子元件居中顯示
                    child: SizedBox( // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
                      width: 250, // 執行相對應的邏輯計算或設定屬性參數
                      height: 250, // 執行相對應的邏輯計算或設定屬性參數
                      child: DogAvatar(
                        controller: _dogController,
                        scale: 2.2,
                        cameraControls: false,
                        instanceId: 'home-chat-dog',
                      ),
                    ), // 執行相對應的邏輯計算或設定屬性參數
                  ), // 執行相對應的邏輯計算或設定屬性參數
                ), // 執行相對應的邏輯計算或設定屬性參數
                Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
                  padding: const EdgeInsets.all(16), // 設定外邊距或內邊距的數值大小（EdgeInsets）
                  decoration: const BoxDecoration( // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
                    color: Color(0xFFE7D9B1), // 設定顏色數值（Color）
                    border: Border(top: BorderSide(color: AppColors.border)), // 設定顏色數值（Color）
                  ), // 執行相對應的邏輯計算或設定屬性參數
                  child: Row( // 建立水平排列元件（Row），橫向排列多個子元件
                    children: [ // 執行相對應的邏輯計算或設定屬性參數
                      Expanded( // 建立填充元件（Expanded），自動佔滿 Row 或 Column 的剩餘空間
                        child: Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
                          padding: const EdgeInsets.symmetric(horizontal: 15), // 設定外邊距或內邊距的數值大小（EdgeInsets）
                          decoration: BoxDecoration(color: const Color(0xFFFCF8EC), borderRadius: BorderRadius.circular(20)), // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
                          child: TextField( // 建立文字輸入框元件（TextField）
                            controller: _inputController, // 執行相對應的邏輯計算或設定屬性參數
                            decoration: const InputDecoration( // 建立輸入框樣式裝飾（InputDecoration）
                              hintText: "詢問建議...",  // 執行相對應的邏輯計算或設定屬性參數
                              border: InputBorder.none, // 執行相對應的邏輯計算或設定屬性參數
                              hintStyle: TextStyle(color: AppColors.textPrimary) // 設定文字字體大小、顏色與粗細等字型樣式（TextStyle）
                            ), // 執行相對應的邏輯計算或設定屬性參數
                            onSubmitted: _handleMessage, // 執行相對應的邏輯計算或設定屬性參數
                          ), // 執行相對應的邏輯計算或設定屬性參數
                        ), // 執行相對應的邏輯計算或設定屬性參數
                      ), // 執行相對應的邏輯計算或設定屬性參數
                      const SizedBox(width: 10), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
                      CircleAvatar( // 執行相對應的邏輯計算或設定屬性參數
                        backgroundColor: AppColors.primary, // 設定顏色數值（Color）
                        child: IconButton( // 建立點擊圖示按鈕（IconButton）
                          icon: const Icon(Icons.send, color: AppColors.background, size: 20), // 設定顏色數值（Color）
                          onPressed: () => _handleMessage(_inputController.text), // 執行相對應的邏輯計算或設定屬性參數
                        ), // 執行相對應的邏輯計算或設定屬性參數
                      ), // 執行相對應的邏輯計算或設定屬性參數
                    ], // 執行相對應的邏輯計算或設定屬性參數
                  ), // 執行相對應的邏輯計算或設定屬性參數
                ), // 執行相對應的邏輯計算或設定屬性參數
              ], // 執行相對應的邏輯計算或設定屬性參數
            ), // 執行相對應的邏輯計算或設定屬性參數
          ), // 執行相對應的邏輯計算或設定屬性參數
        ], // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Widget _buildChatMessage(
    bool isElf,
    String text, {
    List<dynamic>? options,
    String? intentCategory,
    String? queryDate,
  }) {
    return Align(
      alignment: isElf ? Alignment.centerLeft : Alignment.centerRight,
      child: Column(
        crossAxisAlignment: isElf ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
            decoration: BoxDecoration(
              color: isElf ? AppColors.background : AppColors.secondary,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.05), blurRadius: 0.975)],
              border: isElf ? Border.all(color: AppColors.border) : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isElf ? _stripEmojis(text) : text,
                  style: TextStyle(
                    color: isElf ? AppColors.textPrimary : AppColors.background,
                    fontSize: 15,
                    fontWeight: FontWeight.normal,
                    height: 1.4,
                  ),
                ),
                // TODO: 這個部分是甚麼呀? 
                // 若米粒回應含有推薦餐點選項 (options)，於泡泡內繪製可點擊的營養成分按鈕
                if (isElf && options != null) ...[
                  const SizedBox(height: 15),
                  const Divider(height: 1),
                  const SizedBox(height: 10),
                  ...options.map((opt) => Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => _showNutrientDetail(opt['name'], opt['nutrients']),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.surface,
                          foregroundColor: AppColors.textPrimary,
                          elevation: 0,
                          side: const BorderSide(color: AppColors.border),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(opt['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  )).toList(),
                ],
              ],
            ),
          ),
          // 當意圖為「歷史飲食紀錄查詢 (meal_query)」且含有合法日期時，於對話泡泡下方動態掛載卡片
          if (isElf && intentCategory == 'meal_query' && queryDate != null && queryDate.isNotEmpty)
            Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
              child: MealRecordCard(
                queryDate: queryDate,
                onClose: () {},
                // 點擊「查看完整飲食日記」跳轉至日記頁
                onNavigateToDiary: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const DiaryPage()),
                  );
                },
                // todo: 要確認補登記有成功打api 
                // 點擊「＋ 補記這天的飲食」跳轉至手動紀錄頁
                onAddRecordForDate: (date) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const ManualRecordPage()),
                  );
                },
              ),
            ),
        ],
      ),
    );
  } // 程式碼區塊或元件結構結束

  void _showNutrientDetail(String name, Map<String, dynamic> nutrients) { // 執行相對應的邏輯計算或設定屬性參數
    showModalBottomSheet( // 執行相對應的邏輯計算或設定屬性參數
      context: context, // 執行相對應的邏輯計算或設定屬性參數
      backgroundColor: Colors.transparent, // 設定顏色數值（Color）
      isScrollControlled: true, // 執行相對應的邏輯計算或設定屬性參數
      builder: (context) => Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
        height: MediaQuery.of(context).size.height * 0.45, // 執行相對應的邏輯計算或設定屬性參數
        decoration: const BoxDecoration( // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
          color: AppColors.background, // 設定顏色數值（Color）
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)), // 執行相對應的邏輯計算或設定屬性參數
        ), // 執行相對應的邏輯計算或設定屬性參數
        padding: const EdgeInsets.all(24), // 設定外邊距或內邊距的數值大小（EdgeInsets）
        child: Column( // 建立垂直排列元件（Column），縱向排列多個子元件
          children: [ // 執行相對應的邏輯計算或設定屬性參數
            Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))), // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
            const SizedBox(height: 25), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
            Text(name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary)), // 建立文字顯示元件（Text）
            const SizedBox(height: 10), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
            Text("預估攝取熱量: ${nutrients['calories']} kcal", style: const TextStyle(fontSize: 16, color: AppColors.secondary, fontWeight: FontWeight.w600)), // 建立文字顯示元件（Text）
            const Divider(height: 40), // 建立編譯期常數，優化 Flutter 渲染效能
            Row( // 建立水平排列元件（Row），橫向排列多個子元件
              mainAxisAlignment: MainAxisAlignment.spaceAround, // 執行相對應的邏輯計算或設定屬性參數
              children: [ // 執行相對應的邏輯計算或設定屬性參數
                _NutrientInfo(label: "蛋白質", value: "${nutrients['protein']}", unit: "g"), // 執行相對應的邏輯計算或設定屬性參數
                _NutrientInfo(label: "脂肪", value: "${nutrients['fat']}", unit: "g"), // 執行相對應的邏輯計算或設定屬性參數
                _NutrientInfo(label: "碳水", value: "${nutrients['carbs']}", unit: "g"), // 執行相對應的邏輯計算或設定屬性參數
              ], // 執行相對應的邏輯計算或設定屬性參數
            ), // 執行相對應的邏輯計算或設定屬性參數
            const Spacer(), // 建立編譯期常數，優化 Flutter 渲染效能
            ElevatedButton( // 建立常規按鈕（ElevatedButton），點擊時觸作相對應事件
              onPressed: () { // 執行相對應的邏輯計算或設定屬性參數
                Navigator.pop(context); // 關閉彈窗
                _toggleChat(false); // 關閉對話框
                Navigator.push( // 導航路由跳轉：開啟並推入新頁面
                  context, // 執行相對應的邏輯計算或設定屬性參數
                  MaterialPageRoute( // 執行相對應的邏輯計算或設定屬性參數
                    builder: (context) => ElfFeedingPage(
                      imagePath: "",
                      items: [{'name': name, 'portion': '1份', 'calories': '${nutrients['calories']} kcal'}],
                      recordDate: DateTime.now(),
                    ), // 執行相對應的邏輯計算或設定屬性參數
                  ), // 執行相對應的邏輯計算或設定屬性參數
                ); // 程式碼區塊或元件結構結束
              }, // 程式碼區塊或元件結構結束
              style: ElevatedButton.styleFrom( // 執行相對應的邏輯計算或設定屬性參數
                backgroundColor: AppColors.primary, // 設定顏色數值（Color）
                minimumSize: const Size(double.infinity, 55), // 建立編譯期常數，優化 Flutter 渲染效能
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), // 設定容器的圓角弧度半徑大小
                elevation: 2, // 執行相對應的邏輯計算或設定屬性參數
              ), // 執行相對應的邏輯計算或設定屬性參數
              child: const Text("確認食用", style: TextStyle(color: AppColors.background, fontSize: 18, fontWeight: FontWeight.bold)), // 建立文字顯示元件（Text）
            ), // 執行相對應的邏輯計算或設定屬性參數
          ], // 執行相對應的邏輯計算或設定屬性參數
        ), // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Widget _buildRestaurantCard(String text) { // 定義用於重複使用的 UI 封裝建構方法
    return Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
      margin: const EdgeInsets.symmetric(vertical: 10), // 設定外邊距或內邊距的數值大小（EdgeInsets）
      padding: const EdgeInsets.all(15), // 設定外邊距或內邊距的數值大小（EdgeInsets）
      decoration: BoxDecoration( // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
        color: AppColors.background, // 設定顏色數值（Color）
        borderRadius: BorderRadius.circular(20), // 設定容器的圓角弧度半徑大小
        border: Border.all(color: AppColors.border), // 設定容器的四周邊框線條樣式
        boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.05), blurRadius: 1.95)], // 設定容器的陰影效果，包括顏色、模糊半徑與偏移量
      ), // 執行相對應的邏輯計算或設定屬性參數
      child: Column( // 建立垂直排列元件（Column），縱向排列多個子元件
        crossAxisAlignment: CrossAxisAlignment.start, // 執行相對應的邏輯計算或設定屬性參數
        children: [ // 執行相對應的邏輯計算或設定屬性參數
          Row( // 建立水平排列元件（Row），橫向排列多個子元件
            children: [ // 執行相對應的邏輯計算或設定屬性參數
              const Icon(Icons.restaurant, color: AppColors.secondary), // 設定顏色數值（Color）
              const SizedBox(width: 10), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
              Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary))), // 建立文字顯示元件（Text）
            ], // 執行相對應的邏輯計算或設定屬性參數
          ), // 執行相對應的邏輯計算或設定屬性參數
          const SizedBox(height: 10), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
          const Text("點擊查看詳細地址與評價", style: TextStyle(color: AppColors.textPrimary, fontSize: 12)), // 建立文字顯示元件（Text）
        ], // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Widget _buildNutrientCard() { // 定義用於重複使用的 UI 封裝建構方法
    return Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
      margin: const EdgeInsets.symmetric(vertical: 10), // 設定外邊距或內邊距的數值大小（EdgeInsets）
      padding: const EdgeInsets.all(20), // 設定外邊距或內邊距的數值大小（EdgeInsets）
      decoration: BoxDecoration( // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
        color: Colors.white, // 設定顏色數值（Color）
        borderRadius: BorderRadius.circular(25), // 設定容器的圓角弧度半徑大小
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2.925)], // 設定容器的陰影效果，包括顏色、模糊半徑與偏移量
      ), // 執行相對應的邏輯計算或設定屬性參數
      child: Column( // 建立垂直排列元件（Column），縱向排列多個子元件
        children: [ // 執行相對應的邏輯計算或設定屬性參數
          const Text("薯條 (大份)", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), // 建立文字顯示元件（Text）
          const Divider(height: 30), // 建立編譯期常數，優化 Flutter 渲染效能
          const Row( // 建立水平排列元件（Row），橫向排列多個子元件
            mainAxisAlignment: MainAxisAlignment.spaceEvenly, // 執行相對應的邏輯計算或設定屬性參數
            children: [ // 執行相對應的邏輯計算或設定屬性參數
              _NutrientInfo(label: "熱量", value: "380", unit: "kcal"), // 執行相對應的邏輯計算或設定屬性參數
              _NutrientInfo(label: "蛋白質", value: "4", unit: "g"), // 執行相對應的邏輯計算或設定屬性參數
              _NutrientInfo(label: "脂肪", value: "20", unit: "g"), // 執行相對應的邏輯計算或設定屬性參數
            ], // 執行相對應的邏輯計算或設定屬性參數
          ), // 執行相對應的邏輯計算或設定屬性參數
          const SizedBox(height: 20), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
          ElevatedButton( // 建立常規按鈕（ElevatedButton），點擊時觸作相對應事件
            onPressed: () { // 執行相對應的邏輯計算或設定屬性參數
              Navigator.push( // 導航路由跳轉：開啟並推入新頁面
                context, // 執行相對應的邏輯計算或設定屬性參數
                MaterialPageRoute(
                  builder: (context) => ElfFeedingPage(
                    imagePath: "",
                    items: const [{'name': '薯條', 'portion': '大份', 'calories': '380 kcal'}],
                    recordDate: DateTime.now(),
                  ),
                ), // 執行相對應的邏輯計算或設定屬性參數
              ); // 程式碼區塊或元件結構結束
            }, // 程式碼區塊或元件結構結束
            style: ElevatedButton.styleFrom( // 執行相對應的邏輯計算或設定屬性參數
              backgroundColor: AppColors.primary, // 設定顏色數值（Color）
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), // 設定容器的圓角弧度半徑大小
              minimumSize: const Size(double.infinity, 45), // 建立編譯期常數，優化 Flutter 渲染效能
            ), // 執行相對應的邏輯計算或設定屬性參數
            child: const Text("進行餵食", style: TextStyle(color: AppColors.background, fontWeight: FontWeight.bold)), // 建立文字顯示元件（Text）
          ), // 執行相對應的邏輯計算或設定屬性參數
        ], // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  }

  DateTime _parseDateFromPrompt(String prompt) {
    final now = DateTime.now();
    if (prompt.isEmpty) return now;

    // Matches YYYY/MM/DD, YYYY-MM-DD, YYYY年MM月DD日
    final regFull = RegExp(r'(\d{4})[/-年](\d{1,2})[/-月](\d{1,2})');
    final matchFull = regFull.firstMatch(prompt);
    if (matchFull != null) {
      final y = int.tryParse(matchFull.group(1)!) ?? now.year;
      final m = int.tryParse(matchFull.group(2)!) ?? now.month;
      final d = int.tryParse(matchFull.group(3)!) ?? now.day;
      return DateTime(y, m, d);
    }

    // Matches MM/DD, MM-DD, MM月DD日 (e.g. 8/12, 8月12日)
    final regShort = RegExp(r'(\d{1,2})[/-月](\d{1,2})');
    final matchShort = regShort.firstMatch(prompt);
    if (matchShort != null) {
      final m = int.tryParse(matchShort.group(1)!) ?? now.month;
      final d = int.tryParse(matchShort.group(2)!) ?? now.day;
      return DateTime(now.year, m, d);
    }

    return now;
  }

  /// 彈出「飲食紀錄草稿」可編輯確認視窗，允許使用者針對每個餐點卡片獨立點擊展開/收合修改餐點名稱、日期、餐別與份量
  void _showMealRecordDraftDialog(BuildContext context, List<dynamic> mealRecords, {String userPrompt = ''}) {
    final DateTime defaultDate = _parseDateFromPrompt(userPrompt);
    final ScrollController draftScrollController = ScrollController();

    // 1. 將所有解析到的餐點攤平為單一獨立的卡片數據結構
    final List<Map<String, dynamic>> flatCards = [];
    for (var rec in mealRecords) {
      final period = rec['meal_period']?.toString() ?? '早餐';
      final items = (rec['meal_items'] as List<dynamic>? ?? []);
      for (var item in items) {
        flatCards.add({
          'name': item['name']?.toString() ?? '',
          'quantity': int.tryParse(item['quantity']?.toString() ?? '1') ?? 1,
          'unit': (item['unit']?.toString() ?? '').isEmpty ? '份' : item['unit']?.toString(),
          'meal_period': period,
          'date': defaultDate,
          'is_expanded': flatCards.isEmpty, // 第一張預設展開，其餘預設收合
        });
      }
    }

    if (flatCards.isEmpty) {
      flatCards.add({
        'name': '',
        'quantity': 1,
        'unit': '份',
        'meal_period': '早餐',
        'date': defaultDate,
        'is_expanded': true,
      });
    }

    const List<String> mealPeriodOptions = ['早餐', '午餐', '晚餐', '其他'];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        bool isSaving = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 24),
              titlePadding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              contentPadding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
              actionsPadding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              backgroundColor: AppColors.background,
              title: Row(
                children: const [
                  Icon(Icons.edit_note, color: AppColors.primary, size: 28),
                  SizedBox(width: 8),
                  Text(
                    '核對與修改飲食紀錄草稿',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: MediaQuery.of(ctx).size.width,
                child: RawScrollbar(
                  controller: draftScrollController,
                  thumbColor: Colors.grey.shade600,
                  thumbVisibility: true,
                  thickness: 6.0,
                  radius: const Radius.circular(3),
                  child: SingleChildScrollView(
                    controller: draftScrollController,
                    padding: const EdgeInsets.only(right: 6),
                    child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '請核對或修改以下草稿內容：',
                      style: TextStyle(fontSize: 13, color: Colors.black87, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 12),

                    // 每個餐點獨立成可點擊展開/收合的折疊卡片
                    ...flatCards.asMap().entries.map((cardEntry) {
                      final cardIdx = cardEntry.key;
                      final card = cardEntry.value;
                      final cardQty = card['quantity'] as int;
                      final cardUnit = card['unit'].toString();
                      final cardDate = card['date'] as DateTime;
                      final currentPeriod = card['meal_period'].toString();
                      final bool isExpanded = card['is_expanded'] as bool? ?? (cardIdx == 0);
                      final String dishDisplayName = card['name'].toString().trim().isEmpty
                          ? '餐點 ${cardIdx + 1}'
                          : card['name'].toString().trim();

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.border),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            // === 卡片 Header (可點擊切換 展開 / 收合) ===
                            InkWell(
                              onTap: () {
                                setDialogState(() {
                                  flatCards[cardIdx]['is_expanded'] = !isExpanded;
                                });
                              },
                              borderRadius: BorderRadius.circular(16),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                child: Row(
                                  children: [
                                    // 展開 / 收合 箭頭 (放最左側)
                                    Icon(
                                      isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                      color: AppColors.primary,
                                      size: 24,
                                    ),
                                    const SizedBox(width: 8),

                                    // 餐點標籤 Badge
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.restaurant, size: 14, color: AppColors.primary),
                                          const SizedBox(width: 4),
                                          Text(
                                            dishDisplayName,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.primary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),

                                    // 收合狀態時顯示摘要文字 (例如: (早餐 • 1瓶))
                                    if (!isExpanded) ...[
                                      Expanded(
                                        child: Text(
                                          '($currentPeriod • $cardQty$cardUnit)',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ] else
                                      const Spacer(),

                                    // 刪除卡片按鈕 (最右側)
                                    if (flatCards.length > 1)
                                      InkWell(
                                        onTap: isSaving
                                            ? null
                                            : () {
                                                setDialogState(() {
                                                  flatCards.removeAt(cardIdx);
                                                });
                                              },
                                        child: const Padding(
                                          padding: EdgeInsets.symmetric(horizontal: 4.0),
                                          child: Icon(Icons.delete_outline, size: 22, color: AppColors.danger),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),

                            // === 卡片展開詳細內容 ===
                            if (isExpanded) ...[
                              const Divider(height: 1, color: AppColors.border),
                              Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // 1. 餐點名稱
                                    const Text(
                                      '餐點名稱',
                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                    ),
                                    const SizedBox(height: 6),
                                    TextFormField(
                                      initialValue: card['name'].toString(),
                                      enabled: !isSaving,
                                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                      decoration: InputDecoration(
                                        hintText: '請輸入餐點名稱',
                                        hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400, fontWeight: FontWeight.normal),
                                        filled: true,
                                        fillColor: AppColors.background,
                                        isDense: true,
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
                                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
                                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                                      ),
                                      onChanged: (val) {
                                        setDialogState(() {
                                          flatCards[cardIdx]['name'] = val;
                                        });
                                      },
                                    ),
                                    const SizedBox(height: 12),

                                    // 2. 紀錄日期
                                    const Text(
                                      '紀錄日期',
                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                    ),
                                    const SizedBox(height: 6),
                                    InkWell(
                                      onTap: isSaving
                                          ? null
                                          : () async {
                                              final picked = await showDatePicker(
                                                context: context,
                                                initialDate: cardDate,
                                                firstDate: DateTime(2023),
                                                lastDate: DateTime.now().add(const Duration(days: 365)),
                                              );
                                              if (picked != null) {
                                                setDialogState(() {
                                                  flatCards[cardIdx]['date'] = picked;
                                                });
                                              }
                                            },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                        decoration: BoxDecoration(
                                          color: AppColors.background,
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: AppColors.border),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.calendar_today, size: 16, color: AppColors.primary),
                                            const SizedBox(width: 8),
                                            Text(
                                              '${cardDate.year}-${cardDate.month.toString().padLeft(2, '0')}-${cardDate.day.toString().padLeft(2, '0')}',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary),
                                            ),
                                            const Spacer(),
                                            const Icon(Icons.arrow_drop_down, color: Colors.grey),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),

                                    // 3. 餐別與份量 (雙欄)
                                    Row(
                                      children: [
                                        // (A) 餐別選擇
                                        Expanded(
                                          flex: 5,
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                '餐別',
                                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                              ),
                                              const SizedBox(height: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                                decoration: BoxDecoration(
                                                  color: AppColors.background,
                                                  borderRadius: BorderRadius.circular(10),
                                                  border: Border.all(color: AppColors.border),
                                                ),
                                                child: DropdownButtonHideUnderline(
                                                  child: DropdownButton<String>(
                                                    value: mealPeriodOptions.contains(currentPeriod) ? currentPeriod : '早餐',
                                                    isExpanded: true,
                                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                                    onChanged: isSaving
                                                        ? null
                                                        : (newPeriod) {
                                                            if (newPeriod != null) {
                                                              setDialogState(() {
                                                                flatCards[cardIdx]['meal_period'] = newPeriod;
                                                              });
                                                            }
                                                          },
                                                    items: mealPeriodOptions.map((period) {
                                                      return DropdownMenuItem<String>(
                                                        value: period,
                                                        child: Text(period),
                                                      );
                                                    }).toList(),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 12),

                                        // (B) 份量調節
                                        Expanded(
                                          flex: 6,
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                '份量',
                                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                              ),
                                              const SizedBox(height: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                                decoration: BoxDecoration(
                                                  color: AppColors.background,
                                                  borderRadius: BorderRadius.circular(10),
                                                  border: Border.all(color: AppColors.border),
                                                ),
                                                child: Row(
                                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                  children: [
                                                    InkWell(
                                                      onTap: (isSaving || cardQty <= 1)
                                                          ? null
                                                          : () {
                                                              setDialogState(() {
                                                                flatCards[cardIdx]['quantity'] = cardQty - 1;
                                                              });
                                                            },
                                                      borderRadius: BorderRadius.circular(6),
                                                      child: Container(
                                                        padding: const EdgeInsets.all(4),
                                                        decoration: BoxDecoration(
                                                          color: (cardQty <= 1 || isSaving) ? Colors.grey.shade300 : AppColors.primary.withOpacity(0.15),
                                                          borderRadius: BorderRadius.circular(6),
                                                        ),
                                                        child: const Icon(Icons.remove, size: 16, color: AppColors.primary),
                                                      ),
                                                    ),
                                                    Text(
                                                      '$cardQty',
                                                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                                    ),
                                                    InkWell(
                                                      onTap: isSaving
                                                          ? null
                                                          : () {
                                                              setDialogState(() {
                                                                flatCards[cardIdx]['quantity'] = cardQty + 1;
                                                              });
                                                            },
                                                      borderRadius: BorderRadius.circular(6),
                                                      child: Container(
                                                        padding: const EdgeInsets.all(4),
                                                        decoration: BoxDecoration(
                                                          color: isSaving ? Colors.grey.shade300 : AppColors.primary.withOpacity(0.15),
                                                          borderRadius: BorderRadius.circular(6),
                                                        ),
                                                        child: const Icon(Icons.add, size: 16, color: AppColors.primary),
                                                      ),
                                                    ),
                                                    Text(
                                                      cardUnit,
                                                      style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }).toList(),

                    // 新增餐點卡片按鈕
                    Center(
                      child: OutlinedButton.icon(
                        onPressed: isSaving
                            ? null
                            : () {
                                setDialogState(() {
                                  flatCards.add({
                                    'name': '',
                                    'quantity': 1,
                                    'unit': '份',
                                    'meal_period': '早餐',
                                    'date': defaultDate,
                                    'is_expanded': true,
                                  });
                                });
                              },
                        icon: const Icon(Icons.add, size: 16, color: AppColors.primary),
                        label: const Text('新增餐點卡片', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.primary),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () {
                          SystemChannels.textInput.invokeMethod('TextInput.hide');
                          FocusManager.instance.primaryFocus?.unfocus();
                          Navigator.of(ctx).pop();
                        },
                  child: const Text('取消', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: isSaving
                      ? null
                      : () async {
                          setDialogState(() => isSaving = true);
                          try {
                            for (var card in flatCards) {
                              final name = card['name']?.toString().trim() ?? '';
                              final period = card['meal_period']?.toString() ?? '早餐';
                              final qty = card['quantity']?.toString() ?? '1';
                              final unit = card['unit']?.toString() ?? '';
                              final cardDate = card['date'] as DateTime? ?? defaultDate;

                              if (name.isNotEmpty) {
                                final res = await DietService().createDietRecord(
                                  dishName: name,
                                  mealType: period,
                                  amount: '$qty $unit'.trim(),
                                  description: '陪伴精靈解析並經使用者核對修正',
                                  mealDate: cardDate,
                                );
                                if (res['success'] != true) {
                                  throw Exception(res['message'] ?? '寫入資料庫失敗');
                                }
                              }
                            }
                            SystemChannels.textInput.invokeMethod('TextInput.hide');
                            FocusManager.instance.primaryFocus?.unfocus();
                            if (ctx.mounted) Navigator.of(ctx).pop();
                            if (context.mounted) {
                              FocusScope.of(context).unfocus();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('飲食紀錄已成功儲存！'),
                                  backgroundColor: AppColors.primary,
                                ),
                              );
                            }
                          } catch (e) {
                            setDialogState(() => isSaving = false);
                            debugPrint('儲存飲食草稿失敗: $e');
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('儲存失敗：${e.toString().replaceAll('Exception: ', '')}'),
                                  backgroundColor: Colors.redAccent,
                                ),
                              );
                            }
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('確認儲存', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildCalorieArcGaugeCard(int currentCalories) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withOpacity(0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "昨日熱量",
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
          ),

          const SizedBox(height: 6),

          Center(
            child: SizedBox(
              width: 190,
              height: 95,
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  CustomPaint(
                    size: const Size(190, 95),
                    painter: CalorieGaugeArcPainter(currentCalories: currentCalories.toDouble()),
                  ),
                  Positioned(
                    bottom: 6,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text("約", style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w500)),
                        Text(
                          currentCalories.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},'),
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary, height: 1.1),
                        ),
                        const Text("kcal", style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 8),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildGaugeZoneLabel("偏低", "< 1,700 kcal", const Color(0xFF7C83FD)),
              _buildGaugeZoneLabel("適量", "1,700 - 2,000 kcal", const Color(0xFF52C41A)),
              _buildGaugeZoneLabel("偏高", "> 2,000 kcal", const Color(0xFFFF7A45)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGaugeZoneLabel(String zoneTitle, String rangeStr, Color color) {
    return Column(
      children: [
        Text(
          zoneTitle,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
        ),
        const SizedBox(height: 1),
        Text(
          rangeStr,
          style: const TextStyle(fontSize: 9, color: Colors.black54, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildMacronutrientBarChartCard({
    required int carbsPercent,
    required int proteinPercent,
    required int fatPercent,
    required double todayCarbs,
    required double todayProtein,
    required double todayFat,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withOpacity(0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "昨日三大營養素比例",
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
          ),

          const SizedBox(height: 8),

          Column(
            children: [
              SizedBox(
                height: 84,
                child: Stack(
                  children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildDashedGridLine("100%"),
                        _buildDashedGridLine("75%"),
                        _buildDashedGridLine("50%"),
                        _buildDashedGridLine("25%"),
                        _buildDashedGridLine("0%"),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 40, right: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _buildSingleBarItem(carbsPercent, const Color(0xFF7C83FD)),
                          _buildSingleBarItem(proteinPercent, const Color(0xFFFF7A45)),
                          _buildSingleBarItem(fatPercent, const Color(0xFFFFB800)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 40, right: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildMacroLabelItem("碳水化合物", todayCarbs),
                    _buildMacroLabelItem("蛋白質", todayProtein),
                    _buildMacroLabelItem("脂肪", todayFat),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMacroLabelItem(String label, double grams) {
    return SizedBox(
      width: 62,
      child: Column(
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            "約 ${grams.round()} g",
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 9,
              color: Colors.black54,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /*
  Widget _buildLegendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
      ],
    );
  }
  */

  Widget _buildDashedGridLine(String label) {
    return Row(
      children: [
        SizedBox(
          width: 34,
          child: Text(label, style: const TextStyle(fontSize: 9, color: Colors.black45, fontWeight: FontWeight.w500)),
        ),
        Expanded(
          child: Container(
            height: 1,
            color: Colors.black.withOpacity(0.06),
          ),
        ),
      ],
    );
  }

  Widget _buildSingleBarItem(int pct, Color color) {
    const double plotHeight = 84.0;
    final double barHeight = (pct / 100.0 * plotHeight).clamp(4.0, plotHeight);
    final double labelBottom = (barHeight + 3).clamp(4.0, plotHeight - 14);

    return SizedBox(
      width: 62,
      height: plotHeight,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            bottom: 0,
            child: Container(
              width: 38,
              height: barHeight,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                boxShadow: [
                  BoxShadow(color: color.withOpacity(0.25), blurRadius: 3, offset: const Offset(0, 1)),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: labelBottom,
            child: Text(
              "$pct%",
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CalorieGaugeArcPainter extends CustomPainter {
  final double currentCalories;
  CalorieGaugeArcPainter({required this.currentCalories});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height - 10);
    final radius = size.width / 2 - 20;
    final rect = Rect.fromCircle(center: center, radius: radius);
    const strokeWidth = 22.0;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    const double startAngle = math.pi;
    const double totalAngle = math.pi;

    final double seg1Angle = totalAngle * 0.38;
    final double seg2Angle = totalAngle * 0.34;
    final double seg3Angle = totalAngle * 0.28;

    paint.color = const Color(0xFF7C83FD);
    canvas.drawArc(rect, startAngle, seg1Angle, false, paint);

    paint.color = const Color(0xFF52C41A);
    canvas.drawArc(rect, startAngle + seg1Angle, seg2Angle, false, paint);

    paint.color = const Color(0xFFFF7A45);
    canvas.drawArc(rect, startAngle + seg1Angle + seg2Angle, seg3Angle, false, paint);

    double progressRatio;
    if (currentCalories < 1700) {
      progressRatio = (currentCalories / 1700.0).clamp(0.0, 1.0) * 0.38;
    } else if (currentCalories <= 2000) {
      progressRatio = 0.38 + ((currentCalories - 1700.0) / 300.0).clamp(0.0, 1.0) * 0.34;
    } else {
      progressRatio = 0.72 + ((currentCalories - 2000.0) / 1000.0).clamp(0.0, 1.0) * 0.28;
    }

    final double knobAngle = startAngle + progressRatio * totalAngle;
    final double knobX = center.dx + radius * math.cos(knobAngle);
    final double knobY = center.dy + radius * math.sin(knobAngle);

    canvas.drawCircle(Offset(knobX, knobY), 11, Paint()..color = Colors.black26..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
    canvas.drawCircle(Offset(knobX, knobY), 9, Paint()..color = Colors.white);

    Color dotColor;
    if (currentCalories < 1700) {
      dotColor = const Color(0xFF7C83FD);
    } else if (currentCalories <= 2000) {
      dotColor = const Color(0xFF52C41A);
    } else {
      dotColor = const Color(0xFFFF7A45);
    }
    canvas.drawCircle(Offset(knobX, knobY), 4.5, Paint()..color = dotColor);
  }

  @override
  bool shouldRepaint(covariant CalorieGaugeArcPainter oldDelegate) =>
      oldDelegate.currentCalories != currentCalories;
}

class _NutrientInfo extends StatelessWidget { // 定義 _NutrientInfo 類別，繼承自 StatelessWidget
  final String label, value, unit; // 宣告類別成員或方法內部的區域變數
  const _NutrientInfo({required this.label, required this.value, required this.unit}); // 建立編譯期常數，優化 Flutter 渲染效能

  @override // 標記此方法為覆寫父類別之方法
  Widget build(BuildContext context) { // 建立畫面的主要 build 方法，返回元件樹
    return Column( // 建立垂直排列元件（Column），縱向排列多個子元件
      children: [ // 執行相對應的邏輯計算或設定屬性參數
        Text(label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 12)), // 建立文字顯示元件（Text）
        const SizedBox(height: 5), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)), // 建立文字顯示元件（Text）
        Text(unit, style: const TextStyle(fontSize: 10, color: AppColors.textPrimary)), // 建立文字顯示元件（Text）
      ], // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束
} // 程式碼區塊或元件結構結束


class MacronutrientValuesDisplay extends StatelessWidget {
  final double protein;
  final double fat;
  final double carbs;

  const MacronutrientValuesDisplay({
    super.key,
    required this.protein,
    required this.fat,
    required this.carbs,
  });

  @override
  Widget build(BuildContext context) {
    final total = protein + fat + carbs;
    if (total == 0) {
      return const SizedBox(
        height: 60,
        child: Center(
          child: Text(
            '昨日無三大營養素數據',
            style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
          ),
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildValueItem('蛋白質', protein, total, 'g'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildValueItem('脂肪', fat, total, 'g'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildValueItem('碳水', carbs, total, 'g'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '三大營養素合計 ${total.toStringAsFixed(0)} g',
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textPrimary.withOpacity(0.65),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildValueItem(String label, double val, double total, String unit) {
    final pct = (val / total * 100).toStringAsFixed(0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.background.withOpacity(0.65),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.08)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            val.toStringAsFixed(0),
            style: const TextStyle(
              fontSize: 18,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            '$unit / $pct%',
            style: TextStyle(
              fontSize: 10,
              color: AppColors.textPrimary.withOpacity(0.65),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
