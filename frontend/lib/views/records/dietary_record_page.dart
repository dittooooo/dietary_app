import 'package:flutter/material.dart'; // 匯入 material.dart 元件庫或套件
import 'dart:ui'; // 匯入 dart:ui 元件庫或套件
import '../home/home_page.dart'; // 匯入 home_page.dart 元件庫或套件
import '../auth/profile_page.dart'; // 匯入 profile_page.dart 元件庫或套件
import 'diary_page.dart'; // 匯入 diary_page.dart 元件庫或套件
import 'manual_record_page.dart'; // 匯入 manual_record_page.dart 元件庫或套件
import 'dart:math' as math; // 匯入 dart:math 元件庫或套件
import '../../color/app_colors.dart'; // 匯入 app_colors.dart 元件庫或套件
import '../../widgets/dog_avatar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/auth_service.dart';
import '../../config/api_config.dart';
import '../../services/diet_service.dart';

class DietaryRecordPage extends StatefulWidget {
  // 定義 DietaryRecordPage 類別，繼承自 StatefulWidget
  final ValueChanged<DateTime>? onDateSelected;
  const DietaryRecordPage({super.key, this.onDateSelected});

  @override // 標記此方法為覆寫父類別之方法
  State<DietaryRecordPage> createState() => _DietaryRecordPageState(); // 執行相對應的邏輯計算或設定屬性參數
} // 程式碼區塊或元件結構結束

class _DietaryRecordPageState extends State<DietaryRecordPage> {
  // 定義 _DietaryRecordPageState 類別，繼承自 State
  final ScrollController _scrollController =
      ScrollController(); // 宣告類別成員或方法內部的區域變數
  bool _showBackToToday = false; // 宣告類別成員或方法內部的區域變數
  DateTime _selectedDate = DateTime.now(); // 執行相對應的邏輯計算或設定屬性參數
  bool _showOverlay = false; // 宣告類別成員或方法內部的區域變數
  DateTime? _rippleDate; // 執行相對應的邏輯計算或設定屬性參數
  bool _isLoadingRecords = false;
  List<dynamic> _dietRecords = [];

  final List<DateTime> _pathDates = List.generate(
    100,
    (i) => DateTime.now().subtract(Duration(days: i)),
  ); // 宣告類別成員或方法內部的區域變數
  String? _avatarUrl;

  String? _resolveAvatarUrl(dynamic avatarPath) {
    final path = avatarPath?.toString().trim();
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http')) return path;

    final serverBase = ApiConfig.baseUrl.replaceAll('/api', '');
    return '$serverBase$path';
  }

  Future<void> _loadAvatar() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedAvatarUrl = _resolveAvatarUrl(prefs.getString('user_avatar_url'));
    if (mounted) {
      setState(() {
        _avatarUrl = cachedAvatarUrl;
      });
    }
    final result = await AuthService().getUserProfile();
    if (result['success'] == true) {
      final userData = result['data'];
      final avatarPath =
          userData?['avatarUrl'] ?? userData?['user']?['avatarUrl'];
      final fullUrl = _resolveAvatarUrl(avatarPath);
      if (fullUrl != null) {
        if (mounted) {
          setState(() {
            _avatarUrl = fullUrl;
          });
        }
        await prefs.setString('user_avatar_url', fullUrl);
      }
    }
  }

  @override // 標記此方法為覆寫父類別之方法
  void initState() {
    // 初始化狀態生命週期方法，頁面建立時執行一次
    super.initState(); // 執行相對應的邏輯計算或設定屬性參數
    _loadAvatar();
    _loadDietRecords();
    _scrollController.addListener(() {
      // 執行相對應的邏輯計算或設定屬性參數
      if (_scrollController.offset > 200 && !_showBackToToday) {
        // 執行相對應的邏輯計算或設定屬性參數
        setState(() => _showBackToToday = true); // 更新狀態數據並通知 UI 重新渲染畫面
      } else if (_scrollController.offset <= 200 && _showBackToToday) {
        // 執行相對應的邏輯計算或設定屬性參數
        setState(() => _showBackToToday = false); // 更新狀態數據並通知 UI 重新渲染畫面
      } // 程式碼區塊或元件結構結束
    }); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Future<void> _loadDietRecords() async {
    setState(() => _isLoadingRecords = true);
    try {
      final records = await DietService().getMyDietRecords();
      if (mounted) {
        setState(() => _dietRecords = records);
      }
    } catch (e) {
      debugPrint('載入飲食紀錄狀態失敗: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingRecords = false);
      }
    }
  }

  DateTime? _recordDate(dynamic record) {
    if (record == null) return null;
    final value = record['date'] ?? record['mealDate'] ?? record['createdAt'];
    if (value == null) return null;
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (_) {
        return null;
      }
    }
    if (value is List && value.length >= 3) {
      try {
        return DateTime(
          int.parse(value[0].toString()),
          int.parse(value[1].toString()),
          int.parse(value[2].toString()),
        );
      } catch (_) {
        return null;
      }
    }
    if (value is Map) {
      try {
        return DateTime(
          int.parse((value['year'] ?? value['yearValue']).toString()),
          int.parse((value['month'] ?? value['monthValue']).toString()),
          int.parse((value['day'] ?? value['dayOfMonth']).toString()),
        );
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  List<dynamic> _recordsForDate(DateTime date) {
    return _dietRecords.where((record) {
      final recordDate = _recordDate(record);
      return recordDate != null &&
          recordDate.year == date.year &&
          recordDate.month == date.month &&
          recordDate.day == date.day;
    }).toList();
  }

  String _elfRecordMessage() {
    if (_isLoadingRecords) return '正在看看\n飲食紀錄...';

    final records = _recordsForDate(_selectedDate);
    final today = DateTime.now();
    final isToday = _selectedDate.year == today.year &&
        _selectedDate.month == today.month &&
        _selectedDate.day == today.day;

    if (records.isEmpty) {
      return isToday ? '今天還沒記錄\n好餓喔...' : '這天還沒記錄\n可以補一下喔';
    }

    final mealTypes = records
        .map((record) => (record['mealType'] ?? '').toString().toUpperCase())
        .toSet();
    final missingMeals = <String>[
      if (!mealTypes.contains('BREAKFAST')) '早餐',
      if (!mealTypes.contains('LUNCH')) '午餐',
      if (!mealTypes.contains('DINNER')) '晚餐',
    ];

    if (missingMeals.isEmpty) {
      return '三餐都有記錄\n好棒！';
    }
    if (records.length >= 3) {
      return '已記錄 ${records.length} 筆\n繼續保持！';
    }
    return '已記錄 ${records.length} 筆\n還差${missingMeals.first}';
  }

  void _selectDate() async {
    // 執行相對應的邏輯計算或設定屬性參數
    final DateTime? picked = await showDatePicker(
      // 宣告類別成員或方法內部的區域變數
      context: context, // 執行相對應的邏輯計算或設定屬性參數
      initialDate: _selectedDate, // 執行相對應的邏輯計算或設定屬性參數
      firstDate: DateTime(2023), // 執行相對應的邏輯計算或設定屬性參數
      lastDate: DateTime.now(), // 執行相對應的邏輯計算或設定屬性參數
      builder: (context, child) => Theme(
        // 執行相對應的邏輯計算或設定屬性參數
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.primary,
            onPrimary: AppColors.background,
            onSurface: AppColors.textPrimary,
          ),
        ), // 設定顏色數值（Color）
        child: child!, // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
    if (picked != null) _scrollToDate(picked); // 執行相對應的邏輯計算或設定屬性參數
  } // 程式碼區塊或元件結構結束

  void _scrollToDate(DateTime date) {
    // 執行相對應的邏輯計算或設定屬性參數
    int daysDiff = DateTime.now().difference(date).inDays; // 宣告類別成員或方法內部的區域變數
    if (daysDiff < 0) daysDiff = 0; // 執行相對應的邏輯計算或設定屬性參數

    int segmentIndex = (daysDiff / 5).floor(); // 宣告類別成員或方法內部的區域變數
    // 壓縮後的高度為 110。
    // 公式：Padding 250 + 圓點在 List 中的位置 30 - 目標螢幕座標 280 = segmentIndex * 110
    double adjustedOffset = segmentIndex * 110.0; // 宣告類別成員或方法內部的區域變數

    if (adjustedOffset < 0) adjustedOffset = 0; // 執行相對應的邏輯計算或設定屬性參數

    setState(() {
      // 更新狀態數據並通知 UI 重新渲染畫面
      _selectedDate = date; // 執行相對應的邏輯計算或設定屬性參數
      _rippleDate = date; // 執行相對應的邏輯計算或設定屬性參數
      _showOverlay = false;
    }); // 程式碼區塊或元件結構結束

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DiaryPage(
          date: date,
          onDateChanged: widget.onDateSelected,
        ),
      ),
    ).then((_) => _loadDietRecords());
    widget.onDateSelected?.call(date);

    Future.microtask(() {
      // 執行相對應的邏輯計算或設定屬性參數
      if (mounted) {
        // 執行相對應的邏輯計算或設定屬性參數
        _scrollController.animateTo(
          // 執行相對應的邏輯計算或設定屬性參數
          adjustedOffset, // 執行相對應的邏輯計算或設定屬性參數
          duration: const Duration(
            milliseconds: 400,
          ), // 建立編譯期常數，優化 Flutter 渲染效能
          curve: Curves.easeOutQuart, // 執行相對應的邏輯計算或設定屬性參數
        ); // 程式碼區塊或元件結構結束
      } // 程式碼區塊或元件結構結束
    }); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  @override // 標記此方法為覆寫父類別之方法
  Widget build(BuildContext context) {
    // 建立畫面的主要 build 方法，返回元件樹
    final double screenWidth = MediaQuery.of(
      context,
    ).size.width; // 宣告類別成員或方法內部的區域變數
    const double margin = 20.0; // 建立編譯期常數，優化 Flutter 渲染效能
    const double radius = 50.0; // 建立編譯期常數，優化 Flutter 渲染效能
    final double pathWidth =
        screenWidth - (margin * 2) - (radius * 2); // 宣告類別成員或方法內部的區域變數

    final double statusBarHeight = MediaQuery.of(context).padding.top;

    return Scaffold(
      // 建立頁面的基礎 Scaffold 骨架，提供頁面基本版面佈局
      backgroundColor: AppColors.surface, // 設定顏色數值（Color）
      body: Stack(
        // 建立層疊佈局元件（Stack），可將多個子元件重疊顯示
        children: [
          // 執行相對應的邏輯計算或設定屬性參數
          // 1. 路徑區 (高度壓縮至 110)
          Positioned.fill(
            // 執行相對應的邏輯計算或設定屬性參數
            child: ListView.builder(
              // 建立滾動清單元件（ListView），支援多個子元件滾動瀏覽
              controller: _scrollController, // 執行相對應的邏輯計算或設定屬性參數
              padding: EdgeInsets.only(
                top: 250 + statusBarHeight,
                bottom: 200,
              ), // 設定外邊距或內邊距的數值大小（EdgeInsets）
              itemCount: 20, // 執行相對應的邏輯計算或設定屬性參數
              itemBuilder: (context, index) => _buildSPathSegment(
                index,
                pathWidth,
                margin,
              ), // 執行相對應的邏輯計算或設定屬性參數
            ), // 執行相對應的邏輯計算或設定屬性參數
          ), // 執行相對應的邏輯計算或設定屬性參數

          if (_showOverlay) // 執行相對應的邏輯計算或設定屬性參數
            Positioned.fill(
              // 執行相對應的邏輯計算或設定屬性參數
              child: GestureDetector(
                // 建立手勢偵測器（GestureDetector），用於監聽點擊、拖動等觸控事件
                onTap: () => setState(() {
                  _showOverlay = false;
                  _rippleDate = null;
                }), // 更新狀態數據並通知 UI 重新渲染畫面
                behavior: HitTestBehavior.translucent, // 執行相對應的邏輯計算或設定屬性參數
                child: Container(
                  color: Colors.black.withOpacity(0.3),
                ), // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
              ), // 執行相對應的邏輯計算或設定屬性參數
            ), // 執行相對應的邏輯計算或設定屬性參數

          _buildFixedHeader(context), // 執行相對應的邏輯計算或設定屬性參數
          _buildFeatureRow(), // 建立水平排列元件（Row），橫向排列多個子元件

          if (_showOverlay) // 執行相對應的邏輯計算或設定屬性參數
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildActionPanel(context),
            ), // 建立絕對定位元件（Positioned），用於精確設定子元件在 Stack 中的位置
          // 「回今天」按鈕 (中文 + 雙箭頭)
          if (_showBackToToday) // 執行相對應的邏輯計算或設定屬性參數
            Positioned(
              // 建立絕對定位元件（Positioned），用於精確設定子元件在 Stack 中的位置
              right: 20, // 執行相對應的邏輯計算或設定屬性參數
              bottom: _showOverlay
                  ? MediaQuery.of(context).size.height * 0.35 + 20
                  : 20, // 執行相對應的邏輯計算或設定屬性參數
              child: GestureDetector(
                // 建立手勢偵測器（GestureDetector），用於監聽點擊、拖動等觸控事件
                onTap: () => _scrollToDate(DateTime.now()), // 執行相對應的邏輯計算或設定屬性參數
                child: Container(
                  // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ), // 設定外邊距或內邊距的數值大小（EdgeInsets）
                  decoration: BoxDecoration(
                    // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
                    color: AppColors.secondary, // 設定顏色數值（Color）
                    borderRadius: BorderRadius.circular(25), // 設定容器的圓角弧度半徑大小
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.3),
                        blurRadius: 1.95,
                        offset: const Offset(0, 0.78),
                      ),
                    ], // 設定容器的陰影效果，包括顏色、模糊半徑與偏移量
                  ), // 執行相對應的邏輯計算或設定屬性參數
                  child: const Row(
                    // 建立水平排列元件（Row），橫向排列多個子元件
                    mainAxisSize: MainAxisSize.min, // 執行相對應的邏輯計算或設定屬性參數
                    children: [
                      // 執行相對應的邏輯計算或設定屬性參數
                      Icon(
                        Icons.keyboard_double_arrow_up,
                        color: Colors.white,
                        size: 20,
                      ), // 設定顏色數值（Color）
                      SizedBox(width: 4), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
                      Text(
                        '回今天',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ), // 建立文字顯示元件（Text）
                    ], // 執行相對應的邏輯計算或設定屬性參數
                  ), // 執行相對應的邏輯計算或設定屬性參數
                ), // 執行相對應的邏輯計算或設定屬性參數
              ), // 執行相對應的邏輯計算或設定屬性參數
            ), // 執行相對應的邏輯計算或設定屬性參數
        ], // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Widget _buildFixedHeader(BuildContext context) {
    // 定義用於重複使用的 UI 封裝建構方法
    final double statusBarHeight = MediaQuery.of(context).padding.top;
    return Positioned(
      // 建立絕對定位元件（Positioned），用於精確設定子元件在 Stack 中的位置
      top: 0,
      left: 0,
      right: 0, // 執行相對應的邏輯計算或設定屬性參數
      child: ClipRect(
        // 執行相對應的邏輯計算或設定屬性參數
        child: BackdropFilter(
          // 執行相對應的邏輯計算或設定屬性參數
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15), // 執行相對應的邏輯計算或設定屬性參數
          child: Container(
            // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
            height: 80 + statusBarHeight, // 與個人首頁高度一致
            decoration: BoxDecoration(
              // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
              color: AppColors.background.withOpacity(0.7), // 設定顏色數值（Color）
              border: Border(
                bottom: BorderSide(color: AppColors.border, width: 0.5),
              ), // 設定顏色數值（Color）
            ), // 執行相對應的邏輯計算或設定屬性參數
            padding: EdgeInsets.fromLTRB(
              16,
              statusBarHeight + 20,
              16,
              10,
            ), // 設定外邊距或內邊距的數值大小（EdgeInsets）
            child: Row(
              // 建立水平排列元件（Row），橫向排列多個子元件
              mainAxisAlignment:
                  MainAxisAlignment.spaceBetween, // 執行相對應的邏輯計算或設定屬性參數
              children: [
                // 執行相對應的邏輯計算或設定屬性參數
                const SizedBox(width: 50), // 移除返回鍵，保留空白以維持標題置中
                const Text(
                  // 建立文字顯示元件（Text）
                  '飲食紀錄', // 執行相對應的邏輯計算或設定屬性參數
                  style: TextStyle(
                    // 設定文字字體大小、顏色與粗細等字型樣式（TextStyle）
                    fontSize: 22, // 執行相對應的邏輯計算或設定屬性參數
                    fontWeight: FontWeight.bold, // 執行相對應的邏輯計算或設定屬性參數
                    color: AppColors.textPrimary, // 設定顏色數值（Color）
                    letterSpacing: 1.2, // 執行相對應的邏輯計算或設定屬性參數
                  ), // 執行相對應的邏輯計算或設定屬性參數
                ), // 執行相對應的邏輯計算或設定屬性參數
                GestureDetector(
                  // 建立手勢偵測器（GestureDetector），用於監聽點擊、拖動等觸控事件
                  onTap: () => Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(
                      builder: (context) => HomePage(initialIndex: 3),
                    ),
                    (route) => false,
                  ), // 建立編譯期常數，優化 Flutter 渲染效能
                  child: Container(
                    // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
                    decoration: BoxDecoration(
                      // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
                      shape: BoxShape.circle, // 執行相對應的邏輯計算或設定屬性參數
                      boxShadow: [
                        // 執行相對應的邏輯計算或設定屬性參數
                        BoxShadow(
                          // 設定容器的陰影效果，包括顏色、模糊半徑與偏移量
                          color: Colors.black.withOpacity(0.2), // 設定顏色數值（Color）
                          blurRadius: 2.925, // 執行相對應的邏輯計算或設定屬性參數
                          offset: const Offset(
                            0,
                            1.56,
                          ), // 建立編譯期常數，優化 Flutter 渲染效能
                        ), // 執行相對應的邏輯計算或設定屬性參數
                      ], // 執行相對應的邏輯計算或設定屬性參數
                    ), // 執行相對應的邏輯計算或設定屬性參數
                    child: CircleAvatar(
                      // 建立編譯期常數，優化 Flutter 渲染效能
                      radius: 25, // 執行相對應的邏輯計算或設定屬性參數
                      backgroundColor: AppColors.background, // 設定顏色數值（Color）
                      backgroundImage:
                          _avatarUrl != null && _avatarUrl!.isNotEmpty
                          ? NetworkImage(_avatarUrl!)
                          : null,
                      child: _avatarUrl == null || _avatarUrl!.isEmpty
                          ? const Icon(
                              // 顯示預設的圖示元件（Icon）
                              Icons.person, // 執行相對應的邏輯計算或設定屬性參數
                              color: AppColors.textPrimary, // 設定顏色數值（Color）
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
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Widget _buildFeatureRow() {
    // 建立水平排列元件（Row），橫向排列多個子元件
    final double statusBarHeight = MediaQuery.of(context).padding.top;
    return Positioned(
      // 建立絕對定位元件（Positioned），用於精確設定子元件在 Stack 中的位置
      top: 80 + statusBarHeight,
      left: 0,
      right: 0, // 執行相對應的邏輯計算或設定屬性參數
      child: Container(
        // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
        ), // 設定外邊距或內邊距的數值大小（EdgeInsets）
        child: Row(
          // 建立水平排列元件（Row），橫向排列多個子元件
          mainAxisAlignment:
              MainAxisAlignment.spaceBetween, // 執行相對應的邏輯計算或設定屬性參數
          children: [
            // 執行相對應的邏輯計算或設定屬性參數
            // 1. 月份/日期框
            GestureDetector(
              // 建立手勢偵測器（GestureDetector），用於監聽點擊、拖動等觸控事件
              onTap: _selectDate, // 執行相對應的邏輯計算或設定屬性參數
              child: Container(
                // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
                width: 60,
                height: 80, // 執行相對應的邏輯計算或設定屬性參數
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.2),
                      blurRadius: 1.95,
                      offset: const Offset(0.78, 1.17),
                    ),
                  ],
                ), // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('月', style: TextStyle(fontSize: 14)),
                    Text(
                      '${_selectedDate.day}',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ), // 建立垂直排列元件（Column），縱向排列多個子元件
              ), // 執行相對應的邏輯計算或設定屬性參數
            ), // 執行相對應的邏輯計算或設定屬性參數
            // 2. 新增按鈕
            GestureDetector(
              // 建立手勢偵測器（GestureDetector），用於監聽點擊、拖動等觸控事件
              onTap: () {
                // 執行相對應的邏輯計算或設定屬性參數
                Navigator.push(
                  // 導航路由跳轉：開啟並推入新頁面
                  context, // 執行相對應的邏輯計算或設定屬性參數
                  MaterialPageRoute(
                    builder: (context) =>
                        ManualRecordPage(initialDate: _selectedDate),
                  ), // 執行相對應的邏輯計算或設定屬性參數
                ).then((_) => _loadDietRecords()); // 程式碼區塊或元件結構結束
              }, // 程式碼區塊或元件結構結束
              child: Container(
                // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
                width: 160,
                height: 70, // 執行相對應的邏輯計算或設定屬性參數
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.5),
                      blurRadius: 2.925,
                      offset: const Offset(0, 1.95),
                    ),
                  ],
                ), // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
                child: const Icon(
                  Icons.add,
                  color: AppColors.background,
                  size: 35,
                ), // 設定顏色數值（Color）
              ), // 執行相對應的邏輯計算或設定屬性參數
            ), // 執行相對應的邏輯計算或設定屬性參數

            GestureDetector(
              // 建立手勢偵測器（GestureDetector），用於監聽點擊、拖動等觸控事件
              onTap: () => Navigator.pushAndRemoveUntil(
                // 導航路由跳轉：開啟並推入新頁面
                context, // 執行相對應的邏輯計算或設定屬性參數
                MaterialPageRoute(
                  builder: (context) =>
                      const HomePage(initialIndex: 0, showChat: true),
                ), // 建立編譯期常數，優化 Flutter 渲染效能
                (route) => false, // 執行相對應的邏輯計算或設定屬性參數
              ), // 執行相對應的邏輯計算或設定屬性參數
              child: Column(
                // 建立垂直排列元件（Column），縱向排列多個子元件
                children: [
                  // 執行相對應的邏輯計算或設定屬性參數
                  Container(
                    // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ), // 設定外邊距或內邊距的數值大小（EdgeInsets）
                    decoration: BoxDecoration(
                      color: const Color(0xFFFCF8EC),
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.1),
                          blurRadius: 0.975,
                          offset: const Offset(0.39, 0.39),
                        ),
                      ],
                    ), // 建立盒子裝飾元件（BoxDecoration），用來設定圓角防偽陰影樣式
                    child: Text(
                      _elfRecordMessage(),
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textPrimary,
                      ),
                      textAlign: TextAlign.center,
                    ), // 建立文字顯示元件（Text）
                  ), // 執行相對應的邏輯計算或設定屬性參數
                  const SizedBox(height: 5), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
                  Transform.translate(
                    offset: const Offset(0, -6), // 僅將小精靈往上移 6 像素，避免與氣泡重疊
                    child: SizedBox(
                      width: 52,
                      height: 52,
                      child: DogAvatar(
                        instanceId: 'diet-record-prompt',
                        scale: 1.45,
                        cameraControls: false,
                      ),
                    ),
                  ),
                ], // 執行相對應的邏輯計算或設定屬性參數
              ), // 執行相對應的邏輯計算或設定屬性參數
            ), // 執行相對應的邏輯計算或設定屬性參數
          ], // 執行相對應的邏輯計算或設定屬性參數
        ), // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Widget _buildActionPanel(BuildContext context) {
    // 定義用於重複使用的 UI 封裝建構方法
    return Container(
      // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
      height: MediaQuery.of(context).size.height * 0.35, // 執行相對應的邏輯計算或設定屬性參數
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ), // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
      child: Column(
        // 建立垂直排列元件（Column），縱向排列多個子元件
        children: [
          // 執行相對應的邏輯計算或設定屬性參數
          const SizedBox(height: 20), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
          Text(
            "${_selectedDate.month}月${_selectedDate.day}日 飲食記錄",
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ), // 建立文字顯示元件（Text）
          const Spacer(), // 建立編譯期常數，優化 Flutter 渲染效能
          Padding(
            // 建立間距容器（Padding），用於設定內部邊距
            padding: const EdgeInsets.only(
              left: 20,
              right: 20,
              bottom: 50,
            ), // 設定外邊距或內邊距的數值大小（EdgeInsets）
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // 建立水平排列元件（Row），橫向排列多個子元件
                _buildMenuButton(
                  title: "日記",
                  icon: Icons.restaurant,
                  color: const Color.fromARGB(255, 235, 215, 192),
                  onTap: () {
                    setState(() => _showOverlay = false);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => DiaryPage(date: _selectedDate),
                      ),
                    );
                  },
                ), // 更新狀態數據並通知 UI 重新渲染畫面
              ],
            ), // 執行相對應的邏輯計算或設定屬性參數
          ), // 執行相對應的邏輯計算或設定屬性參數
        ], // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Widget _buildMenuButton({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    // 定義用於重複使用的 UI 封裝建構方法
    return GestureDetector(
      // 建立手勢偵測器（GestureDetector），用於監聽點擊、拖動等觸控事件
      onTap: onTap, // 執行相對應的邏輯計算或設定屬性參數
      child: Container(
        // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
        width: 140,
        height: 110, // 執行相對應的邏輯計算或設定屬性參數
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.1),
              blurRadius: 1.95,
              offset: const Offset(0.78, 0.78),
            ),
          ],
        ), // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 45, color: AppColors.textPrimary),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ), // 建立水平排列元件（Row），橫向排列多個子元件
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Widget _buildSPathSegment(int index, double pathWidth, double margin) {
    // 定義用於重複使用的 UI 封裝建構方法
    bool isLeftToRight = index % 2 == 0; // 宣告類別成員或方法內部的區域變數
    return Container(
      // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
      height: 110, // 壓縮高度至 110
      margin: EdgeInsets.symmetric(
        horizontal: margin,
      ), // 設定外邊距或內邊距的數值大小（EdgeInsets）
      child: Stack(
        // 建立層疊佈局元件（Stack），可將多個子元件重疊顯示
        clipBehavior: Clip.none, // 執行相對應的邏輯計算或設定屬性參數
        children: [
          // 執行相對應的邏輯計算或設定屬性參數
          CustomPaint(
            // 執行相對應的邏輯計算或設定屬性參數
            size: const Size(double.infinity, 110), // 建立編譯期常數，優化 Flutter 渲染效能
            painter: GeometricSPathPainter(
              isLeftToRight: isLeftToRight,
            ), // 執行相對應的邏輯計算或設定屬性參數
          ), // 執行相對應的邏輯計算或設定屬性參數
          ..._buildDotsOnGeometricPath(
            index,
            pathWidth,
            isLeftToRight,
          ), // 執行相對應的邏輯計算或設定屬性參數
        ], // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  List<Widget> _buildDotsOnGeometricPath(
    int index,
    double pathWidth,
    bool isLeftToRight,
  ) {
    // 執行相對應的邏輯計算或設定屬性參數
    List<Widget> dots = []; // 執行相對應的邏輯計算或設定屬性參數
    for (int i = 0; i < 5; i++) {
      // 執行相對應的邏輯計算或設定屬性參數
      double t = i / 4.0; // 宣告類別成員或方法內部的區域變數
      double dotX = isLeftToRight
          ? t * pathWidth + 50
          : (1 - t) * pathWidth + 50; // 宣告類別成員或方法內部的區域變數
      DateTime dotDate = _pathDates[index * 5 + i]; // 執行相對應的邏輯計算或設定屬性參數
      // 座標精確對位：線條在 30，圓點中心在 30
      dots.add(
        Positioned(
          left: dotX - 30,
          top: 30 - 45,
          child: _buildDateDot(dotDate),
        ),
      ); // 建立絕對定位元件（Positioned），用於精確設定子元件在 Stack 中的位置
    } // 程式碼區塊或元件結構結束
    return dots; // 回傳建構完成的元件或方法計算結果
  } // 程式碼區塊或元件結構結束

  Widget _buildDateDot(DateTime date) {
    // 定義用於重複使用的 UI 封裝建構方法
    String label = "${date.month}/${date.day}"; // 宣告類別成員或方法內部的區域變數
    bool isSelected =
        date.year == _rippleDate?.year &&
        date.month == _rippleDate?.month &&
        date.day == _rippleDate?.day; // 宣告類別成員或方法內部的區域變數
    double dotSize = isSelected ? 56.0 : 28.0; // 宣告類別成員或方法內部的區域變數

    return GestureDetector(
      // 建立手勢偵測器（GestureDetector），用於監聽點擊、拖動等觸控事件
      behavior: HitTestBehavior.opaque, // 執行相對應的邏輯計算或設定屬性參數
      onTap: () => _scrollToDate(date), // 執行相對應的邏輯計算或設定屬性參數
      child: Column(
        // 建立垂直排列元件（Column），縱向排列多個子元件
        mainAxisSize: MainAxisSize.min, // 執行相對應的邏輯計算或設定屬性參數
        children: [
          // 執行相對應的邏輯計算或設定屬性參數
          Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
          ), // 建立文字顯示元件（Text）
          SizedBox(
            // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
            width: 60,
            height: 60, // 執行相對應的邏輯計算或設定屬性參數
            child: Stack(
              // 建立層疊佈局元件（Stack），可將多個子元件重疊顯示
              alignment: Alignment.center, // 執行相對應的邏輯計算或設定屬性參數
              children: [
                // 執行相對應的邏輯計算或設定屬性參數
                if (isSelected)
                  const RippleAnimation(), // 建立編譯期常數，優化 Flutter 渲染效能
                AnimatedContainer(
                  // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
                  duration: const Duration(
                    milliseconds: 300,
                  ), // 建立編譯期常數，優化 Flutter 渲染效能
                  width: dotSize,
                  height: dotSize, // 執行相對應的邏輯計算或設定屬性參數
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : AppColors.secondary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.4),
                        blurRadius: isSelected ? 2.34 : 1.56,
                        offset: const Offset(0.39, 0.39),
                      ),
                    ],
                  ), // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
                ), // 執行相對應的邏輯計算或設定屬性參數
              ], // 執行相對應的邏輯計算或設定屬性參數
            ), // 執行相對應的邏輯計算或設定屬性參數
          ), // 執行相對應的邏輯計算或設定屬性參數
        ], // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束
} // 程式碼區塊或元件結構結束

class RippleAnimation extends StatefulWidget {
  // 定義 RippleAnimation 類別，繼承自 StatefulWidget
  const RippleAnimation({super.key}); // 建立編譯期常數，優化 Flutter 渲染效能
  @override // 標記此方法為覆寫父類別之方法
  State<RippleAnimation> createState() => _RippleAnimationState(); // 執行相對應的邏輯計算或設定屬性參數
} // 程式碼區塊或元件結構結束

class _RippleAnimationState extends State<RippleAnimation>
    with SingleTickerProviderStateMixin {
  // 定義 _RippleAnimationState 類別，繼承自 State
  late AnimationController _controller; // 宣告類別成員或方法內部的區域變數
  @override // 標記此方法為覆寫父類別之方法
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  } // 初始化狀態生命週期方法，頁面建立時執行一次

  @override // 標記此方法為覆寫父類別之方法
  void dispose() {
    _controller.dispose();
    super.dispose();
  } // 銷毀狀態生命週期方法，釋放頁面資源與控制器

  @override // 標記此方法為覆寫父類別之方法
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Container(
        width: 60,
        height: 60,
        child: CustomPaint(painter: RipplePainter(_controller.value)),
      ),
    );
  } // 建立畫面的主要 build 方法，返回元件樹
} // 程式碼區塊或元件結構結束

class RipplePainter extends CustomPainter {
  // 定義 RipplePainter 類別，繼承自 CustomPainter
  final double animationValue; // 宣告類別成員或方法內部的區域變數
  RipplePainter(this.animationValue); // 執行相對應的邏輯計算或設定屬性參數
  @override // 標記此方法為覆寫父類別之方法
  void paint(Canvas canvas, Size size) {
    // 執行相對應的邏輯計算或設定屬性參數
    for (int i = 0; i < 3; i++) {
      // 執行相對應的邏輯計算或設定屬性參數
      double value = (animationValue + i / 3.0) % 1.0; // 宣告類別成員或方法內部的區域變數
      double radius = (size.width / 2 + 15) * value; // 宣告類別成員或方法內部的區域變數
      double opacity = (1.0 - value).clamp(0.0, 1.0); // 宣告類別成員或方法內部的區域變數
      final paint = Paint()
        ..color = AppColors.accent.withOpacity(opacity * 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5; // 設定顏色數值（Color）
      canvas.drawCircle(
        Offset(size.width / 2, size.height / 2),
        radius,
        paint,
      ); // 執行相對應的邏輯計算或設定屬性參數
    } // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  @override // 標記此方法為覆寫父類別之方法
  bool shouldRepaint(RipplePainter oldDelegate) => true; // 宣告類別成員或方法內部的區域變數
} // 程式碼區塊或元件結構結束

class GeometricSPathPainter extends CustomPainter {
  // 定義 GeometricSPathPainter 類別，繼承自 CustomPainter
  final bool isLeftToRight; // 宣告類別成員或方法內部的區域變數
  GeometricSPathPainter({required this.isLeftToRight}); // 執行相對應的邏輯計算或設定屬性參數
  @override // 標記此方法為覆寫父類別之方法
  void paint(Canvas canvas, Size size) {
    // 執行相對應的邏輯計算或設定屬性參數
    final paint = Paint()
      ..color = const Color(0xFFFCF8EC)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round; // 設定顏色數值（Color）
    const double radius = 50.0; // 建立編譯期常數，優化 Flutter 渲染效能
    double pathWidth = size.width - (radius * 2); // 宣告類別成員或方法內部的區域變數
    // 對接邏輯：線條在 30，弧線高度 110，總高 110。
    // 這樣下一段起始於 110，內部的線條也位於 30 (110+30 = 140)，與上一段弧線結尾 (30+110 = 140) 完美接合
    if (isLeftToRight) {
      // 執行相對應的邏輯計算或設定屬性參數
      canvas.drawLine(
        const Offset(50, 30),
        Offset(50 + pathWidth, 30),
        paint,
      ); // 建立編譯期常數，優化 Flutter 渲染效能
      canvas.drawArc(
        Rect.fromLTWH(50 + pathWidth - radius, 30, radius * 2, 110),
        -math.pi / 2,
        math.pi,
        false,
        paint,
      ); // 執行相對應的邏輯計算或設定屬性參數
    } else {
      // 程式碼區塊或元件結構結束
      canvas.drawLine(
        Offset(50 + pathWidth, 30),
        const Offset(50, 30),
        paint,
      ); // 建立編譯期常數，優化 Flutter 渲染效能
      canvas.drawArc(
        Rect.fromLTWH(50 - radius, 30, radius * 2, 110),
        -math.pi / 2,
        -math.pi,
        false,
        paint,
      ); // 執行相對應的邏輯計算或設定屬性參數
    } // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  @override // 標記此方法為覆寫父類別之方法
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false; // 宣告類別成員或方法內部的區域變數
} // 程式碼區塊或元件結構結束
