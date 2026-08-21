import 'package:flutter/material.dart'; // 匯入 material.dart 元件庫或套件
import 'package:camera/camera.dart'; // 匯入 camera.dart 元件庫或套件
import 'package:shared_preferences/shared_preferences.dart'; // 匯入 shared_preferences.dart 元件庫或套件
import '../../color/app_colors.dart'; // 匯入 app_colors.dart 元件庫或套件
import '../../utils/friendly_error_message.dart';

class SimpleCameraPage extends StatefulWidget { // 定義 SimpleCameraPage 類別，繼承自 StatefulWidget
  const SimpleCameraPage({super.key}); // 建立編譯期常數，優化 Flutter 渲染效能

  @override // 標記此方法為覆寫父類別之方法
  State<SimpleCameraPage> createState() => _SimpleCameraPageState(); // 執行相對應的邏輯計算或設定屬性參數
} // 程式碼區塊或元件結構結束

class _SimpleCameraPageState extends State<SimpleCameraPage> with SingleTickerProviderStateMixin { // 定義 _SimpleCameraPageState 類別，繼承自 State
  CameraController? _controller; // 執行相對應的邏輯計算或設定屬性參數
  Future<void>? _initializeControllerFuture; // 定義非同步方法（Future），執行耗時操作
  bool _isInitializing = true; // 宣告類別成員或方法內部的區域變數
  String _errorMessage = ''; // 宣告類別成員或方法內部的區域變數
  String _petType = '狗兒'; // 宣告類別成員或方法內部的區域變數
  String _dietGoal = '養生'; // 宣告類別成員或方法內部的區域變數

  late AnimationController _hoverController; // 宣告類別成員或方法內部的區域變數
  late Animation<double> _hoverScaleAnimation; // 宣告類別成員或方法內部的區域變數
  late Animation<double> _hoverOffsetAnimation; // 宣告類別成員或方法內部的區域變數

  @override // 標記此方法為覆寫父類別之方法
  void initState() { // 初始化狀態生命週期方法，頁面建立時執行一次
    super.initState(); // 執行相對應的邏輯計算或設定屬性參數
    _loadPetData(); // 執行相對應的邏輯計算或設定屬性參數
    _initCamera(); // 執行相對應的邏輯計算或設定屬性參數

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
  } // 程式碼區塊或元件結構結束

  Future<void> _initCamera() async { // 定義非同步方法（Future），執行耗時操作
    try { // 執行相對應的邏輯計算或設定屬性參數
      final cameras = await availableCameras(); // 宣告類別成員或方法內部的區域變數
      if (cameras.isEmpty) { // 執行相對應的邏輯計算或設定屬性參數
        setState(() { // 更新狀態數據並通知 UI 重新渲染畫面
          _errorMessage = '找不到相機設備'; // 執行相對應的邏輯計算或設定屬性參數
          _isInitializing = false; // 執行相對應的邏輯計算或設定屬性參數
        }); // 程式碼區塊或元件結構結束
        return; // 執行相對應的邏輯計算或設定屬性參數
      } // 程式碼區塊或元件結構結束

      // 優先使用後置鏡頭，若無則使用第一個相機
      CameraDescription selectedCamera = cameras.first; // 執行相對應的邏輯計算或設定屬性參數
      for (var camera in cameras) { // 執行相對應的邏輯計算或設定屬性參數
        if (camera.lensDirection == CameraLensDirection.back) { // 執行相對應的邏輯計算或設定屬性參數
          selectedCamera = camera; // 執行相對應的邏輯計算或設定屬性參數
          break; // 執行相對應的邏輯計算或設定屬性參數
        } // 程式碼區塊或元件結構結束
      } // 程式碼區塊或元件結構結束

      _controller = CameraController( // 執行相對應的邏輯計算或設定屬性參數
        selectedCamera, // 執行相對應的邏輯計算或設定屬性參數
        ResolutionPreset.medium, // 執行相對應的邏輯計算或設定屬性參數
        enableAudio: false, // 執行相對應的邏輯計算或設定屬性參數
      ); // 程式碼區塊或元件結構結束

      _initializeControllerFuture = _controller!.initialize(); // 執行相對應的邏輯計算或設定屬性參數
      await _initializeControllerFuture; // 執行相對應的邏輯計算或設定屬性參數
      
      if (mounted) { // 執行相對應的邏輯計算或設定屬性參數
        setState(() { // 更新狀態數據並通知 UI 重新渲染畫面
          _isInitializing = false; // 執行相對應的邏輯計算或設定屬性參數
        }); // 程式碼區塊或元件結構結束
      } // 程式碼區塊或元件結構結束
    } catch (e) { // 執行相對應的邏輯計算或設定屬性參數
      if (mounted) { // 執行相對應的邏輯計算或設定屬性參數
        setState(() { // 更新狀態數據並通知 UI 重新渲染畫面
          _errorMessage = FriendlyErrorMessage.camera; // 執行相對應的邏輯計算或設定屬性參數
          _isInitializing = false; // 執行相對應的邏輯計算或設定屬性參數
        }); // 程式碼區塊或元件結構結束
      } // 程式碼區塊或元件結構結束
    } // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  @override // 標記此方法為覆寫父類別之方法
  void dispose() { // 銷毀狀態生命週期方法，釋放頁面資源與控制器
    _controller?.dispose(); // 執行相對應的邏輯計算或設定屬性參數
    _hoverController.dispose(); // 執行相對應的邏輯計算或設定屬性參數
    super.dispose(); // 執行相對應的邏輯計算或設定屬性參數
  } // 程式碼區塊或元件結構結束

  Future<void> _loadPetData() async { // 定義非同步方法（Future），執行耗時操作
    final prefs = await SharedPreferences.getInstance(); // 宣告類別成員或方法內部的區域變數
    if (mounted) { // 執行相對應的邏輯計算或設定屬性參數
      setState(() { // 更新狀態數據並通知 UI 重新渲染畫面
        _petType = '狗兒'; // 執行相對應的邏輯計算或設定屬性參數
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

  String _getElfMood(String dietGoal) { // 宣告類別成員或方法內部的區域變數
    if (dietGoal.contains('減脂')) { // 執行相對應的邏輯計算或設定屬性參數
      return "【今日心情：輕盈活力】\n加油！今天也要吃得健康輕盈喔！"; // 回傳建構完成的元件或方法計算結果
    } else if (dietGoal.contains('增肌')) { // 執行相對應的邏輯計算或設定屬性參數
      return "【今日心情：能量滿滿】\n衝啊！蛋白質補滿，肌肉長高高！"; // 回傳建構完成的元件或方法計算結果
    } else { // 程式碼區塊或元件結構結束
      return "【今日心情：悠然舒暢】\n溫補養生，吃出自然好氣色！"; // 回傳建構完成的元件或方法計算結果
    } // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Widget _buildElfOverlay() { // 定義用於重複使用的 UI 封裝建構方法
    final String moodMsg = _getElfMood(_dietGoal); // 宣告類別成員或方法內部的區域變數

    return Positioned( // 建立絕對定位元件（Positioned），用於精確設定子元件在 Stack 中的位置
      bottom: 140, // 位於底部按鈕區上方
      right: 20, // 執行相對應的邏輯計算或設定屬性參數
      child: Column( // 建立垂直排列元件（Column），縱向排列多個子元件
        crossAxisAlignment: CrossAxisAlignment.end, // 執行相對應的邏輯計算或設定屬性參數
        children: [ // 執行相對應的邏輯計算或設定屬性參數
          // 今日心情對話框
          Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), // 設定外邊距或內邊距的數值大小（EdgeInsets）
            decoration: BoxDecoration( // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
              color: Colors.white.withOpacity(0.9), // 設定顏色數值（Color）
              borderRadius: BorderRadius.circular(15), // 設定容器的圓角弧度半徑大小
              boxShadow: [ // 執行相對應的邏輯計算或設定屬性參數
                BoxShadow( // 設定容器的陰影效果，包括顏色、模糊半徑與偏移量
                  color: Colors.black26,  // 設定顏色數值（Color）
                  blurRadius: 3,  // 執行相對應的邏輯計算或設定屬性參數
                  offset: const Offset(0, 1.5), // 建立編譯期常數，優化 Flutter 渲染效能
                ), // 執行相對應的邏輯計算或設定屬性參數
              ], // 執行相對應的邏輯計算或設定屬性參數
            ), // 執行相對應的邏輯計算或設定屬性參數
            child: Text( // 建立文字顯示元件（Text）
              moodMsg, // 執行相對應的邏輯計算或設定屬性參數
              style: const TextStyle( // 設定文字字體大小、顏色與粗細等字型樣式（TextStyle）
                color: Colors.black, // 設定顏色數值（Color）
                fontSize: 12, // 執行相對應的邏輯計算或設定屬性參數
                fontWeight: FontWeight.bold, // 執行相對應的邏輯計算或設定屬性參數
              ), // 執行相對應的邏輯計算或設定屬性參數
            ), // 執行相對應的邏輯計算或設定屬性參數
          ), // 執行相對應的邏輯計算或設定屬性參數
          const SizedBox(height: 8), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
          // 小精靈圓形頭像框 (高品質 3D 渲染柴犬 + 呼吸漂浮動畫)
          AnimatedBuilder( // 建立動畫建構器（AnimatedBuilder），依照動畫進度重新整理局部 UI
            animation: _hoverController, // 執行相對應的邏輯計算或設定屬性參數
            builder: (context, child) { // 執行相對應的邏輯計算或設定屬性參數
              return Transform.translate( // 回傳建構完成的元件或方法計算結果
                offset: Offset(0, _hoverOffsetAnimation.value), // 執行相對應的邏輯計算或設定屬性參數
                child: Transform.scale( // 執行相對應的邏輯計算或設定屬性參數
                  scale: _hoverScaleAnimation.value, // 執行相對應的邏輯計算或設定屬性參數
                  child: Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
                    width: 70, // 執行相對應的邏輯計算或設定屬性參數
                    height: 70, // 執行相對應的邏輯計算或設定屬性參數
                    decoration: BoxDecoration( // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
                      color: Colors.white, // 設定顏色數值（Color）
                      shape: BoxShape.circle, // 執行相對應的邏輯計算或設定屬性參數
                      border: Border.all(color: AppColors.secondary.withOpacity(0.8), width: 3), // 設定容器的四周邊框線條樣式
                      boxShadow: [ // 執行相對應的邏輯計算或設定屬性參數
                        BoxShadow( // 設定容器的陰影效果，包括顏色、模糊半徑與偏移量
                          color: Colors.black.withOpacity(0.2), // 設定顏色數值（Color）
                          blurRadius: 5, // 執行相對應的邏輯計算或設定屬性參數
                          offset: const Offset(0, 2), // 建立編譯期常數，優化 Flutter 渲染效能
                        ), // 執行相對應的邏輯計算或設定屬性參數
                      ], // 執行相對應的邏輯計算或設定屬性參數
                    ), // 執行相對應的邏輯計算或設定屬性參數
                    child: ClipOval( // 執行相對應的邏輯計算或設定屬性參數
                      child: Padding( // 建立間距容器（Padding），用於設定內部邊距
                        padding: const EdgeInsets.all(4.0), // 設定外邊距或內邊距的數值大小（EdgeInsets）
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

  Future<void> _takePicture() async { // 定義非同步方法（Future），執行耗時操作
    if (_controller == null || !_controller!.value.isInitialized) return; // 執行相對應的邏輯計算或設定屬性參數

    try { // 執行相對應的邏輯計算或設定屬性參數
      final XFile image = await _controller!.takePicture(); // 宣告類別成員或方法內部的區域變數
      if (mounted) { // 執行相對應的邏輯計算或設定屬性參數
        Navigator.pop(context, image); // 導航路由返回：關閉當前頁面並返回上一頁
      } // 程式碼區塊或元件結構結束
    } catch (e) { // 執行相對應的邏輯計算或設定屬性參數
      if (mounted) { // 執行相對應的邏輯計算或設定屬性參數
        ScaffoldMessenger.of(context).showSnackBar( // 執行相對應的邏輯計算或設定屬性參數
          const SnackBar(content: Text(FriendlyErrorMessage.camera)), // 建立文字顯示元件（Text）
        ); // 程式碼區塊或元件結構結束
      } // 程式碼區塊或元件結構結束
    } // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  @override // 標記此方法為覆寫父類別之方法
  Widget build(BuildContext context) { // 建立畫面的主要 build 方法，返回元件樹
    return Scaffold( // 建立頁面的基礎 Scaffold 骨架，提供頁面基本版面佈局
      backgroundColor: Colors.black, // 設定顏色數值（Color）
      appBar: AppBar( // 設定頂部的導航欄（AppBar）
        backgroundColor: Colors.black, // 設定顏色數值（Color）
        elevation: 0, // 執行相對應的邏輯計算或設定屬性參數
        leading: IconButton( // 建立點擊圖示按鈕（IconButton）
          icon: const Icon(Icons.close, color: Colors.white, size: 28), // 設定顏色數值（Color）
          onPressed: () => Navigator.pop(context), // 導航路由返回：關閉當前頁面並返回上一頁
        ), // 執行相對應的邏輯計算或設定屬性參數
        title: const Text('相機拍攝', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), // 建立文字顯示元件（Text）
        centerTitle: true, // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
      body: _buildBody(), // 設定頁面的主要內容區域（body）
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Widget _buildBody() { // 定義用於重複使用的 UI 封裝建構方法
    if (_isInitializing) { // 執行相對應的邏輯計算或設定屬性參數
      return const Center( // 建立置中對齊元件（Center），將子元件居中顯示
        child: CircularProgressIndicator(color: Colors.white), // 設定顏色數值（Color）
      ); // 程式碼區塊或元件結構結束
    } // 程式碼區塊或元件結構結束

    if (_errorMessage.isNotEmpty) { // 執行相對應的邏輯計算或設定屬性參數
      return Center( // 建立置中對齊元件（Center），將子元件居中顯示
        child: Padding( // 建立間距容器（Padding），用於設定內部邊距
          padding: const EdgeInsets.all(20.0), // 設定外邊距或內邊距的數值大小（EdgeInsets）
          child: Column( // 建立垂直排列元件（Column），縱向排列多個子元件
            mainAxisAlignment: MainAxisAlignment.center, // 執行相對應的邏輯計算或設定屬性參數
            children: [ // 執行相對應的邏輯計算或設定屬性參數
              const Icon(Icons.error_outline, color: AppColors.danger, size: 60), // 設定顏色數值（Color）
              const SizedBox(height: 15), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
              Text( // 建立文字顯示元件（Text）
                _errorMessage, // 執行相對應的邏輯計算或設定屬性參數
                style: const TextStyle(color: Colors.white, fontSize: 16), // 設定文字字體大小、顏色與粗細等字型樣式（TextStyle）
                textAlign: TextAlign.center, // 執行相對應的邏輯計算或設定屬性參數
              ), // 執行相對應的邏輯計算或設定屬性參數
              const SizedBox(height: 20), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
              ElevatedButton( // 建立常規按鈕（ElevatedButton），點擊時觸作相對應事件
                onPressed: () { // 執行相對應的邏輯計算或設定屬性參數
                  setState(() { // 更新狀態數據並通知 UI 重新渲染畫面
                    _isInitializing = true; // 執行相對應的邏輯計算或設定屬性參數
                    _errorMessage = ''; // 執行相對應的邏輯計算或設定屬性參數
                  }); // 程式碼區塊或元件結構結束
                  _initCamera(); // 執行相對應的邏輯計算或設定屬性參數
                }, // 程式碼區塊或元件結構結束
                style: ElevatedButton.styleFrom( // 執行相對應的邏輯計算或設定屬性參數
                  backgroundColor: AppColors.primary, // 設定顏色數值（Color）
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), // 設定容器的圓角弧度半徑大小
                ), // 執行相對應的邏輯計算或設定屬性參數
                child: const Text('重試', style: TextStyle(color: Colors.white)), // 建立文字顯示元件（Text）
              ), // 執行相對應的邏輯計算或設定屬性參數
            ], // 執行相對應的邏輯計算或設定屬性參數
          ), // 執行相對應的邏輯計算或設定屬性參數
        ), // 執行相對應的邏輯計算或設定屬性參數
      ); // 程式碼區塊或元件結構結束
    } // 程式碼區塊或元件結構結束

    return Stack( // 建立層疊佈局元件（Stack），可將多個子元件重疊顯示
      children: [ // 執行相對應的邏輯計算或設定屬性參數
        Column( // 建立垂直排列元件（Column），縱向排列多個子元件
          children: [ // 執行相對應的邏輯計算或設定屬性參數
            Expanded( // 建立填充元件（Expanded），自動佔滿 Row 或 Column 的剩餘空間
              child: Center( // 建立置中對齊元件（Center），將子元件居中顯示
                child: AspectRatio( // 執行相對應的邏輯計算或設定屬性參數
                  aspectRatio: _controller!.value.aspectRatio / 2, // 將寬高比除以二以拉高兩倍高度
                  child: CameraPreview(_controller!), // 執行相對應的邏輯計算或設定屬性參數
                ), // 執行相對應的邏輯計算或設定屬性參數
              ), // 建立置中對齊元件（Center），將子元件居中顯示
            ), // 執行相對應的邏輯計算或設定屬性參數
            Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
              height: 120, // 執行相對應的邏輯計算或設定屬性參數
              color: Colors.black, // 設定顏色數值（Color）
              child: Center( // 建立置中對齊元件（Center），將子元件居中顯示
                child: GestureDetector( // 建立手勢偵測器（GestureDetector），用於監聽點擊、拖動等觸控事件
                  onTap: _takePicture, // 執行相對應的邏輯計算或設定屬性參數
                  child: Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
                    width: 76, // 執行相對應的邏輯計算或設定屬性參數
                    height: 76, // 執行相對應的邏輯計算或設定屬性參數
                    decoration: BoxDecoration( // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
                      shape: BoxShape.circle, // 執行相對應的邏輯計算或設定屬性參數
                      border: Border.all(color: Colors.white, width: 4), // 設定容器的四周邊框線條樣式
                    ), // 執行相對應的邏輯計算或設定屬性參數
                    child: Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
                      margin: const EdgeInsets.all(4), // 設定外邊距或內邊距的數值大小（EdgeInsets）
                      decoration: const BoxDecoration( // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
                        color: Colors.white, // 設定顏色數值（Color）
                        shape: BoxShape.circle, // 執行相對應的邏輯計算或設定屬性參數
                      ), // 執行相對應的邏輯計算或設定屬性參數
                    ), // 執行相對應的邏輯計算或設定屬性參數
                  ), // 執行相對應的邏輯計算或設定屬性參數
                ), // 執行相對應的邏輯計算或設定屬性參數
              ), // 執行相對應的邏輯計算或設定屬性參數
            ), // 執行相對應的邏輯計算或設定屬性參數
          ], // 執行相對應的邏輯計算或設定屬性參數
        ), // 執行相對應的邏輯計算或設定屬性參數
        _buildElfOverlay(), // 執行相對應的邏輯計算或設定屬性參數
      ], // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束
} // 程式碼區塊或元件結構結束
