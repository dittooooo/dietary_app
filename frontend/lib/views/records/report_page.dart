import 'package:flutter/material.dart'; // 匯入 material.dart 元件庫或套件
import 'dart:ui'; // 匯入 dart:ui 元件庫或套件
import 'dart:math' as math; // 匯入 dart:math 元件庫或套件
import 'dart:convert'; // 匯入 json 處理套件
import '../auth/profile_page.dart'; // 匯入 profile_page.dart 元件庫或套件
import '../home/home_page.dart';
import '../../color/app_colors.dart'; // 匯入 app_colors.dart 元件庫或套件
import '../../controllers/dog_state_controller.dart';
import '../../widgets/dog_avatar.dart';
import '../../services/diet_service.dart'; // 匯入 diet_service.dart

import 'package:shared_preferences/shared_preferences.dart';
import '../../services/auth_service.dart';
import '../../config/api_config.dart';
import 'package:flutter/foundation.dart';

class ReportPage extends StatefulWidget { // 定義 ReportPage 類別，繼承自 StatefulWidget
  final DateTime? initialDate;
  final ValueListenable<DateTime>? selectedDateListenable;
  final ValueChanged<DateTime>? onDateChanged;
  const ReportPage({
    super.key,
    this.initialDate,
    this.selectedDateListenable,
    this.onDateChanged,
  });

  @override // 標記此方法為覆寫父類別之方法
  State<ReportPage> createState() => _ReportPageState(); // 執行相對應的邏輯計算或設定屬性參數
} // 程式碼區塊或元件結構結束

class _ReportPageState extends State<ReportPage> with TickerProviderStateMixin { // 定義 _ReportPageState 類別，繼承自 State
  late DateTime _selectedDate;
  int _viewType = 0; // 0: 今日, 1: 一週
  int? _hoveredIdx; // 用於追蹤圖表上被點擊/懸停的點

  late AnimationController _hoverController; // 宣告類別成員或方法內部的區域變數
  late Animation<double> _hoverScaleAnimation; // 宣告類別成員或方法內部的區域變數
  late Animation<double> _hoverOffsetAnimation; // 宣告類別成員或方法內部的區域變數
  final DogStateController _dogController = DogStateController.instance;

  List<dynamic> _allRecords = [];
  bool _isLoading = false;
  List<double> _weeklyData = [];
  List<double> _monthlyData = [];
  String? _avatarUrl;

  Future<void> _loadAvatar() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _avatarUrl = prefs.getString('user_avatar_url');
      });
    }
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
  }

  @override // 標記此方法為覆寫父類別之方法
  void initState() { // 初始化狀態生命週期方法，頁面建立時執行一次
    super.initState(); // 執行相對應的邏輯計算或設定屬性參數
    _selectedDate = widget.selectedDateListenable?.value ??
        widget.initialDate ??
        DateTime.now();
    widget.selectedDateListenable?.addListener(_handleSharedDateChanged);
    _dogController.setState(DogAnimationState.idle);
    _loadAvatar();
    
    // 初始化呼吸與懸浮動畫
    _hoverController = AnimationController( // 執行相對應的邏輯計算或設定屬性參數
      duration: const Duration(milliseconds: 2000), // 建立編譯期常數，優化 Flutter 渲染效能
      vsync: this, // 執行相對應的邏輯計算或設定屬性參數
    )..repeat(reverse: true); // 執行相對應的邏輯計算或設定屬性參數

    _hoverScaleAnimation = Tween<double>(begin: 0.97, end: 1.03).animate( // 執行相對應的邏輯計算或設定屬性參數
      CurvedAnimation(parent: _hoverController, curve: Curves.easeInOut), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束

    _hoverOffsetAnimation = Tween<double>(begin: -5.0, end: 5.0).animate( // 執行相對應的邏輯計算或設定屬性參數
      CurvedAnimation(parent: _hoverController, curve: Curves.easeInOut), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束

    _fetchRecords();
  }

  Future<void> _fetchRecords() async {
    setState(() => _isLoading = true);
    try {
      final records = await DietService().getMyDietRecords();
      setState(() {
        _allRecords = records;
      });
      _processRecords();
    } catch (e) {
      debugPrint('加載飲食報告失敗: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  double _getCaloriesFromRecord(dynamic record) {
    if (record == null) return 0.0;

    if (record['calories'] != null) {
      final val = double.tryParse(record['calories'].toString());
      if (val != null && val > 0) return val;
    }
    
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

    return dishName.toString().trim().isNotEmpty ? 380.0 : 0.0;
  }

  double _getNutrientFromRecord(dynamic record, String pattern) {
    if (record == null) return 0.0;

    String englishKey = '';
    if (pattern.contains('蛋白質') || pattern.contains('protein')) {
      englishKey = 'protein';
    } else if (pattern.contains('脂肪') || pattern.contains('fat')) {
      englishKey = 'fat';
    } else if (pattern.contains('碳水') || pattern.contains('carbohydrate') || pattern.contains('carb')) {
      englishKey = 'carbohydrates';
    }

    if (englishKey.isNotEmpty && record[englishKey] != null) {
      final val = double.tryParse(record[englishKey].toString());
      if (val != null && val > 0) return val;
    }

    final nutrition = record['nutrition'];
    if (nutrition == null) return 0.0;

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

  double _getProteinFromRecord(dynamic record) {
    return _getNutrientFromRecord(record, r'(?:蛋白質|protein)');
  }

  double _getFatFromRecord(dynamic record) {
    return _getNutrientFromRecord(record, r'(?:脂肪|fat)');
  }

  double _getCarbsFromRecord(dynamic record) {
    return _getNutrientFromRecord(record, r'(?:碳水化合物|碳水|carbohydrate|carbs)');
  }

  void _processRecords() {
    // 1. Weekly data: Sunday to Saturday of the week containing the selected date.
    final sundayOffset = _selectedDate.weekday % 7;
    final sunday = _selectedDate.subtract(Duration(days: sundayOffset));
    List<double> weekly = [];
    for (int i = 0; i < 7; i++) {
      final targetDate = sunday.add(Duration(days: i));
      double dailyTotal = 0.0;
      for (var record in _allRecords) {
        final rDate = _getRecordDate(record);
        if (rDate == null) continue;
        if (rDate.year == targetDate.year &&
            rDate.month == targetDate.month &&
            rDate.day == targetDate.day) {
          dailyTotal += _getCaloriesFromRecord(record);
        }
      }
      weekly.add(dailyTotal);
    }

    // 2. Monthly data: from the selected date - 29 days to the selected date.
    List<double> monthly = [];
    for (int i = 29; i >= 0; i--) {
      final targetDate = _selectedDate.subtract(Duration(days: i));
      double dailyTotal = 0.0;
      for (var record in _allRecords) {
        final rDate = _getRecordDate(record);
        if (rDate == null) continue;
        if (rDate.year == targetDate.year &&
            rDate.month == targetDate.month &&
            rDate.day == targetDate.day) {
          dailyTotal += _getCaloriesFromRecord(record);
        }
      }
      monthly.add(dailyTotal);
    }

    setState(() {
      _weeklyData = weekly;
      _monthlyData = monthly;
    });
  }

  @override // 標記此方法為覆寫父類別之方法
  void dispose() { // 銷毀狀態生命週期方法，釋放頁面資源與控制器
    widget.selectedDateListenable?.removeListener(_handleSharedDateChanged);
    _hoverController.dispose(); // 執行相對應的邏輯計算或設定屬性參數
    super.dispose(); // 執行相對應的邏輯計算或設定屬性參數
  } // 程式碼區塊或元件結構結束



  String get _viewLabel { // 宣告類別成員或方法內部的區域變數
    if (_viewType == 1) return "本週"; // 回傳建構完成的元件或方法計算結果
    return "今日"; // 回傳建構完成的元件或方法計算結果
  } // 程式碼區塊或元件結構結束

  String get _dateDisplay { // 宣告類別成員或方法內部的區域變數
    if (_viewType == 0) { // 執行相對應的邏輯計算或設定屬性參數
      return "${_selectedDate.year}年 ${_selectedDate.month.toString().padLeft(2, '0')}月 ${_selectedDate.day.toString().padLeft(2, '0')}日"; // 回傳建構完成的元件或方法計算結果
    } else { // 程式碼區塊或元件結構結束
      DateTime startDate = _selectedDate.subtract(Duration(days: _selectedDate.weekday % 7));
      DateTime endDate = startDate.add(const Duration(days: 6));
      return "${startDate.year}年 ${startDate.month.toString().padLeft(2, '0')}月 ${startDate.day.toString().padLeft(2, '0')}日 - ${endDate.year == startDate.year ? '' : '${endDate.year}年 '}${endDate.month.toString().padLeft(2, '0')}月 ${endDate.day.toString().padLeft(2, '0')}日"; // 回傳建構完成的元件或方法計算結果
    } // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  void _handleSharedDateChanged() {
    final sharedDate = widget.selectedDateListenable?.value;
    if (sharedDate == null ||
        (sharedDate.year == _selectedDate.year &&
            sharedDate.month == _selectedDate.month &&
            sharedDate.day == _selectedDate.day)) {
      return;
    }

    setState(() {
      _selectedDate = sharedDate;
      _hoveredIdx = null;
    });
    _processRecords();
  }

  Future<void> _changeDate() async {
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
    setState(() {
      _selectedDate = picked;
      _hoveredIdx = null;
    });
    widget.onDateChanged?.call(picked);
    _processRecords();
  }

  Widget _buildTabButton(String label, bool isSelected) { // 定義用於重複使用的 UI 封裝建構方法
    return Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8), // 設定外邊距或內邊距的數值大小（EdgeInsets）
      decoration: BoxDecoration( // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
        color: isSelected ? AppColors.primary : Colors.transparent, // 設定顏色數值（Color）
        borderRadius: BorderRadius.circular(20), // 設定容器的圓角弧度半徑大小
      ), // 執行相對應的邏輯計算或設定屬性參數
      child: Text( // 建立文字顯示元件（Text）
        label,  // 執行相對應的邏輯計算或設定屬性參數
        style: TextStyle( // 設定文字字體大小、顏色與粗細等字型樣式（TextStyle）
          color: isSelected ? AppColors.background : AppColors.textPrimary,  // 設定顏色數值（Color）
          fontWeight: FontWeight.bold // 執行相對應的邏輯計算或設定屬性參數
        ) // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  @override // 標記此方法為覆寫父類別之方法
  Widget build(BuildContext context) { // 建立畫面的主要 build 方法，返回元件樹
    return Scaffold( // 建立頁面的基礎 Scaffold 骨架，提供頁面基本版面佈局
      backgroundColor: const Color(0xFFE7D9B1), // 設定顏色數值（Color）
      body: Stack( // 設定頁面的主要內容區域（body）
        children: [ // 執行相對應的邏輯計算或設定屬性參數
          Positioned.fill( // 執行相對應的邏輯計算或設定屬性參數
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : SingleChildScrollView( // 建立單一元件滾動視圖（SingleChildScrollView），防止內容超出螢幕時溢出
                    child: Column( // 建立垂直排列元件（Column），縱向排列多個子元件
                children: [ // 執行相對應的邏輯計算或設定屬性參數
                  SizedBox(height: 80 + MediaQuery.of(context).padding.top + 16), // 動態計算：網底標題高度(80) + 狀態列高度 + 間距(16)
                  Text(_dateDisplay, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)), // 建立文字顯示元件（Text）
                  if (_viewType == 0) ...[ // 執行相對應的邏輯計算或設定屬性參數
                    const SizedBox(height: 20), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
                    AnimatedBuilder( // 建立動畫建構器（AnimatedBuilder），依照動畫進度重新整理局部 UI
                      animation: _hoverController, // 執行相對應的邏輯計算或設定屬性參數
                      builder: (context, child) { // 執行相對應的邏輯計算或設定屬性參數
                        return Transform.translate( // 回傳建構完成的元件或方法計算結果
                          offset: Offset(0, _hoverOffsetAnimation.value), // 執行相對應的邏輯計算或設定屬性參數
                          child: Transform.scale( // 執行相對應的邏輯計算或設定屬性參數
                            scale: _hoverScaleAnimation.value, // 執行相對應的邏輯計算或設定屬性參數
                            child: Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
                              width: 240, // 執行相對應的邏輯計算或設定屬性參數
                              height: 240, // 執行相對應的邏輯計算或設定屬性參數
                              decoration: BoxDecoration( // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
                                shape: BoxShape.circle, // 執行相對應的邏輯計算或設定屬性參數
                                color: Colors.white, // 設定顏色數值（Color）
                                boxShadow: [ // 執行相對應的邏輯計算或設定屬性參數
                                  BoxShadow( // 設定容器的陰影效果，包括顏色、模糊半徑與偏移量
                                    color: Colors.black.withOpacity(0.05), // 設定顏色數值（Color）
                                    blurRadius: 10, // 執行相對應的邏輯計算或設定屬性參數
                                    spreadRadius: 1, // 執行相對應的邏輯計算或設定屬性參數
                                  ) // 執行相對應的邏輯計算或設定屬性參數
                                ], // 執行相對應的邏輯計算或設定屬性參數
                              ), // 執行相對應的邏輯計算或設定屬性參數
                              child: Padding( // 建立間距容器（Padding），用於設定內部邊距
                                padding: const EdgeInsets.all(20.0), // 設定外邊距或內邊距的數值大小（EdgeInsets）
                                child: DogAvatar(
                                  controller: _dogController,
                                  scale: 1.5,
                                  instanceId: 'report-idle-dog',
                                ),
                              ), // 執行相對應的邏輯計算或設定屬性參數
                            ), // 執行相對應的邏輯計算或設定屬性參數
                          ), // 執行相對應的邏輯計算或設定屬性參數
                        ); // 程式碼區塊或元件結構結束
                      }, // 程式碼區塊或元件結構結束
                    ), // 執行相對應的邏輯計算或設定屬性參數
                    const SizedBox(height: 15), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
                  ], // 執行相對應的邏輯計算或設定屬性參數
                  const SizedBox(height: 30), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
                  Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
                    margin: const EdgeInsets.symmetric(horizontal: 16), // 設定外邊距或內邊距的數值大小（EdgeInsets）
                    padding: const EdgeInsets.all(20), // 設定外邊距或內邊距的數值大小（EdgeInsets）
                    decoration: BoxDecoration( // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
                      color: AppColors.background, // 建立編譯期常數，優化 Flutter 渲染效能
                      borderRadius: BorderRadius.circular(25), // 設定容器的圓角弧度半徑大小
                      boxShadow: [ // 執行相對應的邏輯計算或設定屬性參數
                        BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2.925, offset: const Offset(0, 1.56)), // 設定容器的陰影效果，包括顏色、模糊半徑與偏移量
                      ], // 執行相對應的邏輯計算或設定屬性參數
                    ), // 執行相對應的邏輯計算或設定屬性參數
                    child: Column( // 建立垂直排列元件（Column），縱向排列多個子元件
                      children: [ // 執行相對應的邏輯計算或設定屬性參數
                        Row( // 建立水平排列元件（Row），橫向排列多個子元件
                          mainAxisAlignment: MainAxisAlignment.center, // 執行相對應的邏輯計算或設定屬性參數
                          children: [ // 執行相對應的邏輯計算或設定屬性參數
                            GestureDetector(onTap: () => setState(() { _viewType = 0; _hoveredIdx = null; }), child: _buildTabButton("日", _viewType == 0)), // 更新狀態數據並通知 UI 重新渲染畫面
                            GestureDetector(onTap: () => setState(() { _viewType = 1; _hoveredIdx = null; }), child: _buildTabButton("週", _viewType == 1)), // 更新狀態數據並通知 UI 重新渲染畫面
                          ], // 執行相對應的邏輯計算或設定屬性參數
                        ), // 執行相對應的邏輯計算或設定屬性參數
                        const SizedBox(height: 20), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
                        _viewType == 0 ? _buildTodayStats() : _buildTrendChart(), // 執行相對應的邏輯計算或設定屬性參數
                      ], // 執行相對應的邏輯計算或設定屬性參數
                    ), // 執行相對應的邏輯計算或設定屬性參數
                  ), // 執行相對應的邏輯計算或設定屬性參數
                  const SizedBox(height: 20), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）

                  // 2.5 總結數據區域 (僅限週/月)
                  if (_viewType != 0) ...[ // 執行相對應的邏輯計算或設定屬性參數
                    _buildAggregatedStats(), // 執行相對應的邏輯計算或設定屬性參數
                    const SizedBox(height: 20), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
                  ], // 執行相對應的邏輯計算或設定屬性參數
                  
                  // 3. 總結數據卡片
                  Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
                    width: double.infinity, // 執行相對應的邏輯計算或設定屬性參數
                    margin: const EdgeInsets.symmetric(horizontal: 16), // 設定外邊距或內邊距的數值大小（EdgeInsets）
                    padding: const EdgeInsets.all(20), // 設定外邊距或內邊距的數值大小（EdgeInsets）
                    decoration: BoxDecoration( // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
                      color: AppColors.background, // 建立編譯期常數，優化 Flutter 渲染效能
                      borderRadius: BorderRadius.circular(25), // 設定容器的圓角弧度半徑大小
                      boxShadow: [ // 執行相對應的邏輯計算或設定屬性參數
                        BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2.925, offset: const Offset(0, 1.56)), // 設定容器的陰影效果，包括顏色、模糊半徑與偏移量
                      ] // 執行相對應的邏輯計算或設定屬性參數
                    ), // 執行相對應的邏輯計算或設定屬性參數
                    child: Column( // 建立垂直排列元件（Column），縱向排列多個子元件
                      crossAxisAlignment: CrossAxisAlignment.start, // 執行相對應的邏輯計算或設定屬性參數
                      children: [ // 執行相對應的邏輯計算或設定屬性參數
                        Text("${_viewLabel}總結", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)), // 建立文字顯示元件（Text）
                        const SizedBox(height: 10), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
                        Text( // 建立文字顯示元件（Text）
                          _viewType == 0 ? "您的攝取量穩定，建議增加膳食纖維。" : "${_viewLabel}攝取量穩定，繼續保持！",  // 執行相對應的邏輯計算或設定屬性參數
                          style: const TextStyle(color: AppColors.textPrimary) // 設定文字字體大小、顏色與粗細等字型樣式（TextStyle）
                        ), // 執行相對應的邏輯計算或設定屬性參數
                      ], // 執行相對應的邏輯計算或設定屬性參數
                    ), // 執行相對應的邏輯計算或設定屬性參數
                  ), // 執行相對應的邏輯計算或設定屬性參數
                  const SizedBox(height: 25), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）

                  // 新增：飲食明細 Grid 呈現
                  _buildEatenFoodGrid(),
                  const SizedBox(height: 40), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
                ], // 執行相對應的邏輯計算或設定屬性參數
              ), // 執行相對應的邏輯計算或設定屬性參數
            ), // 執行相對應的邏輯計算或設定屬性參數
          ), // 執行相對應的邏輯計算或設定屬性參數
          // Header omitted for brevity in thought, but should be kept in full file
          _buildHeader(context), // 執行相對應的邏輯計算或設定屬性參數
        ], // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Widget _buildHeader(BuildContext context) {
    final double statusBarHeight = MediaQuery.of(context).padding.top;
    return Positioned(
      top: 0, left: 0, right: 0,
      child: ClipRect(
        child: Container(
          height: 80 + statusBarHeight,
          decoration: BoxDecoration(
            color: AppColors.background,
            border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
          ),
          padding: EdgeInsets.fromLTRB(16, statusBarHeight + 10, 16, 10),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                left: 0,
                child: IconButton(
                  onPressed: () {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                        builder: (context) => HomePage(initialIndex: 1),
                      ),
                      (route) => false,
                    );
                  },
                  icon: const Icon(Icons.arrow_back_ios, size: 28, color: AppColors.textPrimary),
                ),
              ),
              const Text(
                '飲食報告',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                  letterSpacing: 1.2,
                ),
              ),
              Positioned(
                right: 0,
                child: IconButton(
                  tooltip: '更改日期',
                  onPressed: _changeDate,
                  icon: const Icon(Icons.calendar_month_outlined,
                      color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileAvatar(BuildContext context) { // 定義用於重複使用的 UI 封裝建構方法
    return GestureDetector( // 建立手勢偵測器（GestureDetector），用於監聽點擊、拖動等觸控事件
      onTap: () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => HomePage(initialIndex: 3)), (route) => false),
      child: Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
        decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 2.925, offset: const Offset(0, 1.56))]), // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
        child: CircleAvatar(
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
    ); // 程式碼區塊或元件結構結束
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

  // --- 總結數據區域 (週/月) ---
  Widget _buildAggregatedStats() {
    double breakfastCal = 0.0;
    double lunchCal = 0.0;
    double dinnerCal = 0.0;
    double otherCal = 0.0;

    final DateTime startDate = _selectedDate.subtract(Duration(days: _selectedDate.weekday % 7));
    final DateTime endDate = startDate.add(const Duration(days: 6));
    
    final DateTime startLimit = DateTime(startDate.year, startDate.month, startDate.day, 0, 0, 0);
    final DateTime endLimit = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);

    for (var record in _allRecords) {
      final rDate = _getRecordDate(record);
      if (rDate == null) continue;
      try {
        if (rDate.isAfter(startLimit.subtract(const Duration(seconds: 1))) &&
            rDate.isBefore(endLimit.add(const Duration(seconds: 1)))) {
          final String meal = (record['mealType'] ?? record['meal'] ?? '').toString().toUpperCase();
          final double cal = _getCaloriesFromRecord(record);
          if (meal.contains('BREAKFAST') || meal.contains('早')) {
            breakfastCal += cal;
          } else if (meal.contains('LUNCH') || meal.contains('午')) {
            lunchCal += cal;
          } else if (meal.contains('DINNER') || meal.contains('晚')) {
            dinnerCal += cal;
          } else {
            otherCal += cal;
          }
        }
      } catch (_) {}
    }

    final double totalCal = breakfastCal + lunchCal + dinnerCal + otherCal;
    int bPercent = 0;
    int lPercent = 0;
    int dPercent = 0;
    int oPercent = 0;
    
    if (totalCal > 0) {
      bPercent = ((breakfastCal / totalCal) * 100).round();
      lPercent = ((lunchCal / totalCal) * 100).round();
      dPercent = ((dinnerCal / totalCal) * 100).round();
      oPercent = 100 - bPercent - lPercent - dPercent;
    }

    List<Widget> barChildren = [];
    if (totalCal > 0) {
      if (bPercent > 0) {
        barChildren.add(Expanded(
          flex: bPercent,
          child: Container(color: Colors.orange, child: const Center(child: Text("早餐", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)))),
        ));
      }
      if (lPercent > 0) {
        barChildren.add(Expanded(
          flex: lPercent,
          child: Container(color: Colors.green, child: const Center(child: Text("午餐", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)))),
        ));
      }
      if (dPercent > 0) {
        barChildren.add(Expanded(
          flex: dPercent,
          child: Container(color: Colors.blue, child: const Center(child: Text("晚餐", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)))),
        ));
      }
      if (oPercent > 0) {
        barChildren.add(Expanded(
          flex: oPercent,
          child: Container(color: Colors.grey, child: const Center(child: Text("其他", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)))),
        ));
      }
    } else {
      barChildren.add(Expanded(
        child: Container(color: Colors.grey.shade300, child: const Center(child: Text("暫無攝取資料", style: TextStyle(color: Colors.black54, fontSize: 12, fontWeight: FontWeight.bold)))),
      ));
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.background, // 鵝黃色背景
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2.925, offset: const Offset(0, 1.56)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("總結數據", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 25),
          
          // 1. 先顯示分段比例進度條
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 40,
              child: Row(
                children: barChildren,
              ),
            ),
          ),
          
          const SizedBox(height: 30),

          // 2. 後顯示條列式詳細數據
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: const [
              Padding(
                padding: EdgeInsets.only(right: 4),
                child: Text("千卡", style: TextStyle(fontSize: 13, color: Colors.black54, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 5),
          _buildDetailRow("早餐", "($bPercent%)", breakfastCal.round().toString(), Colors.orange),
          const SizedBox(height: 12),
          _buildDetailRow("午餐", "($lPercent%)", lunchCal.round().toString(), Colors.green),
          const SizedBox(height: 12),
          _buildDetailRow("晚餐", "($dPercent%)", dinnerCal.round().toString(), Colors.blue),
          const SizedBox(height: 12),
          _buildDetailRow("其他", "($oPercent%)", otherCal.round().toString(), Colors.grey),
        ],
      ),
    );
  }


  Widget _buildDetailRow(String label, String percentage, String calories, Color color) { // 建立水平排列元件（Row），橫向排列多個子元件
    return Row( // 建立水平排列元件（Row），橫向排列多個子元件
      children: [ // 執行相對應的邏輯計算或設定屬性參數
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)), // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
        const SizedBox(width: 10), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
        SizedBox(width: 50, child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold))), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
        const SizedBox(width: 10), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
        Text(percentage, style: const TextStyle(fontSize: 14, color: AppColors.textPrimary)), // 建立文字顯示元件（Text）
        const Spacer(), // 建立編譯期常數，優化 Flutter 渲染效能
        Text(calories, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)), // 建立文字顯示元件（Text）
      ], // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Widget _buildTodayStats() {
    double todayCal = 0.0;
    double todayProtein = 0.0;
    double todayFat = 0.0;
    double todayCarbs = 0.0;

    for (var record in _allRecords) {
      final rDate = _getRecordDate(record);
      if (rDate == null) continue;
      try {
        if (rDate.year == _selectedDate.year &&
            rDate.month == _selectedDate.month &&
            rDate.day == _selectedDate.day) {
          todayCal += _getCaloriesFromRecord(record);
          todayProtein += _getProteinFromRecord(record);
          todayFat += _getFatFromRecord(record);
          todayCarbs += _getCarbsFromRecord(record);
        }
      } catch (_) {}
    }
    int current = todayCal.round();

    // 依據三大營養素提供之卡路里計算熱量比例 (1g 蛋白質=4kcal, 1g 碳水=4kcal, 1g 脂肪=9kcal)
    final double pCal = todayProtein * 4;
    final double fCal = todayFat * 9;
    final double cCal = todayCarbs * 4;
    final double macroTotalCal = pCal + fCal + cCal;

    int carbsPercent = 0;
    int proteinPercent = 0;
    int fatPercent = 0;

    if (macroTotalCal > 0) {
      carbsPercent = ((cCal / macroTotalCal) * 100).round();
      proteinPercent = ((pCal / macroTotalCal) * 100).round();
      fatPercent = 100 - carbsPercent - proteinPercent;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. 卡路里熱量弧形表 (三區間: 偏低 / 適量 / 偏高)
        _buildCalorieArcGaugeCard(current),

        const SizedBox(height: 20),

        // 2. 三大營養素柱狀圖
        _buildMacronutrientBarChartCard(
          carbsPercent: carbsPercent,
          proteinPercent: proteinPercent,
          fatPercent: fatPercent,
          todayCarbs: todayCarbs,
          todayProtein: todayProtein,
          todayFat: todayFat,
        ),
      ],
    );
  }

  // --- 卡路里弧形表元件 ---
  Widget _buildCalorieArcGaugeCard(int currentCalories) {
    String statusText;
    Color statusColor;
    IconData statusIcon;

    if (currentCalories < 1700) {
      statusText = "熱量攝取偏低，建議多補充熱量！";
      statusColor = const Color(0xFF7C83FD);
      statusIcon = Icons.info_outline;
    } else if (currentCalories <= 2000) {
      statusText = "熱量攝取適中，繼續保持！";
      statusColor = const Color(0xFF52C41A);
      statusIcon = Icons.check_circle_outline;
    } else {
      statusText = "熱量攝取偏高，請注意控制！";
      statusColor = const Color(0xFFFF7A45);
      statusIcon = Icons.warning_amber_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border.withOpacity(0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 標題
          const Text(
            "今日熱量",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
          ),

          const SizedBox(height: 15),

          // 弧形半圓表儀表板
          Center(
            child: SizedBox(
              width: 260,
              height: 135,
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  CustomPaint(
                    size: const Size(260, 135),
                    painter: CalorieGaugeArcPainter(currentCalories: currentCalories.toDouble()),
                  ),
                  Positioned(
                    bottom: 12,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text("約", style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
                        Text(
                          currentCalories.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},'),
                          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.textPrimary, height: 1.1),
                        ),
                        const Text("kcal", style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // 偏低、適量、偏高 三區間說明欄
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildGaugeZoneLabel("偏低", "< 1,700 kcal", const Color(0xFF7C83FD)),
              _buildGaugeZoneLabel("適量", "1,700 - 2,000 kcal", const Color(0xFF52C41A)),
              _buildGaugeZoneLabel("偏高", "> 2,000 kcal", const Color(0xFFFF7A45)),
            ],
          ),

          const SizedBox(height: 16),

          // 底部建議狀態膠囊
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: statusColor.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(statusIcon, color: statusColor, size: 18),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    statusText,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: statusColor),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
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
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color),
        ),
        const SizedBox(height: 2),
        Text(
          rangeStr,
          style: const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  // --- 三大營養素柱狀圖元件 ---
  Widget _buildMacronutrientBarChartCard({
    required int carbsPercent,
    required int proteinPercent,
    required int fatPercent,
    required double todayCarbs,
    required double todayProtein,
    required double todayFat,
  }) {
    String adviceText;
    if (proteinPercent < 20) {
      adviceText = "蛋白質攝取稍少，可以適量增加優質蛋白質來源，如雞胸肉、豆腐、魚類等。";
    } else if (carbsPercent > 60) {
      adviceText = "碳水化合物比例較高，建議適量減少精緻澱粉攝取。";
    } else if (fatPercent > 35) {
      adviceText = "脂肪攝取比例稍高，建議選擇清蒸或煎烤烹調方式。";
    } else {
      adviceText = "三大營養素比例非常均衡，請繼續保持優良飲食習慣！";
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border.withOpacity(0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "今日三大營養素比例",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
          ),

          const SizedBox(height: 16),

          // 圖例顏色標籤
          Row(
            children: [
              _buildLegendDot(const Color(0xFF7C83FD), "碳水化合物"),
              const SizedBox(width: 14),
              _buildLegendDot(const Color(0xFFFF7A45), "蛋白質"),
              const SizedBox(width: 14),
              _buildLegendDot(const Color(0xFFFFB800), "脂肪"),
            ],
          ),

          const SizedBox(height: 20),

          // 柱狀圖與 Y 軸刻度區域
          SizedBox(
            height: 190,
            child: Stack(
              children: [
                // 背景 100%, 75%, 50%, 25%, 0% 網格虛線
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

                // 三支柱狀圖
                Padding(
                  padding: const EdgeInsets.only(left: 45, right: 15, bottom: 25),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _buildSingleBarItem("碳水化合物", carbsPercent, todayCarbs, const Color(0xFF7C83FD)),
                      _buildSingleBarItem("蛋白質", proteinPercent, todayProtein, const Color(0xFFFF7A45)),
                      _buildSingleBarItem("脂肪", fatPercent, todayFat, const Color(0xFFFFB800)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // 底部建議提示框 (帶黃色電燈泡)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.withOpacity(0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lightbulb_outline, color: Colors.amber, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    adviceText,
                    style: const TextStyle(fontSize: 12, color: AppColors.textPrimary, fontWeight: FontWeight.w500, height: 1.4),
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.grey, size: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
      ],
    );
  }

  Widget _buildDashedGridLine(String label) {
    return Row(
      children: [
        SizedBox(
          width: 38,
          child: Text(label, style: const TextStyle(fontSize: 10, color: Colors.black45, fontWeight: FontWeight.w500)),
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

  Widget _buildSingleBarItem(String label, int pct, double grams, Color color) {
    const double maxBarHeight = 110.0;
    final double barHeight = (pct / 100.0 * maxBarHeight).clamp(6.0, maxBarHeight);

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // 柱狀圖頂部百分比數字
        Text(
          "$pct%",
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 4),

        // 圓角柱體
        Container(
          width: 52,
          height: barHeight,
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            boxShadow: [
              BoxShadow(color: color.withOpacity(0.25), blurRadius: 4, offset: const Offset(0, 2)),
            ],
          ),
        ),
        const SizedBox(height: 6),

        // 底部營養素名稱與公克數
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        const SizedBox(height: 1),
        Text("約 ${grams.round()} g", style: const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w500)),
      ],
    );
  } // 程式碼區塊或元件結構結束

  /*
  Widget _buildNutrientLegendItem(String label, String value, Color color) { // 定義用於重複使用的 UI 封裝建構方法
    return Row(children: [Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)), const SizedBox(width: 8), Text("$label $value", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary))]); // 建立水平排列元件（Row），橫向排列多個子元件
  } // 程式碼區塊或元件結構結束
  */

  Widget _buildTrendChart() { // 定義用於重複使用的 UI 封裝建構方法
    List<double> data = _viewType == 1 ? _weeklyData : _monthlyData; // 執行相對應的邏輯計算或設定屬性參數
    if (data.isEmpty) return const SizedBox(height: 200, child: Center(child: Text("暫無資料"))); // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）

    double sum = 0; // 宣告類別成員或方法內部的區域變數
    for (double v in data) { // 執行相對應的邏輯計算或設定屬性參數
      sum += v; // 執行相對應的邏輯計算或設定屬性參數
    } // 程式碼區塊或元件結構結束
    double avg = sum / data.length; // 宣告類別成員或方法內部的區域變數

    return Column( // 建立垂直排列元件（Column），縱向排列多個子元件
      crossAxisAlignment: CrossAxisAlignment.start, // 執行相對應的邏輯計算或設定屬性參數
      children: [ // 執行相對應的邏輯計算或設定屬性參數
        Text("平均攝取卡路里 ${avg.toInt()}", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary)), // 建立文字顯示元件（Text）
        const SizedBox(height: 10), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
        LayoutBuilder( // 執行相對應的邏輯計算或設定屬性參數
          builder: (context, constraints) { // 執行相對應的邏輯計算或設定屬性參數
            final sundayOffset = _selectedDate.weekday % 7;
            final sunday = _selectedDate.subtract(Duration(days: sundayOffset));
            final weekdaysZh = ["日", "一", "二", "三", "四", "五", "六"];
            List<String> labels = [];
            for (int i = 0; i < 7; i++) {
              final d = sunday.add(Duration(days: i));
              labels.add("${d.month}/${d.day}\n(${weekdaysZh[i]})");
            }

            return MouseRegion( // 回傳建構完成的元件或方法計算結果
              onHover: (event) => _handleTouch(event.localPosition, constraints.maxWidth, data.length), // 執行相對應的邏輯計算或設定屬性參數
              onExit: (_) => setState(() => _hoveredIdx = null), // 更新狀態數據並通知 UI 重新渲染畫面
              child: GestureDetector( // 建立手勢偵測器（GestureDetector），用於監聽點擊、拖動等觸控事件
                onPanUpdate: (details) => _handleTouch(details.localPosition, constraints.maxWidth, data.length), // 執行相對應的邏輯計算或設定屬性參數
                onTapDown: (details) => _handleTouch(details.localPosition, constraints.maxWidth, data.length), // 執行相對應的邏輯計算或設定屬性參數
                child: SizedBox( // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
                  height: 220, // 執行相對應的邏輯計算或設定屬性參數
                  width: double.infinity, // 執行相對應的邏輯計算或設定屬性參數
                  child: CustomPaint( // 執行相對應的邏輯計算或設定屬性參數
                    painter: MockLineChartPainter(
                      data: data,
                      hoveredIdx: _hoveredIdx,
                      labels: labels,
                      avg: avg,
                      target: 2000.0,
                    ), // 執行相對應的邏輯計算或設定屬性參數
                  ), // 執行相對應的邏輯計算或設定屬性參數
                ), // 執行相對應的邏輯計算或設定屬性參數
              ), // 執行相對應的邏輯計算或設定屬性參數
            ); // 程式碼區塊或元件結構結束
          }, // 程式碼區塊或元件結構結束
        ), // 執行相對應的邏輯計算或設定屬性參數
      ], // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  void _handleTouch(Offset localPosition, double width, int count) { // 執行相對應的邏輯計算或設定屬性參數
    double step = width / (count - 1); // 宣告類別成員或方法內部的區域變數
    int idx = (localPosition.dx / step).round().clamp(0, count - 1); // 宣告類別成員或方法內部的區域變數
    setState(() { _hoveredIdx = idx; }); // 更新狀態數據並通知 UI 重新渲染畫面
  } // 程式碼區塊或元件結構結束

  Widget _buildEatenFoodGrid() {
    if (_viewType == 0) {
      final todayRecords = _allRecords.where((record) {
        final rDate = _getRecordDate(record);
        if (rDate == null) return false;
        return rDate.year == _selectedDate.year &&
               rDate.month == _selectedDate.month &&
               rDate.day == _selectedDate.day;
      }).toList();

      todayRecords.sort((a, b) {
        final orderA = _getMealOrder(a['mealType'] ?? a['meal'] ?? 'OTHER');
        final orderB = _getMealOrder(b['mealType'] ?? b['meal'] ?? 'OTHER');
        return orderA.compareTo(orderB);
      });

      if (todayRecords.isEmpty) {
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: AppColors.border),
          ),
          child: const Center(
            child: Text("今日尚無飲食紀錄", style: TextStyle(color: Colors.black54, fontSize: 14)),
          ),
        );
      }

      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 12),
              child: Text("今日吃了什麼", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            ),
            ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: todayRecords.length,
              itemBuilder: (context, index) {
                final record = todayRecords[index];
                final dish = record['dishName'] ?? record['dish_name'] ?? '未命名餐點';
                final meal = _mealTypeDisplay(record['mealType'] ?? record['meal'] ?? 'OTHER');
                final cal = _getCaloriesFromRecord(record).round();
                final protein = _getProteinFromRecord(record);
                final fat = _getFatFromRecord(record);
                final carbs = _getCarbsFromRecord(record);

                return DietRecordTile(
                  record: record,
                  meal: meal,
                  cal: cal,
                  protein: protein,
                  fat: fat,
                  carbs: carbs,
                  mealColor: _getMealColor(record['mealType'] ?? record['meal'] ?? 'OTHER'),
                  dish: dish,
                );
              },
            ),
          ],
        ),
      );
    } else {
      final sundayOffset = _selectedDate.weekday % 7;
      final sunday = _selectedDate.subtract(Duration(days: sundayOffset));

      final List<Map<String, dynamic>> daysData = [];
      final weekdaysZh = ["週日", "週一", "週二", "週三", "週四", "週五", "週六"];

      for (int i = 0; i < 7; i++) {
        final targetDate = sunday.add(Duration(days: i));
        final dayRecords = _allRecords.where((record) {
          final rDate = _getRecordDate(record);
          if (rDate == null) return false;
          return rDate.year == targetDate.year &&
                 rDate.month == targetDate.month &&
                 rDate.day == targetDate.day;
        }).toList();

        dayRecords.sort((a, b) {
          final orderA = _getMealOrder(a['mealType'] ?? a['meal'] ?? 'OTHER');
          final orderB = _getMealOrder(b['mealType'] ?? b['meal'] ?? 'OTHER');
          return orderA.compareTo(orderB);
        });

        daysData.add({
          'dayName': weekdaysZh[i],
          'dateStr': "${targetDate.month}/${targetDate.day}",
          'records': dayRecords,
        });
      }

      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 12),
              child: Text("本週飲食清單", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            ),
            ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 7,
              itemBuilder: (context, index) {
                final day = daysData[index];
                final List<dynamic> recs = day['records'];
                final String dayName = day['dayName'];
                final String dateStr = day['dateStr'];

                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2)),
                    ],
                    border: Border.all(color: AppColors.border.withOpacity(0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(dayName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                          Text(dateStr, style: const TextStyle(fontSize: 13, color: Colors.black54)),
                        ],
                      ),
                      const Divider(height: 16, thickness: 0.5),
                      if (recs.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text("無紀錄", style: TextStyle(fontSize: 14, color: Colors.grey)),
                        )
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: recs.length,
                          itemBuilder: (context, rIdx) {
                            final rec = recs[rIdx];
                            final dish = rec['dishName'] ?? rec['dish_name'] ?? '未命名';
                            final meal = _mealTypeDisplay(rec['mealType'] ?? rec['meal'] ?? 'OTHER');
                            final cal = _getCaloriesFromRecord(rec).toInt();
                            final protein = _getProteinFromRecord(rec);
                            final fat = _getFatFromRecord(rec);
                            final carbs = _getCarbsFromRecord(rec);

                            return DietRecordTile(
                              record: rec,
                              meal: meal,
                              cal: cal,
                              protein: protein,
                              fat: fat,
                              carbs: carbs,
                              mealColor: _getMealColor(rec['mealType'] ?? rec['meal'] ?? 'OTHER'),
                              dish: dish,
                            );
                          },
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      );
    }
  }

  // DietRecordTile handles the nutrition display now.
  // Removed old helper.

  String _mealTypeDisplay(dynamic mealType) {
    final m = mealType.toString().toUpperCase();
    if (m.contains('BREAKFAST') || m.contains('早')) return '早餐';
    if (m.contains('LUNCH') || m.contains('午')) return '午餐';
    if (m.contains('DINNER') || m.contains('晚')) return '晚餐';
    return '其他';
  }

  int _getMealOrder(dynamic mealType) {
    final m = mealType.toString().toUpperCase();
    if (m.contains('BREAKFAST') || m.contains('早')) return 1;
    if (m.contains('LUNCH') || m.contains('午')) return 2;
    if (m.contains('DINNER') || m.contains('晚')) return 3;
    return 4; // 其他
  }

  Color _getMealColor(dynamic mealType) {
    final m = mealType.toString().toUpperCase();
    if (m.contains('BREAKFAST') || m.contains('早')) return Colors.orange;
    if (m.contains('LUNCH') || m.contains('午')) return Colors.green;
    if (m.contains('DINNER') || m.contains('晚')) return Colors.blue;
    return Colors.grey;
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

    // 半圓弧度從 math.pi 到 0
    const double startAngle = math.pi;
    const double totalAngle = math.pi;

    // 偏低 38%, 適量 34%, 偏高 28%
    final double seg1Angle = totalAngle * 0.38;
    final double seg2Angle = totalAngle * 0.34;
    final double seg3Angle = totalAngle * 0.28;

    // 1. 偏低區間 (藍紫色)
    paint.color = const Color(0xFF7C83FD);
    canvas.drawArc(rect, startAngle, seg1Angle, false, paint);

    // 2. 適量區間 (綠色)
    paint.color = const Color(0xFF52C41A);
    canvas.drawArc(rect, startAngle + seg1Angle, seg2Angle, false, paint);

    // 3. 偏高區間 (橘紅色)
    paint.color = const Color(0xFFFF7A45);
    canvas.drawArc(rect, startAngle + seg1Angle + seg2Angle, seg3Angle, false, paint);

    // 計算指針角度
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

    // 繪製圓形指針與微陰影
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

class DiagonalLinesPainter extends CustomPainter { // 定義 DiagonalLinesPainter 類別，繼承自 CustomPainter
  final Color color; DiagonalLinesPainter({required this.color}); // 宣告類別成員或方法內部的區域變數
  @override void paint(Canvas canvas, Size size) { final paint = Paint()..color = color..strokeWidth = 1.5; for (double i = -size.height; i < size.width; i += 8) { canvas.drawLine(Offset(i, size.height), Offset(i + size.height, 0), paint); } } // 標記此方法為覆寫父類別之方法
  @override bool shouldRepaint(CustomPainter oldDelegate) => false; // 標記此方法為覆寫父類別之方法
} // 程式碼區塊或元件結構結束

class NutrientPiePainter extends CustomPainter {
  final double fat;
  final double protein;
  final double carbs;
  NutrientPiePainter({required this.fat, required this.protein, required this.carbs});

  @override void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()..style = PaintingStyle.fill;
    
    final double total = fat + protein + carbs;
    if (total == 0) {
      // 繪製灰色空心圓餅圖
      paint.color = Colors.grey.shade300;
      canvas.drawCircle(center, radius, paint);
      paint.color = AppColors.surface;
      canvas.drawCircle(center, radius * 0.3, paint);
      paint.style = PaintingStyle.stroke;
      paint.color = Colors.black12;
      paint.strokeWidth = 1;
      canvas.drawCircle(center, radius, paint);
      return;
    }
    
    double fatVal = fat / total;
    double carbsVal = carbs / total;
    double proteinVal = 1.0 - fatVal - carbsVal;
    
    final data = [
      {'label': '脂肪', 'value': fatVal, 'color': const Color(0xFFEF5350)},
      {'label': '蛋白質', 'value': proteinVal, 'color': const Color(0xFFFFA726)},
      {'label': '碳水', 'value': carbsVal, 'color': const Color(0xFF42A5F5)}
    ];
    
    double startAngle = -math.pi / 2;
    for (var item in data) {
      final sweepAngle = 2 * math.pi * (item['value'] as double);
      paint.color = item['color'] as Color;
      canvas.drawArc(rect, startAngle, sweepAngle, true, paint);
      final labelAngle = startAngle + sweepAngle / 2;
      final labelRadius = radius * 0.7;
      final x = center.dx + labelRadius * math.cos(labelAngle);
      final y = center.dy + labelRadius * math.sin(labelAngle);
      final textPainter = TextPainter(
        text: TextSpan(
          text: "${item['label']}\n${((item['value'] as double) * 100).toInt()}%",
          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x - textPainter.width / 2, y - textPainter.height / 2));
      startAngle += sweepAngle;
    }
    paint.color = AppColors.surface;
    canvas.drawCircle(center, radius * 0.3, paint);
    paint.style = PaintingStyle.stroke;
    paint.color = Colors.black12;
    paint.strokeWidth = 1;
    canvas.drawCircle(center, radius, paint);
  }
  @override bool shouldRepaint(covariant NutrientPiePainter oldDelegate) => 
      oldDelegate.fat != fat || oldDelegate.protein != protein || oldDelegate.carbs != carbs;
}


class MockLineChartPainter extends CustomPainter { // 定義 MockLineChartPainter 類別，繼承自 CustomPainter
  final List<double> data; // 宣告類別成員或方法內部的區域變數
  final int? hoveredIdx; // 宣告類別成員或方法內部的區域變數
  final List<String> labels;
  final double avg;
  final double target;

  MockLineChartPainter({
    required this.data,
    this.hoveredIdx,
    required this.labels,
    required this.avg,
    required this.target,
  }); // 執行相對應的邏輯計算或設定屬性參數

  @override // 標記此方法為覆寫父類別之方法
  void paint(Canvas canvas, Size size) { // 執行相對應的邏輯計算或設定屬性參數
    if (data.isEmpty) return; // 執行相對應的邏輯計算或設定屬性參數
    final double stepX = size.width / (data.length - 1); // 宣告類別成員或方法內部的區域變數
    
    // 手動找出最大最小值，避免 reduce 報錯
    double maxVal = data[0]; // 宣告類別成員或方法內部的區域變數
    double minVal = data[0]; // 宣告類別成員或方法內部的區域變數
    for (double v in data) { // 執行相對應的邏輯計算或設定屬性參數
      if (v > maxVal) maxVal = v; // 執行相對應的邏輯計算或設定屬性參數
      if (v < minVal) minVal = v; // 執行相對應的邏輯計算或設定屬性參數
    } // 程式碼區塊或元件結構結束
    
    // 將建議攝取與平均值納入邊界計算，確保虛線總是能正常顯示在圖表中
    if (target > maxVal) maxVal = target;
    if (avg > maxVal) maxVal = avg;
    if (target < minVal) minVal = target;
    if (avg < minVal) minVal = avg;
    
    minVal = minVal * 0.8; // 執行相對應的邏輯計算或設定屬性參數
    final double range = (maxVal - minVal) == 0 ? 1.0 : (maxVal - minVal); // 宣告類別成員或方法內部的區域變數

    final double chartHeight = size.height - 45; // 預留底部空間給兩行 X 軸標籤

    // 輔助計算 Y 軸座標的函數
    double yForValue(double val) {
      return chartHeight - ((val - minVal) / range * chartHeight) + 10;
    }

    // 繪製虛線輔助線
    final targetY = yForValue(target);
    final avgY = yForValue(avg);

    final targetPaint = Paint()
      ..color = Colors.green.withOpacity(0.6)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    _drawDashedLine(canvas, Offset(0, targetY), Offset(size.width, targetY), targetPaint, 5.0, 3.0);

    final avgPaint = Paint()
      ..color = Colors.orange.withOpacity(0.6)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    _drawDashedLine(canvas, Offset(0, avgY), Offset(size.width, avgY), avgPaint, 5.0, 3.0);

    // 標示輔助線文字
    final targetTextPainter = TextPainter(
      text: TextSpan(
        text: ' 建議攝取: ${target.round()} kcal',
        style: TextStyle(color: Colors.green.shade700, fontSize: 12, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    targetTextPainter.paint(canvas, Offset(5, targetY - 16));

    final avgTextPainter = TextPainter(
      text: TextSpan(
        text: ' 本週平均: ${avg.round()} kcal',
        style: TextStyle(color: Colors.orange.shade700, fontSize: 12, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    avgTextPainter.paint(canvas, Offset(5, avgY - 16));

    final paint = Paint()..color = Colors.blue.withOpacity(0.5)..style = PaintingStyle.stroke..strokeWidth = 3.0; // 設定顏色數值（Color）
    final path = Path(); // 宣告類別成員或方法內部的區域變數
    
    List<Offset> points = []; // 執行相對應的邏輯計算或設定屬性參數
    for (int i = 0; i < data.length; i++) { // 執行相對應的邏輯計算或設定屬性參數
      double x = i * stepX; // 宣告類別成員或方法內部的區域變數
      double y = yForValue(data[i]);
      points.add(Offset(x, y)); // 執行相對應的邏輯計算或設定屬性參數
      if (i == 0) path.moveTo(x, y); else path.lineTo(x, y); // 執行相對應的邏輯計算或設定屬性參數
    } // 程式碼區塊或元件結構結束
    canvas.drawPath(path, paint); // 執行相對應的邏輯計算或設定屬性參數

    final dotPaint = Paint()..color = AppColors.secondary; // 設定顏色數值（Color）
    for (int i = 0; i < points.length; i++) { // 執行相對應的邏輯計算或設定屬性參數
      bool isHovered = hoveredIdx == i; // 宣告類別成員或方法內部的區域變數
      canvas.drawCircle(points[i], isHovered ? 8 : 4, isHovered ? (Paint()..color = Colors.red) : dotPaint); // 設定顏色數值（Color）
      
      if (isHovered) { // 執行相對應的邏輯計算或設定屬性參數
        final textPainter = TextPainter( // 宣告類別成員或方法內部的區域變數
          text: TextSpan(text: data[i].round().toString(), style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold, backgroundColor: Colors.white70)), // 設定文字字體大小、顏色與粗細等字型樣式（TextStyle）
          textDirection: TextDirection.ltr, // 執行相對應的邏輯計算或設定屬性參數
        )..layout(); // 執行相對應的邏輯計算或設定屬性參數
        textPainter.paint(canvas, Offset(points[i].dx - textPainter.width / 2, points[i].dy - 25)); // 執行相對應的邏輯計算或設定屬性參數
      } // 程式碼區塊或元件結構結束

      // 繪製 X 軸日期與星期標籤
      if (i < labels.length) {
        final labelPainter = TextPainter(
          text: TextSpan(
            text: labels[i],
            style: TextStyle(
              color: Colors.black54,
              fontSize: 10,
              height: 1.2,
              fontWeight: isHovered ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
        )..layout();
        labelPainter.paint(canvas, Offset(points[i].dx - labelPainter.width / 2, size.height - 30));
      }
    } // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束
  @override bool shouldRepaint(covariant MockLineChartPainter oldDelegate) => 
      oldDelegate.hoveredIdx != hoveredIdx || 
      oldDelegate.data != data || 
      oldDelegate.labels != labels ||
      oldDelegate.avg != avg ||
      oldDelegate.target != target; // 標記此方法為覆寫父類別之方法

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint, double dashWidth, double dashSpace) {
    double currentX = p1.dx;
    while (currentX < p2.dx) {
      canvas.drawLine(
        Offset(currentX, p1.dy),
        Offset((currentX + dashWidth).clamp(p1.dx, p2.dx), p1.dy),
        paint,
      );
      currentX += dashWidth + dashSpace;
    }
  }
} // 程式碼區塊或元件結構結束

class DietRecordTile extends StatefulWidget {
  final dynamic record;
  final String meal;
  final int cal;
  final double protein;
  final double fat;
  final double carbs;
  final Color mealColor;
  final String dish;

  const DietRecordTile({
    super.key,
    required this.record,
    required this.meal,
    required this.cal,
    required this.protein,
    required this.fat,
    required this.carbs,
    required this.mealColor,
    required this.dish,
  });

  @override
  State<DietRecordTile> createState() => _DietRecordTileState();
}

class _DietRecordTileState extends State<DietRecordTile> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 4)),
        ],
        border: Border.all(color: AppColors.border.withOpacity(0.4)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: _isExpanded,
          onExpansionChanged: (val) {
            setState(() {
              _isExpanded = val;
            });
          },
          trailing: Icon(
            _isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
            color: AppColors.textPrimary,
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: widget.mealColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  widget.meal,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: widget.mealColor,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      for (int i = 0; i < widget.dish.split(', ').length; i++) ...[
                        if (i > 0) const TextSpan(text: ", ", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                        TextSpan(
                          text: widget.dish.split(', ')[i],
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                        ),
                        TextSpan(
                          text: " (${_parsePortionAtIndex(widget.record, i)})",
                          style: const TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                      ]
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                "${widget.cal} kcal",
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
            ],
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 16, thickness: 0.5),
                  const SizedBox(height: 8),
                  _buildNutritionRow("蛋白質", "${widget.protein.toStringAsFixed(1)}克", Colors.orange),
                  const SizedBox(height: 8),
                  _buildNutritionRow("脂肪", "${widget.fat.toStringAsFixed(1)}g", Colors.redAccent),
                  const SizedBox(height: 8),
                  _buildNutritionRow("碳水化合物", "${widget.carbs.toStringAsFixed(1)}g", Colors.lightBlue),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNutritionRow(String label, String value, Color color) {
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(
          "$label:",
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
      ],
    );
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
}
