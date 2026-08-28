import 'package:flutter/material.dart'; // 匯入 material.dart 元件庫或套件
import 'dart:ui'; // 匯入 dart:ui 元件庫或套件
import 'package:shared_preferences/shared_preferences.dart'; // 匯入 shared_preferences.dart 元件庫或套件
import 'package:image_picker/image_picker.dart'; // 匯入相簿套件
// import 'dart:typed_data'; // 處理圖片
import '../home/home_page.dart'; // 匯入 home_page.dart 元件庫或套件
import '../auth/profile_page.dart'; // 匯入 profile_page.dart 元件庫或套件
import '../../color/app_colors.dart'; // 匯入 app_colors.dart 元件庫或套件
import '../../services/diet_service.dart'; // 匯入 diet_service.dart
import '../../utils/friendly_error_message.dart';
import '../../config/api_config.dart'; // 匯入 api_config.dart
import 'dart:convert'; // 處理 JSON 轉換
import 'manual_record_page.dart'; // 匯入手動紀錄頁面
import '../../services/auth_service.dart';

class DiaryPage extends StatefulWidget { // 定義 DiaryPage 類別，繼承自 StatefulWidget
  final DateTime date; // 宣告類別成員或方法內部的區域變數
  final ValueChanged<DateTime>? onDateChanged;
  const DiaryPage({super.key, required this.date, this.onDateChanged}); // 建立編譯期常數，優化 Flutter 渲染效能

  @override // 標記此方法為覆寫父類別之方法
  State<DiaryPage> createState() => _DiaryPageState(); // 執行相對應的邏輯計算或設定屬性參數
} // 程式碼區塊或元件結構結束

class _DiaryPageState extends State<DiaryPage> { // 定義 _DiaryPageState 類別，繼承自 State
  late DateTime _selectedDate;
  final Set<String> _expandedMeals = {}; // 宣告類別成員或方法內部的區域變數
  String? _swipedMeal; // 執行相對應的邏輯計算或設定屬性參數
  double _dragExtent = 0.0; // 宣告類別成員或方法內部的區域變數
  // String _petType = '米粒(Mili)'; // 未使用，先註解
  // String _dietGoal = '養生'; // 未使用，先註解
  String? _jwtToken; // JWT Token 儲存變數

  List<dynamic> _allRecords = []; // 從後端獲取的所有紀錄
  bool _isLoading = false;
  String? _avatarUrl;

  @override // 標記此方法為覆寫父類別之方法
  void initState() { // 初始化狀態生命週期方法，頁面建立時執行一次
    super.initState(); // 執行相對應的邏輯計算或設定屬性參數
    _selectedDate = widget.date;
    _loadPetData(); // 執行相對應的邏輯計算或設定屬性參數
    _fetchRecords(); // 獲取後端飲食紀錄
  } // 程式碼區塊或元件結構結束

  Future<void> _loadPetData() async { // 定義非同步方法（Future），執行耗時操作
    final prefs = await SharedPreferences.getInstance(); // 宣告類別成員或方法內部的區域變數
    if (mounted) { // 執行相對應的邏輯計算或設定屬性參數
      setState(() { // 更新狀態數據並通知 UI 重新渲染畫面
        // _petType = '米粒(Mili)'; // 未使用，先註解
        // _dietGoal = prefs.getString('user_diet_goal') ?? '養生'; // 未使用，先註解
        _jwtToken = prefs.getString('jwt_token'); // 讀取 JWT Token
        _avatarUrl = prefs.getString('user_avatar_url');
      }); // 程式碼區塊或結構結束
    } // 程式碼區塊或結構結束
    final result = await AuthService().getUserProfile();
    if (result['success'] == true) {
      final userData = result['data'];
      final avatarPath = userData?['avatarUrl'] ?? userData?['user']?['avatarUrl'];
      if (avatarPath != null && avatarPath.isNotEmpty) {
        final serverBase = ApiConfig.baseUrl.replaceAll('/api', '');
        final fullUrl = avatarPath.startsWith('http') ? avatarPath : '$serverBase$avatarPath';
        if (mounted) {
          setState(() {
            _avatarUrl = fullUrl;
          });
        }
        await prefs.setString('user_avatar_url', fullUrl);
      }
    }
  } // 程式碼區塊或結構結束

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.primary,
            onPrimary: AppColors.background,
            onSurface: AppColors.textPrimary,
          ),
        ),
        child: child!,
      ),
    );

    if (picked == null || !mounted) return;
    final selectedDate = DateTime(picked.year, picked.month, picked.day);
    setState(() {
      _selectedDate = selectedDate;
      _expandedMeals.clear();
      _swipedMeal = null;
    });
    widget.onDateChanged?.call(selectedDate);
  }

  Future<void> _fetchRecords() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      final records = await DietService().getMyDietRecords();
      debugPrint("DEBUG: Fetched ${records.length} records: $records");
      for (var r in records) {
        debugPrint("DEBUG: record id=${r['id']}, dishName=${r['dishName']}, mealDate=${r['mealDate']}, createdAt=${r['createdAt']} -> parsed=${_getRecordDate(r)}");
      }
      setState(() {
        _jwtToken = token; // 確保 JWT Token 在 UI 載入前就緒，防止圖片 headers 變更觸發二次下載
        _allRecords = records;
      });
      // 預加載所有餐點圖片，點擊展開時瞬間顯示
      for (var record in records) {
        if (record['photoUrl'] != null && (record['photoUrl'] as String).isNotEmpty) {
          final imageUrl = "${ApiConfig.baseUrl.replaceAll('/api', '')}${record['photoUrl']}";
          final provider = NetworkImage(
            imageUrl,
            headers: token != null ? {'Authorization': 'Bearer $token'} : null,
          );
          precacheImage(provider, context).catchError((e) {
            debugPrint("Precache image error: $e");
          });
        }
      }
    } catch (e) {
      debugPrint('加載飲食紀錄失敗: $e');
    } finally {
      setState(() => _isLoading = false);
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

  String _parsePortionAtIndex(dynamic record, int index) {
    if (record == null) return "1份";
    final amountVal = record['amount'];
    final portionsVal = record['portions'];
    final descriptionVal = record['description'];
    final sourceStr = (amountVal != null && amountVal.toString().trim().isNotEmpty)
        ? amountVal.toString().trim()
        : ((portionsVal != null && portionsVal.toString().trim().isNotEmpty)
            ? portionsVal.toString().trim()
            : (descriptionVal != null ? descriptionVal.toString().trim() : ''));

    if (sourceStr.isEmpty || sourceStr == "手動輸入飲食紀錄") {
      return "1份";
    }
    final parts = sourceStr.split(RegExp(r',\s*'));
    if (index >= parts.length) return "1份";
    final part = parts[index].trim();
    
    final match = RegExp(r'^(\d+(?:\.\d+)?)\s*(?:份)?$').firstMatch(part);
    if (match != null) {
      final numStr = match.group(1)!;
      final val = double.tryParse(numStr);
      if (val != null) {
        if (val == val.toInt()) {
          return "${val.toInt()}份";
        }
        return "${val}份";
      }
    }
    if (part.contains("份")) {
      final m = RegExp(r'(\d+(?:\.\d+)?)\s*份').firstMatch(part);
      if (m != null) {
        final val = double.tryParse(m.group(1)!);
        if (val != null) {
          if (val == val.toInt()) {
            return "${val.toInt()}份";
          }
          return "${val}份";
        }
      }
      return part;
    }
    return "1份";
  }

  // 根據日期過濾今日的飲食紀錄
  List<dynamic> _getRecordsForSelectedDate() {
    return _allRecords.where((record) {
      final rDate = _getRecordDate(record);
      if (rDate == null) return false;
      return rDate.year == _selectedDate.year &&
             rDate.month == _selectedDate.month &&
             rDate.day == _selectedDate.day;
    }).toList();
  }

  @override // 標記此方法為覆寫父類別之方法
  Widget build(BuildContext context) { // 建立畫面的主要 build 方法，返回元件樹
    String dateStr = "${_selectedDate.year}年${_selectedDate.month}月${_selectedDate.day}日"; // 宣告類別成員或方法內部的區域變數
    final todayRecords = _getRecordsForSelectedDate();

    // 依餐點時段分類
    final breakfastRecords = todayRecords.where((r) => r['mealType'] == 'BREAKFAST').toList();
    final lunchRecords = todayRecords.where((r) => r['mealType'] == 'LUNCH').toList();
    final dinnerRecords = todayRecords.where((r) => r['mealType'] == 'DINNER').toList();
    final otherRecords = todayRecords.where((r) => r['mealType'] == 'OTHER' || r['mealType'] == '其他').toList();

    return Scaffold( // 建立頁面的基礎 Scaffold 骨架，提供頁面基本版面佈局
      backgroundColor: AppColors.surface, // 設定顏色數值（Color）
      body: Stack( // 設定頁面的主要內容區域（body）
        children: [ // 執行相對應的邏輯計算或設定屬性參數
          // 內容區域
          Positioned.fill( // 執行相對應的邏輯計算或設定屬性參數
            child: SafeArea(
              bottom: false,
              child: Column( // 建立垂直排列元件（Column），縱向排列多個子元件
                children: [ // 執行相對應的邏輯計算或設定屬性參數
                  const SizedBox(height: 80), // 預留標題列高度
                  _buildDateBar(dateStr), // 執行相對應的邏輯計算或設定屬性參數
                  Expanded( // 建立填充元件（Expanded），自動佔滿 Row 或 Column 的剩餘空間
                    child: _isLoading 
                      ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                      : ListView( // 建立滾動清單元件（ListView），支援多個子元件滾動瀏覽
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16), // 設定外邊距或內邊距的數值大小（EdgeInsets）
                          children: [ // 執行相對應的邏輯計算或設定屬性參數
                            _buildMealSection("早餐", Icons.wb_sunny_outlined, breakfastRecords),
                            const SizedBox(height: 15), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
                            _buildMealSection("中餐", Icons.wb_sunny, lunchRecords),
                            const SizedBox(height: 15), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
                            _buildMealSection("晚餐", Icons.nights_stay_outlined, dinnerRecords),
                            const SizedBox(height: 15),
                            _buildMealSection("其他", Icons.more_horiz, otherRecords),
                          ], // 執行相對應的邏輯計算或設定屬性參數
                        ), // 執行相對應的邏輯計算或設定屬性參數
                  ), // 執行相對應的邏輯計算或設定屬性參數
                ], // 執行相對應的邏輯計算或設定屬性參數
              ), // 執行相對應的邏輯計算或設定屬性參數
            ), // 執行相對應的邏輯計算或設定屬性參數
          ), // 執行相對應的邏輯計算或設定屬性參數
          // 頂部固定標題列
          Positioned( // 建立絕對定位元件（Positioned），用於精確設定子元件在 Stack 中的位置
            top: 0, left: 0, right: 0, // 執行相對應的邏輯計算或設定屬性參數
            child: _buildHeader(context), // 執行相對應的邏輯計算或設定屬性參數
          ), // 執行相對應的邏輯計算或設定屬性參數
        ], // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ManualRecordPage(initialDate: _selectedDate),
            ),
          );
          _fetchRecords(); // 新增完成後重新整理頁面數據
        },
        backgroundColor: AppColors.primary,
        shape: const CircleBorder(),
        child: const Icon(Icons.add, color: Colors.white, size: 30),
      ),
      bottomNavigationBar: BottomNavigationBar( // 執行相對應的邏輯計算或設定屬性參數
        currentIndex: 1,  // 執行相對應的邏輯計算或設定屬性參數
        selectedItemColor: AppColors.primary, // 設定顏色數值（Color）
        unselectedItemColor: Colors.grey, // 設定顏色數值（Color）
        backgroundColor: AppColors.background, // 設定顏色數值（Color）
        type: BottomNavigationBarType.fixed, // 執行相對應的邏輯計算或設定屬性參數
        onTap: (index) => Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => HomePage(
              initialIndex: index,
              initialReportDate: _selectedDate,
            ),
          ),
          (route) => false,
        ), // 導航路由跳轉：開啟並推入新頁面
        items: const [ // 建立編譯期常數，優化 Flutter 渲染效能
          BottomNavigationBarItem(icon: Icon(Icons.home), label: '首頁'),  // 顯示預設的圖示元件（Icon）
          BottomNavigationBarItem(icon: Icon(Icons.edit_note), label: '飲食紀錄'),  // 顯示預設的圖示元件（Icon）
          BottomNavigationBarItem(icon: Icon(Icons.assignment_outlined), label: '飲食報告'),
          BottomNavigationBarItem(icon: Icon(Icons.account_circle), label: '個人首頁') // 顯示預設的圖示元件（Icon）
        ], // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Widget _buildHeader(BuildContext context) { // 定義用於重複使用的 UI 封裝建構方法
    final double statusBarHeight = MediaQuery.of(context).padding.top;
    return ClipRect( // 回傳建構完成的元件或方法計算結果
        child: BackdropFilter( // 執行相對應的邏輯計算或設定屬性參數
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15), // 執行相對應的邏輯計算或設定屬性參數
          child: Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
            height: 80 + statusBarHeight,  // 執行相對應的邏輯計算或設定屬性參數
            decoration: BoxDecoration( // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
              color: AppColors.background.withOpacity(0.5), // 設定顏色數值（Color）
              border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)), // 設定顏色數值（Color）
            ), // 執行相對應的邏輯計算或設定屬性參數
          padding: EdgeInsets.fromLTRB(16, statusBarHeight + 20, 16, 10), // 設定外邊距或內邊距的數值大小（EdgeInsets）
          child: Row( // 建立水平排列元件（Row），橫向排列多個子元件
            mainAxisAlignment: MainAxisAlignment.spaceBetween, // 執行相對應的邏輯計算或設定屬性參數
            children: [ // 執行相對應的邏輯計算或設定屬性參數
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios, size: 28)), // 導航路由返回：關閉當前頁面並返回上一頁
                const Text( // 建立文字顯示元件（Text）
                  '日記',  // 執行相對應的邏輯計算或設定屬性參數
                  style: TextStyle( // 設定文字字體大小、顏色與粗細等字型樣式（TextStyle）
                    fontSize: 22,  // 執行相對應的邏輯計算或設定屬性參數
                    fontWeight: FontWeight.bold,  // 執行相對應的邏輯計算或設定屬性參數
                    color: AppColors.textPrimary,  // 設定顏色數值（Color）
                    letterSpacing: 1.2 // 執行相對應的邏輯計算或設定屬性參數
                  ) // 執行相對應的邏輯計算或設定屬性參數
                ), // 執行相對應的邏輯計算或設定屬性參數
              GestureDetector( // 建立手勢偵測器（GestureDetector），用於監聽點擊、拖動等觸控事件
                onTap: () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const ProfilePage(returnIndex: 1)), (route) => false), // 導航路由跳轉：開啟並推入新頁面
                child: Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
                  decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 2.925, offset: const Offset(0, 1.56))]), // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
                  child: CircleAvatar( // 建立編譯期常數，優化 Flutter 渲染效能
                    radius: 25,  // 執行相對應的邏輯計算或設定屬性參數
                    backgroundColor: AppColors.background,  // 設定顏色數值（Color）
                    backgroundImage: _avatarUrl != null && _avatarUrl!.isNotEmpty
                        ? NetworkImage(_avatarUrl!)
                        : null,
                    child: _avatarUrl == null || _avatarUrl!.isEmpty
                        ? const Icon( // 顯示預設的圖示元件（Icon）
                            Icons.person,  // 執行相對應的邏輯計算或設定屬性參數
                            color: AppColors.textPrimary,  // 設定顏色數值（Color）
                            size: 35, // 執行相對應的邏輯計算或設定屬性參數
                          )
                        : null, // 執行相對應的邏輯計算或設定屬性參數
                  ), // 執行相對應的邏輯計算或設定屬性參數
                ), // 執行相對應的邏輯計算或設定屬性參數
              ), // 執行相對應的邏輯計算或設定屬性參數
            ], // 執行相對應的邏輯計算或設定屬性參數
          ), // 執行相對應的邏輯計算或設定屬性參數
        ), // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Widget _buildDateBar(String dateStr) { // 定義用於重複使用的 UI 封裝建構方法
    return Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
      width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 10), // 設定外邊距或內邊距的數值大小（EdgeInsets）
      decoration: BoxDecoration( // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
        color: AppColors.background, // 設定顏色數值（Color）
        boxShadow: [ // 執行相對應的邏輯計算或設定屬性參數
          BoxShadow( // 設定容器的陰影效果，包括顏色、模糊半徑與偏移量
            color: Colors.black.withOpacity(0.05), // 設定顏色數值（Color）
            blurRadius: 0.975, // 執行相對應的邏輯計算或設定屬性參數
            offset: const Offset(0, 0.39), // 建立編譯期常數，優化 Flutter 渲染效能
          ), // 執行相對應的邏輯計算或設定屬性參數
        ], // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
      child: InkWell(
        onTap: _selectDate,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(dateStr, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500)),
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_down, color: AppColors.textPrimary),
            ],
          ),
        ),
      ),
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  // 組合餐點時段與多筆後端飲食紀錄
  Widget _buildMealSection(String title, IconData icon, List<dynamic> records) {
    if (records.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.05),
              blurRadius: 5,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: Row(
          children: [
            Icon(icon, size: 24, color: Colors.grey),
            const SizedBox(width: 12),
            Text(
              "$title - 今日無紀錄",
              style: const TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );
    }

    return Column(
      children: records.map((record) {
        final List<String> dishItems = (record['dishName'] as String).split(', ');
        return Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: _buildMealCard(title, icon, dishItems, record),
        );
      }).toList(),
    );
  }

  Widget _buildMealCard(String title, IconData icon, List<String> items, dynamic record) { // 定義用於重複使用的 UI 封裝建構方法
    bool isExpanded = _expandedMeals.contains(record['id'].toString()); // 宣告類別成員或方法內部的區域變數
    bool isSwiped = _swipedMeal == record['id'].toString(); // 宣告類別成員或方法內部的區域變數
    bool needsExpansion = true; // 無論是否有相片，都允許展開以顯示營養數值或相片
    final nutritionParts = _getNutritionParts(record['nutrition']);

    return Column( // 建立垂直排列元件（Column），縱向排列多個子元件
      children: [ // 執行相對應的邏輯計算或設定屬性參數
        GestureDetector( // 建立手勢偵測器（GestureDetector），用於監聽點擊、拖動等觸控事件
          // 支援拖拽與滑動雙模式
          onHorizontalDragUpdate: (details) { // 執行相對應的邏輯計算或設定屬性參數
            _dragExtent += details.delta.dx; // 執行相對應的邏輯計算或設定屬性參數
            if (_dragExtent < -5) setState(() => _swipedMeal = record['id'].toString()); // 更新狀態數據並通知 UI 重新渲染畫面
            else if (_dragExtent > 5) setState(() => _swipedMeal = null); // 更新狀態數據並通知 UI 重新渲染畫面
          }, // 程式碼區塊或元件結構結束
          onHorizontalDragEnd: (details) { // 執行相對應的邏輯計算或設定屬性參數
            _dragExtent = 0; // 重置拖動計量
            if (details.primaryVelocity! < -300) setState(() => _swipedMeal = record['id'].toString()); // 更新狀態數據並通知 UI 重新渲染畫面
            else if (details.primaryVelocity! > 300) setState(() => _swipedMeal = null); // 更新狀態數據並通知 UI 重新渲染畫面
          }, // 程式碼區塊或元件結構結束
          child: Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
            height: 120, // 執行相對應的邏輯計算或設定屬性參數
            decoration: BoxDecoration( // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
              color: Colors.white, // 設定顏色數值（Color）
              borderRadius: BorderRadius.circular(15), // 設定容器的圓角弧度半徑大小
              boxShadow: [ // 執行相對應的邏輯計算或設定屬性參數
                BoxShadow( // 設定容器的陰影效果，包括顏色、模糊半徑與偏移量
                  color: AppColors.primary.withOpacity(0.1), // 設定顏色數值（Color）
                  blurRadius: 1.95, // 執行相對應的邏輯計算或設定屬性參數
                  offset: const Offset(0, 0.78), // 建立編譯期常數，優化 Flutter 渲染效能
                ), // 執行相對應的邏輯計算或設定屬性參數
              ], // 執行相對應的邏輯計算或設定屬性參數
            ), // 執行相對應的邏輯計算或設定屬性參數
            child: Stack( // 建立層疊佈局元件（Stack），可將多個子元件重疊顯示
              children: [ // 執行相對應的邏輯計算或設定屬性參數
                Positioned.fill( // 執行相對應的邏輯計算或設定屬性參數
                  child: Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
                    color: const Color(0xFFEEEEEE), padding: const EdgeInsets.only(right: 10), // 設定外邊距或內邊距的數值大小（EdgeInsets）
                    child: Row( // 建立水平排列元件（Row），橫向排列多個子元件
                      mainAxisAlignment: MainAxisAlignment.end, // 執行相對應的邏輯計算或設定屬性參數
                      children: [ // 執行相對應的邏輯計算或設定屬性參數
                        _buildActionBtn(Icons.edit, "編輯", AppColors.secondary, () => _handleEditRecord(record)), // 編輯按鈕
                        _buildActionBtn(Icons.image, "相片", AppColors.accent, () => _handleUploadPhoto(record)), // 照片上傳
                        _buildActionBtn(Icons.delete, "刪除", AppColors.danger, () => _handleDeleteRecord(record)), // 刪除按鈕
                      ], // 執行相對應的邏輯計算或設定屬性參數
                    ), // 執行相對應的邏輯計算或設定屬性參數
                  ), // 執行相對應的邏輯計算或設定屬性參數
                ), // 執行相對應的邏輯計算或設定屬性參數
                AnimatedPositioned( // 建立絕對定位元件（Positioned），用於精確設定子元件在 Stack 中的位置
                  duration: const Duration(milliseconds: 250), curve: Curves.easeOutQuart, // 建立編譯期常數，優化 Flutter 渲染效能
                  left: isSwiped ? -200 : 0, right: isSwiped ? 200 : 0, // 執行相對應的邏輯計算或設定屬性參數
                  top: 0, bottom: 0, // 執行相對應的邏輯計算或設定屬性參數
                  child: Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
                    color: Colors.white, // 設定顏色數值（Color）
                    child: Row( // 建立水平排列元件（Row），橫向排列多個子元件
                      children: [ // 執行相對應的邏輯計算或設定屬性參數
                        Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
                          width: 80, decoration: BoxDecoration(border: Border(right: BorderSide(color: AppColors.border, width: 1.5))), // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 30, color: AppColors.secondary), Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary))]), // 建立垂直排列元件（Column），縱向排列多個子元件
                        ), // 執行相對應的邏輯計算或設定屬性參數
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  for (int i = 0; i < (isExpanded ? items.length : items.take(2).length); i++) ...[
                                    if (i > 0) const TextSpan(text: "\n"),
                                    TextSpan(
                                      text: items[i],
                                      style: const TextStyle(fontSize: 18, height: 1.4, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                    ),
                                    TextSpan(
                                      text: " (${_parsePortionAtIndex(record, i)})",
                                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                                    ),
                                  ]
                                ],
                              ),
                              maxLines: isExpanded ? 10 : 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ), // 建立間距容器（Padding），用於設定內部邊距
                        Row( // 建立水平排列元件（Row），橫向排列多個子元件
                          children: [ // 執行相對應的邏輯計算或設定屬性參數
                             if (needsExpansion) IconButton(icon: Icon(isExpanded ? Icons.arrow_drop_up : Icons.arrow_drop_down, color: AppColors.textPrimary), onPressed: () { setState(() { if (isExpanded) _expandedMeals.remove(record['id'].toString()); else _expandedMeals.add(record['id'].toString()); }); }), // 更新狀態數據並通知 UI 重新渲染畫面
                            Container(width: 4, height: 40, margin: const EdgeInsets.only(right: 4), decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))), // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
                          ], // 執行相對應的邏輯計算或設定屬性參數
                        ), // 執行相對應的邏輯計算或設定屬性參數
                      ], // 執行相對應的邏輯計算或設定屬性參數
                    ), // 執行相對應的邏輯計算或設定屬性參數
                  ), // 執行相對應的邏輯計算或設定屬性參數
                ), // 執行相對應的邏輯計算或設定屬性參數
              ], // 執行相對應的邏輯計算或設定屬性參數
            ), // 執行相對應的邏輯計算或設定屬性參數
          ), // 執行相對應的邏輯計算或設定屬性參數
        ), // 執行相對應的邏輯計算或設定屬性參數
        Visibility(
          visible: isExpanded,
          maintainState: true,
          child: Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
            width: double.infinity, padding: const EdgeInsets.all(12), // 設定外邊距或內邊距的數值大小（EdgeInsets）
            decoration: BoxDecoration( // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
              color: AppColors.surface, // 設定顏色數值（Color）
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(15)), // 建立編譯期常數，優化 Flutter 渲染效能
              boxShadow: [ // 執行相對應的邏輯計算或設定屬性參數
                BoxShadow( // 設定容器的陰影效果，包括顏色、模糊半徑與偏移量
                  color: Colors.black.withOpacity(0.05), // 設定顏色數值（Color）
                  blurRadius: 0.975, // 執行相對應的邏輯計算或設定屬性參數
                  offset: const Offset(0, 0.39), // 建立編譯期常數，優化 Flutter 渲染效能
                ), // 執行相對應的邏輯計算或設定屬性參數
              ], // 執行相對應的邏輯計算或設定屬性參數
            ), // 執行相對應的邏輯計算或設定屬性參數
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (items.length > 2)
                  Text(items.skip(2).join("\n"), style: const TextStyle(fontSize: 18, height: 1.5, color: AppColors.textPrimary)),
                if (nutritionParts.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.secondary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "營養分析",
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.secondary),
                          ),
                          const SizedBox(height: 6),
                          ...nutritionParts.map((part) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2.0),
                            child: Row(
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: AppColors.secondary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  part.trim(),
                                  style: const TextStyle(fontSize: 14, color: AppColors.textPrimary, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          )).toList(),
                        ],
                      ),
                    ),
                  ),
                if (record['photoUrl'] != null && (record['photoUrl'] as String).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        "${ApiConfig.baseUrl.replaceAll('/api', '')}${record['photoUrl']}",
                        headers: _jwtToken != null ? {'Authorization': 'Bearer $_jwtToken'} : null,
                        width: double.infinity,
                        height: 200,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Container(
                            height: 200,
                            color: Colors.grey[100],
                            child: const Center(
                              child: CircularProgressIndicator(color: AppColors.primary),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, size: 50, color: Colors.grey),
                      ),
                    ),
                  ),
              ],
            ), // 建立文字顯示元件（Text）
          ),
        ), // 執行相對應的邏輯計算或設定屬性參數
      ], // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Widget _buildActionBtn(IconData icon, String label, Color color, VoidCallback onTap) { // 定義用於重複使用的 UI 封裝建構方法
    return GestureDetector( // 建立手勢偵測器（GestureDetector），用於監聽點擊、拖動等觸控事件
      onTap: onTap, // 執行相對應的邏輯計算或設定屬性參數
      child: Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
        margin: const EdgeInsets.symmetric(horizontal: 4), width: 50, // 設定外邊距或內邊距的數值大小（EdgeInsets）
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(shape: BoxShape.circle, color: color.withOpacity(0.1)), child: Icon(icon, color: color, size: 20)), const SizedBox(height: 4), Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold))]), // 建立垂直排列元件（Column），縱向排列多個子元件
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  List<String> _getNutritionParts(dynamic nutritionVal) {
    if (nutritionVal == null) return [];
    
    String formatValue(String key, dynamic val) {
      if (val == null) return '--';
      final sVal = val.toString().trim();
      if (sVal.isEmpty || sVal == 'null' || sVal == 'None') return '--';

      if (key.contains('熱量') || key.toLowerCase().contains('calories') || key.toLowerCase().contains('cal')) {
        if (sVal.contains('kcal') || sVal.contains('卡')) return sVal;
        return '$sVal kcal';
      }
      if (key.contains('蛋白質') || key.toLowerCase().contains('protein') ||
          key.contains('脂肪') || key.toLowerCase().contains('fat') ||
          key.contains('碳水') || key.toLowerCase().contains('carb')) {
        if (sVal.contains('g') || sVal.contains('克')) return sVal;
        return '$sVal g';
      }
      return sVal;
    }

    if (nutritionVal is Map) {
      final List<String> parts = [];
      nutritionVal.forEach((k, v) {
        final keyStr = k.toString().trim();
        final valStr = formatValue(keyStr, v);
        String displayKey = keyStr;
        if (keyStr.toLowerCase() == 'calories') displayKey = '熱量';
        else if (keyStr.toLowerCase() == 'protein') displayKey = '蛋白質';
        else if (keyStr.toLowerCase() == 'fat') displayKey = '脂肪';
        else if (keyStr.toLowerCase() == 'carbohydrates' || keyStr.toLowerCase() == 'carbs') displayKey = '碳水化合物';
        parts.add('$displayKey: $valStr');
      });
      return parts;
    }
    if (nutritionVal is String) {
      if (nutritionVal.isEmpty) return [];
      final trimmed = nutritionVal.trim();
      if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
        try {
          final parsed = jsonDecode(trimmed);
          if (parsed is Map) {
            return _getNutritionParts(parsed);
          }
        } catch (_) {}
      }
      return nutritionVal.split(', ').where((s) => s.trim().isNotEmpty).toList();
    }
    return [nutritionVal.toString()];
  }

  String _parseNutrient(String? nutritionStr, String pattern) {
    if (nutritionStr == null || nutritionStr.isEmpty) return '';
    final regExp = RegExp(pattern + r':\s*(\d+(?:\.\d+)?)', caseSensitive: false);
    final match = regExp.firstMatch(nutritionStr);
    return match != null ? (match.group(1) ?? '') : '';
  }

  // 1. 編輯紀錄
  void _handleEditRecord(dynamic record) {
    setState(() => _swipedMeal = null);
    final String nutritionStr = record['nutrition'] is Map 
        ? _getNutritionParts(record['nutrition']).join(', ')
        : (record['nutrition']?.toString() ?? '');
    final calVal = _parseNutrient(nutritionStr, r'(?:熱量|calories|kcal)');
    final proVal = _parseNutrient(nutritionStr, r'(?:蛋白質|protein)');
    final fatVal = _parseNutrient(nutritionStr, r'(?:脂肪|fat)');
    final carbVal = _parseNutrient(nutritionStr, r'(?:碳水化合物|碳水|carbs)');

    final nameController = TextEditingController(text: record['dishName']);
    final calController = TextEditingController(text: calVal);
    final proController = TextEditingController(text: proVal);
    final fatController = TextEditingController(text: fatVal);
    final carbController = TextEditingController(text: carbVal);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('編輯飲食內容與營養資訊'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: '飲食項目 (逗號分隔)',
                  hintText: '例：水煮蛋, 豆漿',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: calController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: '熱量 (kcal)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: proController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: '蛋白質 (g)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: fatController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: '脂肪 (g)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: carbController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: '碳水化合物 (g)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              if (nameController.text.trim().isNotEmpty) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在更新...')));

                final c = calController.text.trim();
                final p = proController.text.trim();
                final f = fatController.text.trim();
                final cb = carbController.text.trim();
                
                final List<String> nutritionParts = [];
                if (c.isNotEmpty) nutritionParts.add('熱量: $c kcal');
                if (p.isNotEmpty) nutritionParts.add('蛋白質: $p g');
                if (f.isNotEmpty) nutritionParts.add('脂肪: $f g');
                if (cb.isNotEmpty) nutritionParts.add('碳水化合物: $cb g');
                final newNutrition = nutritionParts.isNotEmpty 
                    ? nutritionParts.join(', ') 
                    : '熱量: 0 kcal, 蛋白質: 0 g, 脂肪: 0 g, 碳水化合物: 0 g';

                final res = await DietService().updateDietRecord(
                  record['id'],
                  dishName: nameController.text.trim(),
                  mealType: record['mealType'],
                  description: record['description'] ?? '',
                  nutrition: newNutrition,
                  mealDate: _getRecordDate(record),
                );
                if (res['success'] == true) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('更新成功！')));
                  _fetchRecords();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text(FriendlyErrorMessage.dietRecord)),
                  );
                }
              }
            },
            child: const Text('儲存', style: TextStyle(fontWeight: FontWeight.bold)),
          )
        ],
      )
    );
  }

  // 2. 上傳相片
  Future<void> _handleUploadPhoto(dynamic record) async {
    setState(() => _swipedMeal = null);
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在上傳餐點照片...')));
        final bytes = await image.readAsBytes();
        final res = await DietService().uploadDietPhoto(record['id'], bytes, image.name);
        if (res['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('照片上傳成功！')));
          _fetchRecords();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(FriendlyErrorMessage.upload)),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(FriendlyErrorMessage.upload)),
      );
    }
  }

  // 3. 刪除紀錄
  void _handleDeleteRecord(dynamic record) {
    setState(() => _swipedMeal = null);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('確認刪除'),
        content: Text('確定要刪除「${record['dishName']}」這筆飲食紀錄嗎？此動作無法復原。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在刪除...')));
              final success = await DietService().deleteDietRecord(record['id']);
              if (success) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已刪除紀錄！')));
                _fetchRecords();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('刪除失敗，請再試一次。')));
              }
            },
            child: const Text('確認刪除', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold)),
          )
        ],
      )
    );
  }
}
