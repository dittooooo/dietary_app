import 'package:flutter/material.dart'; // 匯入 material.dart 元件庫或套件
import 'dart:ui'; // 匯入 dart:ui 元件庫或套件
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
  @override // 標記此方法為覆寫父類別之方法
  void initState() { // 初始化狀態生命週期方法，頁面建立時執行一次
    super.initState(); // 執行相對應的邏輯計算或設定屬性參數
    _isChatOpen = widget.initialOpenChat; // 執行相對應的邏輯計算或設定屬性參數
    _chatPanelX = widget.initialOpenChat ? 0.0 : 1.0; // 執行相對應的邏輯計算或設定屬性參數
    _dogController.setState(DogAnimationState.idle);
    _loadHomeData(); // 執行相對應的邏輯計算或設定屬性參數
    
    // 檢查並顯示 7/26 飲食總結報告彈窗
    WidgetsBinding.instance.addPostFrameCallback((_) {
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
        {'isElf': true, 'text': '嗨 $_userNickname！\n我是您的$_petType助理。\n可以在下方輸入框輸入\n你需要我提供的飲食建議喔！'}, // 執行相對應的邏輯計算或設定屬性參數
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
          _messages[0]['text'] = '嗨 $_userNickname！\n我是您的$_petType助理。\n可以在下方輸入框輸入\n你需要我提供的飲食建議喔！'; // 執行相對應的邏輯計算或設定屬性參數
        } // 程式碼區塊或元件結構結束
      }); // 程式碼區塊或元件結構結束
    } // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  static bool _hasShownSummaryDialogThisRun = false;

  void _checkAndShowDietSummaryDialog() {
    if (_hasShownSummaryDialogThisRun) return;
    final now = DateTime.now();
    // 方便測試：當月份為 7 月，且日期在 26 到 29 日之間時，自動跳出彈窗報告
    if (now.month == 7 && (now.day >= 26 && now.day <= 29)) {
      _hasShownSummaryDialogThisRun = true;
      _showDietSummaryDialog();
    }
  }

  void _showDietSummaryDialog() {
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
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 28.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 標題與日期
                  const Text(
                    '📅 7/26 飲食總結報告',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '（今日模擬日期：7/29）',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textPrimary.withOpacity(0.5),
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // 小精靈動畫播放預留區
                  Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.15),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // 動態呼吸背景環
                        Positioned.fill(
                          child: AnimatedBuilder(
                            animation: _hoverScaleAnimation,
                            builder: (context, child) {
                              return Transform.scale(
                                scale: _hoverScaleAnimation.value,
                                child: Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: AppColors.primary.withOpacity(0.2),
                                      width: 4,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        // 小精靈動畫播放佔位/GIF/圖片
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.auto_awesome,
                              color: AppColors.secondary,
                              size: 24,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '【精靈動畫播放區】\n($_petType)',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: AppColors.secondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // 飲食營養素匯總
                  Container(
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16.0),
                    ),
                    child: Column(
                      children: [
                        _buildSummaryRow('總熱量攝取', '1,450 kcal', Icons.local_fire_department, AppColors.danger),
                        const Divider(height: 16, thickness: 0.5),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildNutrientItem('蛋白質', '68g', AppColors.primary),
                            _buildNutrientItem('脂肪', '45g', AppColors.secondary),
                            _buildNutrientItem('碳水化合物', '192g', Colors.orange),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  
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
                        const Text('💬 ', style: TextStyle(fontSize: 16)),
                        Expanded(
                          child: Text(
                            '汪！7/26 的整體熱量控制得很好喔！蛋白質的補充也符合標準，唯獨晚餐的澱粉稍微多了一點點，明天晚餐可以多搭配蔬菜喔！',
                            style: TextStyle(
                              fontSize: 13.5,
                              color: AppColors.textPrimary.withOpacity(0.85),
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  
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
        if (text.contains("推薦")) {
          _messages.add({
            'isElf': true,
            'text': '正在搜尋附近的店家與健康推薦項目...',
            'type': 'restaurant'
          });
          _scrollToBottom(); // 新增：載入中提示滑到底部
          
          AdminService().listRestaurants().then((restaurants) {
            AdminService().listMenuItems().then((menus) {
              _showDogResponseThenIdle();
              setState(() {
                if (_messages.isNotEmpty && _messages.last['text'] == '正在搜尋附近的店家與健康推薦項目...') {
                  _messages.removeLast();
                }
                
                if (restaurants.isEmpty) {
                  _messages.add({
                    'isElf': true,
                    'text': '已為您搜尋附近的推薦項目：\n目前系統暫無推薦餐廳，您可以使用管理員面板的「餐廳管理」新增更多選擇！',
                    'type': 'restaurant'
                  });
                } else {
                  final String restText = restaurants.asMap().entries.map((entry) {
                    final idx = entry.key + 1;
                    final rest = entry.value;
                    final restName = rest['name'] ?? '店家';
                    final restAddr = rest['address'] ?? '';
                    final restStars = '★' * (rest['stars'] ?? 5);
                    
                    final matchedMenus = menus.where((m) => m['restaurantName'] == restName).toList();
                    final menuText = matchedMenus.isNotEmpty
                        ? '\n   精選推薦：' + matchedMenus.map((m) => '${m['dishName']} (${m['recommendLevel'] ?? '高'}推薦, ${m['nutrition'] ?? ''})').join(', ')
                        : '';
                        
                    return '$idx. $restName $restStars\n   地址: $restAddr$menuText';
                  }).join('\n\n');
                  
                  _messages.add({
                    'isElf': true,
                    'text': '已為您搜尋附近的店家與菜單推薦項目：\n\n$restText',
                    'type': 'restaurant'
                  });
                }
              });
              _scrollToBottom(); // 新增：餐廳推薦完成滑到底部
            }).catchError((e) {
              _showDogResponseThenIdle();
              setState(() {
                if (_messages.isNotEmpty && _messages.last['text'] == '正在搜尋附近的店家與健康推薦項目...') {
                  _messages.removeLast();
                }
                _messages.add({'isElf': true, 'text': '推薦菜單載入錯誤: $e'});
              });
              _scrollToBottom(); // 新增：選單載入錯誤滑到底部
            });
          }).catchError((e) {
            _showDogResponseThenIdle();
            setState(() {
              if (_messages.isNotEmpty && _messages.last['text'] == '正在搜尋附近的店家與健康推薦項目...') {
                _messages.removeLast();
              }
              _messages.add({'isElf': true, 'text': '推薦餐廳載入錯誤: $e'});
            });
            _scrollToBottom();
          });
        } else { // 程式碼區塊或元件結構結束
          _messages.add({
            'isElf': true,
            'text': '正在為您載入個人與週飲食紀錄，進行智能評估中...',
          });
          _scrollToBottom(); // 新增：載入中提示滑到底部
          
          DietService().askWeeklyAnalysis(text).then((res) {
            _showDogResponseThenIdle();
            setState(() {
              if (_messages.isNotEmpty && _messages.last['text'] == '正在為您載入個人與週飲食紀錄，進行智能評估中...') {
                _messages.removeLast();
              }
              
              if (res['success'] == true) {
                final payload = res['data'];
                final profile = payload['user_profile'] ?? {};
                final health = payload['health_condition'] ?? {};
                final List<dynamic> records = payload['weekly_diet_records'] ?? [];
                
                final String gender = profile['gender'] ?? '未設定';
                final double height = (profile['height_cm'] as num?)?.toDouble() ?? 0.0;
                final double weight = (profile['weight_kg'] as num?)?.toDouble() ?? 0.0;
                final int age = (profile['age'] as num?)?.toInt() ?? 0;
                final String goal = profile['goal'] ?? '健康維持';
                
                final bool hasChronic = health['has_chronic_disease'] ?? false;
                final List<dynamic> diseases = health['chronic_diseases'] ?? [];
                
                double bmi = 0.0;
                if (height > 0) {
                  bmi = weight / ((height / 100.0) * (height / 100.0));
                }
                
                String bmiText = bmi > 0 ? bmi.toStringAsFixed(1) : '未知';
                
                String recordDetail = '';
                if (records.isEmpty) {
                  recordDetail = '• 過去 7 天內尚無飲食紀錄。建議您在「飲食日記」新增近日餐點，讓我能提供更精準的分析喔！';
                } else {
                  recordDetail = records.map((r) {
                    final date = r['date'] ?? '';
                    final meal = r['meal'] ?? '';
                    final dish = r['dish_name'] ?? '';
                    final note = r['description'] ?? r['note'] ?? '';
                    final noteText = note.isNotEmpty ? ' ($note)' : '';
                    return '• $date $meal: $dish$noteText';
                  }).join('\n');
                }
                
                String chronicText = hasChronic
                    ? '有 (${diseases.join(', ')})'
                    : '無';
                    
                String advice = '';
                if (goal.contains('減脂')) {
                  advice = '精靈建議：您的目標是減脂，目前 BMI 為 $bmiText。近一週飲食中請注意控制油鹽，適量攝取優質蛋白質，以維持肌肉量。';
                } else if (goal.contains('增肌')) {
                  advice = '精靈建議：您的目標是增肌，目前 BMI 為 $bmiText。請務必補充足量碳水化合物與高蛋白質食物，配合阻力訓練效果更佳！';
                } else {
                  advice = '精靈建議：您的目標是養生，目前 BMI 為 $bmiText。請保持均衡飲食，多攝取膳食纖維，維持規律作息。';
                }
                
                String finalMessage = '【飲食智能小精靈 - 週飲食分析】\n\n'
                    '個人狀態簡介：\n'
                    ' • 身高/體重：${height.toStringAsFixed(0)} cm / ${weight.toStringAsFixed(0)} kg\n'
                    ' • 年齡/性別：$age 歲 / $gender\n'
                    ' • BMI：$bmiText\n'
                    ' • 飲食目標：$goal\n'
                    ' • 慢性病歷史：$chronicText\n\n'
                    '過去 7 天飲食明細：\n'
                    '$recordDetail\n\n'
                    '$advice\n\n'
                    '如果您有任何具體問題（如想吃特定食物或外送推薦），隨時可以問我！';
                
                _messages.add({
                  'isElf': true,
                  'text': finalMessage,
                });
              } else {
                _messages.add({
                  'isElf': true,
                  'text': '分析讀取失敗：${res['message']}',
                });
              }
            });
            _scrollToBottom(); // 新增：智能評估分析完成後滑到底部
          }).catchError((e) {
            _showDogResponseThenIdle();
            setState(() {
              if (_messages.isNotEmpty && _messages.last['text'] == '正在為您載入個人與週飲食紀錄，進行智能評估中...') {
                _messages.removeLast();
              }
              _messages.add({
                'isElf': true,
                'text': '智能分析發生異常: $e',
              });
            });
            _scrollToBottom(); // 新增：發生異常後滑到底部
          });
        } // 程式碼區塊或元件結構結束
      }); // 程式碼區塊或元件結構結束
    }); // 程式碼區塊或元件結構結束
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
              child: Column( // 建立垂直排列元件（Column），縱向排列多個子元件
                mainAxisSize: MainAxisSize.min, // 執行相對應的邏輯計算或設定屬性參數
                children: [ // 執行相對應的邏輯計算或設定屬性參數
                  GestureDetector( // 建立手勢偵測器（GestureDetector），用於監聽點擊、拖動等觸控事件
                    onTap: () => _toggleChat(true), // 執行相對應的邏輯計算或設定屬性參數
                    child: Hero( // 建立跨頁面過渡動畫元件（Hero），點擊時呈現放大或縮小移動特效
                      tag: 'elf', // 執行相對應的邏輯計算或設定屬性參數
                              child: Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
                                width: 280, height: 280, // 執行相對應的邏輯計算或設定屬性參數
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
                                  borderRadius: BorderRadius.circular(140), // 設定容器的圓角弧度半徑大小
                                  child: Padding( // 建立間距容器（Padding），用於設定內部邊距
                                    padding: const EdgeInsets.all(25.0), // 設定外邊距或內邊距的數值大小（EdgeInsets）
                                    child: DogAvatar(
                                      controller: _dogController,
                                      scale: 1.5,
                                      instanceId: 'home-main-dog',
                                    ),
                                  ), // 執行相對應的邏輯計算或設定屬性參數
                                ), // 執行相對應的邏輯計算或設定屬性參數
                              ), // 執行相對應的邏輯計算或設定屬性參數
                    ), // 執行相對應的邏輯計算或設定屬性參數
                  ), // 執行相對應的邏輯計算或設定屬性參數
                  const SizedBox(height: 20), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
                  // 精靈說話框 (初始狀態)
                  if (!_isChatOpen) ...[ // 執行相對應的邏輯計算或設定屬性參數
                    Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15), // 設定外邊距或內邊距的數值大小（EdgeInsets）
                      margin: const EdgeInsets.symmetric(horizontal: 40), // 設定外邊距或內邊距的數值大小（EdgeInsets）
                      decoration: BoxDecoration( // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
                        color: AppColors.background, // 設定顏色數值（Color）
                        borderRadius: BorderRadius.circular(20), // 設定容器的圓角弧度半徑大小
                        boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.1), blurRadius: 1.95)], // 設定容器的陰影效果，包括顏色、模糊半徑與偏移量
                      ), // 執行相對應的邏輯計算或設定屬性參數
                      child: Text( // 建立文字顯示元件（Text）
                        _messages.isNotEmpty ? _messages[0]['text'] : "載入中...", // 執行相對應的邏輯計算或設定屬性參數
                        textAlign: TextAlign.center, // 執行相對應的邏輯計算或設定屬性參數
                        style: const TextStyle( // 設定文字字體大小、顏色與粗細等字型樣式（TextStyle）
                          fontSize: 16,  // 執行相對應的邏輯計算或設定屬性參數
                          fontWeight: FontWeight.w500, // 執行相對應的邏輯計算或設定屬性參數
                          color: AppColors.textPrimary // 設定顏色數值（Color）
                        ), // 執行相對應的邏輯計算或設定屬性參數
                      ), // 執行相對應的邏輯計算或設定屬性參數
                    ), // 執行相對應的邏輯計算或設定屬性參數
                    const SizedBox(height: 15), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
                  ], // 執行相對應的邏輯計算或設定屬性參數
                ], // 執行相對應的邏輯計算或設定屬性參數
              ), // 執行相對應的邏輯計算或設定屬性參數
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
      color: AppColors.background.withOpacity(0.98), // 設定顏色數值（Color）
      child: SafeArea( // 執行相對應的邏輯計算或設定屬性參數
        child: Column( // 建立垂直排列元件（Column），縱向排列多個子元件
          children: [ // 執行相對應的邏輯計算或設定屬性參數
            // 對話面板頭部
            Padding( // 建立間距容器（Padding），用於設定內部邊距
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
            Expanded( // 建立填充元件（Expanded），自動佔滿 Row 或 Column 的剩餘空間
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
                  return _buildChatMessage(msg['isElf'], msg['text'], options: msg['options']); // 回傳建構完成的元件或方法計算結果
                }, // 程式碼區塊或元件結構結束
              ), // 執行相對應的邏輯計算或設定屬性參數
            ), // 執行相對應的邏輯計算或設定屬性參數
            // 面板內也提供輸入框 (包含小精靈站位符)
            Stack( // 建立層疊佈局元件（Stack），可將多個子元件重疊顯示
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
                    color: AppColors.background, // 設定顏色數值（Color）
                    border: Border(top: BorderSide(color: AppColors.border)), // 設定顏色數值（Color）
                  ), // 執行相對應的邏輯計算或設定屬性參數
                  child: Row( // 建立水平排列元件（Row），橫向排列多個子元件
                    children: [ // 執行相對應的邏輯計算或設定屬性參數
                      Expanded( // 建立填充元件（Expanded），自動佔滿 Row 或 Column 的剩餘空間
                        child: Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
                          padding: const EdgeInsets.symmetric(horizontal: 15), // 設定外邊距或內邊距的數值大小（EdgeInsets）
                          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20)), // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
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
          ], // 執行相對應的邏輯計算或設定屬性參數
        ), // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Widget _buildChatMessage(bool isElf, String text, {List<dynamic>? options}) { // 定義用於重複使用的 UI 封裝建構方法
    return Align( // 回傳建構完成的元件或方法計算結果
      alignment: isElf ? Alignment.centerLeft : Alignment.centerRight, // 執行相對應的邏輯計算或設定屬性參數
      child: Column( // 建立垂直排列元件（Column），縱向排列多個子元件
        crossAxisAlignment: isElf ? CrossAxisAlignment.start : CrossAxisAlignment.end, // 執行相對應的邏輯計算或設定屬性參數
        children: [ // 執行相對應的邏輯計算或設定屬性參數
          Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
            margin: const EdgeInsets.symmetric(vertical: 8), // 設定外邊距或內邊距的數值大小（EdgeInsets）
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), // 設定外邊距或內邊距的數值大小（EdgeInsets）
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75), // 執行相對應的邏輯計算或設定屬性參數
            decoration: BoxDecoration( // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
              color: isElf ? AppColors.background : AppColors.secondary, // 設定顏色數值（Color）
              borderRadius: BorderRadius.circular(20), // 設定容器的圓角弧度半徑大小
              boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.05), blurRadius: 0.975)], // 設定容器的陰影效果，包括顏色、模糊半徑與偏移量
              border: isElf ? Border.all(color: AppColors.border) : null, // 設定容器的四周邊框線條樣式
            ), // 執行相對應的邏輯計算或設定屬性參數
            child: Column( // 建立垂直排列元件（Column），縱向排列多個子元件
              crossAxisAlignment: CrossAxisAlignment.start, // 執行相對應的邏輯計算或設定屬性參數
              children: [ // 執行相對應的邏輯計算或設定屬性參數
                Text( // 建立文字顯示元件（Text）
                  text, // 執行相對應的邏輯計算或設定屬性參數
                  style: TextStyle(color: isElf ? AppColors.textPrimary : AppColors.background, fontSize: 15), // 設定文字字體大小、顏色與粗細等字型樣式（TextStyle）
                ), // 執行相對應的邏輯計算或設定屬性參數
                if (isElf && options != null) ...[ // 執行相對應的邏輯計算或設定屬性參數
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
} // 程式碼區塊或元件結構結束

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
