import 'package:flutter/material.dart'; // 匯入 material.dart 元件庫或套件
import 'package:camera/camera.dart'; // 匯入 camera.dart 元件庫或套件
import 'dart:ui'; // 匯入 dart:ui 元件庫或套件
import 'dart:async'; // 匯入 dart:async 元件庫或套件
import 'dart:io'; // 匯入 dart:io 元件庫或套件
import 'package:flutter/foundation.dart' show kIsWeb; // 匯入 foundation.dart 元件庫或套件
import 'package:shared_preferences/shared_preferences.dart'; // 匯入 shared_preferences.dart 元件庫或套件
import 'elf_feeding_page.dart'; // 匯入 elf_feeding_page.dart 元件庫或套件

class CameraRecordPage extends StatefulWidget { // 定義 CameraRecordPage 類別，繼承自 StatefulWidget
  const CameraRecordPage({super.key}); // 建立編譯期常數，優化 Flutter 渲染效能

  @override // 標記此方法為覆寫父類別之方法
  State<CameraRecordPage> createState() => _CameraRecordPageState(); // 執行相對應的邏輯計算或設定屬性參數
} // 程式碼區塊或元件結構結束

enum RecordStage { shooting, recognizing, result } // 執行相對應的邏輯計算或設定屬性參數

class _CameraRecordPageState extends State<CameraRecordPage> with TickerProviderStateMixin { // 定義 _CameraRecordPageState 類別，繼承自 State
  CameraController? _controller; // 執行相對應的邏輯計算或設定屬性參數
  Future<void>? _initializeControllerFuture; // 定義非同步方法（Future），執行耗時操作
  RecordStage _currentStage = RecordStage.shooting; // 執行相對應的邏輯計算或設定屬性參數
  XFile? _capturedImage; // 執行相對應的邏輯計算或設定屬性參數
  String _petType = '米粒(Mili)'; // 宣告類別成員或方法內部的區域變數
  String _dietGoal = '養生'; // 宣告類別成員或方法內部的區域變數
  
  // 動畫相關
  late AnimationController _elfAnimController; // 宣告類別成員或方法內部的區域變數
  late Animation<Offset> _elfPosition; // 宣告類別成員或方法內部的區域變數
  late AnimationController _scanningController; // 宣告類別成員或方法內部的區域變數
  late AnimationController _hoverController; // 宣告類別成員或方法內部的區域變數
  late Animation<double> _hoverScaleAnimation; // 宣告類別成員或方法內部的區域變數
  late Animation<double> _hoverOffsetAnimation; // 宣告類別成員或方法內部的區域變數

  // 辨識結果模擬數據
  final List<Map<String, dynamic>> _detectedItems = [ // 宣告類別成員或方法內部的區域變數
    {'name': '茶葉蛋', 'x': 0.3, 'y': 0.4, 'portion': '1 顆', 'calories': '75 kcal'}, // 執行相對應的邏輯計算或設定屬性參數
    {'name': '豆漿', 'x': 0.7, 'y': 0.5, 'portion': '300 ml', 'calories': '120 kcal'}, // 執行相對應的邏輯計算或設定屬性參數
  ]; // 程式碼區塊或元件結構結束

  @override // 標記此方法為覆寫父類別之方法
  void initState() { // 初始化狀態生命週期方法，頁面建立時執行一次
    super.initState(); // 執行相對應的邏輯計算或設定屬性參數
    _loadPetData(); // 執行相對應的邏輯計算或設定屬性參數
    _initCamera(); // 執行相對應的邏輯計算或設定屬性參數
    
    _elfAnimController = AnimationController( // 執行相對應的邏輯計算或設定屬性參數
      vsync: this, // 執行相對應的邏輯計算或設定屬性參數
      duration: const Duration(milliseconds: 1500), // 建立編譯期常數，優化 Flutter 渲染效能
    ); // 程式碼區塊或元件結構結束
    
    _elfPosition = Tween<Offset>( // 執行相對應的邏輯計算或設定屬性參數
      begin: const Offset(0.5, 0.0), // 從右側偏外一點點進來，更平穩，且防出界
      end: const Offset(0.0, 0.0), // 建立編譯期常數，優化 Flutter 渲染效能
    ).animate(CurvedAnimation(parent: _elfAnimController, curve: Curves.elasticOut)); // 執行相對應的邏輯計算或設定屬性參數

    _scanningController = AnimationController( // 執行相對應的邏輯計算或設定屬性參數
      vsync: this, // 執行相對應的邏輯計算或設定屬性參數
      duration: const Duration(seconds: 2), // 建立編譯期常數，優化 Flutter 渲染效能
    )..repeat(reverse: true); // 執行相對應的邏輯計算或設定屬性參數

    // 漂浮與呼吸微動畫
    _hoverController = AnimationController( // 執行相對應的邏輯計算或設定屬性參數
      duration: const Duration(milliseconds: 2000), // 建立編譯期常數，優化 Flutter 渲染效能
      vsync: this, // 執行相對應的邏輯計算或設定屬性參數
    )..repeat(reverse: true); // 執行相對應的邏輯計算或設定屬性參數

    _hoverScaleAnimation = Tween<double>(begin: 0.96, end: 1.04).animate( // 執行相對應的邏輯計算或設定屬性參數
      CurvedAnimation(parent: _hoverController, curve: Curves.easeInOut), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束

    _hoverOffsetAnimation = Tween<double>(begin: -4.0, end: 4.0).animate( // 執行相對應的邏輯計算或設定屬性參數
      CurvedAnimation(parent: _hoverController, curve: Curves.easeInOut), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束

    _elfAnimController.forward(); // 執行相對應的邏輯計算或設定屬性參數
  } // 程式碼區塊或元件結構結束

  Future<void> _loadPetData() async { // 定義非同步方法（Future），執行耗時操作
    final prefs = await SharedPreferences.getInstance(); // 宣告類別成員或方法內部的區域變數
    if (mounted) { // 執行相對應的邏輯計算或設定屬性參數
      setState(() { // 更新狀態數據並通知 UI 重新渲染畫面
        _petType = '米粒(Mili)'; // 執行相對應的邏輯計算或設定屬性參數
        _dietGoal = prefs.getString('user_diet_goal') ?? '養生'; // 執行相對應的邏輯計算或設定屬性參數
      }); // 程式碼區塊或元件結構結束
    } // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  String _getPetImagePath(String petType, String dietGoal) { // 宣告類別成員或方法內部的區域變數
    String path = 'assets/images/shiba_normal.png'; // 宣告類別成員或方法內部的區域變數
    if (dietGoal.contains('減脂')) { // 執行相對應的邏輯計算或設定屬性參數
      path = 'assets/images/shiba_fat.png'; // 執行相對應的邏輯計算或設定屬性參數
    } else if (dietGoal.contains('增肌')) { // 執行相對應的邏輯計算或設定屬性參數
      path = 'assets/images/shiba_muscular.png'; // 執行相對應的邏輯計算或設定屬性參數
    } else if (dietGoal.contains('養生')) { // 執行相對應的邏輯計算或設定屬性參數
      path = 'assets/images/shiba_thin.png'; // 執行相對應的邏輯計算或設定屬性參數
    } // 程式碼區塊或元件結構結束
    return path; // 回傳建構完成的元件或方法計算結果
  } // 程式碼區塊或元件結構結束

  Future<void> _initCamera() async { // 定義非同步方法（Future），執行耗時操作
    final cameras = await availableCameras(); // 宣告類別成員或方法內部的區域變數
    if (cameras.isEmpty) return; // 執行相對應的邏輯計算或設定屬性參數
    
    _controller = CameraController( // 執行相對應的邏輯計算或設定屬性參數
      cameras.first, // 執行相對應的邏輯計算或設定屬性參數
      ResolutionPreset.medium, // 執行相對應的邏輯計算或設定屬性參數
      enableAudio: false, // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束

    _initializeControllerFuture = _controller!.initialize(); // 執行相對應的邏輯計算或設定屬性參數
    if (mounted) setState(() {}); // 更新狀態數據並通知 UI 重新渲染畫面
  } // 程式碼區塊或元件結構結束

  @override // 標記此方法為覆寫父類別之方法
  void dispose() { // 銷毀狀態生命週期方法，釋放頁面資源與控制器
    _controller?.dispose(); // 執行相對應的邏輯計算或設定屬性參數
    _elfAnimController.dispose(); // 執行相對應的邏輯計算或設定屬性參數
    _scanningController.dispose(); // 執行相對應的邏輯計算或設定屬性參數
    _hoverController.dispose(); // 執行相對應的邏輯計算或設定屬性參數
    super.dispose(); // 執行相對應的邏輯計算或設定屬性參數
  } // 程式碼區塊或元件結構結束

  String _getTimeLabel() { // 宣告類別成員或方法內部的區域變數
    final hour = DateTime.now().hour; // 宣告類別成員或方法內部的區域變數
    if (hour >= 5 && hour < 11) return "早餐"; // 回傳建構完成的元件或方法計算結果
    if (hour >= 11 && hour < 17) return "中餐"; // 回傳建構完成的元件或方法計算結果
    return "晚餐"; // 回傳建構完成的元件或方法計算結果
  } // 程式碼區塊或元件結構結束

  String _getCurrentTime() { // 宣告類別成員或方法內部的區域變數
    final now = DateTime.now(); // 宣告類別成員或方法內部的區域變數
    return "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}"; // 回傳建構完成的元件或方法計算結果
  } // 程式碼區塊或元件結構結束

  void _onCapture() async { // 執行相對應的邏輯計算或設定屬性參數
    try { // 執行相對應的邏輯計算或設定屬性參數
      await _initializeControllerFuture; // 執行相對應的邏輯計算或設定屬性參數
      final image = await _controller!.takePicture(); // 宣告類別成員或方法內部的區域變數
      setState(() { // 更新狀態數據並通知 UI 重新渲染畫面
        _capturedImage = image; // 執行相對應的邏輯計算或設定屬性參數
        _currentStage = RecordStage.recognizing; // 執行相對應的邏輯計算或設定屬性參數
      }); // 程式碼區塊或元件結構結束
      
      // 模擬辨識過程 (加速至 0.3 秒)
      Timer(const Duration(milliseconds: 300), () { // 建立編譯期常數，優化 Flutter 渲染效能
        setState(() { // 更新狀態數據並通知 UI 重新渲染畫面
          _currentStage = RecordStage.result; // 執行相對應的邏輯計算或設定屬性參數
        }); // 程式碼區塊或元件結構結束
      }); // 程式碼區塊或元件結構結束
    } catch (e) { // 執行相對應的邏輯計算或設定屬性參數
      debugPrint(e.toString()); // 執行相對應的邏輯計算或設定屬性參數
    } // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  void _showEditDialog(int index) { // 執行相對應的邏輯計算或設定屬性參數
    final item = _detectedItems[index]; // 宣告類別成員或方法內部的區域變數
    final nameController = TextEditingController(text: item['name']); // 宣告類別成員或方法內部的區域變數
    final portionController = TextEditingController(text: item['portion']); // 宣告類別成員或方法內部的區域變數
    final calorieController = TextEditingController(text: item['calories']); // 宣告類別成員或方法內部的區域變數

    showDialog( // 執行相對應的邏輯計算或設定屬性參數
      context: context, // 執行相對應的邏輯計算或設定屬性參數
      builder: (context) => AlertDialog( // 執行相對應的邏輯計算或設定屬性參數
        title: const Text("編輯餐點資訊", style: TextStyle(fontWeight: FontWeight.bold)), // 建立文字顯示元件（Text）
        content: Column( // 建立垂直排列元件（Column），縱向排列多個子元件
          mainAxisSize: MainAxisSize.min, // 執行相對應的邏輯計算或設定屬性參數
          children: [ // 執行相對應的邏輯計算或設定屬性參數
            TextField(controller: nameController, decoration: const InputDecoration(labelText: "名稱")), // 建立文字輸入框元件（TextField）
            TextField(controller: portionController, decoration: const InputDecoration(labelText: "份量")), // 建立文字輸入框元件（TextField）
            TextField(controller: calorieController, decoration: const InputDecoration(labelText: "熱量")), // 建立文字輸入框元件（TextField）
          ], // 執行相對應的邏輯計算或設定屬性參數
        ), // 執行相對應的邏輯計算或設定屬性參數
        actions: [ // 執行相對應的邏輯計算或設定屬性參數
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("取消")), // 導航路由返回：關閉當前頁面並返回上一頁
          ElevatedButton( // 建立常規按鈕（ElevatedButton），點擊時觸作相對應事件
            onPressed: () { // 執行相對應的邏輯計算或設定屬性參數
              setState(() { // 更新狀態數據並通知 UI 重新渲染畫面
                _detectedItems[index] = { // 執行相對應的邏輯計算或設定屬性參數
                  'name': nameController.text, // 執行相對應的邏輯計算或設定屬性參數
                  'portion': portionController.text, // 執行相對應的邏輯計算或設定屬性參數
                  'calories': calorieController.text, // 執行相對應的邏輯計算或設定屬性參數
                  'x': item['x'], // 執行相對應的邏輯計算或設定屬性參數
                  'y': item['y'], // 執行相對應的邏輯計算或設定屬性參數
                }; // 執行相對應的邏輯計算或設定屬性參數
              }); // 程式碼區塊或元件結構結束
              Navigator.pop(context); // 導航路由返回：關閉當前頁面並返回上一頁
            }, // 程式碼區塊或元件結構結束
            child: const Text("儲存"), // 建立文字顯示元件（Text）
          ), // 執行相對應的邏輯計算或設定屬性參數
        ], // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  void _addNewItem() { // 執行相對應的邏輯計算或設定屬性參數
    final nameController = TextEditingController(); // 宣告類別成員或方法內部的區域變數
    final portionController = TextEditingController(); // 宣告類別成員或方法內部的區域變數
    final calorieController = TextEditingController(); // 宣告類別成員或方法內部的區域變數

    showDialog( // 執行相對應的邏輯計算或設定屬性參數
      context: context, // 執行相對應的邏輯計算或設定屬性參數
      builder: (context) => AlertDialog( // 執行相對應的邏輯計算或設定屬性參數
        title: const Text("新增餐點", style: TextStyle(fontWeight: FontWeight.bold)), // 建立文字顯示元件（Text）
        content: Column( // 建立垂直排列元件（Column），縱向排列多個子元件
          mainAxisSize: MainAxisSize.min, // 執行相對應的邏輯計算或設定屬性參數
          children: [ // 執行相對應的邏輯計算或設定屬性參數
            TextField(controller: nameController, decoration: const InputDecoration(labelText: "名稱")), // 建立文字輸入框元件（TextField）
            TextField(controller: portionController, decoration: const InputDecoration(labelText: "份量")), // 建立文字輸入框元件（TextField）
            TextField(controller: calorieController, decoration: const InputDecoration(labelText: "熱量")), // 建立文字輸入框元件（TextField）
          ], // 執行相對應的邏輯計算或設定屬性參數
        ), // 執行相對應的邏輯計算或設定屬性參數
        actions: [ // 執行相對應的邏輯計算或設定屬性參數
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("取消")), // 導航路由返回：關閉當前頁面並返回上一頁
          ElevatedButton( // 建立常規按鈕（ElevatedButton），點擊時觸作相對應事件
            onPressed: () { // 執行相對應的邏輯計算或設定屬性參數
              setState(() { // 更新狀態數據並通知 UI 重新渲染畫面
                _detectedItems.add({ // 執行相對應的邏輯計算或設定屬性參數
                  'name': nameController.text, // 執行相對應的邏輯計算或設定屬性參數
                  'portion': portionController.text, // 執行相對應的邏輯計算或設定屬性參數
                  'calories': calorieController.text, // 執行相對應的邏輯計算或設定屬性參數
                  'x': 0.5, // 默認位置
                  'y': 0.5, // 執行相對應的邏輯計算或設定屬性參數
                }); // 程式碼區塊或元件結構結束
              }); // 程式碼區塊或元件結構結束
              Navigator.pop(context); // 導航路由返回：關閉當前頁面並返回上一頁
            }, // 程式碼區塊或元件結構結束
            child: const Text("新增"), // 建立文字顯示元件（Text）
          ), // 執行相對應的邏輯計算或設定屬性參數
        ], // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  void _deleteItem(int index) { // 執行相對應的邏輯計算或設定屬性參數
    setState(() { // 更新狀態數據並通知 UI 重新渲染畫面
      _detectedItems.removeAt(index); // 執行相對應的邏輯計算或設定屬性參數
    }); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  @override // 標記此方法為覆寫父類別之方法
  Widget build(BuildContext context) { // 建立畫面的主要 build 方法，返回元件樹
    return Scaffold( // 建立頁面的基礎 Scaffold 骨架，提供頁面基本版面佈局
      backgroundColor: Colors.black, // 設定顏色數值（Color）
      body: Stack( // 設定頁面的主要內容區域（body）
        children: [ // 執行相對應的邏輯計算或設定屬性參數
          // 1. 相機預覽或已拍攝圖片
          _buildCameraView(), // 執行相對應的邏輯計算或設定屬性參數

          // 2. 頂部狀態列
          _buildTopOverlay(), // 執行相對應的邏輯計算或設定屬性參數

          // 3. 掃描動畫 (僅在辨識階段顯示)
          // 3. 掃描動畫 (已移除)
          // if (_currentStage == RecordStage.recognizing) _buildScanningEffect(),

          // 4. 小精靈與對話框
          _buildElfOverlay(), // 執行相對應的邏輯計算或設定屬性參數

          // 5. 辨識標籤 (僅在結果階段顯示)
          // 5. 辨識標籤 (已移除)
          // if (_currentStage == RecordStage.result) ..._buildResultLabels(),

          // 6. 底部功能卡片或按鈕
          _buildBottomAction(), // 執行相對應的邏輯計算或設定屬性參數
        ], // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Widget _buildCameraView() { // 定義用於重複使用的 UI 封裝建構方法
    if (_currentStage == RecordStage.shooting) { // 執行相對應的邏輯計算或設定屬性參數
      return FutureBuilder<void>( // 建立異步建構器（FutureBuilder），根據非同步任務狀態渲染不同畫面
        future: _initializeControllerFuture, // 執行相對應的邏輯計算或設定屬性參數
        builder: (context, snapshot) { // 執行相對應的邏輯計算或設定屬性參數
          if (snapshot.connectionState == ConnectionState.done) { // 執行相對應的邏輯計算或設定屬性參數
            return Center( // 建立置中對齊元件（Center），將子元件居中顯示
              child: AspectRatio( // 執行相對應的邏輯計算或設定屬性參數
                aspectRatio: 1.0, // 正方形預覽
                child: CameraPreview(_controller!), // 執行相對應的邏輯計算或設定屬性參數
              ), // 執行相對應的邏輯計算或設定屬性參數
            ); // 程式碼區塊或元件結構結束
          } else { // 程式碼區塊或元件結構結束
            return const Center(child: CircularProgressIndicator(color: Colors.white)); // 建立置中對齊元件（Center），將子元件居中顯示
          } // 程式碼區塊或元件結構結束
        }, // 程式碼區塊或元件結構結束
      ); // 程式碼區塊或元件結構結束
    } else { // 程式碼區塊或元件結構結束
      return Center( // 建立置中對齊元件（Center），將子元件居中顯示
        child: AspectRatio( // 執行相對應的邏輯計算或設定屬性參數
          aspectRatio: 1.0, // 執行相對應的邏輯計算或設定屬性參數
          child: kIsWeb  // 執行相對應的邏輯計算或設定屬性參數
              ? Image.network(_capturedImage!.path, fit: BoxFit.cover) // 執行相對應的邏輯計算或設定屬性參數
              : Image.file(File(_capturedImage!.path), fit: BoxFit.cover), // 執行相對應的邏輯計算或設定屬性參數
        ), // 執行相對應的邏輯計算或設定屬性參數
      ); // 程式碼區塊或元件結構結束
    } // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Widget _buildTopOverlay() { // 定義用於重複使用的 UI 封裝建構方法
    return Positioned( // 建立絕對定位元件（Positioned），用於精確設定子元件在 Stack 中的位置
      top: 0, left: 0, right: 0, // 執行相對應的邏輯計算或設定屬性參數
      child: SafeArea( // 執行相對應的邏輯計算或設定屬性參數
        child: Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), // 設定外邊距或內邊距的數值大小（EdgeInsets）
          child: Row( // 建立水平排列元件（Row），橫向排列多個子元件
            mainAxisAlignment: MainAxisAlignment.spaceBetween, // 執行相對應的邏輯計算或設定屬性參數
            children: [ // 執行相對應的邏輯計算或設定屬性參數
              IconButton( // 建立點擊圖示按鈕（IconButton）
                onPressed: () => Navigator.pop(context), // 導航路由返回：關閉當前頁面並返回上一頁
                icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 28), // 設定顏色數值（Color）
              ), // 執行相對應的邏輯計算或設定屬性參數
              Column( // 建立垂直排列元件（Column），縱向排列多個子元件
                children: [ // 執行相對應的邏輯計算或設定屬性參數
                  Row( // 建立水平排列元件（Row），橫向排列多個子元件
                    children: [ // 執行相對應的邏輯計算或設定屬性參數
                      const Icon(Icons.wb_sunny, color: Colors.orange, size: 20), // 設定顏色數值（Color）
                      const SizedBox(width: 5), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
                      Text( // 建立文字顯示元件（Text）
                        _getTimeLabel(), // 執行相對應的邏輯計算或設定屬性參數
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold), // 設定文字字體大小、顏色與粗細等字型樣式（TextStyle）
                      ), // 執行相對應的邏輯計算或設定屬性參數
                    ], // 執行相對應的邏輯計算或設定屬性參數
                  ), // 執行相對應的邏輯計算或設定屬性參數
                  Text( // 建立文字顯示元件（Text）
                    _getCurrentTime(), // 執行相對應的邏輯計算或設定屬性參數
                    style: const TextStyle(color: Colors.white70, fontSize: 14), // 設定文字字體大小、顏色與粗細等字型樣式（TextStyle）
                  ), // 執行相對應的邏輯計算或設定屬性參數
                ], // 執行相對應的邏輯計算或設定屬性參數
              ), // 執行相對應的邏輯計算或設定屬性參數
              const SizedBox(width: 48), // 平衡返回鍵
            ], // 執行相對應的邏輯計算或設定屬性參數
          ), // 執行相對應的邏輯計算或設定屬性參數
        ), // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Widget _buildScanningEffect() { // 定義用於重複使用的 UI 封裝建構方法
    return Center( // 建立置中對齊元件（Center），將子元件居中顯示
      child: AspectRatio( // 執行相對應的邏輯計算或設定屬性參數
        aspectRatio: 1.0, // 執行相對應的邏輯計算或設定屬性參數
        child: AnimatedBuilder( // 建立動畫建構器（AnimatedBuilder），依照動畫進度重新整理局部 UI
          animation: _scanningController, // 執行相對應的邏輯計算或設定屬性參數
          builder: (context, child) { // 執行相對應的邏輯計算或設定屬性參數
            return Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
              decoration: BoxDecoration( // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
                border: Border.all(color: Colors.blue.withOpacity(0.3), width: 2), // 設定容器的四周邊框線條樣式
              ), // 執行相對應的邏輯計算或設定屬性參數
              child: Stack( // 建立層疊佈局元件（Stack），可將多個子元件重疊顯示
                children: [ // 執行相對應的邏輯計算或設定屬性參數
                  Positioned( // 建立絕對定位元件（Positioned），用於精確設定子元件在 Stack 中的位置
                    top: _scanningController.value * 300, // 模擬掃描線
                    left: 0, right: 0, // 執行相對應的邏輯計算或設定屬性參數
                    child: Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
                      height: 2, // 執行相對應的邏輯計算或設定屬性參數
                      decoration: BoxDecoration( // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
                        boxShadow: [ // 執行相對應的邏輯計算或設定屬性參數
                          BoxShadow(color: Colors.blue.withOpacity(0.8), blurRadius: 1.95, spreadRadius: 0.39), // 設定容器的陰影效果，包括顏色、模糊半徑與偏移量
                        ], // 執行相對應的邏輯計算或設定屬性參數
                      ), // 執行相對應的邏輯計算或設定屬性參數
                    ), // 執行相對應的邏輯計算或設定屬性參數
                  ), // 執行相對應的邏輯計算或設定屬性參數
                ], // 執行相對應的邏輯計算或設定屬性參數
              ), // 執行相對應的邏輯計算或設定屬性參數
            ); // 程式碼區塊或元件結構結束
          }, // 程式碼區塊或元件結構結束
        ), // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Widget _buildElfOverlay() { // 定義用於重複使用的 UI 封裝建構方法
    String moodPrefix = ""; // 宣告類別成員或方法內部的區域變數
    if (_dietGoal.contains('減脂')) { // 執行相對應的邏輯計算或設定屬性參數
      moodPrefix = "【今日心情：輕盈活力】\n"; // 執行相對應的邏輯計算或設定屬性參數
    } else if (_dietGoal.contains('增肌')) { // 執行相對應的邏輯計算或設定屬性參數
      moodPrefix = "【今日心情：能量滿滿】\n"; // 執行相對應的邏輯計算或設定屬性參數
    } else { // 程式碼區塊或元件結構結束
      moodPrefix = "【今日心情：悠然舒暢】\n"; // 執行相對應的邏輯計算或設定屬性參數
    } // 程式碼區塊或元件結構結束

    String msg = ""; // 宣告類別成員或方法內部的區域變數
    if (_currentStage == RecordStage.shooting) msg = "${moodPrefix}我已經好多天\n沒吃蔬菜了"; // 執行相對應的邏輯計算或設定屬性參數
    else if (_currentStage == RecordStage.recognizing) msg = "${moodPrefix}聞...好香\n好像是茶葉蛋"; // 執行相對應的邏輯計算或設定屬性參數
    else msg = "${moodPrefix}這份子不錯，補充蛋白質"; // 執行相對應的邏輯計算或設定屬性參數

    final screenHeight = MediaQuery.of(context).size.height; // 宣告類別成員或方法內部的區域變數
    final bottomOffset = _currentStage == RecordStage.result ? 140.0 : 120.0; // 挪下來一點

    return Positioned( // 建立絕對定位元件（Positioned），用於精確設定子元件在 Stack 中的位置
      bottom: bottomOffset, // 執行相對應的邏輯計算或設定屬性參數
      right: 20, // 執行相對應的邏輯計算或設定屬性參數
      child: Column( // 建立垂直排列元件（Column），縱向排列多個子元件
        crossAxisAlignment: CrossAxisAlignment.end, // 執行相對應的邏輯計算或設定屬性參數
        children: [ // 執行相對應的邏輯計算或設定屬性參數
          // 對話框
          Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10), // 設定外邊距或內邊距的數值大小（EdgeInsets）
            decoration: BoxDecoration( // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
              color: Colors.white.withOpacity(0.9), // 設定顏色數值（Color）
              borderRadius: BorderRadius.circular(20), // 設定容器的圓角弧度半徑大小
              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 1.95)], // 設定容器的陰影效果，包括顏色、模糊半徑與偏移量
            ), // 執行相對應的邏輯計算或設定屬性參數
            child: Text( // 建立文字顯示元件（Text）
              msg,  // 執行相對應的邏輯計算或設定屬性參數
              style: const TextStyle( // 設定文字字體大小、顏色與粗細等字型樣式（TextStyle）
                color: Colors.black, // Explicitly black to prevent default text white theme issue
                fontSize: 14,  // 執行相對應的邏輯計算或設定屬性參數
                fontWeight: FontWeight.bold, // 執行相對應的邏輯計算或設定屬性參數
              ), // 執行相對應的邏輯計算或設定屬性參數
            ), // 執行相對應的邏輯計算或設定屬性參數
          ), // 執行相對應的邏輯計算或設定屬性參數
          const SizedBox(height: 10), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
          // 小精靈圖片 (高品質 3D 渲染圖 + 呼吸浮動微動畫)
          AnimatedBuilder( // 建立動畫建構器（AnimatedBuilder），依照動畫進度重新整理局部 UI
            animation: _hoverController, // 執行相對應的邏輯計算或設定屬性參數
            builder: (context, child) { // 執行相對應的邏輯計算或設定屬性參數
              return Transform.translate( // 回傳建構完成的元件或方法計算結果
                offset: Offset(0, _hoverOffsetAnimation.value), // 執行相對應的邏輯計算或設定屬性參數
                child: Transform.scale( // 執行相對應的邏輯計算或設定屬性參數
                  scale: _hoverScaleAnimation.value, // 執行相對應的邏輯計算或設定屬性參數
                  child: Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
                    width: 80, height: 80, // 執行相對應的邏輯計算或設定屬性參數
                    decoration: BoxDecoration( // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
                      color: Colors.white, // 設定顏色數值（Color）
                      shape: BoxShape.circle, // 執行相對應的邏輯計算或設定屬性參數
                      border: Border.all(color: Colors.blue.shade100, width: 3), // 設定容器的四周邊框線條樣式
                      boxShadow: [ // 執行相對應的邏輯計算或設定屬性參數
                        BoxShadow( // 設定容器的陰影效果，包括顏色、模糊半徑與偏移量
                          color: Colors.black.withOpacity(0.15), // 設定顏色數值（Color）
                          blurRadius: 5, // 執行相對應的邏輯計算或設定屬性參數
                          offset: const Offset(0, 2), // 建立編譯期常數，優化 Flutter 渲染效能
                        ) // 執行相對應的邏輯計算或設定屬性參數
                      ], // 執行相對應的邏輯計算或設定屬性參數
                    ), // 執行相對應的邏輯計算或設定屬性參數
                    child: ClipOval( // 執行相對應的邏輯計算或設定屬性參數
                      child: Padding( // 建立間距容器（Padding），用於設定內部邊距
                        padding: const EdgeInsets.all(5.0), // 設定外邊距或內邊距的數值大小（EdgeInsets）
                        child: Image.asset( // 執行相對應的邏輯計算或設定屬性參數
                          _getPetImagePath(_petType, _dietGoal), // 執行相對應的邏輯計算或設定屬性參數
                          fit: BoxFit.contain, // 執行相對應的邏輯計算或設定屬性參數
                        ), // 執行相對應的邏輯計算或設定屬性參數
                      ), // 執行相對應的邏輯計算或設定屬性參數
                    ), // 執行相對應的邏輯計算或設定屬性參數
                  ), // 執行相對應的邏輯計算或設定屬性參數
                ), // 執行相對應的邏輯計算或設定屬性參數
              ); // 程式碼區塊或元件結構結束
            }, // 程式碼區塊或元件結構結束
          ), // 執行相對應的邏輯計算或設定屬性參數
        ], // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  List<Widget> _buildResultLabels() { // 執行相對應的邏輯計算或設定屬性參數
    return _detectedItems.map((item) { // 回傳建構完成的元件或方法計算結果
      return Positioned( // 建立絕對定位元件（Positioned），用於精確設定子元件在 Stack 中的位置
        left: MediaQuery.of(context).size.width * item['x'], // 執行相對應的邏輯計算或設定屬性參數
        top: MediaQuery.of(context).size.height * 0.3 + (MediaQuery.of(context).size.width * item['y']), // 執行相對應的邏輯計算或設定屬性參數
        child: Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), // 設定外邊距或內邊距的數值大小（EdgeInsets）
          decoration: BoxDecoration( // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
            color: Colors.blue.withOpacity(0.8), // 設定顏色數值（Color）
            borderRadius: BorderRadius.circular(10), // 設定容器的圓角弧度半徑大小
            border: Border.all(color: Colors.white70), // 設定容器的四周邊框線條樣式
          ), // 執行相對應的邏輯計算或設定屬性參數
          child: Text(item['name'], style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)), // 建立文字顯示元件（Text）
        ), // 執行相對應的邏輯計算或設定屬性參數
      ); // 程式碼區塊或元件結構結束
    }).toList(); // 執行相對應的邏輯計算或設定屬性參數
  } // 程式碼區塊或元件結構結束

  Widget _buildBottomAction() { // 定義用於重複使用的 UI 封裝建構方法
    if (_currentStage == RecordStage.result) { // 執行相對應的邏輯計算或設定屬性參數
      return Positioned( // 建立絕對定位元件（Positioned），用於精確設定子元件在 Stack 中的位置
        bottom: 40, left: 0, right: 0, // 執行相對應的邏輯計算或設定屬性參數
        child: Stack( // 建立層疊佈局元件（Stack），可將多個子元件重疊顯示
          alignment: Alignment.center, // 執行相對應的邏輯計算或設定屬性參數
          children: [ // 執行相對應的邏輯計算或設定屬性參數
            // 1. 重拍按鈕 (維持原本相機按鈕樣式)
            GestureDetector( // 建立手勢偵測器（GestureDetector），用於監聽點擊、拖動等觸控事件
              onTap: () { // 執行相對應的邏輯計算或設定屬性參數
                setState(() { // 更新狀態數據並通知 UI 重新渲染畫面
                  _currentStage = RecordStage.shooting; // 執行相對應的邏輯計算或設定屬性參數
                  _capturedImage = null; // 執行相對應的邏輯計算或設定屬性參數
                }); // 程式碼區塊或元件結構結束
              }, // 程式碼區塊或元件結構結束
              child: Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
                width: 80, height: 80, // 執行相對應的邏輯計算或設定屬性參數
                decoration: BoxDecoration( // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
                  shape: BoxShape.circle, // 執行相對應的邏輯計算或設定屬性參數
                  border: Border.all(color: Colors.white, width: 5), // 設定容器的四周邊框線條樣式
                ), // 執行相對應的邏輯計算或設定屬性參數
                child: Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
                  margin: const EdgeInsets.all(5), // 設定外邊距或內邊距的數值大小（EdgeInsets）
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
                  child: const Icon(Icons.camera_alt, color: Colors.black, size: 35), // 設定顏色數值（Color）
                ), // 執行相對應的邏輯計算或設定屬性參數
              ), // 執行相對應的邏輯計算或設定屬性參數
            ), // 執行相對應的邏輯計算或設定屬性參數
            // 2. 確認按鈕 (在右側)
            Positioned( // 建立絕對定位元件（Positioned），用於精確設定子元件在 Stack 中的位置
              right: MediaQuery.of(context).size.width * 0.15, // 執行相對應的邏輯計算或設定屬性參數
              child: GestureDetector( // 建立手勢偵測器（GestureDetector），用於監聽點擊、拖動等觸控事件
                onTap: () { // 執行相對應的邏輯計算或設定屬性參數
                  Navigator.push( // 導航路由跳轉：開啟並推入新頁面
                    context, // 執行相對應的邏輯計算或設定屬性參數
                    MaterialPageRoute( // 執行相對應的邏輯計算或設定屬性參數
                      builder: (context) => ElfFeedingPage( // 執行相對應的邏輯計算或設定屬性參數
                        imagePath: _capturedImage!.path, // 執行相對應的邏輯計算或設定屬性參數
                        items: _detectedItems, // 執行相對應的邏輯計算或設定屬性參數
                      ), // 執行相對應的邏輯計算或設定屬性參數
                    ), // 執行相對應的邏輯計算或設定屬性參數
                  ); // 程式碼區塊或元件結構結束
                }, // 程式碼區塊或元件結構結束
                child: Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
                  width: 65, height: 65, // 執行相對應的邏輯計算或設定屬性參數
                  decoration: BoxDecoration( // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
                    shape: BoxShape.circle, // 執行相對應的邏輯計算或設定屬性參數
                    border: Border.all(color: Colors.blue.shade400, width: 4), // 設定容器的四周邊框線條樣式
                  ), // 執行相對應的邏輯計算或設定屬性參數
                  child: Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
                    margin: const EdgeInsets.all(4), // 設定外邊距或內邊距的數值大小（EdgeInsets）
                    decoration: BoxDecoration(color: Colors.blue.shade400, shape: BoxShape.circle), // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
                    child: const Icon(Icons.check, color: Colors.white, size: 35), // 設定顏色數值（Color）
                  ), // 執行相對應的邏輯計算或設定屬性參數
                ), // 執行相對應的邏輯計算或設定屬性參數
              ), // 執行相對應的邏輯計算或設定屬性參數
            ), // 執行相對應的邏輯計算或設定屬性參數
          ], // 執行相對應的邏輯計算或設定屬性參數
        ), // 執行相對應的邏輯計算或設定屬性參數
      ); // 程式碼區塊或元件結構結束
    } // 程式碼區塊或元件結構結束

    return Positioned( // 建立絕對定位元件（Positioned），用於精確設定子元件在 Stack 中的位置
      bottom: 40, left: 0, right: 0, // 執行相對應的邏輯計算或設定屬性參數
      child: Center( // 建立置中對齊元件（Center），將子元件居中顯示
        child: GestureDetector( // 建立手勢偵測器（GestureDetector），用於監聽點擊、拖動等觸控事件
          onTap: _onCapture, // 執行相對應的邏輯計算或設定屬性參數
          child: Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
            width: 80, height: 80, // 執行相對應的邏輯計算或設定屬性參數
            decoration: BoxDecoration( // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
              shape: BoxShape.circle, // 執行相對應的邏輯計算或設定屬性參數
              border: Border.all(color: Colors.white, width: 5), // 設定容器的四周邊框線條樣式
            ), // 執行相對應的邏輯計算或設定屬性參數
            child: Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
              margin: const EdgeInsets.all(5), // 設定外邊距或內邊距的數值大小（EdgeInsets）
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
              child: const Icon(Icons.camera_alt, color: Colors.black, size: 35), // 設定顏色數值（Color）
            ), // 執行相對應的邏輯計算或設定屬性參數
          ), // 執行相對應的邏輯計算或設定屬性參數
        ), // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Widget _buildNutritionSection() { // 定義用於重複使用的 UI 封裝建構方法
    return Column( // 建立垂直排列元件（Column），縱向排列多個子元件
      crossAxisAlignment: CrossAxisAlignment.start, // 執行相對應的邏輯計算或設定屬性參數
      children: [ // 執行相對應的邏輯計算或設定屬性參數
        const Padding( // 建立間距容器（Padding），用於設定內部邊距
          padding: EdgeInsets.symmetric(horizontal: 20), // 設定外邊距或內邊距的數值大小（EdgeInsets）
          child: Text("營養資訊", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), // 建立文字顯示元件（Text）
        ), // 執行相對應的邏輯計算或設定屬性參數
        const SizedBox(height: 10), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
        Row( // 建立水平排列元件（Row），橫向排列多個子元件
          mainAxisAlignment: MainAxisAlignment.spaceEvenly, // 執行相對應的邏輯計算或設定屬性參數
          children: [ // 執行相對應的邏輯計算或設定屬性參數
            _buildCircularNutrient("195", "總熱量", Colors.blue, 0.45), // 設定顏色數值（Color）
            _buildCircularNutrient("15.9g", "碳水", Colors.orange, 0.6), // 設定顏色數值（Color）
            _buildCircularNutrient("21.2g", "蛋白質", Colors.green, 0.8), // 設定顏色數值（Color）
            _buildCircularNutrient("8.5g", "脂肪", Colors.redAccent, 0.4), // 設定顏色數值（Color）
          ], // 執行相對應的邏輯計算或設定屬性參數
        ), // 執行相對應的邏輯計算或設定屬性參數
      ], // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Widget _buildCircularNutrient(String value, String label, Color color, double percent) { // 定義用於重複使用的 UI 封裝建構方法
    return Column( // 建立垂直排列元件（Column），縱向排列多個子元件
      children: [ // 執行相對應的邏輯計算或設定屬性參數
        Stack( // 建立層疊佈局元件（Stack），可將多個子元件重疊顯示
          alignment: Alignment.center, // 執行相對應的邏輯計算或設定屬性參數
          children: [ // 執行相對應的邏輯計算或設定屬性參數
            SizedBox( // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
              width: 60, height: 60, // 執行相對應的邏輯計算或設定屬性參數
              child: CircularProgressIndicator( // 執行相對應的邏輯計算或設定屬性參數
                value: percent, // 執行相對應的邏輯計算或設定屬性參數
                strokeWidth: 5, // 執行相對應的邏輯計算或設定屬性參數
                backgroundColor: color.withOpacity(0.1), // 執行相對應的邏輯計算或設定屬性參數
                valueColor: AlwaysStoppedAnimation<Color>(color), // 執行相對應的邏輯計算或設定屬性參數
              ), // 執行相對應的邏輯計算或設定屬性參數
            ), // 執行相對應的邏輯計算或設定屬性參數
            Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)), // 建立文字顯示元件（Text）
          ], // 執行相對應的邏輯計算或設定屬性參數
        ), // 執行相對應的邏輯計算或設定屬性參數
        const SizedBox(height: 5), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)), // 建立文字顯示元件（Text）
      ], // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束
} // 程式碼區塊或元件結構結束
