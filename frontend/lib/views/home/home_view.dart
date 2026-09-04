import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// [代碼清理/Lint修正] 移除重複匯入的 dart:ui，因為 material.dart 已涵蓋相關 UI 元素與型態定義
import 'dart:convert';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import '../../controllers/dog_state_controller.dart';
import '../../services/auth_service.dart';
// import '../../services/admin_service.dart';
import '../../services/body_status_api_service.dart';
import '../../services/diet_service.dart';
import '../../utils/friendly_error_message.dart';
import '../../color/app_colors.dart';
import '../../widgets/body_transition_animation_dialog.dart';
import '../../widgets/dog_avatar.dart';
import '../../widgets/meal_record_card.dart';
import '../records/diary_page.dart';
import '../records/elf_feeding_page.dart';
import '../records/manual_record_page.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

// === 1. AI 主對話頁面與狀態定義 (HomeView & State) ===
class HomeView extends StatefulWidget {
  final bool initialOpenChat;
  const HomeView({super.key, this.initialOpenChat = false});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView>
    with TickerProviderStateMixin, WidgetsBindingObserver {
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

  final TextEditingController _inputController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  final AuthService _authService = AuthService();
  final BodyStatusApiService _bodyStatusApi = BodyStatusApiService();
  final DogStateController _dogController = DogStateController.instance;

  late stt.SpeechToText _speech; // 語音轉文字 (SpeechToText) 服務實例
  bool _isListening = false; // 紀錄目前是否正處於語音收聽/錄音狀態
  bool _speechAvailable = false; // 紀錄語音辨識服務是否已被順利初始化且可用

  late bool _isChatOpen;
  late double _chatPanelX;
  String _userNickname = '使用者';
  String _petType = '米粒(Mili)';
  // String _dietGoal = '養生'; // 未使用，先註解

  List<Map<String, dynamic>> _messages = []; // UI 顯示的對話氣泡清單
  List<Map<String, String>> _tempStory =
      []; // 前端託管最近最多 3 則訊息 ([{role: 'user'|'assistant', content: '...'}])
  DateTime? _lastUpdateTime; // 最後互動時間戳，供 24h 閒置檢測比對

  String _stripEmojis(String text) {
    final regex = RegExp(
      r'[\u{1F300}-\u{1F5FF}\u{1F600}-\u{1F64F}\u{1F680}-\u{1F6FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}\u{1F900}-\u{1F9FF}\u{1F1E0}-\u{1F1FF}\u{1F004}\u{1F0CF}\u{1F170}-\u{1F19A}\u{1F201}-\u{1F251}\u{1fa00}-\u{1faff}]',
      unicode: true,
    );
    String result = text.replaceAll(regex, '');
    result = result.replaceAll(
      RegExp(r'[\u2700-\u27BF\u2600-\u26FF\u2300-\u23FF]'),
      '',
    );
    return result.trim();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isChatOpen = widget.initialOpenChat;
    _chatPanelX = widget.initialOpenChat ? 0.0 : 1.0;
    _dogController.setState(DogAnimationState.idle);
    _loadHomeData();

    _speech = stt.SpeechToText(); // 建立語音轉文字元件實例
    // 語音引擎延遲至點擊時初始化，避免在 initState 阻塞主 UI 執行緒造成 ANR 凍結

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      SystemChannels.textInput.invokeMethod('TextInput.hide');
      FocusManager.instance.primaryFocus?.unfocus();
      await _checkAndShowDietSummaryDialog();
      if (!mounted) return;
      await _checkAndShowBodyTransitionOnStartup();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_isListening) {
      _speech.stop(); // 頁面銷毀時，若正處於收聽狀態，自動停止錄音以釋放資源
    }
    _inputController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  // === 2. 語音辨識與文字輸入邏輯 (SpeechToText & Text Input) ===
  Future<bool> _initSpeech() async {
    try {
      _speechAvailable = await _speech
          .initialize(
            onStatus: (status) {
              debugPrint('🗣️ [SpeechToText Status] $status');
              // 語音辨識結束或停止收聽時，自動更新 UI 狀態
              if (status == 'done' || status == 'notListening') {
                if (mounted) setState(() => _isListening = false);
              }
            },
            onError: (errorNotification) {
              debugPrint(
                '⚠️ [SpeechToText Error] ${errorNotification.errorMsg} (permanent: ${errorNotification.permanent})',
              );
              // 發生語音辨識錯誤時，停止收聽並重置 UI 狀態
              if (mounted) setState(() => _isListening = false);
            },
          )
          .timeout(
            const Duration(seconds: 4),
            onTimeout: () {
              debugPrint('⚠️ [SpeechToText] 初始化超時（硬體/模擬器缺少語音引擎服務）');
              return false;
            },
          );
      debugPrint('🗣️ [SpeechToText] 初始化成功狀態: $_speechAvailable');
    } catch (e) {
      debugPrint('❌ [SpeechToText] 初始化失敗: $e');
      _speechAvailable = false;
    }
    if (mounted) setState(() {});
    return _speechAvailable;
  }

  /// 切換語音收聽狀態（開始錄音 / 停止錄音）
  void _toggleListening() async {
    if (_isListening) {
      // 若目前正在收聽，先更新狀態為 false，並呼叫 cancel 丟棄殘餘 callback
      if (mounted) setState(() => _isListening = false);
      try {
        await _speech.cancel();
      } catch (e) {
        debugPrint('取消語音收聽失敗: $e');
      }
      return;
    }

    // 若尚未初始化，重新嘗試初始化
    if (!_speechAvailable) {
      final initialized = await _initSpeech();
      if (!initialized) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('無法啟動語音辨識，請確認手機已啟用 Google 語音服務。'),
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }
    }

    // 1. 智慧判斷語音辨識 Locale 語系（優先尋找台灣/繁體中文 TW / Hant / HK，並規範使用 Android BCP-47 - 劃線格式）
    String localeId = 'zh-TW';
    try {
      final availableLocales = await _speech.locales();
      // 第一優先：尋找包含 tw (台灣)、hant (繁體) 或 hk (香港) 的標籤
      final twLocale = availableLocales.firstWhere(
        (loc) {
          final id = loc.localeId.toLowerCase();
          return id.contains('tw') || id.contains('hant') || id.contains('hk');
        },
        // 第二優先：退回尋找一般中文標籤 (如 zh 或 cmn)
        orElse: () => availableLocales.firstWhere((loc) {
          final id = loc.localeId.toLowerCase();
          return id.contains('zh') || id.contains('cmn');
        }, orElse: () => stt.LocaleName('zh-TW', '繁體中文')),
      );
      // 將底線 _ 轉換為 Android BCP-47 標準連字號 - (例如 zh_TW -> zh-TW, cmn_CN -> cmn-CN)，避免 Android 原生拒絕
      localeId = twLocale.localeId.replaceAll('_', '-');
      debugPrint('🗣️ [SpeechToText] 優先選用台灣/繁體中文語系 Tag: $localeId');
    } catch (e) {
      // 若查詢失敗，強制保留 zh-TW 讓 Google 開啟線上雲端中文辨識
      localeId = 'zh-TW';
      debugPrint('取得 SpeechToText Locales 失敗，強制使用預設 zh-TW: $e');
    }

    try {
      // 2. 開始聽取語音，設定中文辨識與停頓時間
      if (mounted) setState(() => _isListening = true);
      debugPrint('🗣️ [SpeechToText] 開始監聽語音，使用 Locale: $localeId');
      await _speech.listen(
        localeId: localeId,
        listenOptions: stt.SpeechListenOptions(
          partialResults: true, // 允許實時邊講邊回傳文字片段
          cancelOnError: false, // 遭遇短暫雜訊不強制中斷收聽
          listenMode: stt.ListenMode.dictation, // 設定為連續聽寫模式
        ),
        listenFor: const Duration(seconds: 30), // 設定單次語音輸入最長可聽取 30 秒
        pauseFor: const Duration(seconds: 6), // 允許說話前思考或中途停頓最多 6 秒，不會太快過期
        onResult: (result) {
          debugPrint(
            '🗣️ [SpeechToText Result] 收到文字: "${result.recognizedWords}" (final: ${result.finalResult})',
          );
          // 若已非收聽狀態（例如已關閉或已送出訊息），忽略殘餘非同步回傳，避免覆蓋已清空的輸入框
          if (!mounted || !_isListening) return;
          if (result.recognizedWords.isNotEmpty) {
            setState(() {
              // 將辨識出的文字即時更新寫入輸入框控制器
              _inputController.text = result.recognizedWords;
              // 將輸入框游標移動至文字最後方，方便使用者手動修改
              _inputController.selection = TextSelection.fromPosition(
                TextPosition(offset: _inputController.text.length),
              );
            });
          }
        },
      );
    } catch (e) {
      debugPrint('❌ [SpeechToText] 啟動語音收聽失敗，嘗試退回系統預設語言: $e');
      try {
        await _speech.listen(
          listenOptions: stt.SpeechListenOptions(
            partialResults: true,
            cancelOnError: false,
            listenMode: stt.ListenMode.dictation,
          ),
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 6),
          onResult: (result) {
            if (!mounted || !_isListening) return;
            if (result.recognizedWords.isNotEmpty) {
              setState(() {
                _inputController.text = result.recognizedWords;
                _inputController.selection = TextSelection.fromPosition(
                  TextPosition(offset: _inputController.text.length),
                );
              });
            }
          },
        );
      } catch (e2) {
        if (mounted) {
          setState(() => _isListening = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('語音輸入失敗，請重新再試一次。'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _check24hIdleTimeout();
    }
  }

  Future<String> _getUserStorageKey() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('user_email');
    final nickname = prefs.getString('user_nickname');
    final rawKey = (email != null && email.trim().isNotEmpty)
        ? email.trim().toLowerCase()
        : ((nickname != null && nickname.trim().isNotEmpty)
              ? nickname.trim().toLowerCase()
              : 'default');
    return rawKey;
  }

  /// 從 SharedPreferences 載入 temp_story 快取與最後更新時間（依使用者帳號隔離）
  Future<void> _loadTempStoryFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final userKey = await _getUserStorageKey();
    final String? storyJson = prefs.getString('temp_story_$userKey');
    final int? lastTimeMs = prefs.getInt('last_update_time_$userKey');

    if (lastTimeMs != null) {
      _lastUpdateTime = DateTime.fromMillisecondsSinceEpoch(lastTimeMs);
    }

    if (storyJson != null) {
      try {
        final List<dynamic> decoded = jsonDecode(storyJson);
        _tempStory = decoded
            .map((e) => Map<String, String>.from(e as Map))
            .toList();
      } catch (e) {
        debugPrint('載入 temp_story_$userKey 快取失敗: $e');
        _tempStory = [];
      }
    }

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

  /// 清空對話歷史與 SharedPreferences 快取，重置為初始話題（依使用者帳號隔離）
  Future<void> resetChat() async {
    final prefs = await SharedPreferences.getInstance();
    final userKey = await _getUserStorageKey();
    await prefs.remove('temp_story_$userKey');
    await prefs.remove('last_update_time_$userKey');

    setState(() {
      _messages = [
        {
          'isElf': true,
          'text': '嗨 $_userNickname！我是你的飲食夥伴精靈！無論想記錄餐點、詢問營養建議，或是隨意聊聊都歡迎跟我說喔！',
        },
      ];
      _tempStory.clear();
      _lastUpdateTime = DateTime.now();
    });
  }

  /// 將新對話推入 tempStory，維持最多 3 則訊息的滑動視窗，並寫入 SharedPreferences 快取（依使用者帳號隔離）
  void _appendTempStory(String role, String content) async {
    _tempStory.add({'role': role, 'content': content});
    if (_tempStory.length > 3) {
      _tempStory.removeAt(0);
    }
    _lastUpdateTime = DateTime.now();

    final prefs = await SharedPreferences.getInstance();
    final userKey = await _getUserStorageKey();
    await prefs.setString('temp_story_$userKey', jsonEncode(_tempStory));
    await prefs.setInt(
      'last_update_time_$userKey',
      _lastUpdateTime!.millisecondsSinceEpoch,
    );
  }

  /// 內嵌於 home_view.dart 中的「開啟新話題」按鈕 UI
  Widget _buildNewTopicButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          resetChat();
          _scrollToBottom();
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.secondary, width: 1.2),
          ),
          child: const Text(
            '開啟新話題',
            style: TextStyle(
              color: AppColors.secondary,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  // === 3. 寵物數據載入與狀態控制器 (Pet State & Dog Controller) ===
  Future<void> _loadHomeData() async {
    // 1. 先從本地快取讀取 (前端輔助，速度快)
    final prefs = await SharedPreferences.getInstance();
    final cachedRole = prefs.getString('user_role');
    final cachedEmail = prefs.getString('user_email') ?? '';
    final bool isCachedAdmin =
        cachedRole == 'ROLE_ADMIN' ||
        cachedRole == 'ADMIN' ||
        cachedEmail.trim().toLowerCase() == 'admin@gmail.com';
    String nick =
        prefs.getString('user_nickname') ?? (isCachedAdmin ? '系統管理員' : '使用者');
    if (isCachedAdmin && (nick == 'aaa' || nick == '使用者')) {
      nick = '系統管理員';
    }

    setState(() {
      _userNickname = prefs.getString('user_nickname') ?? '使用者';
      _petType = '米粒(Mili)';
      // _dietGoal = prefs.getString('user_diet_goal') ?? '養生'; // 未使用，先註解
      _messages = [
        {
          'isElf': true,
          'text': '嗨 $_userNickname！我是你的飲食夥伴精靈！無論想記錄餐點、詢問營養建議，或是隨意聊聊都歡迎跟我說喔！',
        },
      ];
    });
    await _loadTempStoryFromStorage();

    // 2. 向後端請求最新資料 (後端為主，保持同步)
    await _syncBodyStatus(prefs);
    if (!mounted) return;

    final result = await _authService.getUserProfile();
    if (result['success'] == true) {
      final userData = result['data'];
      final String g = userData['dietGoal'] ?? userData['diet_goal'] ?? '養生';
      await prefs.setString('user_diet_goal', g);

      final String? userRole =
          userData['user']?['role'] ?? userData['role'] ?? cachedRole;
      final String userEmail =
          userData['email'] ?? userData['user']?['email'] ?? cachedEmail;
      final bool isUserAdmin =
          userRole == 'ROLE_ADMIN' ||
          userRole == 'ADMIN' ||
          userEmail.trim().toLowerCase() == 'admin@gmail.com';

      String fetchedNick = userData['nickname'] ?? '';
      if (isUserAdmin &&
          (fetchedNick.isEmpty ||
              fetchedNick == 'aaa' ||
              fetchedNick == '使用者')) {
        fetchedNick = '系統管理員';
      } else if (fetchedNick.isEmpty) {
        fetchedNick = _userNickname;
      }

      setState(() {
        _userNickname = userData['nickname'] ?? '使用者';
        _petType = '米粒(Mili)';
        // _dietGoal = g; // 未使用，先註解
        // 更新歡迎詞
        if (_messages.isNotEmpty && _messages[0]['isElf'] == true) {
          _messages[0]['text'] =
              '嗨 $_userNickname！我是你的飲食夥伴精靈！無論想記錄餐點、詢問營養建議，或是隨意聊聊都歡迎跟我說喔！';
        }
      });
      prefs.setString('user_nickname', _userNickname);
    }
  }

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
          final y = int.parse(
            (dateVal['year'] ?? dateVal['yearValue']).toString(),
          );
          final m = int.parse(
            (dateVal['month'] ?? dateVal['monthValue']).toString(),
          );
          final d = int.parse(
            (dateVal['day'] ?? dateVal['dayOfMonth']).toString(),
          );
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
          final y = int.parse(
            (mealDateVal['year'] ?? mealDateVal['yearValue']).toString(),
          );
          final m = int.parse(
            (mealDateVal['month'] ?? mealDateVal['monthValue']).toString(),
          );
          final d = int.parse(
            (mealDateVal['day'] ?? mealDateVal['dayOfMonth']).toString(),
          );
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
          final h = createdAtVal.length > 3
              ? int.parse(createdAtVal[3].toString())
              : 0;
          final min = createdAtVal.length > 4
              ? int.parse(createdAtVal[4].toString())
              : 0;
          final s = createdAtVal.length > 5
              ? int.parse(createdAtVal[5].toString())
              : 0;
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
          final numMatch = RegExp(
            r'(\d+(?:\.\d+)?)',
          ).firstMatch(calVal.toString());
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
                final numMatch = RegExp(
                  r'(\d+(?:\.\d+)?)',
                ).firstMatch(parsed['calories'].toString());
                if (numMatch != null) {
                  return double.tryParse(numMatch.group(1) ?? '') ?? 0.0;
                }
              }
            }
          } catch (_) {}

          final numRegExp = RegExp(
            r'(\d+(?:\.\d+)?)\s*(?:kcal|千卡|卡)?',
            caseSensitive: false,
          );
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
    final kcalMatch = RegExp(
      r'(\d+(?:\.\d+)?)\s*(?:kcal|千卡|卡)',
      caseSensitive: false,
    ).firstMatch(combined);
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
    } else if (pattern.contains('碳水') ||
        pattern.contains('carbohydrate') ||
        pattern.contains('carb')) {
      englishKey = 'carbohydrates';
    }

    if (nutrition is Map) {
      if (englishKey.isNotEmpty) {
        final val = nutrition[englishKey];
        if (val != null) {
          final numMatch = RegExp(
            r'(\d+(?:\.\d+)?)',
          ).firstMatch(val.toString());
          if (numMatch != null) {
            return double.tryParse(numMatch.group(1) ?? '') ?? 0.0;
          }
        }
      }
    } else {
      final nutritionStr = nutrition.toString().trim();
      if (nutritionStr.isNotEmpty) {
        final regExp = RegExp(
          pattern + r':\s*(\d+(?:\.\d+)?)',
          caseSensitive: false,
        );
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

    final asksAboutDate =
        normalizedPrompt.contains('今天') ||
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
      final dateLabel = isToday
          ? '今天'
          : '${reportDate.month}/${reportDate.day}';
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

  // === 4. 昨日總結與體態變化彈窗觸發器 (Yesterday Summary & Body Transition) ===
  Future<void> _checkAndShowDietSummaryDialog() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now();
    final todayStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final userEmail = prefs.getString('user_email')?.trim().toLowerCase() ?? '';
    final userNick = prefs.getString('user_nickname')?.trim() ?? '';
    final userKey = userEmail.isNotEmpty
        ? userEmail
        : (userNick.isNotEmpty ? userNick : 'default');
    final summaryKey = 'last_shown_summary_date_$userKey';

    // 檢查今天是否已經顯示過飲食總結彈窗（每人每天僅第一次開啟 app 時跳出）
    final lastShownDate = prefs.getString(summaryKey);
    if (lastShownDate == todayStr) {
      debugPrint('今日 ($todayStr) 使用者 ($userKey) 已顯示過飲食總結彈窗，不再重複跳出。');
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
          totalCarbs += _getNutrientFromRecord(
            record,
            r'(?:碳水化合物|碳水|carbohydrate|carbs)',
          );

          if (record['dishName'] != null) {
            yesterdayDishes.add(record['dishName'].toString());
          }
        }
      }

      if (!mounted) return;
      debugPrint('=============================================');
      debugPrint('準備跳出昨日飲食總結彈窗！ User: $userKey, Dishes: $yesterdayDishes');
      debugPrint('=============================================');

      // 紀錄今日已跳出飲食總結彈窗
      await prefs.setString(summaryKey, todayStr);

      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      await _showDietSummaryDialog(
        date: yesterday,
        calories: totalCalories,
        protein: totalProtein,
        fat: totalFat,
        carbs: totalCarbs,
        dishes: yesterdayDishes,
      );
    } catch (e) {
      debugPrint('取得昨日飲食總結失敗: $e');
    }
  }

  // [代碼清理/Lint修正] 靜態分析發出未呼叫警告，保留此方法作為測試或手動觸發昨日飲食總結彈窗之入口
  // ignore: unused_element
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

  // [代碼清理/Lint修正] 靜態分析發出未呼叫警告，保留此方法作為手動觸發體態評估彈窗之備用入口
  // ignore: unused_element
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
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 16.0,
            ),
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
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
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

  Future<void> _showDietSummaryDialog({
    required DateTime date,
    required double calories,
    required double protein,
    required double fat,
    required double carbs,
    required List<String> dishes,
    String? emptyComment,
    String Function(List<String> dishes, double calories)? filledCommentBuilder,
  }) async {
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

    await showDialog(
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
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 16.0,
            ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12.0,
                    vertical: 8.0,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12.0),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          comment,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textPrimary.withValues(
                              alpha: 0.85,
                            ),
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
          style: TextStyle(fontSize: 12, color: AppColors.textPrimary.withValues(alpha: 0.5)),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
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
      final status = await _bodyStatusApi.getBodyStatus().timeout(
        const Duration(seconds: 6),
      );
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
      final prefs = await SharedPreferences.getInstance();

      DogBodyType oldBodyType;
      DogBodyType newBodyType;
      bool shouldShowDialog = false;

      final bool pendingShow =
          prefs.getBool('pending_body_transition_show') ?? false;
      if (pendingShow) {
        final pendingOldStr = prefs.getString('pending_old_body_type');
        final pendingNewStr = prefs.getString('pending_new_body_type');
        await prefs.remove('pending_body_transition_show');
        await prefs.remove('pending_old_body_type');
        await prefs.remove('pending_new_body_type');

        oldBodyType = DogStateController.parseBodyType(pendingOldStr);
        newBodyType = DogStateController.parseBodyType(pendingNewStr);
        shouldShowDialog = oldBodyType != newBodyType;
      } else {
        final settlement = await _bodyStatusApi.settleDailyScores().timeout(
          const Duration(seconds: 8),
        );
        await prefs.setString('dog_body_type', settlement.bodyType);
        oldBodyType = DogStateController.parseBodyType(settlement.oldBodyType);
        newBodyType = DogStateController.parseBodyType(settlement.newBodyType);
        shouldShowDialog =
            settlement.bodyTypeChanged && oldBodyType != newBodyType;
      }

      if (!shouldShowDialog) {
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
    switch (petType) {
      case '奶油皮丘': return Icons.pets; // 回傳建構完成的元件或方法計算結果
      case '薄荷兔兔': return Icons.eco; // 回傳建構完成的元件或方法計算結果
      case '草莓狐狸': return Icons.star;
      default: return Icons.pets;
    }
  }

  // 獲取 3D 渲染的柴犬精靈圖片路徑
  String _getPetImagePath(String petType, String dietGoal) {
    String path = 'assets/images/shiba_normal.png';
    if (petType == '奶油皮丘' || petType.isNotEmpty) {
      if (dietGoal.contains('減脂')) {
        path = 'assets/images/shiba_fat.png';
      } else if (dietGoal.contains('增肌')) {
        path = 'assets/images/shiba_muscular.png';
      } else if (dietGoal.contains('養生')) {
        path = 'assets/images/shiba_thin.png';
      }
    }
    return path;
  }
  */

  // 根據小精靈名稱獲取對應顏色
  Color _getPetColor(String petType) {
    switch (petType) {
      case '奶油皮丘':
        return const Color(0xFFD4A373); // Muted orange (retro)
      case '薄荷兔兔':
        return const Color(0xFF8A9A5B); // Muted sage (retro)
      case '草莓狐狸':
        return const Color(0xFFB07D62); // Muted terracotta (retro)
      default:
        return AppColors.secondary;
    }
  }

  void _toggleChat(bool open) {
    setState(() {
      _isChatOpen = open;
      _chatPanelX = open ? 0.0 : 1.0;
    });
    if (open) {
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    // 新增：自動滾動對話清單到底部
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
      if (!mounted || _dogController.state != DogAnimationState.response)
        return;
      _dogController.setState(DogAnimationState.idle);
    });
  }

  // === 5. AI 聊天訊息發送與 API 呼叫 (Chat API & Voice Processing) ===
  void _handleMessage(String text) {
    FocusScope.of(context).unfocus(); // 送出訊息後立刻收起軟鍵盤
    if (text.trim().isEmpty) return;

    // 送出訊息時若語音辨識仍在收聽，先取消語音並重置狀態，避免非同步 callback 覆蓋已清空的輸入框
    if (_isListening) {
      _isListening = false;
      _speech.cancel();
    }

    // 複製一份當前歷史傳給後端
    final payloadHistory = List<Map<String, String>>.from(_tempStory);
    _appendTempStory('user', text);

    setState(() {
      _messages.add({'isElf': false, 'text': text});
      _inputController.clear();
      _isChatOpen = true;
      _chatPanelX = 0.0;
    });
    _dogController.setState(DogAnimationState.thinking);
    _scrollToBottom();

    // 模擬回覆
    Future.delayed(const Duration(milliseconds: 500), () {
      setState(() {
        _messages.add({'isElf': true, 'text': '米粒正在思考中....'});
      });
      _scrollToBottom();

      DietService()
          .sendCompanionUserPrompt(text, tempStory: payloadHistory)
          .then((res) {
            _showDogResponseThenIdle();
            setState(() {
              if (_messages.isNotEmpty &&
                  _messages.last['text'] == '米粒正在思考中....') {
                _messages.removeLast();
              }

              final reply =
                  res['companion_reply'] ??
                  (res['data'] is Map ? res['data']['companion_reply'] : null);

              if (res['success'] == true &&
                  reply != null &&
                  reply.toString().isNotEmpty) {
                final replyStr = reply.toString();
                // 取得 AI 助手識別的意圖類別 (intent_category) 與歷史查詢日期 (query_date)
                final intent = (res['intent_category'] ?? '').toString();
                final queryDate = res['query_date']?.toString();

                // 判斷意圖若為 meal_record 且含草稿，採延遲渲染模式 (Delayed Display Pattern)
                final mealRecords = res['meal_records'] as List<dynamic>? ?? [];
                if (intent == 'meal_record' && mealRecords.isNotEmpty) {
                  _showMealRecordDraftDialog(
                    context,
                    mealRecords,
                    userPrompt: text,
                    delayedReply: replyStr,
                  );
                } else {
                  _messages.add({
                    'isElf': true,
                    'text': replyStr,
                    'intentCategory': intent,
                    'queryDate': queryDate,
                  });
                  _appendTempStory('assistant', replyStr);
                  if (_shouldShowDietReportForPrompt(text, intent)) {
                    Future.microtask(() => _showDietReportFromCompanion(text));
                  }
                }
              } else {
                _messages.add({
                  'isElf': true,
                  'text': FriendlyErrorMessage.companionReply(res['message']),
                });
              }
            });
            _scrollToBottom();
          })
          .catchError((e) {
            _showDogResponseThenIdle();
            setState(() {
              if (_messages.isNotEmpty &&
                  _messages.last['text'] == '米粒正在思考中....') {
                _messages.removeLast();
              }
              _messages.add({
                'isElf': true,
                'text': FriendlyErrorMessage.companionReply(e),
              });
            });
            _scrollToBottom();
          });
    });
  }

  // === 6. UI 畫面建構主體 (Scaffold & Stack Build) ===
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        if (details.delta.dx < -5) _toggleChat(true); // 左滑開啟
        if (details.delta.dx > 5) _toggleChat(false); // 右滑關閉
      },
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: Stack(
          children: [
            // === 7. 頂部 Bar 與寵物狀態卡片組件 (Header Bar & Pet Status Card) ===
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Container(
                  height: 80,
                  alignment: Alignment.center,
                  child: const Text(
                    "精靈助手",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ),

            // 2. 中央大精靈
            Center(
              child: SingleChildScrollView(
                child: Builder(
                  builder: (context) {
                    final isKeyboardVisible =
                        MediaQuery.of(context).viewInsets.bottom > 0;
                    final elfSize = isKeyboardVisible ? 160.0 : 280.0;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _toggleChat(true), // 單擊：開啟對話對話框
                          child: Hero(
                            tag: 'elf',
                            child: Container(
                              width: elfSize,
                              height: elfSize,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.background,
                                boxShadow: [
                                  BoxShadow(
                                    color: _getPetColor(
                                      _petType,
                                    ).withValues(alpha: 0.15),
                                    blurRadius: 15,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  elfSize / 2,
                                ),
                                child: Padding(
                                  padding: EdgeInsets.all(
                                    isKeyboardVisible ? 15.0 : 25.0,
                                  ),
                                  child: AbsorbPointer(
                                    child: DogAvatar(
                                      controller: _dogController,
                                      scale: isKeyboardVisible ? 1.0 : 1.5,
                                      instanceId: 'home-main-dog',
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (!isKeyboardVisible) const SizedBox(height: 20),
                        // 精靈說話框 (初始狀態)
                        if (!_isChatOpen && !isKeyboardVisible) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 15,
                            ),
                            margin: const EdgeInsets.symmetric(horizontal: 20),
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.1,
                                  ),
                                  blurRadius: 1.95,
                                ),
                              ],
                            ),
                            child: Text(
                              _stripEmojis(
                                _messages.isNotEmpty
                                    ? _messages[0]['text']
                                    : "載入中...",
                              ),
                              textAlign: TextAlign.left,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.normal,
                                height: 1.4,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 15),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ),

            // 3. 底部輸入框
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.05),
                      blurRadius: 2.925,
                      offset: const Offset(0, 0.975),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        _isListening ? Icons.mic : Icons.mic_none,
                        color: _isListening ? Colors.red : AppColors.primary,
                      ),
                      onPressed: _toggleListening,
                    ),
                    Expanded(
                      child: TextField(
                        controller: _inputController,
                        decoration: InputDecoration(
                          hintText: _isListening ? "收聽中，請說話..." : "輸入訊息...",
                          border: InputBorder.none,
                          hintStyle: const TextStyle(
                            color: AppColors.textPrimary,
                          ),
                        ),
                        onSubmitted: _handleMessage,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.send, color: AppColors.primary),
                      onPressed: () => _handleMessage(_inputController.text),
                    ),
                  ],
                ),
              ),
            ),

            // 4. 右側滑出的對話面板
            IgnorePointer(
              ignoring: !_isChatOpen,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                transform: Matrix4.translationValues(
                  MediaQuery.of(context).size.width * _chatPanelX,
                  0,
                  0,
                ),
                child: _buildChatPanel(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // === 8. 對話訊息列表與輸入框組件 (Chat ListView & Input Bar) ===
  Widget _buildChatPanel() {
    return Container(
      width: MediaQuery.of(context).size.width,
      color: const Color(0xFFE7D9B1),
      child: Column(
        children: [
          // 對話面板頭部
          Container(
            color: const Color(0xFFFCF8EC), // 頂部標題以上/狀態列使用奶油白
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios,
                      color: AppColors.textPrimary,
                    ),
                    onPressed: () => _toggleChat(false),
                  ),
                  const Text(
                    "與精靈對話",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  _buildNewTopicButton(),
                ],
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              behavior: HitTestBehavior.opaque,
              child: ListView.builder(
                controller: _chatScrollController, // 新增：連結滾動控制器
                padding: const EdgeInsets.fromLTRB(
                  20,
                  20,
                  20,
                  127,
                ), // 新增：底部預留 127 像素，防止文字被小精靈 3D 模型遮擋
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  if (msg['type'] == 'restaurant') {
                    return _buildRestaurantCard(msg['text']);
                  } else if (msg['type'] == 'nutrient') {
                    return _buildNutrientCard();
                  }
                  return _buildChatMessage(
                    msg['isElf'],
                    msg['text'],
                    options: msg['options'],
                    intentCategory: msg['intentCategory'],
                    queryDate: msg['queryDate'],
                  );
                },
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: -130,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: SizedBox(
                      width: 250,
                      height: 250,
                      child: DogAvatar(
                        controller: _dogController,
                        scale: 2.2,
                        cameraControls: false,
                        instanceId: 'home-chat-dog',
                      ),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: Color(0xFFE7D9B1),
                    border: Border(top: BorderSide(color: AppColors.border)),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        // 麥克風語音輸入按鈕
                        icon: Icon(
                          _isListening
                              ? Icons.mic
                              : Icons.mic_none, // 依收聽狀態動態切換圖示
                          color: _isListening
                              ? Colors.red
                              : AppColors.primary, // 錄音中顯示紅色
                        ),
                        onPressed: _toggleListening, // 點擊切換語音收聽狀態
                      ),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 15),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFCF8EC),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: TextField(
                            controller: _inputController,
                            decoration: InputDecoration(
                              hintText: _isListening ? "收聽中，請說話..." : "詢問建議...",
                              border: InputBorder.none,
                              hintStyle: const TextStyle(
                                color: AppColors.textPrimary,
                              ),
                            ),
                            onSubmitted: _handleMessage,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      CircleAvatar(
                        backgroundColor: AppColors.primary,
                        child: IconButton(
                          icon: const Icon(
                            Icons.send,
                            color: AppColors.background,
                            size: 20,
                          ),
                          onPressed: () =>
                              _handleMessage(_inputController.text),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

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
        crossAxisAlignment: isElf
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.end,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            decoration: BoxDecoration(
              color: isElf ? AppColors.background : AppColors.secondary,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.05),
                  blurRadius: 0.975,
                ),
              ],
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
                  // [代碼清理/Lint修正] 在 Spread 運算子 (...) 中直接展開 Iterable，移除贅餘的 .toList()
                  ...options.map(
                    (opt) => Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => _showNutrientDetail(
                            opt['name'],
                            opt['nutrients'],
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.surface,
                            foregroundColor: AppColors.textPrimary,
                            elevation: 0,
                            side: const BorderSide(color: AppColors.border),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            opt['name'],
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // 當意圖為「歷史飲食紀錄查詢 (meal_query)」且含有合法日期時，於對話泡泡下方動態掛載卡片
          if (isElf &&
              intentCategory == 'meal_query' &&
              queryDate != null &&
              queryDate.isNotEmpty)
            Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              child: MealRecordCard(
                queryDate: queryDate,
                onClose: () {},
                // 點擊「查看完整飲食日記」跳轉至日記頁
                onNavigateToDiary: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => DiaryPage(
                        date: DateTime.tryParse(queryDate) ?? DateTime.now(),
                      ),
                    ),
                  );
                },
                // todo: 補記這天的飲食
                // 點擊「＋ 補記這天的飲食」跳轉至手動紀錄頁 (帶入解析後的目標日期，並於返回時觸發畫面刷新)
                onAddRecordForDate: (date) async {
                  final targetDate = DateTime.tryParse(date) ?? DateTime.now();
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          ManualRecordPage(initialDate: targetDate),
                    ),
                  );
                  if (mounted) {
                    setState(() {});
                  }
                },
              ),
            ),
        ],
      ),
    );
  }

  // === 9. 體態評估與歷史分析彈窗元件 (Body Status & History Dialogs) ===
  void _showNutrientDetail(String name, Map<String, dynamic> nutrients) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.45,
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 25),
            Text(
              name,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              "預估攝取熱量: ${nutrients['calories']} kcal",
              style: const TextStyle(
                fontSize: 16,
                color: AppColors.secondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Divider(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NutrientInfo(
                  label: "蛋白質",
                  value: "${nutrients['protein']}",
                  unit: "g",
                ),
                _NutrientInfo(
                  label: "脂肪",
                  value: "${nutrients['fat']}",
                  unit: "g",
                ),
                _NutrientInfo(
                  label: "碳水",
                  value: "${nutrients['carbs']}",
                  unit: "g",
                ),
              ],
            ),
            const Spacer(),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context); // 關閉彈窗
                _toggleChat(false); // 關閉對話框
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ElfFeedingPage(
                      imagePath: "",
                      items: [
                        {
                          'name': name,
                          'portion': '1份',
                          'calories': '${nutrients['calories']} kcal',
                        },
                      ],
                      recordDate: DateTime.now(),
                    ),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size(double.infinity, 55),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                elevation: 2,
              ),
              child: const Text(
                "確認食用",
                style: TextStyle(
                  color: AppColors.background,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRestaurantCard(String text) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.05),
            blurRadius: 1.95,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.restaurant, color: AppColors.secondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            "點擊查看詳細地址與評價",
            style: TextStyle(color: AppColors.textPrimary, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildNutrientCard() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 2.925,
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            "薯條 (大份)",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const Divider(height: 30),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _NutrientInfo(label: "熱量", value: "380", unit: "kcal"),
              _NutrientInfo(label: "蛋白質", value: "4", unit: "g"),
              _NutrientInfo(label: "脂肪", value: "20", unit: "g"),
            ],
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ElfFeedingPage(
                    imagePath: "",
                    items: const [
                      {'name': '薯條', 'portion': '大份', 'calories': '380 kcal'},
                    ],
                    recordDate: DateTime.now(),
                  ),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              minimumSize: const Size(double.infinity, 45),
            ),
            child: const Text(
              "進行餵食",
              style: TextStyle(
                color: AppColors.background,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
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
  void _showMealRecordDraftDialog(
    BuildContext context,
    List<dynamic> mealRecords, {
    String userPrompt = '',
    String? delayedReply,
  }) {
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
          'unit': (item['unit']?.toString() ?? '').isEmpty
              ? '份'
              : item['unit']?.toString(),
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
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 24,
              ),
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
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.black87,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // [代碼清理/Lint修正] 在 Spread 運算子 (...) 中直接展開 Iterable，移除贅餘的 .toList()
                        // 每個餐點獨立成可點擊展開/收合的折疊卡片
                        ...flatCards.asMap().entries.map((cardEntry) {
                          final cardIdx = cardEntry.key;
                          final card = cardEntry.value;
                          final cardQty = card['quantity'] as int;
                          final cardUnit = card['unit'].toString();
                          final cardDate = card['date'] as DateTime;
                          final currentPeriod = card['meal_period'].toString();
                          final bool isExpanded =
                              card['is_expanded'] as bool? ?? (cardIdx == 0);
                          final String dishDisplayName =
                              card['name'].toString().trim().isEmpty
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
                                  color: Colors.black.withValues(alpha: 0.04),
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
                                      flatCards[cardIdx]['is_expanded'] =
                                          !isExpanded;
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(16),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 12,
                                    ),
                                    child: Row(
                                      children: [
                                        // 展開 / 收合 箭頭 (放最左側)
                                        Icon(
                                          isExpanded
                                              ? Icons.keyboard_arrow_up
                                              : Icons.keyboard_arrow_down,
                                          color: AppColors.primary,
                                          size: 24,
                                        ),
                                        const SizedBox(width: 8),

                                        // 餐點標籤 Badge
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary.withValues(
                                              alpha: 0.15,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                Icons.restaurant,
                                                size: 14,
                                                color: AppColors.primary,
                                              ),
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
                                                      flatCards.removeAt(
                                                        cardIdx,
                                                      );
                                                    });
                                                  },
                                            child: const Padding(
                                              padding: EdgeInsets.symmetric(
                                                horizontal: 4.0,
                                              ),
                                              child: Icon(
                                                Icons.delete_outline,
                                                size: 22,
                                                color: AppColors.danger,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),

                                // === 卡片展開詳細內容 ===
                                if (isExpanded) ...[
                                  const Divider(
                                    height: 1,
                                    color: AppColors.border,
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // 1. 餐點名稱
                                        const Text(
                                          '餐點名稱',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        TextFormField(
                                          initialValue: card['name'].toString(),
                                          enabled: !isSaving,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.textPrimary,
                                          ),
                                          decoration: InputDecoration(
                                            hintText: '請輸入餐點名稱',
                                            hintStyle: TextStyle(
                                              fontSize: 13,
                                              color: Colors.grey.shade400,
                                              fontWeight: FontWeight.normal,
                                            ),
                                            filled: true,
                                            fillColor: AppColors.background,
                                            isDense: true,
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 10,
                                                ),
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              borderSide: const BorderSide(
                                                color: AppColors.border,
                                              ),
                                            ),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              borderSide: const BorderSide(
                                                color: AppColors.border,
                                              ),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              borderSide: const BorderSide(
                                                color: AppColors.primary,
                                                width: 1.5,
                                              ),
                                            ),
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
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        InkWell(
                                          onTap: isSaving
                                              ? null
                                              : () async {
                                                  final picked =
                                                      await showDatePicker(
                                                        context: context,
                                                        initialDate: cardDate,
                                                        firstDate: DateTime(
                                                          2023,
                                                        ),
                                                        lastDate: DateTime.now()
                                                            .add(
                                                              const Duration(
                                                                days: 365,
                                                              ),
                                                            ),
                                                      );
                                                  if (picked != null) {
                                                    setDialogState(() {
                                                      flatCards[cardIdx]['date'] =
                                                          picked;
                                                    });
                                                  }
                                                },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 10,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppColors.background,
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              border: Border.all(
                                                color: AppColors.border,
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                const Icon(
                                                  Icons.calendar_today,
                                                  size: 16,
                                                  color: AppColors.primary,
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  '${cardDate.year}-${cardDate.month.toString().padLeft(2, '0')}-${cardDate.day.toString().padLeft(2, '0')}',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14,
                                                    color:
                                                        AppColors.textPrimary,
                                                  ),
                                                ),
                                                const Spacer(),
                                                const Icon(
                                                  Icons.arrow_drop_down,
                                                  color: Colors.grey,
                                                ),
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
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  const Text(
                                                    '餐別',
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color:
                                                          AppColors.textPrimary,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 10,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color:
                                                          AppColors.background,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            10,
                                                          ),
                                                      border: Border.all(
                                                        color: AppColors.border,
                                                      ),
                                                    ),
                                                    child: DropdownButtonHideUnderline(
                                                      child: DropdownButton<String>(
                                                        value:
                                                            mealPeriodOptions
                                                                .contains(
                                                                  currentPeriod,
                                                                )
                                                            ? currentPeriod
                                                            : '早餐',
                                                        isExpanded: true,
                                                        style: const TextStyle(
                                                          fontSize: 13,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: AppColors
                                                              .textPrimary,
                                                        ),
                                                        onChanged: isSaving
                                                            ? null
                                                            : (newPeriod) {
                                                                if (newPeriod !=
                                                                    null) {
                                                                  setDialogState(() {
                                                                    flatCards[cardIdx]['meal_period'] =
                                                                        newPeriod;
                                                                  });
                                                                }
                                                              },
                                                        items: mealPeriodOptions
                                                            .map((period) {
                                                              return DropdownMenuItem<
                                                                String
                                                              >(
                                                                value: period,
                                                                child: Text(
                                                                  period,
                                                                ),
                                                              );
                                                            })
                                                            .toList(),
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
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  const Text(
                                                    '份量',
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color:
                                                          AppColors.textPrimary,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                          vertical: 6,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color:
                                                          AppColors.background,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            10,
                                                          ),
                                                      border: Border.all(
                                                        color: AppColors.border,
                                                      ),
                                                    ),
                                                    child: Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .spaceBetween,
                                                      children: [
                                                        InkWell(
                                                          onTap:
                                                              (isSaving ||
                                                                  cardQty <= 1)
                                                              ? null
                                                              : () {
                                                                  setDialogState(() {
                                                                    flatCards[cardIdx]['quantity'] =
                                                                        cardQty -
                                                                        1;
                                                                  });
                                                                },
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                6,
                                                              ),
                                                          child: Container(
                                                            padding:
                                                                const EdgeInsets.all(
                                                                  4,
                                                                ),
                                                            decoration: BoxDecoration(
                                                              color:
                                                                  (cardQty <=
                                                                          1 ||
                                                                      isSaving)
                                                                  ? Colors
                                                                        .grey
                                                                        .shade300
                                                                  : AppColors
                                                                        .primary
                                                                        .withValues(
                                                                          alpha:
                                                                              0.15,
                                                                        ),
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    6,
                                                                  ),
                                                            ),
                                                            child: const Icon(
                                                              Icons.remove,
                                                              size: 16,
                                                              color: AppColors
                                                                  .primary,
                                                            ),
                                                          ),
                                                        ),
                                                        Text(
                                                          '$cardQty',
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 14,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              ),
                                                        ),
                                                        InkWell(
                                                          onTap: isSaving
                                                              ? null
                                                              : () {
                                                                  setDialogState(() {
                                                                    flatCards[cardIdx]['quantity'] =
                                                                        cardQty +
                                                                        1;
                                                                  });
                                                                },
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                6,
                                                              ),
                                                          child: Container(
                                                            padding:
                                                                const EdgeInsets.all(
                                                                  4,
                                                                ),
                                                            decoration: BoxDecoration(
                                                              color: isSaving
                                                                  ? Colors
                                                                        .grey
                                                                        .shade300
                                                                  : AppColors
                                                                        .primary
                                                                        .withValues(
                                                                          alpha:
                                                                              0.15,
                                                                        ),
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    6,
                                                                  ),
                                                            ),
                                                            child: const Icon(
                                                              Icons.add,
                                                              size: 16,
                                                              color: AppColors
                                                                  .primary,
                                                            ),
                                                          ),
                                                        ),
                                                        Text(
                                                          cardUnit,
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 12,
                                                                color:
                                                                    Colors.grey,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              ),
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
                        }),

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
                            icon: const Icon(
                              Icons.add,
                              size: 16,
                              color: AppColors.primary,
                            ),
                            label: const Text(
                              '新增餐點卡片',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppColors.primary),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
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
                          SystemChannels.textInput.invokeMethod(
                            'TextInput.hide',
                          );
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
                              final name =
                                  card['name']?.toString().trim() ?? '';
                              final period =
                                  card['meal_period']?.toString() ?? '早餐';
                              final qty = card['quantity']?.toString() ?? '1';
                              final unit = card['unit']?.toString() ?? '';
                              final cardDate =
                                  card['date'] as DateTime? ?? defaultDate;

                              if (name.isNotEmpty) {
                                final res = await DietService()
                                    .createDietRecord(
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
                            SystemChannels.textInput.invokeMethod(
                              'TextInput.hide',
                            );
                            FocusManager.instance.primaryFocus?.unfocus();
                            if (ctx.mounted) Navigator.of(ctx).pop();
                            if (context.mounted) {
                              FocusScope.of(context).unfocus();

                              // 延遲渲染 Companion 成功對話泡泡至對話紀錄中
                              if (delayedReply != null &&
                                  delayedReply.trim().isNotEmpty) {
                                setState(() {
                                  _messages.add({
                                    'isElf': true,
                                    'text': delayedReply,
                                    'intentCategory': 'meal_record',
                                  });
                                });
                                _appendTempStory('assistant', delayedReply);
                                _scrollToBottom();
                              }

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
                                  content: Text(
                                    '儲存失敗：${e.toString().replaceAll('Exception: ', '')}',
                                  ),
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
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          '確認儲存',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // === 10. 昨日飲食總結彈窗與動態畫筆 (Yesterday Summary Dialog & Painters) ===
  Widget _buildCalorieArcGaugeCard(int currentCalories) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "昨日熱量",
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
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
                    painter: CalorieGaugeArcPainter(
                      currentCalories: currentCalories.toDouble(),
                    ),
                  ),
                  Positioned(
                    bottom: 6,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          "約",
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          currentCalories.toString().replaceAllMapped(
                            RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                            (m) => '${m[1]},',
                          ),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                            height: 1.1,
                          ),
                        ),
                        const Text(
                          "kcal",
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
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
              _buildGaugeZoneLabel(
                "偏低",
                "< 1,700 kcal",
                const Color(0xFF7C83FD),
              ),
              _buildGaugeZoneLabel(
                "適量",
                "1,700 - 2,000 kcal",
                const Color(0xFF52C41A),
              ),
              _buildGaugeZoneLabel(
                "偏高",
                "> 2,000 kcal",
                const Color(0xFFFF7A45),
              ),
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
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          rangeStr,
          style: const TextStyle(
            fontSize: 9,
            color: Colors.black54,
            fontWeight: FontWeight.w500,
          ),
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
        border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "昨日三大營養素比例",
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
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
                          _buildSingleBarItem(
                            carbsPercent,
                            const Color(0xFF7C83FD),
                          ),
                          _buildSingleBarItem(
                            proteinPercent,
                            const Color(0xFFFF7A45),
                          ),
                          _buildSingleBarItem(
                            fatPercent,
                            const Color(0xFFFFB800),
                          ),
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
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              color: Colors.black45,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 1,
            color: Colors.black.withValues(alpha: 0.06),
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
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(6),
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.25),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
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
    canvas.drawArc(
      rect,
      startAngle + seg1Angle + seg2Angle,
      seg3Angle,
      false,
      paint,
    );

    double progressRatio;
    if (currentCalories < 1700) {
      progressRatio = (currentCalories / 1700.0).clamp(0.0, 1.0) * 0.38;
    } else if (currentCalories <= 2000) {
      progressRatio =
          0.38 + ((currentCalories - 1700.0) / 300.0).clamp(0.0, 1.0) * 0.34;
    } else {
      progressRatio =
          0.72 + ((currentCalories - 2000.0) / 1000.0).clamp(0.0, 1.0) * 0.28;
    }

    final double knobAngle = startAngle + progressRatio * totalAngle;
    final double knobX = center.dx + radius * math.cos(knobAngle);
    final double knobY = center.dy + radius * math.sin(knobAngle);

    canvas.drawCircle(
      Offset(knobX, knobY),
      11,
      Paint()
        ..color = Colors.black26
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
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

class _NutrientInfo extends StatelessWidget {
  final String label, value, unit;
  const _NutrientInfo({
    required this.label,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
        ),
        const SizedBox(height: 5),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        Text(
          unit,
          style: const TextStyle(fontSize: 10, color: AppColors.textPrimary),
        ),
      ],
    );
  }
}

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
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildValueItem('蛋白質', protein, total, 'g')),
            const SizedBox(width: 8),
            Expanded(child: _buildValueItem('脂肪', fat, total, 'g')),
            const SizedBox(width: 8),
            Expanded(child: _buildValueItem('碳水', carbs, total, 'g')),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '三大營養素合計 ${total.toStringAsFixed(0)} g',
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textPrimary.withValues(alpha: 0.65),
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
        color: AppColors.background.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
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
              color: AppColors.textPrimary.withValues(alpha: 0.65),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
