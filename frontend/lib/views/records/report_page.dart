import 'package:flutter/material.dart'; // 匯入 material.dart 元件庫或套件
import 'dart:ui'; // 匯入 dart:ui 元件庫或套件
import 'dart:math' as math; // 匯入 dart:math 元件庫或套件
import 'dart:convert'; // 匯入 json 處理套件
import '../home/home_page.dart'; // 匯入 home_page.dart 元件庫或套件
import '../auth/profile_page.dart'; // 匯入 profile_page.dart 元件庫或套件
import '../../color/app_colors.dart'; // 匯入 app_colors.dart 元件庫或套件
import '../../controllers/dog_state_controller.dart';
import '../../widgets/dog_avatar.dart';
import '../../services/diet_service.dart'; // 匯入 diet_service.dart

class ReportPage extends StatefulWidget { // 定義 ReportPage 類別，繼承自 StatefulWidget
  final DateTime date; // 宣告類別成員或方法內部的區域變數
  const ReportPage({super.key, required this.date}); // 建立編譯期常數，優化 Flutter 渲染效能

  @override // 標記此方法為覆寫父類別之方法
  State<ReportPage> createState() => _ReportPageState(); // 執行相對應的邏輯計算或設定屬性參數
} // 程式碼區塊或元件結構結束

class _ReportPageState extends State<ReportPage> with TickerProviderStateMixin { // 定義 _ReportPageState 類別，繼承自 State
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

  @override // 標記此方法為覆寫父類別之方法
  void initState() { // 初始化狀態生命週期方法，頁面建立時執行一次
    super.initState(); // 執行相對應的邏輯計算或設定屬性參數
    _dogController.setState(DogAnimationState.idle);
    
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
    // 1. Weekly data: Sunday to Saturday of the week containing widget.date
    final sundayOffset = widget.date.weekday % 7;
    final sunday = widget.date.subtract(Duration(days: sundayOffset));
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

    // 2. Monthly data: from widget.date - 29 days to widget.date
    List<double> monthly = [];
    for (int i = 29; i >= 0; i--) {
      final targetDate = widget.date.subtract(Duration(days: i));
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
    _hoverController.dispose(); // 執行相對應的邏輯計算或設定屬性參數
    super.dispose(); // 執行相對應的邏輯計算或設定屬性參數
  } // 程式碼區塊或元件結構結束



  String get _viewLabel { // 宣告類別成員或方法內部的區域變數
    if (_viewType == 1) return "本週"; // 回傳建構完成的元件或方法計算結果
    return "今日"; // 回傳建構完成的元件或方法計算結果
  } // 程式碼區塊或元件結構結束

  String get _dateDisplay { // 宣告類別成員或方法內部的區域變數
    if (_viewType == 0) { // 執行相對應的邏輯計算或設定屬性參數
      return "${widget.date.year}年 ${widget.date.month.toString().padLeft(2, '0')}月 ${widget.date.day.toString().padLeft(2, '0')}日"; // 回傳建構完成的元件或方法計算結果
    } else { // 程式碼區塊或元件結構結束
      DateTime startDate = widget.date.subtract(Duration(days: widget.date.weekday % 7));
      DateTime endDate = startDate.add(const Duration(days: 6));
      return "${startDate.year}年 ${startDate.month.toString().padLeft(2, '0')}月 ${startDate.day.toString().padLeft(2, '0')}日 - ${endDate.year == startDate.year ? '' : '${endDate.year}年 '}${endDate.month.toString().padLeft(2, '0')}月 ${endDate.day.toString().padLeft(2, '0')}日"; // 回傳建構完成的元件或方法計算結果
    } // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

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
      backgroundColor: AppColors.background, // 設定顏色數值（Color）
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
                    const Text("小精靈目前狀態：休息中", style: TextStyle(color: AppColors.textSecondary, fontSize: 14)), // 建立文字顯示元件（Text）
                  ], // 執行相對應的邏輯計算或設定屬性參數
                  const SizedBox(height: 30), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
                  Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
                    margin: const EdgeInsets.symmetric(horizontal: 16), // 設定外邊距或內邊距的數值大小（EdgeInsets）
                    padding: const EdgeInsets.all(20), // 設定外邊距或內邊距的數值大小（EdgeInsets）
                    decoration: BoxDecoration( // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
                      color: const Color.fromARGB(255, 227, 224, 224), // 建立編譯期常數，優化 Flutter 渲染效能
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
                      color: const Color.fromARGB(255, 208, 231, 192), // 建立編譯期常數，優化 Flutter 渲染效能
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
      bottomNavigationBar: BottomNavigationBar( // 執行相對應的邏輯計算或設定屬性參數
        currentIndex: 1, // 執行相對應的邏輯計算或設定屬性參數
        selectedItemColor: AppColors.primary, // 設定顏色數值（Color）
        unselectedItemColor: Colors.grey, // 設定顏色數值（Color）
        backgroundColor: AppColors.background, // 設定顏色數值（Color）
        type: BottomNavigationBarType.fixed, // 執行相對應的邏輯計算或設定屬性參數
        onTap: (index) { // 執行相對應的邏輯計算或設定屬性參數
          Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => HomePage(initialIndex: index)), (route) => false); // 導航路由跳轉：開啟並推入新頁面
        }, // 程式碼區塊或元件結構結束
        items: const [ // 建立編譯期常數，優化 Flutter 渲染效能
          BottomNavigationBarItem(icon: Icon(Icons.home), label: '首頁'), // 顯示預設的圖示元件（Icon）
          BottomNavigationBarItem(icon: Icon(Icons.edit_note), label: '飲食紀錄'), // 顯示預設的圖示元件（Icon）
          BottomNavigationBarItem(icon: Icon(Icons.account_circle), label: '個人首頁'), // 顯示預設的圖示元件（Icon）
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
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios, size: 28)),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () => setState(() { _viewType = (_viewType + 1) % 2; _hoveredIdx = null; }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(10)),
                      child: Text(_viewLabel, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text('趨勢報告', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary, letterSpacing: 1.2)),
                ],
              ),
              _buildProfileAvatar(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileAvatar(BuildContext context) { // 定義用於重複使用的 UI 封裝建構方法
    return GestureDetector( // 建立手勢偵測器（GestureDetector），用於監聽點擊、拖動等觸控事件
      onTap: () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const ProfilePage(returnIndex: 1)), (route) => false), // 導航路由跳轉：開啟並推入新頁面
      child: Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
        decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 2.925, offset: const Offset(0, 1.56))]), // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
        child: const CircleAvatar( // 建立編譯期常數，優化 Flutter 渲染效能
          radius: 25,  // 執行相對應的邏輯計算或設定屬性參數
          backgroundColor: AppColors.background,  // 設定顏色數值（Color）
          child: Icon( // 顯示預設的圖示元件（Icon）
            Icons.person,  // 執行相對應的邏輯計算或設定屬性參數
            color: AppColors.textPrimary,  // 設定顏色數值（Color）
            size: 35, // 執行相對應的邏輯計算或設定屬性參數
          ), // 執行相對應的邏輯計算或設定屬性參數
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

    final DateTime startDate = widget.date.subtract(Duration(days: widget.date.weekday % 7));
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
        color: const Color.fromARGB(255, 248, 242, 191), // 鵝黃色背景
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
          _buildDetailRow("早餐", "($bPercent%)", breakfastCal.toInt().toString(), Colors.orange),
          const SizedBox(height: 12),
          _buildDetailRow("午餐", "($lPercent%)", lunchCal.toInt().toString(), Colors.green),
          const SizedBox(height: 12),
          _buildDetailRow("晚餐", "($dPercent%)", dinnerCal.toInt().toString(), Colors.blue),
          const SizedBox(height: 12),
          _buildDetailRow("其他", "($oPercent%)", otherCal.toInt().toString(), Colors.grey),
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

  Widget _buildTodayStats() { // 定義用於重複使用的 UI 封裝建構方法
    double todayCal = 0.0;
    double todayProtein = 0.0;
    double todayFat = 0.0;
    double todayCarbs = 0.0;

    for (var record in _allRecords) {
      final rDate = _getRecordDate(record);
      if (rDate == null) continue;
      try {
        if (rDate.year == widget.date.year &&
            rDate.month == widget.date.month &&
            rDate.day == widget.date.day) {
          todayCal += _getCaloriesFromRecord(record);
          todayProtein += _getProteinFromRecord(record);
          todayFat += _getFatFromRecord(record);
          todayCarbs += _getCarbsFromRecord(record);
        }
      } catch (_) {}
    }
    int current = todayCal.toInt();
    int target = 2000; // 宣告類別成員或方法內部的區域變數
    double progress = (current / target).clamp(0.0, 1.0); // 宣告類別成員或方法內部的區域變數
    Color progressColor = progress >= 1.0 ? AppColors.danger : (progress >= 0.8 ? Colors.orange : Colors.green); // 設定顏色數值（Color）

    final double totalGrams = todayProtein + todayFat + todayCarbs;
    int fatPercent = 0;
    int carbsPercent = 0;
    int proteinPercent = 0;
    if (totalGrams > 0) {
      fatPercent = ((todayFat / totalGrams) * 100).round();
      carbsPercent = ((todayCarbs / totalGrams) * 100).round();
      proteinPercent = 100 - fatPercent - carbsPercent;
    }

    return Column( // 建立垂直排列元件（Column），縱向排列多個子元件
      crossAxisAlignment: CrossAxisAlignment.center, // 執行相對應的邏輯計算或設定屬性參數
      children: [ // 執行相對應的邏輯計算或設定屬性參數
        Align(alignment: Alignment.centerLeft, child: const Text("總結數據", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))), // 建立文字顯示元件（Text）
        const SizedBox(height: 20), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("卡路里", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), Text("今日攝取: $current / $target", style: const TextStyle(fontSize: 12))]), // 建立水平排列元件（Row），橫向排列多個子元件
        const SizedBox(height: 8), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
        LayoutBuilder(builder: (context, constraints) { // 執行相對應的邏輯計算或設定屬性參數
          final double fullWidth = constraints.maxWidth; // 宣告類別成員或方法內部的區域變數
          final double progressWidth = fullWidth * progress; // 宣告類別成員或方法內部的區域變數
          return Container(height: 35, width: fullWidth, decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(10)), // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
            child: Stack(children: [if (progressWidth > 0) Container(width: progressWidth, height: 35, decoration: BoxDecoration(color: progressColor, borderRadius: BorderRadius.circular(8)), child: ClipRRect(borderRadius: BorderRadius.circular(8), child: CustomPaint(painter: DiagonalLinesPainter(color: Colors.white.withOpacity(0.25)))))])); // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
        }), // 執行相對應的邏輯計算或設定屬性參數
        const SizedBox(height: 40), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
        Align(alignment: Alignment.centerLeft, child: const Text("三大營養素", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))), // 建立文字顯示元件（Text）
        const SizedBox(height: 30), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          SizedBox(
            width: 170, 
            height: 170, 
            child: CustomPaint(
              painter: NutrientPiePainter(
                fat: todayFat, 
                protein: todayProtein, 
                carbs: todayCarbs
              )
            )
          ), 
          const SizedBox(width: 15), 
          Column(
            crossAxisAlignment: CrossAxisAlignment.start, 
            children: [
              _buildNutrientLegendItem("脂肪", "$fatPercent%", const Color(0xFFEF5350)), 
              const SizedBox(height: 12), 
              _buildNutrientLegendItem("碳水", "$carbsPercent%", const Color(0xFF42A5F5)), 
              const SizedBox(height: 12), 
              _buildNutrientLegendItem("蛋白質", "$proteinPercent%", const Color(0xFFFFA726))
            ]
          )
        ]), // 建立水平排列元件（Row），橫向排列多個子元件
        const SizedBox(height: 20), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
      ], // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Widget _buildNutrientLegendItem(String label, String value, Color color) { // 定義用於重複使用的 UI 封裝建構方法
    return Row(children: [Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)), const SizedBox(width: 8), Text("$label $value", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary))]); // 建立水平排列元件（Row），橫向排列多個子元件
  } // 程式碼區塊或元件結構結束

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
            return MouseRegion( // 回傳建構完成的元件或方法計算結果
              onHover: (event) => _handleTouch(event.localPosition, constraints.maxWidth, data.length), // 執行相對應的邏輯計算或設定屬性參數
              onExit: (_) => setState(() => _hoveredIdx = null), // 更新狀態數據並通知 UI 重新渲染畫面
              child: GestureDetector( // 建立手勢偵測器（GestureDetector），用於監聽點擊、拖動等觸控事件
                onPanUpdate: (details) => _handleTouch(details.localPosition, constraints.maxWidth, data.length), // 執行相對應的邏輯計算或設定屬性參數
                onTapDown: (details) => _handleTouch(details.localPosition, constraints.maxWidth, data.length), // 執行相對應的邏輯計算或設定屬性參數
                child: SizedBox( // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
                  height: 200, // 執行相對應的邏輯計算或設定屬性參數
                  width: double.infinity, // 執行相對應的邏輯計算或設定屬性參數
                  child: CustomPaint( // 執行相對應的邏輯計算或設定屬性參數
                    painter: MockLineChartPainter(data: data, hoveredIdx: _hoveredIdx), // 執行相對應的邏輯計算或設定屬性參數
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
        return rDate.year == widget.date.year &&
               rDate.month == widget.date.month &&
               rDate.day == widget.date.day;
      }).toList();

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
              physics: const NeverScrollableScrollPhysics(),
              itemCount: todayRecords.length,
              itemBuilder: (context, index) {
                final record = todayRecords[index];
                final dish = record['dishName'] ?? record['dish_name'] ?? '未命名餐點';
                final meal = _mealTypeDisplay(record['mealType'] ?? record['meal'] ?? 'OTHER');
                final cal = _getCaloriesFromRecord(record).toInt();
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
      final sundayOffset = widget.date.weekday % 7;
      final sunday = widget.date.subtract(Duration(days: sundayOffset));

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

  Color _getMealColor(dynamic mealType) {
    final m = mealType.toString().toUpperCase();
    if (m.contains('BREAKFAST') || m.contains('早')) return Colors.orange;
    if (m.contains('LUNCH') || m.contains('午')) return Colors.green;
    if (m.contains('DINNER') || m.contains('晚')) return Colors.blue;
    return Colors.grey;
  }
} // 程式碼區塊或元件結構結束

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
  MockLineChartPainter({required this.data, this.hoveredIdx}); // 執行相對應的邏輯計算或設定屬性參數

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
    
    minVal = minVal * 0.8; // 執行相對應的邏輯計算或設定屬性參數
    final double range = (maxVal - minVal) == 0 ? 1.0 : (maxVal - minVal); // 宣告類別成員或方法內部的區域變數

    final paint = Paint()..color = Colors.blue.withOpacity(0.5)..style = PaintingStyle.stroke..strokeWidth = 3.0; // 設定顏色數值（Color）
    final path = Path(); // 宣告類別成員或方法內部的區域變數
    
    List<Offset> points = []; // 執行相對應的邏輯計算或設定屬性參數
    for (int i = 0; i < data.length; i++) { // 執行相對應的邏輯計算或設定屬性參數
      double x = i * stepX; // 宣告類別成員或方法內部的區域變數
      double y = size.height - ((data[i] - minVal) / range * size.height); // 宣告類別成員或方法內部的區域變數
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
          text: TextSpan(text: data[i].toInt().toString(), style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold, backgroundColor: Colors.white70)), // 設定文字字體大小、顏色與粗細等字型樣式（TextStyle）
          textDirection: TextDirection.ltr, // 執行相對應的邏輯計算或設定屬性參數
        )..layout(); // 執行相對應的邏輯計算或設定屬性參數
        textPainter.paint(canvas, Offset(points[i].dx - textPainter.width / 2, points[i].dy - 25)); // 執行相對應的邏輯計算或設定屬性參數
      } // 程式碼區塊或元件結構結束
    } // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束
  @override bool shouldRepaint(covariant MockLineChartPainter oldDelegate) => oldDelegate.hoveredIdx != hoveredIdx || oldDelegate.data != data; // 標記此方法為覆寫父類別之方法
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
                  if (widget.record['description'] != null &&
                      widget.record['description'].toString().trim().isNotEmpty &&
                      widget.record['description'].toString().trim() != '手動輸入飲食紀錄' &&
                      !widget.record['description'].toString().contains('份')) ...[
                    const SizedBox(height: 12),
                    Text(
                      "備註: ${widget.record['description']}",
                      style: const TextStyle(fontSize: 13, color: Colors.grey, fontStyle: FontStyle.italic),
                    ),
                  ]
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
    final portionsVal = record['portions'];
    final descriptionVal = record['description'];
    final sourceStr = (portionsVal != null && portionsVal.toString().trim().isNotEmpty)
        ? portionsVal.toString().trim()
        : (descriptionVal != null ? descriptionVal.toString().trim() : '');

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
