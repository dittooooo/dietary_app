import 'package:flutter/material.dart'; // 匯入 material.dart 元件庫或套件
import 'dart:io'; // 匯入 dart:io 元件庫或套件
import 'package:flutter/foundation.dart'
    show kIsWeb; // 匯入 foundation.dart 元件庫或套件
import 'package:shared_preferences/shared_preferences.dart'; // 匯入 shared_preferences.dart 元件庫或套件
import '../home/home_page.dart';
import '../../controllers/dog_state_controller.dart';
import '../../widgets/dog_avatar.dart'; // 匯入 home_page.dart 元件庫或套件
import '../../color/app_colors.dart'; // 匯入 app_colors.dart 元件庫或套件

class ElfFeedingPage extends StatefulWidget {
  // 定義 ElfFeedingPage 類別，繼承自 StatefulWidget
  final String imagePath; // 宣告類別成員或方法內部的區域變數
  final List<Map<String, dynamic>> items; // 宣告類別成員或方法內部的區域變數

  const ElfFeedingPage({
    // 建立編譯期常數，優化 Flutter 渲染效能
    super.key, // 執行相對應的邏輯計算或設定屬性參數
    required this.imagePath, // 執行相對應的邏輯計算或設定屬性參數
    required this.items, // 執行相對應的邏輯計算或設定屬性參數
  }); // 程式碼區塊或元件結構結束

  @override // 標記此方法為覆寫父類別之方法
  State<ElfFeedingPage> createState() => _ElfFeedingPageState(); // 執行相對應的邏輯計算或設定屬性參數
} // 程式碼區塊或元件結構結束

class _ElfFeedingPageState extends State<ElfFeedingPage>
    with TickerProviderStateMixin {
  // 定義 _ElfFeedingPageState 類別，繼承自 State
  late AnimationController _elfController; // 宣告類別成員或方法內部的區域變數
  late Animation<double> _elfScale; // 宣告類別成員或方法內部的區域變數
  late Animation<Offset> _elfMove; // 宣告類別成員或方法內部的區域變數
  bool _isEaten = false; // 宣告類別成員或方法內部的區域變數
  String _petType = '狗兒'; // 宣告類別成員或方法內部的區域變數
  String _dietGoal = '養生'; // 宣告類別成員或方法內部的區域變數
  final DogStateController _dogController = DogStateController.instance;

  @override // 標記此方法為覆寫父類別之方法
  void initState() {
    // 初始化狀態生命週期方法，頁面建立時執行一次
    super.initState(); // 執行相對應的邏輯計算或設定屬性參數
    _loadPetData();
    _dogController.setState(DogAnimationState.eating); // 執行相對應的邏輯計算或設定屬性參數
    _elfController = AnimationController(
      // 執行相對應的邏輯計算或設定屬性參數
      vsync: this, // 執行相對應的邏輯計算或設定屬性參數
      duration: const Duration(seconds: 7), // 建立編譯期常數，優化 Flutter 渲染效能
    ); // 程式碼區塊或元件結構結束

    _elfMove =
        Tween<Offset>(
          // 執行相對應的邏輯計算或設定屬性參數
          begin: const Offset(0, 1.5), // 建立編譯期常數，優化 Flutter 渲染效能
          end: const Offset(0, 0), // 建立編譯期常數，優化 Flutter 渲染效能
        ).animate(
          CurvedAnimation(
            parent: _elfController,
            curve: const Interval(0.0, 0.3, curve: Curves.easeOutBack),
          ),
        ); // 建立編譯期常數，優化 Flutter 渲染效能

    _elfScale = Tween<double>(begin: 1.0, end: 1.5).animate(
      // 執行相對應的邏輯計算或設定屬性參數
      CurvedAnimation(
        parent: _elfController,
        curve: const Interval(0.3, 0.5, curve: Curves.elasticOut),
      ), // 建立編譯期常數，優化 Flutter 渲染效能
    ); // 程式碼區塊或元件結構結束

    _elfController.forward().then((_) {
      // 執行相對應的邏輯計算或設定屬性參數
      if (mounted) _goToDiary(); // 執行相對應的邏輯計算或設定屬性參數
    }); // 程式碼區塊或元件結構結束

    // 延遲一段時間讓食物消失
    Future.delayed(const Duration(seconds: 4), () {
      // 建立編譯期常數，優化 Flutter 渲染效能
      if (mounted) setState(() => _isEaten = true); // 更新狀態數據並通知 UI 重新渲染畫面
    }); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Future<void> _loadPetData() async {
    // 定義非同步方法（Future），執行耗時操作
    final prefs = await SharedPreferences.getInstance(); // 宣告類別成員或方法內部的區域變數
    if (mounted) {
      // 執行相對應的邏輯計算或設定屬性參數
      setState(() {
        // 更新狀態數據並通知 UI 重新渲染畫面
        _petType = '狗兒'; // 執行相對應的邏輯計算或設定屬性參數
        _dogController.setBodyTypeFromBackend(
          prefs.getString('dog_body_type') ?? prefs.getString('user_diet_goal'),
        );
        _dietGoal =
            prefs.getString('user_diet_goal') ?? '養生'; // 執行相對應的邏輯計算或設定屬性參數
      }); // 程式碼區塊或元件結構結束
    } // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  String _getPetImagePath(String petType, String dietGoal) {
    // 宣告類別成員或方法內部的區域變數
    String path = 'assets/images/shiba_normal.png'; // 宣告類別成員或方法內部的區域變數
    if (petType == '奶油皮丘' || petType.isNotEmpty) {
      // 執行相對應的邏輯計算或設定屬性參數
      if (dietGoal.contains('減脂')) {
        // 執行相對應的邏輯計算或設定屬性參數
        path = 'assets/images/shiba_fat.png'; // 執行相對應的邏輯計算或設定屬性參數
      } else if (dietGoal.contains('增肌')) {
        // 執行相對應的邏輯計算或設定屬性參數
        path = 'assets/images/shiba_muscular.png'; // 執行相對應的邏輯計算或設定屬性參數
      } else if (dietGoal.contains('養生')) {
        // 執行相對應的邏輯計算或設定屬性參數
        path = 'assets/images/shiba_thin.png'; // 執行相對應的邏輯計算或設定屬性參數
      } // 程式碼區塊或元件結構結束
    } // 程式碼區塊或元件結構結束
    return path; // 回傳建構完成的元件或方法計算結果
  } // 程式碼區塊或元件結構結束

  void _goToDiary() {
    // 執行相對應的邏輯計算或設定屬性參數
    Navigator.pushAndRemoveUntil(
      // 導航路由跳轉：開啟並推入新頁面
      context, // 執行相對應的邏輯計算或設定屬性參數
      MaterialPageRoute(
        builder: (context) => const HomePage(initialIndex: 1),
      ), // 建立編譯期常數，優化 Flutter 渲染效能
      (route) => false, // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  @override // 標記此方法為覆寫父類別之方法
  void dispose() {
    // 銷毀狀態生命週期方法，釋放頁面資源與控制器
    _elfController.dispose(); // 執行相對應的邏輯計算或設定屬性參數
    super.dispose(); // 執行相對應的邏輯計算或設定屬性參數
  } // 程式碼區塊或元件結構結束

  @override // 標記此方法為覆寫父類別之方法
  Widget build(BuildContext context) {
    // 建立畫面的主要 build 方法，返回元件樹
    return Scaffold(
      // 建立頁面的基礎 Scaffold 骨架，提供頁面基本版面佈局
      backgroundColor: AppColors.surface, // 設定顏色數值（Color）
      body: Stack(
        // 設定頁面的主要內容區域（body）
        children: [
          // 執行相對應的邏輯計算或設定屬性參數
          // 背景與標題
          Positioned.fill(
            // 執行相對應的邏輯計算或設定屬性參數
            child: Column(
              // 建立垂直排列元件（Column），縱向排列多個子元件
              mainAxisAlignment: MainAxisAlignment.center, // 執行相對應的邏輯計算或設定屬性參數
              children: [
                // 執行相對應的邏輯計算或設定屬性參數
                Transform.translate(
                  offset: const Offset(0, -250),
                  child: const Text(
                    // 建立文字顯示元件（Text）
                    "小精靈用餐中...", // 執行相對應的邏輯計算或設定屬性參數
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ), // 設定文字字體大小、顏色與粗細等字型樣式（TextStyle）
                  ),
                ), // 執行相對應的邏輯計算或設定屬性參數
                const SizedBox(height: 30), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
              ], // 執行相對應的邏輯計算或設定屬性參數
            ), // 執行相對應的邏輯計算或設定屬性參數
          ), // 執行相對應的邏輯計算或設定屬性參數
          // 小精靈動畫
          Align(
            // 執行相對應的邏輯計算或設定屬性參數
            alignment: Alignment.bottomCenter, // 執行相對應的邏輯計算或設定屬性參數
            child: SlideTransition(
              // 執行相對應的邏輯計算或設定屬性參數
              position: _elfMove, // 執行相對應的邏輯計算或設定屬性參數
              child: ScaleTransition(
                // 執行相對應的邏輯計算或設定屬性參數
                scale: _elfScale, // 執行相對應的邏輯計算或設定屬性參數
                child: Padding(
                  // 建立間距容器（Padding），用於設定內部邊距
                  padding: const EdgeInsets.only(
                    bottom: 310,
                  ), // 設定外邊距或內邊距的數值大小（EdgeInsets）
                  child: Transform.translate(
                    offset: const Offset(-50, 0),
                    child: Column(
                      // 建立垂直排列元件（Column），縱向排列多個子元件
                      mainAxisSize: MainAxisSize.min, // 執行相對應的邏輯計算或設定屬性參數
                      children: [
                        // 執行相對應的邏輯計算或設定屬性參數
                        if (!_isEaten) // 執行相對應的邏輯計算或設定屬性參數
                          Container(
                            // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
                            padding: const EdgeInsets.all(
                              10,
                            ), // 設定外邊距或內邊距的數值大小（EdgeInsets）
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              borderRadius: BorderRadius.circular(15),
                            ), // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
                            child: const Text(
                              "啊姆！看起來很好吃！",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ), // 建立文字顯示元件（Text）
                          ), // 執行相對應的邏輯計算或設定屬性參數
                        const SizedBox(
                          height: 10,
                        ), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
                        SizedBox(
                          width: 180,
                          height: 180,
                          child: DogAvatar(
                            controller: _dogController,
                            instanceId: 'feeding-eating',
                            scale: 1.8,
                            cameraControls: false,
                          ),
                        ),
                      ], // 執行相對應的邏輯計算或設定屬性參數
                    ), // 執行相對應的邏輯計算或設定屬性參數
                  ), // 執行相對應的邏輯計算或設定屬性參數
                ), // 執行相對應的邏輯計算或設定屬性參數
              ), // 執行相對應的邏輯計算或設定屬性參數
            ), // 執行相對應的邏輯計算或設定屬性參數
          ), // 執行相對應的邏輯計算或設定屬性參數
          // 固定位置的「跳過動畫」按鈕 (不隨 SnackBar 浮動)
          Positioned(
            bottom: 165.0, // 185.0 - 20.0 = 165.0
            left: 0,
            right: 0,
            child: Center(
              child: FloatingActionButton.extended(
                onPressed: _goToDiary,
                label: const Text(
                  "跳過動畫 >>",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                backgroundColor: AppColors.background.withOpacity(0.8),
                foregroundColor: AppColors.textPrimary,
                elevation: 1.0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
                extendedPadding: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 12,
                ),
              ),
            ),
          ),
        ], // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束
} // 程式碼區塊或元件結構結束
