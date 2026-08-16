import 'package:flutter/material.dart'; // 匯入 material.dart 元件庫或套件
import 'package:flutter/services.dart';
import 'dart:ui'; // 匯入 dart:ui 元件庫或套件
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart'; // 匯入 shared_preferences.dart 元件庫或套件
import '../../controllers/dog_state_controller.dart';
import '../../services/auth_service.dart'; // 匯入 auth_service.dart 元件庫或套件
import '../../services/admin_service.dart'; // 匯入 admin_service.dart 元件庫或套件
import '../../services/body_status_api_service.dart';
import '../../services/diet_service.dart'; // 匯入 diet_service.dart 元件庫或套件
import '../../color/app_colors.dart'; // 匯入 app_colors.dart 元件庫或套件
import '../../widgets/dog_avatar.dart';
import '../records/elf_feeding_page.dart'; // 匯入 elf_feeding_page.dart 元件庫或套件

class HomeView extends StatefulWidget { // 定義 HomeView 類別，繼承自 StatefulWidget
  final bool initialOpenChat; // 宣告類別成員或方法內部的區域變數
  const HomeView({super.key, this.initialOpenChat = false}); // 建立編譯期常數，優化 Flutter 渲染效能

  @override // 標記此方法為覆寫父類別之方法
  State<HomeView> createState() => _HomeViewState(); // 執行相對應的邏輯計算或設定屬性參數
} // 程式碼區塊或元件結構結束

class _HomeViewState extends State<HomeView> with TickerProviderStateMixin { // 定義 _HomeViewState 類別，繼承自 State
  final TextEditingController _inputController = TextEditingController(); // 宣告類別成員或方法內部的區域變數
  final ScrollController _chatScrollController = ScrollController(); // 新增：對話滾動控制器
  final AuthService _authService = AuthService(); // 宣告類別成員或方法內部的區域變數
  final BodyStatusApiService _bodyStatusApi = BodyStatusApiService();
  final DogStateController _dogController = DogStateController.instance;
  
  late bool _isChatOpen; // 宣告類別成員或方法內部的區域變數
  late double _chatPanelX;  // 宣告類別成員或方法內部的區域變數
  String _userNickname = '使用者'; // 宣告類別成員或方法內部的區域變數
  String _petType = '狗兒'; // 宣告類別成員或方法內部的區域變數
  String _dietGoal = '養生'; // 宣告類別成員或方法內部的區域變數
  
  List<Map<String, dynamic>> _messages = []; // 執行相對應的邏輯計算或設定屬性參數

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
    _isChatOpen = widget.initialOpenChat; // 執行相對應的邏輯計算或設定屬性參數
    _chatPanelX = widget.initialOpenChat ? 0.0 : 1.0; // 執行相對應的邏輯計算或設定屬性參數
    _dogController.setState(DogAnimationState.idle);
    _loadHomeData(); // 執行相對應的邏輯計算或設定屬性參數
    
    // 檢查並顯示飲食總結報告彈窗，並於初始化/Hot Restart時強制收起鍵盤
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SystemChannels.textInput.invokeMethod('TextInput.hide');
      FocusManager.instance.primaryFocus?.unfocus();
      _checkAndShowDietSummaryDialog();
    });
  } // 程式碼區塊或元件結構結束
 
  @override // 標記此方法為覆寫父類別之方法
  void dispose() { // 銷毀狀態生命週期方法，釋放頁面資源與控制器
    _inputController.dispose(); // 執行相對應的邏輯計算或設定屬性參數
    _chatScrollController.dispose(); // 新增：釋放對話滾動控制器資源
    super.dispose(); // 執行相對應的邏輯計算或設定屬性參數
  } // 程式碼區塊或元件結構結束
 
  Future<void> _loadHomeData() async { // 定義非同步方法（Future），執行耗時操作
    // 1. 先從本地快取讀取 (前端輔助，速度快)
    final prefs = await SharedPreferences.getInstance(); // 宣告類別成員或方法內部的區域變數
    setState(() { // 更新狀態數據並通知 UI 重新渲染畫面
      _userNickname = prefs.getString('user_nickname') ?? '使用者'; // 執行相對應的邏輯計算或設定屬性參數
      _petType = '狗兒'; // 執行相對應的邏輯計算或設定屬性參數
      _dietGoal = prefs.getString('user_diet_goal') ?? '養生'; // 執行相對應的邏輯計算或設定屬性參數
      _messages = [ // 執行相對應的邏輯計算或設定屬性參數
        {
          'isElf': true, 
          'text': '嗨 $_userNickname！我是你的飲食夥伴精靈！無論想記錄餐點、詢問營養建議，或是隨意聊聊都歡迎跟我說喔！'
        }, // 執行相對應的邏輯計算或設定屬性參數
      ]; // 程式碼區塊或元件結構結束
    }); // 程式碼區塊或元件結構結束
 
    // 2. 向後端請求最新資料 (後端為主，保持同步)
    await _syncBodyStatus(prefs);
    if (!mounted) return;

    final result = await _authService.getUserProfile(); // 宣告類別成員或方法內部的區域變數
    if (result['success'] == true) { // 執行相對應的邏輯計算或設定屬性參數
      final userData = result['data']; // 宣告類別成員或方法內部的區域變數
      final String g = userData['dietGoal'] ?? userData['diet_goal'] ?? '養生'; // 宣告類別成員或方法內部的區域變數
      await prefs.setString('user_diet_goal', g); // 執行相對應的邏輯計算或設定屬性參數
      setState(() { // 更新狀態數據並通知 UI 重新渲染畫面
        _userNickname = userData['nickname'] ?? '使用者'; // 執行相對應的邏輯計算或設定屬性參數
        _petType = '狗兒'; // 執行相對應的邏輯計算或設定屬性參數
        _dietGoal = g; // 執行相對應的邏輯計算或設定屬性參數
        // 更新歡迎詞
        if (_messages.isNotEmpty && _messages[0]['isElf'] == true) { // 執行相對應的邏輯計算或設定屬性參數
          _messages[0]['text'] = '嗨 $_userNickname！我是你的飲食夥伴精靈！無論想記錄餐點、詢問營養建議，或是隨意聊聊都歡迎跟我說喔！'; // 執行相對應的邏輯計算或設定屬性參數
        } // 程式碼區塊或元件結構結束
      }); // 程式碼區塊或元件結構結束
    } // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  static bool _hasShownSummaryDialogThisRun = false;

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

  void _checkAndShowDietSummaryDialog() async {
    if (_hasShownSummaryDialogThisRun) return;
    _hasShownSummaryDialogThisRun = true;

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

      if (!mounted) return;
      debugPrint('=============================================');
      debugPrint('準備跳出昨日飲食總結彈窗！ Dishes: $yesterdayDishes');
      debugPrint('=============================================');
      
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

  void _showDietSummaryDialog({
    required DateTime date,
    required double calories,
    required double protein,
    required double fat,
    required double carbs,
    required List<String> dishes,
  }) {
    final String dateStr = '${date.month}/${date.day}';
    final String comment = dishes.isEmpty
        ? '昨天沒有記錄任何飲食。記得補記錄，我才能為您做評估喔。'
        : '昨天記錄了：${dishes.join('、')}。總熱量為 ${calories.toStringAsFixed(0)} kcal。請繼續保持健康飲食！';

    SystemChannels.textInput.invokeMethod('TextInput.hide');
    FocusManager.instance.primaryFocus?.unfocus();
    FocusScope.of(context).unfocus();

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
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
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
                  
                  const SizedBox(height: 20),
                  
                  // 飲食營養素匯總與圓餅圖
                  Container(
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16.0),
                    ),
                    child: Column(
                      children: [
                        _buildSummaryRow('總熱量攝取', '${calories.toStringAsFixed(0)} kcal', Icons.local_fire_department, AppColors.danger),
                        const Divider(height: 16, thickness: 0.5),
                        MacronutrientPieChart(
                          protein: protein,
                          fat: fat,
                          carbs: carbs,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // 精靈評語
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
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
                              fontSize: 13.0,
                              color: AppColors.textPrimary.withOpacity(0.85),
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // 按鈕區
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.background,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      '太棒了，我知道了！',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

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
          'text': '正在為您載入個人與週飲食紀錄，進行智能評估中...',
        });
      });
      _scrollToBottom(); // 新增：載入中提示滑到底部
      
      DietService().sendCompanionUserPrompt(text).then((res) {
        _showDogResponseThenIdle();
        setState(() {
          if (_messages.isNotEmpty &&
              (_messages.last['text'] == '正在思考中...' ||
               _messages.last['text'] == '正在為您載入個人與週飲食紀錄，進行智能評估中...')) {
            _messages.removeLast();
          }

          final reply = res['companion_reply'] ??
              (res['data'] is Map ? res['data']['companion_reply'] : null);

          if (res['success'] == true && reply != null && reply.toString().isNotEmpty) {
            _messages.add({
              'isElf': true,
              'text': reply.toString(),
            });

            // 判斷意圖若為 meal_record 且含草稿，自動觸發飲食紀錄確認彈窗
            final intent = res['intent_category'] ?? '';
            final mealRecords = res['meal_records'] as List<dynamic>? ?? [];
            if (intent == 'meal_record' && mealRecords.isNotEmpty) {
              _showMealRecordDraftDialog(context, mealRecords, userPrompt: text);
            }
          } else {
            _messages.add({
              'isElf': true,
              'text': res['message'] ?? '讀取精靈回覆失敗，請稍後再試。',
            });
          }
        });
        _scrollToBottom(); // 新增：智能評估分析完成後滑到底部
      }).catchError((e) {
        _showDogResponseThenIdle();
        setState(() {
          if (_messages.isNotEmpty &&
              (_messages.last['text'] == '正在思考中...' ||
               _messages.last['text'] == '正在為您載入個人與週飲食紀錄，進行智能評估中...')) {
            _messages.removeLast();
          }
          _messages.add({
            'isElf': true,
            'text': '連線發生錯誤: $e',
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
                    onTap: () => _toggleChat(true), // 執行相對應的邏輯計算或設定屬性參數
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
                                    child: DogAvatar(
                                      controller: _dogController,
                                      scale: isKeyboardVisible ? 1.0 : 1.5,
                                      instanceId: 'home-main-dog',
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

  Widget _buildChatMessage(bool isElf, String text, {List<dynamic>? options}) {
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
                if (isElf && options != null) ...[
                  const SizedBox(height: 15), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
                  const Divider(height: 1), // 建立編譯期常數，優化 Flutter 渲染效能
                  const SizedBox(height: 10), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
                  ...options.map((opt) => Padding( // 建立間距容器（Padding），用於設定內部邊距
                    padding: const EdgeInsets.only(bottom: 8.0), // 設定外邊距或內邊距的數值大小（EdgeInsets）
                    child: SizedBox( // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
                      width: double.infinity, // 執行相對應的邏輯計算或設定屬性參數
                      child: ElevatedButton( // 建立常規按鈕（ElevatedButton），點擊時觸作相對應事件
                        onPressed: () => _showNutrientDetail(opt['name'], opt['nutrients']), // 執行相對應的邏輯計算或設定屬性參數
                        style: ElevatedButton.styleFrom( // 執行相對應的邏輯計算或設定屬性參數
                          backgroundColor: AppColors.surface, // 設定顏色數值（Color）
                          foregroundColor: AppColors.textPrimary, // 設定顏色數值（Color）
                          elevation: 0, // 執行相對應的邏輯計算或設定屬性參數
                          side: const BorderSide(color: AppColors.border), // 設定顏色數值（Color）
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), // 設定容器的圓角弧度半徑大小
                        ), // 執行相對應的邏輯計算或設定屬性參數
                        child: Text(opt['name'], style: const TextStyle(fontWeight: FontWeight.bold)), // 建立文字顯示元件（Text）
                      ), // 執行相對應的邏輯計算或設定屬性參數
                    ), // 執行相對應的邏輯計算或設定屬性參數
                  )).toList(), // 執行相對應的邏輯計算或設定屬性參數
                ], // 執行相對應的邏輯計算或設定屬性參數
              ], // 執行相對應的邏輯計算或設定屬性參數
            ), // 執行相對應的邏輯計算或設定屬性參數
          ), // 執行相對應的邏輯計算或設定屬性參數
        ], // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
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
                    builder: (context) => ElfFeedingPage( // 執行相對應的邏輯計算或設定屬性參數
                      imagePath: "",  // 執行相對應的邏輯計算或設定屬性參數
                      items: [{'name': name, 'portion': '1份', 'calories': '${nutrients['calories']} kcal'}], // 執行相對應的邏輯計算或設定屬性參數
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
                MaterialPageRoute( // 執行相對應的邏輯計算或設定屬性參數
                  builder: (context) => const ElfFeedingPage( // 建立編譯期常數，優化 Flutter 渲染效能
                    imagePath: "", // 這裡可以用預設圖片
                    items: [{'name': '薯條', 'portion': '大份', 'calories': '380 kcal'}], // 執行相對應的邏輯計算或設定屬性參數
                  ), // 執行相對應的邏輯計算或設定屬性參數
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

  /// 彈出「飲食紀錄草稿」可編輯確認視窗，允許使用者自行修正餐期、餐點名稱與數量
  void _showMealRecordDraftDialog(BuildContext context, List<dynamic> mealRecords, {String userPrompt = ''}) {
    // 1. 深拷貝為本地可變狀態，確保使用者修改不影響全域原數據
    final List<Map<String, dynamic>> editableRecords = mealRecords.map((rec) {
      final items = (rec['meal_items'] as List<dynamic>? ?? []).map((item) {
        return {
          'name': item['name']?.toString() ?? '',
          'quantity': int.tryParse(item['quantity']?.toString() ?? '1') ?? 1,
          'unit': item['unit']?.toString() ?? '',
        };
      }).toList();
      return {
        'meal_period': rec['meal_period']?.toString() ?? '早餐',
        'meal_items': items,
      };
    }).toList();

    const List<String> mealPeriodOptions = ['早餐', '午餐', '晚餐', '其他'];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        bool isSaving = false;
        DateTime selectedDate = _parseDateFromPrompt(userPrompt);
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
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
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 精簡頂部提示說明
                    const Text(
                      '請核對或修改以下草稿內容：',
                      style: TextStyle(fontSize: 13, color: Colors.black87, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 12),

                    // 1. 紀錄日期選擇器 (可點擊選擇)
                    InkWell(
                      onTap: isSaving
                          ? null
                          : () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: selectedDate,
                                firstDate: DateTime(2023),
                                lastDate: DateTime.now().add(const Duration(days: 365)),
                              );
                              if (picked != null) {
                                setDialogState(() {
                                  selectedDate = picked;
                                });
                              }
                            },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today, size: 16, color: AppColors.primary),
                            const SizedBox(width: 8),
                            Text(
                              '紀錄日期：${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary),
                            ),
                            const Spacer(),
                            const Icon(Icons.arrow_drop_down, color: Colors.grey),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 2. 草稿紀錄卡片 (餐點名稱為主體)
                    ...editableRecords.asMap().entries.map((recEntry) {
                      final recIndex = recEntry.key;
                      final record = recEntry.value;
                      final currentPeriod = record['meal_period'].toString();
                      final items = record['meal_items'] as List<Map<String, dynamic>>;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ...items.asMap().entries.map((itemEntry) {
                              final itemIndex = itemEntry.key;
                              final item = itemEntry.value;
                              final currentQty = item['quantity'] as int;
                              final unitStr = item['unit'].toString();

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // (A) 餐點名稱 (主體 - 醒目淺色背景輸入框)
                                  TextFormField(
                                    initialValue: item['name'].toString(),
                                    enabled: !isSaving,
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                    decoration: InputDecoration(
                                      labelText: '餐點名稱',
                                      filled: true,
                                      fillColor: AppColors.background,
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
                                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
                                    ),
                                    onChanged: (val) {
                                      editableRecords[recIndex]['meal_items'][itemIndex]['name'] = val;
                                    },
                                  ),
                                  const SizedBox(height: 10),

                                  // (B) 餐別與數量列
                                  Row(
                                    children: [
                                      // 餐別選擇
                                      Expanded(
                                        flex: 5,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10),
                                          decoration: BoxDecoration(
                                            color: AppColors.background,
                                            borderRadius: BorderRadius.circular(8),
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
                                                          editableRecords[recIndex]['meal_period'] = newPeriod;
                                                        });
                                                      }
                                                    },
                                              items: mealPeriodOptions.map((period) {
                                                return DropdownMenuItem<String>(
                                                  value: period,
                                                  child: Text('餐別: $period'),
                                                );
                                              }).toList(),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),

                                      // 數量加減器 [- 1 +] 份
                                      Row(
                                        children: [
                                          InkWell(
                                            onTap: (isSaving || currentQty <= 1)
                                                ? null
                                                : () {
                                                    setDialogState(() {
                                                      editableRecords[recIndex]['meal_items'][itemIndex]['quantity'] = currentQty - 1;
                                                    });
                                                  },
                                            borderRadius: BorderRadius.circular(6),
                                            child: Container(
                                              padding: const EdgeInsets.all(4),
                                              decoration: BoxDecoration(
                                                color: (currentQty <= 1 || isSaving) ? Colors.grey.shade300 : AppColors.primary.withOpacity(0.15),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: const Icon(Icons.remove, size: 16, color: AppColors.primary),
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 6),
                                            child: Text(
                                              '$currentQty',
                                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                          InkWell(
                                            onTap: isSaving
                                                ? null
                                                : () {
                                                    setDialogState(() {
                                                      editableRecords[recIndex]['meal_items'][itemIndex]['quantity'] = currentQty + 1;
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
                                          const SizedBox(width: 4),
                                          Text(
                                            unitStr,
                                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              );
                            }).toList(),
                          ],
                        ),
                      );
                    }).toList(),
                  ],
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
                            for (var record in editableRecords) {
                              final mealPeriod = record['meal_period']?.toString() ?? '早餐';
                              final items = record['meal_items'] as List<Map<String, dynamic>>;
                              for (var item in items) {
                                final name = item['name']?.toString().trim() ?? '';
                                final qty = item['quantity']?.toString() ?? '1';
                                final unit = item['unit']?.toString() ?? '';
                                if (name.isNotEmpty) {
                                  await DietService().createDietRecord(
                                    dishName: name,
                                    mealType: mealPeriod,
                                    amount: '$qty $unit'.trim(),
                                    description: '陪伴精靈解析並經使用者核對修正',
                                    mealDate: selectedDate,
                                  );
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


class MacronutrientPieChart extends StatelessWidget {
  final double protein;
  final double fat;
  final double carbs;

  const MacronutrientPieChart({
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

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 70,
          height: 70,
          child: CustomPaint(
            painter: PieChartPainter(
              protein: protein,
              fat: fat,
              carbs: carbs,
            ),
          ),
        ),
        const SizedBox(width: 24),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildLegendItem('脂肪', fat, total, const Color(0xFFEF5350)),
            const SizedBox(height: 6),
            _buildLegendItem('碳水化合物', carbs, total, const Color(0xFF29B6F6)),
            const SizedBox(height: 6),
            _buildLegendItem('蛋白質', protein, total, const Color(0xFFFFA726)),
          ],
        ),
      ],
    );
  }

  Widget _buildLegendItem(String label, double val, double total, Color color) {
    final pct = (val / total * 100).toStringAsFixed(0);
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$label: ${val.toStringAsFixed(0)}g ($pct%)',
          style: const TextStyle(fontSize: 11, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class PieChartPainter extends CustomPainter {
  final double protein;
  final double fat;
  final double carbs;

  PieChartPainter({
    required this.protein,
    required this.fat,
    required this.carbs,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final total = protein + fat + carbs;
    if (total == 0) return;

    final paint = Paint()..style = PaintingStyle.fill;
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    
    double startAngle = -3.1415926 / 2; // Start from top
    
    // Draw Fat
    final fatSweep = (fat / total) * 2 * 3.1415926;
    paint.color = const Color(0xFFEF5350);
    canvas.drawArc(rect, startAngle, fatSweep, true, paint);
    startAngle += fatSweep;

    // Draw Carbs
    final carbsSweep = (carbs / total) * 2 * 3.1415926;
    paint.color = const Color(0xFF29B6F6);
    canvas.drawArc(rect, startAngle, carbsSweep, true, paint);
    startAngle += carbsSweep;

    // Draw Protein
    final proteinSweep = (protein / total) * 2 * 3.1415926;
    paint.color = const Color(0xFFFFA726);
    canvas.drawArc(rect, startAngle, proteinSweep, true, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
