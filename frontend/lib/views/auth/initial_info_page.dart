import 'dart:math';  // 匯入 dart:math 元件庫或套件
import 'package:flutter/material.dart';  // 匯入 material.dart 元件庫或套件
import 'package:flutter/services.dart'; // 匯入 services.dart 元件庫或套件
import 'package:http/http.dart' as http; // 匯入 http.dart 元件庫或套件
import 'dart:convert'; // 匯入 dart:convert 元件庫或套件
import 'package:shared_preferences/shared_preferences.dart'; // 匯入 shared_preferences.dart 元件庫或套件
import '../../config/api_config.dart'; // 匯入 api_config.dart 元件庫或套件
import '../home/home_page.dart'; // 匯入 home_page.dart 元件庫或套件
import 'login_page.dart'; // 匯入 login_page.dart 元件庫或套件
import '../../color/app_colors.dart'; // 匯入 api_config.dart 元件庫或套件
import 'model_viewer_web_stub.dart'
    if (dart.library.html) 'model_viewer_web_impl.dart';

class InitialInfoPage extends StatefulWidget { // 定義 InitialInfoPage 類別，繼承自 StatefulWidget
  // 定義初始資訊填寫頁面 StatefulWidget
  const InitialInfoPage({super.key}); // 建構子

  @override // 標記此方法為覆寫父類別之方法
  State<InitialInfoPage> createState() => _InitialInfoPageState(); // 建立頁面狀態
} // 程式碼區塊或元件結構結束

class _InitialInfoPageState extends State<InitialInfoPage> // 定義 _InitialInfoPageState 類別，繼承自 State
    with TickerProviderStateMixin { // 執行相對應的邏輯計算或設定屬性參數
  // 注入 Ticker 以支援小精靈動畫
  late PageController _pageController; // 宣告分頁控制器
  late AnimationController _pacmanController; // 宣告小精靈嘴巴動畫控制器
  int _currentPage = 0; // 追蹤當前所在頁碼

  static const TextStyle _titleStyle = TextStyle( // 設定文字字體大小、顏色與粗細等字型樣式（TextStyle）
    fontSize: 28, // 執行相對應的邏輯計算或設定屬性參數
    fontWeight: FontWeight.bold, // 執行相對應的邏輯計算或設定屬性參數
    color: AppColors.textPrimary, // 設定顏色數值（Color）
    fontFamily: 'Roboto', // 執行相對應的邏輯計算或設定屬性參數
  ); // 程式碼區塊或元件結構結束

  static const TextStyle _inputTextStyle = TextStyle( // 設定文字字體大小、顏色與粗細等字型樣式（TextStyle）
    // 輸入框字體風格
    fontWeight: FontWeight.bold, // 粗體
    fontSize: 16,  // 執行相對應的邏輯計算或設定屬性參數
  ); // 程式碼區塊或元件結構結束

  static const TextStyle _buttonTextStyle = TextStyle( // 設定文字字體大小、顏色與粗細等字型樣式（TextStyle）
    // 按鈕文字風格
    fontSize: 16,  // 執行相對應的邏輯計算或設定屬性參數

    fontWeight: FontWeight.bold, // 粗體
    color: Colors.black, // 黑色
  ); // 程式碼區塊或元件結構結束

  final Map<int, String> _pageErrors = {}; // 儲存各頁面的錯誤訊息

  String _name = ''; // 保存：姓名 (對應 backend: nickname)
  String _gender = ''; // 保存：性別
  String _age = ''; // 保存：年齡
  String _height = ''; // 保存：身高
  String _weight = ''; // 保存 : 體重
  Set<String> _diseases = {}; // 保存：疾病集 (對應 backend: healthConditions)
  Set<String> _goals = {}; // 保存：目標集 (對應 backend: dietGoal)
  
  // 新增小精靈選擇相關變數
  final List<String> _petOptions = ['狗兒', '狗兒', '狗兒']; // 宣告類別成員或方法內部的區域變數
  int _selectedPetIndex = 0; // 宣告類別成員或方法內部的區域變數
  bool _isSubmitting = false; // 宣告類別成員或方法內部的區域變數

  final List<String> _diseaseOptions = ['糖尿病', '高血壓', '無疾病'];  // 宣告類別成員或方法內部的區域變數
  final List<String> _goalOptions = ['減脂', '增肌', '養生'];  // 宣告類別成員或方法內部的區域變數

  @override // 標記此方法為覆寫父類別之方法
  void initState() { // 初始化狀態生命週期方法，頁面建立時執行一次
    // 狀態初始化
    super.initState(); // 執行父類初始化
    _pageController = PageController(); // 建立分頁控制器實體
    _pacmanController = AnimationController( // 執行相對應的邏輯計算或設定屬性參數
      // 初始化小精靈嘴巴動畫
      vsync: this, // 綁定 Ticker 
      duration: const Duration(milliseconds: 300), // 動畫週期
    )..repeat(reverse: true); // 循環往復播放
  } // 程式碼區塊或元件結構結束

  @override // 標記此方法為覆寫父類別之方法
  void dispose() { // 銷毀狀態生命週期方法，釋放頁面資源與控制器
    // 狀態銷毀時執行
    _pageController.dispose(); // 釋放分頁控制器資源
    _pacmanController.dispose(); // 釋放嘴巴動畫控制器
    super.dispose(); // 執行父類銷毀
  } // 程式碼區塊或元件結構結束

  void _nextPage() { // 執行相對應的邏輯計算或設定屬性參數
    // 下一頁處理邏輯
    print('DEBUG: [邏輯執行] _nextPage 啟動, 目前頁碼: $_currentPage'); // 執行相對應的邏輯計算或設定屬性參數
    if (!_canProceed()) { // 執行相對應的邏輯計算或設定屬性參數
      // 檢查當前頁面是否完成
      final msg = _validationMessage(); // 獲取報錯訊息
      debugPrint('校驗失敗: $msg'); // 執行相對應的邏輯計算或設定屬性參數
      setState(() { // 更新狀態數據並通知 UI 重新渲染畫面
        _pageErrors[_currentPage] = msg; // 記錄該頁錯誤
      }); // 程式碼區塊或元件結構結束
      ScaffoldMessenger.of( // 執行相對應的邏輯計算或設定屬性參數
        context, // 執行相對應的邏輯計算或設定屬性參數
      ).showSnackBar(SnackBar(content: Text(msg))); // 顯示錯誤提示
      return; // 停止執行
    } // 程式碼區塊或元件結構結束

    if (_currentPage < 6) { // 執行相對應的邏輯計算或設定屬性參數
      // 若非最後一頁
      debugPrint('執行翻頁動畫...'); // 執行相對應的邏輯計算或設定屬性參數
      _pageController.nextPage( // 執行相對應的邏輯計算或設定屬性參數
        // 執行翻頁動畫
        duration: const Duration(milliseconds: 500), // 設定動畫時長
        curve: Curves.easeInOut, // 設定動畫曲線
      ); // 程式碼區塊或元件結構結束
    } else { // 程式碼區塊或元件結構結束
      // 若為最後一頁
      debugPrint('已在最後一頁，啟動完成設定流程...'); // 執行相對應的邏輯計算或設定屬性參數
      _completeSetup(); // 執行完成設置
    } // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  void _previousPage() { // 執行相對應的邏輯計算或設定屬性參數
    // 上一頁處理邏輯
    if (_currentPage > 0) { // 執行相對應的邏輯計算或設定屬性參數
      // 若非第一頁
      _pageController.previousPage( // 執行相對應的邏輯計算或設定屬性參數
        // 執行回翻動畫
        duration: const Duration(milliseconds: 400), // 動畫時長
        curve: Curves.easeInOut, // 動畫曲線
      ); // 程式碼區塊或元件結構結束
    } // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  bool _isNumeric(String? s) { // 宣告類別成員或方法內部的區域變數
    // 判斷是否為有效數字的輔助函式
    if (s == null || s.trim().isEmpty) return false; // 回傳建構完成的元件或方法計算結果
    return double.tryParse(s.trim()) != null; // 使用 double.tryParse 嘗試轉換
  } // 程式碼區塊或元件結構結束

  bool _canProceed() { // 宣告類別成員或方法內部的區域變數
    // 頁面校驗判斷
    switch (_currentPage) { // 執行相對應的邏輯計算或設定屬性參數
      // 根據頁碼判斷
      case 0: // 執行相對應的邏輯計算或設定屬性參數
        return _name.trim().isNotEmpty; // 頁面0：名字必填
      case 1: // 執行相對應的邏輯計算或設定屬性參數
        return _gender.isNotEmpty; // 頁面1：性別必選
      case 2: // 執行相對應的邏輯計算或設定屬性參數
        return _isNumeric(_age); // 頁面2：年齡必須是數字
      case 3: // 執行相對應的邏輯計算或設定屬性參數
        return _isNumeric(_height) && _isNumeric(_weight); // 頁面3：身高體重必須是數字
      case 4: // 執行相對應的邏輯計算或設定屬性參數
        return _diseases.isNotEmpty; // 頁面4：疾病必選
      case 5: // 執行相對應的邏輯計算或設定屬性參數
        return _goals.isNotEmpty; // 頁面5：目標必選
      case 6: // 執行相對應的邏輯計算或設定屬性參數
        return true; // 頁面6：精靈選擇暫不強制
      default: // 執行相對應的邏輯計算或設定屬性參數
        return true; // 預設返回 True
    } // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  String _validationMessage() { // 宣告類別成員或方法內部的區域變數
    // 錯誤訊息生成器
    switch (_currentPage) { // 執行相對應的邏輯計算或設定屬性參數
      // 根據頁碼返回對應文字
      case 0: // 執行相對應的邏輯計算或設定屬性參數
        return '請輸入您的名字';  // 回傳建構完成的元件或方法計算結果
      case 1: // 執行相對應的邏輯計算或設定屬性參數
        return '請選擇性別';  // 回傳建構完成的元件或方法計算結果
      case 2: // 執行相對應的邏輯計算或設定屬性參數
        if (_age.trim().isEmpty) return '請輸入年齡'; // 回傳建構完成的元件或方法計算結果
        return '年齡必須為數字';  // 回傳建構完成的元件或方法計算結果
      case 3: // 執行相對應的邏輯計算或設定屬性參數
        if (_height.trim().isEmpty || _weight.trim().isEmpty) return '請輸入身高與體重'; // 回傳建構完成的元件或方法計算結果
        if (!_isNumeric(_height)) return '身高必須為數字'; // 回傳建構完成的元件或方法計算結果
        if (!_isNumeric(_weight)) return '體重必須為數字'; // 回傳建構完成的元件或方法計算結果
        return '請輸入正確的身高與體重';  // 回傳建構完成的元件或方法計算結果
      case 4: // 執行相對應的邏輯計算或設定屬性參數
        return '請選擇是否有特殊疾病';  // 回傳建構完成的元件或方法計算結果
      case 5: // 執行相對應的邏輯計算或設定屬性參數
        return '請選擇至少一個飲食目標';  // 回傳建構完成的元件或方法計算結果
      default: // 執行相對應的邏輯計算或設定屬性參數
        return '請完成本頁內容'; // 其他通用報錯
    } // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Future<void> _completeSetup() async { // 定義非同步方法（Future），執行耗時操作
    // 防止重複提交
    if (_isSubmitting) return; // 執行相對應的邏輯計算或設定屬性參數

    debugPrint('開始啟動提交流程...'); // 執行相對應的邏輯計算或設定屬性參數
    setState(() => _isSubmitting = true); // 更新狀態數據並通知 UI 重新渲染畫面
    
    // 立即顯示提示避免使用者覺得沒反應
    if (mounted) { // 執行相對應的邏輯計算或設定屬性參數
      ScaffoldMessenger.of(context).showSnackBar( // 執行相對應的邏輯計算或設定屬性參數
        const SnackBar(content: Text('正在連線伺服器，請稍候...'), duration: Duration(milliseconds: 1500)), // 建立文字顯示元件（Text）
      ); // 程式碼區塊或元件結構結束
    } // 程式碼區塊或元件結構結束

    try { // 執行相對應的邏輯計算或設定屬性參數
      // 獲取 JWT Token
      final prefs = await SharedPreferences.getInstance(); // 宣告類別成員或方法內部的區域變數
      final token = prefs.getString('jwt_token'); // 宣告類別成員或方法內部的區域變數

      if (token == null) { // 執行相對應的邏輯計算或設定屬性參數
        debugPrint('錯誤: 找不到 token'); // 執行相對應的邏輯計算或設定屬性參數
        if (mounted) { // 執行相對應的邏輯計算或設定屬性參數
          ScaffoldMessenger.of(context).showSnackBar( // 執行相對應的邏輯計算或設定屬性參數
            const SnackBar(content: Text('授權失效，請重新登入')), // 建立文字顯示元件（Text）
          ); // 程式碼區塊或元件結構結束
          Navigator.pushReplacement( // 導航路由跳轉：開啟並推入新頁面
            context, // 執行相對應的邏輯計算或設定屬性參數
            MaterialPageRoute(builder: (context) => const LoginPage()), // 建立編譯期常數，優化 Flutter 渲染效能
          ); // 程式碼區塊或元件結構結束
        } // 程式碼區塊或元件結構結束
        return; // 執行相對應的邏輯計算或設定屬性參數
      } // 程式碼區塊或元件結構結束

      // 封裝用戶數據為 OnboardingRequest 格式 (根據 backend 變數)
      final Map<String, dynamic> onboardingData = { // 宣告類別成員或方法內部的區域變數
        'nickname': _name, // 執行相對應的邏輯計算或設定屬性參數
        'gender': _gender, // 執行相對應的邏輯計算或設定屬性參數
        'age': int.tryParse(_age) ?? 0, // 執行相對應的邏輯計算或設定屬性參數
        'height': double.tryParse(_height) ?? 0, // 執行相對應的邏輯計算或設定屬性參數
        'weight': double.tryParse(_weight) ?? 0, // 執行相對應的邏輯計算或設定屬性參數
        'healthConditions': _diseases.toList(), // 執行相對應的邏輯計算或設定屬性參數
        'dietGoal': _goals.join(', '), // 將 Set 轉為逗號分隔字串
        'petType': _petOptions[_selectedPetIndex], // 執行相對應的邏輯計算或設定屬性參數
      }; // 執行相對應的邏輯計算或設定屬性參數

      debugPrint('提交資料至後端: $onboardingData'); // 執行相對應的邏輯計算或設定屬性參數

      final response = await http.post( // 宣告類別成員或方法內部的區域變數
        Uri.parse('${ApiConfig.baseUrl}/user/onboarding'), // 執行相對應的邏輯計算或設定屬性參數
        headers: { // 執行相對應的邏輯計算或設定屬性參數
          'Content-Type': 'application/json', // 執行相對應的邏輯計算或設定屬性參數
          'Authorization': 'Bearer $token', // 執行相對應的邏輯計算或設定屬性參數
        }, // 程式碼區塊或元件結構結束
        body: jsonEncode(onboardingData), // 設定頁面的主要內容區域（body）
      ).timeout(const Duration(seconds: 15)); // 建立編譯期常數，優化 Flutter 渲染效能

      debugPrint('收到回應狀態碼: ${response.statusCode}'); // 執行相對應的邏輯計算或設定屬性參數

      if (response.statusCode == 200) { // 執行相對應的邏輯計算或設定屬性參數
        final result = jsonDecode(response.body); // 宣告類別成員或方法內部的區域變數
        debugPrint('API 回應內容: $result'); // 執行相對應的邏輯計算或設定屬性參數
        if (result['success'] == true) { // 執行相對應的邏輯計算或設定屬性參數
          if (mounted) { // 執行相對應的邏輯計算或設定屬性參數
            debugPrint('提交成功，切換至首頁'); // 執行相對應的邏輯計算或設定屬性參數
            Navigator.pushReplacement( // 導航路由跳轉：開啟並推入新頁面
              context, // 執行相對應的邏輯計算或設定屬性參數
              MaterialPageRoute( // 執行相對應的邏輯計算或設定屬性參數
                builder: (context) => const HomePage(), // 建立編譯期常數，優化 Flutter 渲染效能
              ), // 執行相對應的邏輯計算或設定屬性參數
            ); // 程式碼區塊或元件結構結束
          } // 程式碼區塊或元件結構結束
        } else { // 程式碼區塊或元件結構結束
          throw Exception(result['message'] ?? '設定失敗'); // 執行相對應的邏輯計算或設定屬性參數
        } // 程式碼區塊或元件結構結束
      } else { // 程式碼區塊或元件結構結束
        throw Exception('連線錯誤: ${response.statusCode}'); // 執行相對應的邏輯計算或設定屬性參數
      } // 程式碼區塊或元件結構結束
    } catch (e) { // 執行相對應的邏輯計算或設定屬性參數
      debugPrint('提交過程發生例外: $e'); // 執行相對應的邏輯計算或設定屬性參數
      if (mounted) { // 執行相對應的邏輯計算或設定屬性參數
        ScaffoldMessenger.of(context).showSnackBar( // 執行相對應的邏輯計算或設定屬性參數
          SnackBar(content: Text('發生錯誤: ${e.toString()}')), // 建立文字顯示元件（Text）
        ); // 程式碼區塊或元件結構結束
      } // 程式碼區塊或元件結構結束
    } finally { // 執行相對應的邏輯計算或設定屬性參數
      if (mounted) setState(() => _isSubmitting = false); // 更新狀態數據並通知 UI 重新渲染畫面
    } // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  @override // 標記此方法為覆寫父類別之方法
  Widget build(BuildContext context) { // 建立畫面的主要 build 方法，返回元件樹
    // 建立畫面 UI
    return Scaffold( // 建立頁面的基礎 Scaffold 骨架，提供頁面基本版面佈局
      body: Container( // 設定頁面的主要內容區域（body）
        // 主容器
        color: AppColors.surface, // 改為主題淺灰背景
        child: Stack( // 建立層疊佈局元件（Stack），可將多個子元件重疊顯示
        // 疊層佈局
        children: [ // 執行相對應的邏輯計算或設定屬性參數
          AnimatedBuilder( // 建立動畫建構器（AnimatedBuilder），依照動畫進度重新整理局部 UI
            // 監聽進度與動畫以平滑移動小精靈
            animation: Listenable.merge([ // 執行相對應的邏輯計算或設定屬性參數
              _pageController, // 執行相對應的邏輯計算或設定屬性參數
              _pacmanController, // 執行相對應的邏輯計算或設定屬性參數
            ]), // 整合兩個動畫源
            builder: (context, child) { // 執行相對應的邏輯計算或設定屬性參數
              return CustomPaint( // 回傳建構完成的元件或方法計算結果
                // 背景手繪筆記本畫布
                painter: HandDrawnNotebookPainter( // 執行相對應的邏輯計算或設定屬性參數
                  scrollProgress: _pageController.hasClients // 執行相對應的邏輯計算或設定屬性參數
                      ? (_pageController.page ?? 0) // 執行相對應的邏輯計算或設定屬性參數
                      : 0, // 傳遞平滑滾動進度
                  mouthProgress: _pacmanController.value, // 傳遞嘴巴張合值
                ), // 執行相對應的邏輯計算或設定屬性參數
                size: Size.infinite, // 鋪滿全屏
              ); // 程式碼區塊或元件結構結束
            }, // 程式碼區塊或元件結構結束
          ), // 執行相對應的邏輯計算或設定屬性參數
          PageView.builder( // 執行相對應的邏輯計算或設定屬性參數
            // 分頁滾動組件
            controller: _pageController, // 控制器連結
            scrollDirection: Axis.vertical, // 垂直捲動模式
            onPageChanged: (index) { // 執行相對應的邏輯計算或設定屬性參數
              // 頁面切換後動作
              setState(() { // 更新狀態數據並通知 UI 重新渲染畫面
                // 更新狀態
                _currentPage = index; // 刷新頁碼
              }); // 程式碼區塊或元件結構結束
            }, // 程式碼區塊或元件結構結束
            pageSnapping: true, // 啟用頁面捕捉 (整頁對齊)
            physics: const PageScrollPhysics(), // 設定分頁物理效果
            itemCount: 7, // 總頁數
            itemBuilder: (context, index) { // 執行相對應的邏輯計算或設定屬性參數
              // 構建分頁內容
              return _buildPageByIndex(index); // 根據索引調用子頁面
            }, // 程式碼區塊或元件結構結束
          ), // 執行相對應的邏輯計算或設定屬性參數
          AnimatedBuilder( // 建立動畫建構器（AnimatedBuilder），依照動畫進度重新整理局部 UI
            // 動畫建構器
            animation: _pageController, // 監聽控制器
            builder: (context, child) { // 執行相對應的邏輯計算或設定屬性參數
              // 建置邏輯
              if (_pageController.positions.isEmpty) { // 執行相對應的邏輯計算或設定屬性參數
                // 檢查位置是否初始化
                return Container(); // 未初始化則不顯示
              } // 程式碼區塊或元件結構結束

              double pageValue = // 宣告類別成員或方法內部的區域變數
                  _pageController.page ?? _currentPage.toDouble(); // 獲取當前偏移值

              if ((pageValue - pageValue.floor()).abs() > 0.01 && // 若正在翻頁過渡中
                  (pageValue - pageValue.floor()).abs() < 0.99) { // 執行相對應的邏輯計算或設定屬性參數
                // 判定過渡區間
                return CustomPaint( // 回傳建構完成的元件或方法計算結果
                  // 顯示翻頁特效畫布
                  painter: PageFlipPainter( // 執行相對應的邏輯計算或設定屬性參數
                    progress: pageValue - pageValue.floor(), // 執行相對應的邏輯計算或設定屬性參數
                  ), // 同步翻頁進度
                  size: Size.infinite, // 鋪滿全屏
                ); // 程式碼區塊或元件結構結束
              } // 程式碼區塊或元件結構結束

              return Container(); // 靜態狀態返回空
            }, // 程式碼區塊或元件結構結束
          ), // 執行相對應的邏輯計算或設定屬性參數
        ], // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    )); // 執行相對應的邏輯計算或設定屬性參數
  } // 程式碼區塊或元件結構結束

  Widget _buildPageContainer({ // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
    // 封裝頁面通用容器
    required String title, // 頁面標題
    required Widget content, // 內容組件
    bool scrollable = true, // 是否可捲動
  }) { // 執行相對應的邏輯計算或設定屬性參數
    return Padding( // 建立間距容器（Padding），用於設定內部邊距
      // 內容邊距設定
      padding: const EdgeInsets.fromLTRB(60, 140, 60, 70), // 設定四邊間距
      child: Stack( // 建立層疊佈局元件（Stack），可將多個子元件重疊顯示
        // 頁面內部疊層
        clipBehavior: Clip.none, // 允許裝飾物溢出
        children: [ // 執行相對應的邏輯計算或設定屬性參數
          Column( // 建立垂直排列元件（Column），縱向排列多個子元件
            // 垂直排列
            crossAxisAlignment: CrossAxisAlignment.start, // 靠左對齊
            children: [ // 執行相對應的邏輯計算或設定屬性參數
              Material( // 執行相對應的邏輯計算或設定屬性參數
                // 標題文字層
                color: Colors.transparent, // 背景透明
                child: Text( // 建立文字顯示元件（Text）
                  // 顯示標題
                  title, // 標題內容
                  style: _titleStyle, // 標題風格
                ), // 執行相對應的邏輯計算或設定屬性參數
              ), // 執行相對應的邏輯計算或設定屬性參數
              const SizedBox(height: 20), // 標題與內容間距
              Expanded( // 建立填充元件（Expanded），自動佔滿 Row 或 Column 的剩餘空間
                // 撐開剩餘空間
                child: // 執行相對應的邏輯計算或設定屬性參數
                    scrollable // 根據設定決定捲動性
                    ? SingleChildScrollView(child: content) // 啟動捲動
                    : content, // 靜態展示
              ), // 執行相對應的邏輯計算或設定屬性參數
              SizedBox(height: scrollable ? 60 : 20), // 底部保留緩衝空間
            ], // 執行相對應的邏輯計算或設定屬性參數
          ), // 執行相對應的邏輯計算或設定屬性參數
          Positioned( // 建立絕對定位元件（Positioned），用於精確設定子元件在 Stack 中的位置
            // 按鈕定位
            bottom: 10, // 執行相對應的邏輯計算或設定屬性參數
            left: 0, // 執行相對應的邏輯計算或設定屬性參數
            right: 0, // 執行相對應的邏輯計算或設定屬性參數
            child: Row( // 建立水平排列元件（Row），橫向排列多個子元件
              mainAxisAlignment: MainAxisAlignment.spaceBetween, // 執行相對應的邏輯計算或設定屬性參數
              children: [ // 執行相對應的邏輯計算或設定屬性參數
                if (_currentPage > 0) // 執行相對應的邏輯計算或設定屬性參數
                  GestureDetector( // 建立手勢偵測器（GestureDetector），用於監聽點擊、拖動等觸控事件
                    behavior: HitTestBehavior.opaque, // 執行相對應的邏輯計算或設定屬性參數
                    onTap: () { // 執行相對應的邏輯計算或設定屬性參數
                      HapticFeedback.selectionClick(); // 執行相對應的邏輯計算或設定屬性參數
                      _previousPage(); // 執行相對應的邏輯計算或設定屬性參數
                    }, // 程式碼區塊或元件結構結束
                    child: Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
                      padding: const EdgeInsets.all(12), // 設定外邊距或內邊距的數值大小（EdgeInsets）
                      child: CustomPaint( // 執行相對應的邏輯計算或設定屬性參數
                        painter: WashiTapeButtonPainter(text: '返回修改'), // 執行相對應的邏輯計算或設定屬性參數
                        size: const Size(110, 40), // 建立編譯期常數，優化 Flutter 渲染效能
                      ), // 執行相對應的邏輯計算或設定屬性參數
                    ), // 執行相對應的邏輯計算或設定屬性參數
                  ) // 執行相對應的邏輯計算或設定屬性參數
                else // 執行相對應的邏輯計算或設定屬性參數
                  const SizedBox(width: 134), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）

                GestureDetector( // 建立手勢偵測器（GestureDetector），用於監聽點擊、拖動等觸控事件
                  behavior: HitTestBehavior.opaque, // 執行相對應的邏輯計算或設定屬性參數
                  onTap: () { // 執行相對應的邏輯計算或設定屬性參數
                    HapticFeedback.mediumImpact(); // 執行相對應的邏輯計算或設定屬性參數
                    if (_isSubmitting) return; // 執行相對應的邏輯計算或設定屬性參數
                    _nextPage(); // 執行相對應的邏輯計算或設定屬性參數
                  }, // 程式碼區塊或元件結構結束
                  child: Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
                    padding: const EdgeInsets.all(12), // 設定外邊距或內邊距的數值大小（EdgeInsets）
                    child: Opacity( // 執行相對應的邏輯計算或設定屬性參數
                      opacity: _isSubmitting ? 0.6 : 1.0, // 執行相對應的邏輯計算或設定屬性參數
                      child: CustomPaint( // 執行相對應的邏輯計算或設定屬性參數
                        painter: WashiTapeButtonPainter( // 執行相對應的邏輯計算或設定屬性參數
                          text: _isSubmitting  // 執行相對應的邏輯計算或設定屬性參數
                              ? '提交中...'  // 執行相對應的邏輯計算或設定屬性參數
                              : (_currentPage == 6 ? '完成' : '下一頁 >'), // 執行相對應的邏輯計算或設定屬性參數
                        ), // 執行相對應的邏輯計算或設定屬性參數
                        size: const Size(110, 40), // 建立編譯期常數，優化 Flutter 渲染效能
                      ), // 執行相對應的邏輯計算或設定屬性參數
                    ), // 執行相對應的邏輯計算或設定屬性參數
                  ), // 執行相對應的邏輯計算或設定屬性參數
                ), // 執行相對應的邏輯計算或設定屬性參數
              ], // 執行相對應的邏輯計算或設定屬性參數
            ), // 執行相對應的邏輯計算或設定屬性參數
          ), // 執行相對應的邏輯計算或設定屬性參數
        ], // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Widget _buildPageByIndex(int index) { // 定義用於重複使用的 UI 封裝建構方法
    // 頁面導引邏輯
    switch (index) { // 執行相對應的邏輯計算或設定屬性參數
      // 分頁控制
      case 0: // 執行相對應的邏輯計算或設定屬性參數
        return _buildNamePage(); // 0號頁：名字
      case 1: // 執行相對應的邏輯計算或設定屬性參數
        return _buildGenderPage(); // 1號頁：性別
      case 2: // 執行相對應的邏輯計算或設定屬性參數
        return _buildAgePage(); // 2號頁：年齡
      case 3: // 執行相對應的邏輯計算或設定屬性參數
        return _buildHeightWeightPage(); // 3號頁：身高體重
      case 4: // 執行相對應的邏輯計算或設定屬性參數
        return _buildDiseasesPage(); // 4號頁：疾病
      case 5: // 執行相對應的邏輯計算或設定屬性參數
        return _buildGoalsPage(); // 5號頁：目標
      case 6: // 執行相對應的邏輯計算或設定屬性參數
        return _buildElfSelectionPage(); // 6號頁：精靈選擇
      default: // 執行相對應的邏輯計算或設定屬性參數
        return _buildNamePage(); // 預設返回名字頁
    } // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Widget _buildNamePage() { // 定義用於重複使用的 UI 封裝建構方法
    // 建構名字頁面
    return _buildPageContainer( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
      title: '嗨！您想我如何稱呼您呢?', // 執行相對應的邏輯計算或設定屬性參數
      content: Column( // 建立垂直排列元件（Column），縱向排列多個子元件
        crossAxisAlignment: CrossAxisAlignment.start, // 執行相對應的邏輯計算或設定屬性參數
        children: [ // 執行相對應的邏輯計算或設定屬性參數
          const SizedBox(height: 40), // 增加間距
            _buildHandDrawnTextField( // 建立文字輸入框元件（TextField）
              '輸入您的名字', // 執行相對應的邏輯計算或設定屬性參數
              (value) => setState(() { // 更新狀態數據並通知 UI 重新渲染畫面
                _name = value; // 執行相對應的邏輯計算或設定屬性參數
                _pageErrors.remove(0); // 執行相對應的邏輯計算或設定屬性參數
              }), // 執行相對應的邏輯計算或設定屬性參數
              initialValue: _name, // 執行相對應的邏輯計算或設定屬性參數
              onSubmitted: _nextPage, // 執行相對應的邏輯計算或設定屬性參數
            ), // 執行相對應的邏輯計算或設定屬性參數
        ], // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Widget _buildGenderPage() { // 定義用於重複使用的 UI 封裝建構方法
    // 建構性別頁面
    return _buildPageContainer( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
      title: '您的性別是?', // 執行相對應的邏輯計算或設定屬性參數
      content: Column( // 建立垂直排列元件（Column），縱向排列多個子元件
        crossAxisAlignment: CrossAxisAlignment.start, // 執行相對應的邏輯計算或設定屬性參數
        children: [ // 執行相對應的邏輯計算或設定屬性參數
          const SizedBox(height: 60), // 增加間距
          Row( // 建立水平排列元件（Row），橫向排列多個子元件
            mainAxisAlignment: MainAxisAlignment.spaceAround, // 執行相對應的邏輯計算或設定屬性參數
            children: [ // 執行相對應的邏輯計算或設定屬性參數
              _buildHandDrawnButton( // 執行相對應的邏輯計算或設定屬性參數
                '男', // 執行相對應的邏輯計算或設定屬性參數
                _gender == '男', // 執行相對應的邏輯計算或設定屬性參數
                () => setState(() { // 更新狀態數據並通知 UI 重新渲染畫面
                  _gender = '男'; // 執行相對應的邏輯計算或設定屬性參數
                  _pageErrors.remove(1); // 執行相對應的邏輯計算或設定屬性參數
                }), // 執行相對應的邏輯計算或設定屬性參數
              ), // 執行相對應的邏輯計算或設定屬性參數
              _buildHandDrawnButton( // 執行相對應的邏輯計算或設定屬性參數
                '女', // 執行相對應的邏輯計算或設定屬性參數
                _gender == '女', // 執行相對應的邏輯計算或設定屬性參數
                () => setState(() { // 更新狀態數據並通知 UI 重新渲染畫面
                  _gender = '女'; // 執行相對應的邏輯計算或設定屬性參數
                  _pageErrors.remove(1); // 執行相對應的邏輯計算或設定屬性參數
                }), // 執行相對應的邏輯計算或設定屬性參數
              ), // 執行相對應的邏輯計算或設定屬性參數
            ], // 執行相對應的邏輯計算或設定屬性參數
          ), // 執行相對應的邏輯計算或設定屬性參數
        ], // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Widget _buildAgePage() { // 定義用於重複使用的 UI 封裝建構方法
    // 建構年齡頁面
    return _buildPageContainer( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
      title: '請輸入您的年齡', // 執行相對應的邏輯計算或設定屬性參數
      content: Column( // 建立垂直排列元件（Column），縱向排列多個子元件
        crossAxisAlignment: CrossAxisAlignment.start, // 執行相對應的邏輯計算或設定屬性參數
        children: [ // 執行相對應的邏輯計算或設定屬性參數
          const SizedBox(height: 40), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
          _buildHandDrawnTextField( // 建立文字輸入框元件（TextField）
            '年齡', // 執行相對應的邏輯計算或設定屬性參數
            (value) => setState(() { // 更新狀態數據並通知 UI 重新渲染畫面
              _age = value; // 執行相對應的邏輯計算或設定屬性參數
              _pageErrors.remove(2); // 執行相對應的邏輯計算或設定屬性參數
            }), // 執行相對應的邏輯計算或設定屬性參數
            isNumber: true, // 執行相對應的邏輯計算或設定屬性參數
            initialValue: _age, // 執行相對應的邏輯計算或設定屬性參數
            onSubmitted: _nextPage, // 執行相對應的邏輯計算或設定屬性參數
          ), // 執行相對應的邏輯計算或設定屬性參數
        ], // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Widget _buildHeightWeightPage() { // 定義用於重複使用的 UI 封裝建構方法
    // 建構身高體重頁面
    return _buildPageContainer( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
      title: '請輸入您的身高與體重', // 執行相對應的邏輯計算或設定屬性參數
      content: Column( // 建立垂直排列元件（Column），縱向排列多個子元件
        crossAxisAlignment: CrossAxisAlignment.start, // 執行相對應的邏輯計算或設定屬性參數
        children: [ // 執行相對應的邏輯計算或設定屬性參數
          const SizedBox(height: 20), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
          Row( // 建立水平排列元件（Row），橫向排列多個子元件
            children: [ // 執行相對應的邏輯計算或設定屬性參數
              Expanded( // 建立填充元件（Expanded），自動佔滿 Row 或 Column 的剩餘空間
                child: Column( // 建立垂直排列元件（Column），縱向排列多個子元件
                  crossAxisAlignment: CrossAxisAlignment.start, // 執行相對應的邏輯計算或設定屬性參數
                  children: [ // 執行相對應的邏輯計算或設定屬性參數
                    Text( // 建立文字顯示元件（Text）
                      '身高', // 執行相對應的邏輯計算或設定屬性參數
                      style: _buttonTextStyle.copyWith(fontSize: 22), // 執行相對應的邏輯計算或設定屬性參數
                    ), // 執行相對應的邏輯計算或設定屬性參數
                    const SizedBox(height: 12), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
                    _buildHandDrawnTextField( // 建立文字輸入框元件（TextField）
                      'cm', // 執行相對應的邏輯計算或設定屬性參數
                      (value) => setState(() { // 更新狀態數據並通知 UI 重新渲染畫面
                        _height = value; // 執行相對應的邏輯計算或設定屬性參數
                        _pageErrors.remove(3); // 執行相對應的邏輯計算或設定屬性參數
                      }), // 執行相對應的邏輯計算或設定屬性參數
                      isNumber: true, // 執行相對應的邏輯計算或設定屬性參數
                      initialValue: _height, // 執行相對應的邏輯計算或設定屬性參數
                      onSubmitted: _nextPage, // 執行相對應的邏輯計算或設定屬性參數
                    ), // 執行相對應的邏輯計算或設定屬性參數
                  ], // 執行相對應的邏輯計算或設定屬性參數
                ), // 執行相對應的邏輯計算或設定屬性參數
              ), // 執行相對應的邏輯計算或設定屬性參數
              const SizedBox(width: 30), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
              Expanded( // 建立填充元件（Expanded），自動佔滿 Row 或 Column 的剩餘空間
                child: Column( // 建立垂直排列元件（Column），縱向排列多個子元件
                  crossAxisAlignment: CrossAxisAlignment.start, // 執行相對應的邏輯計算或設定屬性參數
                  children: [ // 執行相對應的邏輯計算或設定屬性參數
                    Text( // 建立文字顯示元件（Text）
                      '體重', // 執行相對應的邏輯計算或設定屬性參數
                      style: _buttonTextStyle.copyWith(fontSize: 22), // 執行相對應的邏輯計算或設定屬性參數
                    ), // 執行相對應的邏輯計算或設定屬性參數
                    const SizedBox(height: 12), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
                    _buildHandDrawnTextField( // 建立文字輸入框元件（TextField）
                      'kg', // 執行相對應的邏輯計算或設定屬性參數
                      (value) => setState(() { // 更新狀態數據並通知 UI 重新渲染畫面
                        _weight = value; // 執行相對應的邏輯計算或設定屬性參數
                        _pageErrors.remove(3); // 執行相對應的邏輯計算或設定屬性參數
                      }), // 執行相對應的邏輯計算或設定屬性參數
                      isNumber: true, // 執行相對應的邏輯計算或設定屬性參數
                      initialValue: _weight, // 執行相對應的邏輯計算或設定屬性參數
                      onSubmitted: _nextPage, // 執行相對應的邏輯計算或設定屬性參數
                    ), // 執行相對應的邏輯計算或設定屬性參數
                  ], // 執行相對應的邏輯計算或設定屬性參數
                ), // 執行相對應的邏輯計算或設定屬性參數
              ), // 執行相對應的邏輯計算或設定屬性參數
            ], // 執行相對應的邏輯計算或設定屬性參數
          ), // 執行相對應的邏輯計算或設定屬性參數
        ], // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Widget _buildDiseasesPage() { // 定義用於重複使用的 UI 封裝建構方法
    // 建構疾病頁面
    return _buildPageContainer( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
      title: '您是否患有特殊疾病?', // 執行相對應的邏輯計算或設定屬性參數
      content: Column( // 建立垂直排列元件（Column），縱向排列多個子元件
        crossAxisAlignment: CrossAxisAlignment.start, // 執行相對應的邏輯計算或設定屬性參數
        children: [ // 執行相對應的邏輯計算或設定屬性參數
          const SizedBox(height: 20), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
          Wrap( // 執行相對應的邏輯計算或設定屬性參數
            spacing: 20, // 執行相對應的邏輯計算或設定屬性參數
            runSpacing: 20, // 執行相對應的邏輯計算或設定屬性參數
            children: _diseaseOptions // 執行相對應的邏輯計算或設定屬性參數
                .map((disease) => _buildHandDrawnToggleButton( // 執行相對應的邏輯計算或設定屬性參數
                      disease, // 執行相對應的邏輯計算或設定屬性參數
                      _diseases.contains(disease), // 執行相對應的邏輯計算或設定屬性參數
                      () { // 執行相對應的邏輯計算或設定屬性參數
                        setState(() { // 更新狀態數據並通知 UI 重新渲染畫面
                          if (_diseases.contains(disease)) { // 執行相對應的邏輯計算或設定屬性參數
                            _diseases.remove(disease); // 執行相對應的邏輯計算或設定屬性參數
                          } else { // 程式碼區塊或元件結構結束
                            _diseases.add(disease); // 執行相對應的邏輯計算或設定屬性參數
                          } // 程式碼區塊或元件結構結束
                          if (_diseases.isNotEmpty) _pageErrors.remove(4); // 執行相對應的邏輯計算或設定屬性參數
                        }); // 程式碼區塊或元件結構結束
                      }, // 程式碼區塊或元件結構結束
                    )) // 執行相對應的邏輯計算或設定屬性參數
                .toList(), // 執行相對應的邏輯計算或設定屬性參數
          ), // 執行相對應的邏輯計算或設定屬性參數
        ], // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Widget _buildGoalsPage() { // 定義用於重複使用的 UI 封裝建構方法
    // 建構目標頁面
    return _buildPageContainer( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
      title: '您的飲食目標是?', // 執行相對應的邏輯計算或設定屬性參數
      content: Column( // 建立垂直排列元件（Column），縱向排列多個子元件
        crossAxisAlignment: CrossAxisAlignment.start, // 執行相對應的邏輯計算或設定屬性參數
        children: [ // 執行相對應的邏輯計算或設定屬性參數
          const SizedBox(height: 20), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
          Wrap( // 執行相對應的邏輯計算或設定屬性參數
            spacing: 20, // 執行相對應的邏輯計算或設定屬性參數
            runSpacing: 20, // 執行相對應的邏輯計算或設定屬性參數
            children: _goalOptions // 執行相對應的邏輯計算或設定屬性參數
                .map((goal) => _buildHandDrawnToggleButton( // 執行相對應的邏輯計算或設定屬性參數
                      goal, // 執行相對應的邏輯計算或設定屬性參數
                      _goals.contains(goal), // 執行相對應的邏輯計算或設定屬性參數
                      () { // 執行相對應的邏輯計算或設定屬性參數
                        setState(() { // 更新狀態數據並通知 UI 重新渲染畫面
                          if (_goals.contains(goal)) { // 執行相對應的邏輯計算或設定屬性參數
                            _goals.remove(goal); // 執行相對應的邏輯計算或設定屬性參數
                          } else { // 程式碼區塊或元件結構結束
                            _goals.add(goal); // 執行相對應的邏輯計算或設定屬性參數
                          } // 程式碼區塊或元件結構結束
                          if (_goals.isNotEmpty) _pageErrors.remove(5); // 執行相對應的邏輯計算或設定屬性參數
                        }); // 程式碼區塊或元件結構結束
                      }, // 程式碼區塊或元件結構結束
                    )) // 執行相對應的邏輯計算或設定屬性參數
                .toList(), // 執行相對應的邏輯計算或設定屬性參數
          ), // 執行相對應的邏輯計算或設定屬性參數
        ], // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Widget _buildElfSelectionPage() { // 定義用於重複使用的 UI 封裝建構方法
    // 建構精靈選擇頁面
    // 強制選中奶油皮丘，只展示 3D 狗狗
    return _buildPageContainer( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
      // 調用容器
      title: '這是您專屬的小精靈', // 標題
      scrollable: false, // 禁止捲動以保持置中
      content: Stack( // 建立層疊佈局元件（Stack），可將多個子元件重疊顯示
        clipBehavior: Clip.none, // 執行相對應的邏輯計算或設定屬性參數
        alignment: Alignment.center, // 執行相對應的邏輯計算或設定屬性參數
        children: [ // 執行相對應的邏輯計算或設定屬性參數
          Align( // 執行相對應的邏輯計算或設定屬性參數
            alignment: const Alignment(0, -0.55), // 稍微往上一點
            child: _buildHandDrawnBox( // 執行相對應的邏輯計算或設定屬性參數
              width: 300, // 放大0.7倍 (大約1.7x，原本是180)
              height: 300, // 執行相對應的邏輯計算或設定屬性參數
              child: Center( // 建立置中對齊元件（Center），將子元件居中顯示
                child: Column( // 建立垂直排列元件（Column），縱向排列多個子元件
                  mainAxisAlignment: MainAxisAlignment.center, // 執行相對應的邏輯計算或設定屬性參數
                  children: [ // 執行相對應的邏輯計算或設定屬性參數
                    SizedBox(
                      width: 200,
                      height: 200,
                      child: createWebModelView(
                        colorScheme: 'orange',
                        autoSpin: false,
                        scale: 1.4,
                        src: 'assets/images/0606.glb',
                      ),
                    ),
                    const SizedBox(height: 15), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
                    Text( // 建立文字顯示元件（Text）
                      _petOptions[0], // 執行相對應的邏輯計算或設定屬性參數
                      style: const TextStyle( // 設定文字字體大小、顏色與粗細等字型樣式（TextStyle）
                        fontWeight: FontWeight.bold, // 執行相對應的邏輯計算或設定屬性參數
                        fontSize: 30, // 放大字體
                      ), // 執行相對應的邏輯計算或設定屬性參數
                    ), // 執行相對應的邏輯計算或設定屬性參數
                  ], // 執行相對應的邏輯計算或設定屬性參數
                ), // 執行相對應的邏輯計算或設定屬性參數
              ), // 執行相對應的邏輯計算或設定屬性參數
            ), // 執行相對應的邏輯計算或設定屬性參數
          ), // 執行相對應的邏輯計算或設定屬性參數
        ], // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Widget _buildSideNavButton(String direction, VoidCallback onTap) { // 定義用於重複使用的 UI 封裝建構方法
    // 側邊導航組件
    return GestureDetector( // 建立手勢偵測器（GestureDetector），用於監聽點擊、拖動等觸控事件
      // 手勢
      onTap: onTap, // 點擊動作
      child: Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
        // 裝飾容器
        width: 55, // 執行相對應的邏輯計算或設定屬性參數
        height: 100, // 尺寸
        decoration: BoxDecoration( // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
          // 風格
          color: AppColors.primary, // 改為純黑
          borderRadius: BorderRadius.circular(6), // 圓角
          boxShadow: [ // 執行相對應的邏輯計算或設定屬性參數
            BoxShadow( // 設定容器的陰影效果，包括顏色、模糊半徑與偏移量
              color: AppColors.primary.withOpacity(0.2), // 設定顏色數值（Color）
              blurRadius: 0.78, // 執行相對應的邏輯計算或設定屬性參數
              offset: const Offset(0.39, 0.39), // 建立編譯期常數，優化 Flutter 渲染效能
            ), // 執行相對應的邏輯計算或設定屬性參數
          ], // 陰影
        ), // 執行相對應的邏輯計算或設定屬性參數
        alignment: Alignment.center, // 內部置中
        child: CustomPaint( // 執行相對應的邏輯計算或設定屬性參數
          painter: ArrowPainter(direction: direction), // 執行相對應的邏輯計算或設定屬性參數
          size: const Size(25, 25), // 建立編譯期常數，優化 Flutter 渲染效能
        ), // 繪製箭頭
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Widget _buildHandDrawnTextField( // 建立文字輸入框元件（TextField）
    String hint, // 宣告類別成員或方法內部的區域變數
    Function(String) onChanged, { // 執行相對應的邏輯計算或設定屬性參數
    bool isNumber = false, // 宣告類別成員或方法內部的區域變數
    String initialValue = '', // 宣告類別成員或方法內部的區域變數
    VoidCallback? onSubmitted, // 執行相對應的邏輯計算或設定屬性參數
  }) { // 執行相對應的邏輯計算或設定屬性參數
    // 手繪输入框
    return CustomPaint( // 回傳建構完成的元件或方法計算結果
      painter: HandDrawnBoxPainter(), // 執行相對應的邏輯計算或設定屬性參數
      child: Material( // 執行相對應的邏輯計算或設定屬性參數
        color: Colors.transparent, // 設定顏色數值（Color）
        child: Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17), // 放大 0.4 倍
          child: TextField( // 建立文字輸入框元件（TextField）
            controller: TextEditingController.fromValue( // 執行相對應的邏輯計算或設定屬性參數
              TextEditingValue( // 執行相對應的邏輯計算或設定屬性參數
                text: initialValue, // 執行相對應的邏輯計算或設定屬性參數
                selection: TextSelection.fromPosition( // 執行相對應的邏輯計算或設定屬性參數
                  TextPosition(offset: initialValue.length), // 執行相對應的邏輯計算或設定屬性參數
                ), // 執行相對應的邏輯計算或設定屬性參數
              ), // 執行相對應的邏輯計算或設定屬性參數
            ), // 執行相對應的邏輯計算或設定屬性參數
            keyboardType: isNumber ? TextInputType.number : TextInputType.text, // 執行相對應的邏輯計算或設定屬性參數
            onChanged: onChanged, // 執行相對應的邏輯計算或設定屬性參數
            onSubmitted: (_) => onSubmitted?.call(), // 執行相對應的邏輯計算或設定屬性參數
            style: _inputTextStyle, // 執行相對應的邏輯計算或設定屬性參數
            decoration: InputDecoration( // 建立輸入框樣式裝飾（InputDecoration）
              hintText: hint, // 執行相對應的邏輯計算或設定屬性參數
              hintStyle: const TextStyle(color: Colors.grey, fontSize: 20), // 設定文字字體大小、顏色與粗細等字型樣式（TextStyle）
              border: InputBorder.none, // 執行相對應的邏輯計算或設定屬性參數
              isDense: true, // 執行相對應的邏輯計算或設定屬性參數
              contentPadding: EdgeInsets.zero, // 設定外邊距或內邊距的數值大小（EdgeInsets）
            ), // 執行相對應的邏輯計算或設定屬性參數
          ), // 執行相對應的邏輯計算或設定屬性參數
        ), // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Widget _buildHandDrawnButton( // 定義用於重複使用的 UI 封裝建構方法
    String label, // 宣告類別成員或方法內部的區域變數
    bool isSelected, // 宣告類別成員或方法內部的區域變數
    VoidCallback onTap, // 執行相對應的邏輯計算或設定屬性參數
  ) { // 執行相對應的邏輯計算或設定屬性參數
    // 手繪普通按鈕
    return GestureDetector( // 建立手勢偵測器（GestureDetector），用於監聽點擊、拖動等觸控事件
      onTap: onTap, // 執行相對應的邏輯計算或設定屬性參數
      child: CustomPaint( // 執行相對應的邏輯計算或設定屬性參數
        painter: HandDrawnBoxPainter(isSelected: isSelected), // 執行相對應的邏輯計算或設定屬性參數
        child: Material( // 執行相對應的邏輯計算或設定屬性參數
          color: Colors.transparent, // 設定顏色數值（Color）
          child: Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
            padding: const EdgeInsets.symmetric(horizontal: 42, vertical: 20), // 放大 0.4 倍
            child: Text( // 建立文字顯示元件（Text）
              label, // 執行相對應的邏輯計算或設定屬性參數
              style: _buttonTextStyle.copyWith( // 執行相對應的邏輯計算或設定屬性參數
                color: isSelected ? const Color(0xFFFFA500) : Colors.black, // 設定顏色數值（Color）
              ), // 執行相對應的邏輯計算或設定屬性參數
            ), // 執行相對應的邏輯計算或設定屬性參數
          ), // 執行相對應的邏輯計算或設定屬性參數
        ), // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Widget _buildHandDrawnToggleButton( // 定義用於重複使用的 UI 封裝建構方法
    String label, // 宣告類別成員或方法內部的區域變數
    bool isSelected, // 宣告類別成員或方法內部的區域變數
    VoidCallback onTap, // 執行相對應的邏輯計算或設定屬性參數
  ) { // 執行相對應的邏輯計算或設定屬性參數
    // 手繪切換圓角按鈕
    return GestureDetector( // 建立手勢偵測器（GestureDetector），用於監聽點擊、拖動等觸控事件
      onTap: onTap, // 執行相對應的邏輯計算或設定屬性參數
      child: CustomPaint( // 執行相對應的邏輯計算或設定屬性參數
        painter: HandDrawnRoundedBoxPainter(isSelected: isSelected), // 執行相對應的邏輯計算或設定屬性參數
        child: Material( // 執行相對應的邏輯計算或設定屬性參數
          color: Colors.transparent, // 設定顏色數值（Color）
          child: Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14), // 放大 0.4 倍
            child: Text( // 建立文字顯示元件（Text）
              label, // 執行相對應的邏輯計算或設定屬性參數
              style: _buttonTextStyle.copyWith( // 執行相對應的邏輯計算或設定屬性參數
                fontSize: 20, // 放大
                color: isSelected ? const Color(0xFFFFA500) : Colors.black, // 設定顏色數值（Color）
              ), // 執行相對應的邏輯計算或設定屬性參數
            ), // 執行相對應的邏輯計算或設定屬性參數
          ), // 執行相對應的邏輯計算或設定屬性參數
        ), // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Widget _buildHandDrawnBox({ // 定義用於重複使用的 UI 封裝建構方法
    required Widget child, // 執行相對應的邏輯計算或設定屬性參數
    double width = 200, // 宣告類別成員或方法內部的區域變數
    double height = 200, // 宣告類別成員或方法內部的區域變數
  }) { // 執行相對應的邏輯計算或設定屬性參數
    // 純飾性手繪框
    return CustomPaint( // 回傳建構完成的元件或方法計算結果
      painter: HandDrawnBoxPainter(), // 畫筆
      child: Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
        width: width, // 寬度
        height: height, // 高度
        alignment: Alignment.center, // 置中
        child: child, // 所含內容
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束
} // 程式碼區塊或元件結構結束

// ===== 手繪筆記本整體背景繪製器 =====
class HandDrawnNotebookPainter extends CustomPainter { // 定義 HandDrawnNotebookPainter 類別，繼承自 CustomPainter
  // 定義畫筆類別
  final double scrollProgress; // 保存平滑滾動偏移量
  final double mouthProgress; // 保存嘴巴張合進度 (0~1)
  HandDrawnNotebookPainter({ // 執行相對應的邏輯計算或設定屬性參數
    required this.scrollProgress, // 執行相對應的邏輯計算或設定屬性參數
    required this.mouthProgress, // 執行相對應的邏輯計算或設定屬性參數
  }); // 建構子

  @override // 標記此方法為覆寫父類別之方法
  void paint(Canvas canvas, Size size) { // 執行相對應的邏輯計算或設定屬性參數
    // 執行繪製邏輯
    final Rect rect = Offset.zero & size; // 定義全屏矩形
    final Paint paint = Paint()..color = const Color(0xFFF5F0EB); // 設定底色 (米白色)
    canvas.drawRect(rect, paint); // 填滿畫布底色

    // 計算「紙張」的範圍 (留出邊緣)
    double margin = 20; // 邊距
    double paperW = size.width - margin * 2; // 紙張寬度
    double paperH = size.height - margin * 2; // 紙張高度
    Offset paperOrigin = Offset(margin, margin); // 紙張起點

    // 1. 繪製紙張底色 (白色，帶一點手繪不規則感)
    Paint paperPaint = Paint()..color = Colors.white; // 白色畫筆
    Path paperPath = _getHandDrawnRectPath( // 執行相對應的邏輯計算或設定屬性參數
      paperOrigin, // 執行相對應的邏輯計算或設定屬性參數
      paperW, // 執行相對應的邏輯計算或設定屬性參數
      paperH, // 執行相對應的邏輯計算或設定屬性參數
    ); // 獲取手繪路徑

    // 繪製紙張陰影
    canvas.drawShadow( // 執行相對應的邏輯計算或設定屬性參數
      paperPath, // 執行相對應的邏輯計算或設定屬性參數
      Colors.black.withOpacity(0.1), // 設定顏色數值（Color）
      10.0, // 執行相對應的邏輯計算或設定屬性參數
      true, // 執行相對應的邏輯計算或設定屬性參數
    ); // 加上淡淡投影
    canvas.drawPath(paperPath, paperPaint); // 畫出白色紙面

    // 2. 橫線已依需求移除，保持白色頁面純度

    // 3. 繪製活頁孔位與圈環 (位於頂部，製造筆記本感)
    _drawBinderRings(canvas, paperOrigin, paperW); // 調用子函數繪製

    // 4. 繪製頁面進度 UI (Pac-Man 升級版：大尺寸 + 動畫)
    _drawPacManProgress(canvas, paperOrigin, paperW); // 調用子函數繪製

    // 5. 繪製右下角的裝飾性山丘與小人 (最後一頁精靈選擇頁不顯示，且上移避免被按鈕擋住)
    if (scrollProgress < 5.5) { // 執行相對應的邏輯計算或設定屬性參數
      // 判斷是否接近最後一頁
      _drawHillAndFigure(canvas, paperOrigin, paperW, paperH); // 調用子函數繪製
    } // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  // 生成不規則的手繪感矩形路徑
  Path _getHandDrawnRectPath(Offset origin, double w, double h) { // 執行相對應的邏輯計算或設定屬性參數
    // 計算路徑
    Path path = Path(); // 建立路徑實體
    Random rand = Random(); // 亂數產生器

    path.moveTo(origin.dx, origin.dy); // 移動到左上角

    // 頂邊 (由左向右，每 20 像素抖動一次)
    for (double x = 0; x < w; x += 20) { // 執行相對應的邏輯計算或設定屬性參數
      // 迴圈分段
      double nextX = origin.dx + x + 20; // 下一點 X
      path.quadraticBezierTo( // 執行相對應的邏輯計算或設定屬性參數
        // 使用二次貝茲曲線製造彎曲
        origin.dx + x + 10 + rand.nextDouble() * 2, // 控制點 X
        origin.dy - 2 + rand.nextDouble() * 2, // 控制點 Y (抖動)
        nextX, // 終點 X
        origin.dy, // 終點 Y
      ); // 程式碼區塊或元件結構結束
    } // 程式碼區塊或元件結構結束

    // 右邊 (由上向下)
    for (double y = 0; y < h; y += 20) { // 執行相對應的邏輯計算或設定屬性參數
      // 迴圈分段
      double nextY = origin.dy + y + 20; // 下一點 Y
      path.quadraticBezierTo( // 執行相對應的邏輯計算或設定屬性參數
        // 彎曲路徑
        origin.dx + w + 2 + rand.nextDouble() * 2, // 抖動
        origin.dy + y + 10, // 控制點 Y
        origin.dx + w, // 終點 X
        nextY, // 終點 Y
      ); // 程式碼區塊或元件結構結束
    } // 程式碼區塊或元件結構結束

    // 底邊 (由右向左)
    for (double x = w; x > 0; x -= 20) { // 執行相對應的邏輯計算或設定屬性參數
      // 迴圈分段
      double nextX = origin.dx + x - 20; // 下一點 X
      path.quadraticBezierTo( // 執行相對應的邏輯計算或設定屬性參數
        // 彎曲路徑
        origin.dx + x - 10 + rand.nextDouble() * 2, // 抖動
        origin.dy + h + 2 + rand.nextDouble() * 2, // 控制點 Y
        nextX, // 終點 X
        origin.dy + h, // 終點 Y
      ); // 程式碼區塊或元件結構結束
    } // 程式碼區塊或元件結構結束

    // 左邊 (由下向上)
    for (double y = h; y > 0; y -= 20) { // 執行相對應的邏輯計算或設定屬性參數
      // 迴圈分段
      double nextY = origin.dy + y - 20; // 下一點 Y
      path.quadraticBezierTo( // 執行相對應的邏輯計算或設定屬性參數
        // 彎曲路徑
        origin.dx - 2 + rand.nextDouble() * 2, // 控制點 X (抖動)
        origin.dy + y - 10, // 控制點 Y
        origin.dx, // 終點 X
        nextY, // 終點 Y
      ); // 程式碼區塊或元件結構結束
    } // 程式碼區塊或元件結構結束

    path.close(); // 封閉路徑
    return path; // 返回生成的路徑
  } // 程式碼區塊或元件結構結束

  // 繪製活頁線圈 (金屬風格)
  void _drawBinderRings(Canvas canvas, Offset origin, double w) { // 執行相對應的邏輯計算或設定屬性參數
    // 子函數邏輯
    int ringCount = 18; // 線圈數量
    double yPos = origin.dy; // 紙張頂邊位置
    double ringSpacing = w / (ringCount + 1); // 線圈間距

    Paint ringPaint = // 執行相對應的邏輯計算或設定屬性參數
        Paint() // 金屬色畫筆
          ..color = // 執行相對應的邏輯計算或設定屬性參數
              const Color(0xFF707070) // 灰色
          ..style = PaintingStyle // 執行相對應的邏輯計算或設定屬性參數
              .stroke // 描邊
          ..strokeWidth = 2.5; // 線寬

    Paint shadowPaint = // 執行相對應的邏輯計算或設定屬性參數
        Paint() // 陰影畫筆
          ..color = Colors.black // 設定顏色數值（Color）
              .withOpacity(0.2) // 黑色透明
          ..style = PaintingStyle // 執行相對應的邏輯計算或設定屬性參數
              .stroke // 描邊
          ..strokeWidth = 2.5; // 執行相對應的邏輯計算或設定屬性參數

    for (int i = 1; i <= ringCount; i++) { // 執行相對應的邏輯計算或設定屬性參數
      // 根據數量繪製
      double cx = origin.dx + ringSpacing * i; // 計算圓心 X

      canvas.drawArc( // 執行相對應的邏輯計算或設定屬性參數
        // 繪製陰影弧線 (稍微偏移)
        Rect.fromCircle(center: Offset(cx + 1, yPos + 1), radius: 12), // 執行相對應的邏輯計算或設定屬性參數
        -0.8 * pi, // 執行相對應的邏輯計算或設定屬性參數
        1.6 * pi, // 執行相對應的邏輯計算或設定屬性參數
        false, // 執行相對應的邏輯計算或設定屬性參數
        shadowPaint, // 執行相對應的邏輯計算或設定屬性參數
      ); // 程式碼區塊或元件結構結束

      Rect ringRect = Rect.fromCenter( // 建立置中對齊元件（Center），將子元件居中顯示
        center: Offset(cx, yPos), // 執行相對應的邏輯計算或設定屬性參數
        width: 10, // 執行相對應的邏輯計算或設定屬性參數
        height: 24, // 執行相對應的邏輯計算或設定屬性參數
      ); // 線圈橢圓範圍
      canvas.drawArc( // 執行相對應的邏輯計算或設定屬性參數
        ringRect, // 執行相對應的邏輯計算或設定屬性參數
        -0.8 * pi, // 執行相對應的邏輯計算或設定屬性參數
        1.6 * pi, // 執行相對應的邏輯計算或設定屬性參數
        false, // 執行相對應的邏輯計算或設定屬性參數
        ringPaint, // 執行相對應的邏輯計算或設定屬性參數
      ); // 繪製主要金屬圈

      Paint holePaint = Paint()..color = Colors.black; // 孔位畫筆
      canvas.drawCircle(Offset(cx, yPos + 15), 3, holePaint); // 畫出穿紙的小黑洞
    } // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  // 繪製 Pac-Man 進度點 (升級：雙倍大小 + 嘴巴張合動畫 + 平滑移動)
  void _drawPacManProgress(Canvas canvas, Offset origin, double w) { // 執行相對應的邏輯計算或設定屬性參數
    double yPos = origin.dy + 75; // 稍微下移，適配更大的尺寸
    int dotCount = 7; // 進度點數量
    double dotSpacing = w / (dotCount + 1); // 點間距

    for (int i = 1; i <= dotCount; i++) { // 執行相對應的邏輯計算或設定屬性參數
      // 繪製豆子
      double dotX = origin.dx + dotSpacing * i; // 座標 X
      // 根據小精靈當前位置判斷豆子是否被吃掉
      if (i > scrollProgress + 1.2) { // 執行相對應的邏輯計算或設定屬性參數
        Paint dotPaint = Paint()..color = Colors.black; // 設定顏色數值（Color）
        canvas.drawCircle(Offset(dotX, yPos), 7, dotPaint); // 豆子放大一倍 (3.5 -> 7)
      } // 程式碼區塊或元件結構結束
    } // 程式碼區塊或元件結構結束

    // 小精靈位置隨捲動平滑計算
    double pacX = origin.dx + dotSpacing * (scrollProgress + 1); // 宣告類別成員或方法內部的區域變數
    Paint pacPaint = Paint() // 執行相對應的邏輯計算或設定屬性參數
      ..color = const Color(0xFFFFA500) // 設定顏色數值（Color）
      ..style = PaintingStyle.fill; // 執行相對應的邏輯計算或設定屬性參數

    // 計算嘴巴開合角度 (動態張合)
    double openingAngle = 0.1 * pi + (0.25 * pi * mouthProgress); // 嘴巴張開的弧度
    double startAngle = openingAngle; // 起始角
    double sweepAngle = 2 * pi - (2 * openingAngle); // 掃描角 (剩下的圓)

    Path pacPath = Path(); // 建立 Pac-Man 形狀
    pacPath.moveTo(pacX, yPos); // 移至圓心以畫出扇形
    pacPath.arcTo( // 執行相對應的邏輯計算或設定屬性參數
      Rect.fromCircle( // 執行相對應的邏輯計算或設定屬性參數
        center: Offset(pacX, yPos), // 執行相對應的邏輯計算或設定屬性參數
        radius: 14, // 執行相對應的邏輯計算或設定屬性參數
      ), // 半徑放大一倍 (7 -> 14)
      startAngle, // 執行相對應的邏輯計算或設定屬性參數
      sweepAngle, // 執行相對應的邏輯計算或設定屬性參數
      false, // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
    pacPath.close(); // 封閉形成嘴巴
    canvas.drawPath(pacPath, pacPaint); // 填色

    Paint pacStroke = Paint() // 執行相對應的邏輯計算或設定屬性參數
      ..color = Colors.black // 設定顏色數值（Color）
      ..style = PaintingStyle.stroke // 執行相對應的邏輯計算或設定屬性參數
      ..strokeWidth = 2; // 描邊加粗
    canvas.drawPath(pacPath, pacStroke); // 描邊
  } // 程式碼區塊或元件結構結束

  // 繪製山丘與打招呼的小人 (裝飾性內容)
  void _drawHillAndFigure(Canvas canvas, Offset origin, double w, double h) { // 執行相對應的邏輯計算或設定屬性參數
    // 子函數邏輯
    // 將中心點 Y 座標從 h - 70 上移至 h - 160，避免被底部「下一頁」按鈕擋住
    Offset hillCenter = Offset( // 執行相對應的邏輯計算或設定屬性參數
      origin.dx + w - 80, // 執行相對應的邏輯計算或設定屬性參數
      origin.dy + h - 160, // 執行相對應的邏輯計算或設定屬性參數
    ); // 山丘中心定位
    double hillRadius = 35; // 半徑

    Paint hillPaint = Paint()..color = const Color(0xFFD4E5D9); // 水綠色山丘
    canvas.drawArc( // 執行相對應的邏輯計算或設定屬性參數
      Rect.fromCircle(center: hillCenter, radius: hillRadius), // 執行相對應的邏輯計算或設定屬性參數
      pi, // 執行相對應的邏輯計算或設定屬性參數
      pi, // 執行相對應的邏輯計算或設定屬性參數
      false, // 執行相對應的邏輯計算或設定屬性參數
      hillPaint, // 執行相對應的邏輯計算或設定屬性參數
    ); // 畫半圓

    Paint hillBorder = Paint() // 執行相對應的邏輯計算或設定屬性參數
      ..color = Colors.black // 設定顏色數值（Color）
      ..style = PaintingStyle.stroke // 執行相對應的邏輯計算或設定屬性參數
      ..strokeWidth = 2; // 黑邊
    canvas.drawArc( // 執行相對應的邏輯計算或設定屬性參數
      Rect.fromCircle(center: hillCenter, radius: hillRadius), // 執行相對應的邏輯計算或設定屬性參數
      pi, // 執行相對應的邏輯計算或設定屬性參數
      pi, // 執行相對應的邏輯計算或設定屬性參數
      false, // 執行相對應的邏輯計算或設定屬性參數
      hillBorder, // 執行相對應的邏輯計算或設定屬性參數
    ); // 描邊

    Offset headPos = hillCenter.translate(0, -hillRadius / 2 - 5); // 小人頭部位置
    Paint headPaint = Paint() // 執行相對應的邏輯計算或設定屬性參數
      ..color = Colors.white // 設定顏色數值（Color）
      ..style = PaintingStyle.fill; // 白色填充
    Paint headStroke = Paint() // 執行相對應的邏輯計算或設定屬性參數
      ..color = Colors.black // 設定顏色數值（Color）
      ..style = PaintingStyle.stroke // 執行相對應的邏輯計算或設定屬性參數
      ..strokeWidth = 2; // 黑描邊

    canvas.drawCircle(headPos, 7, headPaint); // 畫圓圈頭部 (內部)
    canvas.drawCircle(headPos, 7, headStroke); // 畫圓圈頭部 (邊緣)

    Paint footPaint = Paint() // 執行相對應的邏輯計算或設定屬性參數
      ..color = Colors.black // 設定顏色數值（Color）
      ..strokeWidth = 2; // 腳部畫筆
    canvas.drawLine( // 執行相對應的邏輯計算或設定屬性參數
      headPos.translate(-3, 7), // 執行相對應的邏輯計算或設定屬性參數
      headPos.translate(-3, 14), // 執行相對應的邏輯計算或設定屬性參數
      footPaint, // 執行相對應的邏輯計算或設定屬性參數
    ); // 左腳
    canvas.drawLine( // 執行相對應的邏輯計算或設定屬性參數
      headPos.translate(3, 7), // 執行相對應的邏輯計算或設定屬性參數
      headPos.translate(3, 14), // 執行相對應的邏輯計算或設定屬性參數
      footPaint, // 執行相對應的邏輯計算或設定屬性參數
    ); // 右腳

    TextPainter helloText = TextPainter( // 執行相對應的邏輯計算或設定屬性參數
      // Hello 文字
      text: const TextSpan( // 建立編譯期常數，優化 Flutter 渲染效能
        text: 'Hello!', // 執行相對應的邏輯計算或設定屬性參數
        style: TextStyle( // 設定文字字體大小、顏色與粗細等字型樣式（TextStyle）
          color: Colors.black, // 設定顏色數值（Color）
          fontSize: 14, // 執行相對應的邏輯計算或設定屬性參數
          fontWeight: FontWeight.bold, // 執行相對應的邏輯計算或設定屬性參數
          fontStyle: FontStyle.italic, // 執行相對應的邏輯計算或設定屬性參數
        ), // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
      textDirection: TextDirection.ltr, // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
    helloText.layout(); // 文字排版
    helloText.paint(canvas, headPos.translate(15, -5)); // 在小人右手邊繪製文字
  } // 程式碼區塊或元件結構結束

  @override // 標記此方法為覆寫父類別之方法
  bool shouldRepaint(HandDrawnNotebookPainter oldDelegate) { // 宣告類別成員或方法內部的區域變數
    // 當平滑滾動進度或嘴巴張合值改變時都需要重繪
    return oldDelegate.scrollProgress != scrollProgress || // 回傳建構完成的元件或方法計算結果
        oldDelegate.mouthProgress != mouthProgress; // 執行相對應的邏輯計算或設定屬性參數
  } // 程式碼區塊或元件結構結束
} // 程式碼區塊或元件結構結束

// ===== 手繪風格方框繪製器 =====
class HandDrawnBoxPainter extends CustomPainter { // 定義 HandDrawnBoxPainter 類別，繼承自 CustomPainter
  // 方框畫筆類
  final bool isSelected; // 選中狀態
  HandDrawnBoxPainter({this.isSelected = false}); // 建構子

  @override // 標記此方法為覆寫父類別之方法
  void paint(Canvas canvas, Size size) { // 執行相對應的邏輯計算或設定屬性參數
    // 繪製邏輯
    Path boxPath = Path(); // 建立路徑
    Random rand = Random(); // 隨機數
    boxPath.moveTo(3, 2); // 起點

    for (double x = 0; x < size.width - 3; x += 15) { // 執行相對應的邏輯計算或設定屬性參數
      // 頂邊繪製
      double nextX = (x + 15 > size.width - 3) ? size.width - 3 : x + 15; // 宣告類別成員或方法內部的區域變數
      boxPath.quadraticBezierTo( // 執行相對應的邏輯計算或設定屬性參數
        x + 7.5 + rand.nextDouble() * 2 - 1, // 執行相對應的邏輯計算或設定屬性參數
        1 + rand.nextDouble() * 1.5, // 執行相對應的邏輯計算或設定屬性參數
        nextX, // 執行相對應的邏輯計算或設定屬性參數
        2, // 執行相對應的邏輯計算或設定屬性參數
      ); // 程式碼區塊或元件結構結束
    } // 程式碼區塊或元件結構結束
    for (double y = 0; y < size.height - 3; y += 15) { // 執行相對應的邏輯計算或設定屬性參數
      // 右邊繪製
      double nextY = (y + 15 > size.height - 3) ? size.height - 3 : y + 15; // 宣告類別成員或方法內部的區域變數
      boxPath.quadraticBezierTo( // 執行相對應的邏輯計算或設定屬性參數
        size.width - 1 + rand.nextDouble() * 1, // 執行相對應的邏輯計算或設定屬性參數
        y + 7.5 + rand.nextDouble() * 2 - 1, // 執行相對應的邏輯計算或設定屬性參數
        size.width - 3, // 執行相對應的邏輯計算或設定屬性參數
        nextY, // 執行相對應的邏輯計算或設定屬性參數
      ); // 程式碼區塊或元件結構結束
    } // 程式碼區塊或元件結構結束
    for (double x = size.width - 3; x > 3; x -= 15) { // 執行相對應的邏輯計算或設定屬性參數
      // 底邊繪製 (逆向)
      double nextX = (x - 15 < 3) ? 3 : x - 15; // 宣告類別成員或方法內部的區域變數
      boxPath.quadraticBezierTo( // 執行相對應的邏輯計算或設定屬性參數
        x - 7.5 + rand.nextDouble() * 2 - 1, // 執行相對應的邏輯計算或設定屬性參數
        size.height - 1 + rand.nextDouble() * 1, // 執行相對應的邏輯計算或設定屬性參數
        nextX, // 執行相對應的邏輯計算或設定屬性參數
        size.height - 3, // 執行相對應的邏輯計算或設定屬性參數
      ); // 程式碼區塊或元件結構結束
    } // 程式碼區塊或元件結構結束
    for (double y = size.height - 3; y > 3; y -= 15) { // 執行相對應的邏輯計算或設定屬性參數
      // 左邊繪製 (逆向)
      double nextY = (y - 15 < 3) ? 3 : y - 15; // 宣告類別成員或方法內部的區域變數
      boxPath.quadraticBezierTo( // 執行相對應的邏輯計算或設定屬性參數
        1 + rand.nextDouble() * 1, // 執行相對應的邏輯計算或設定屬性參數
        y - 7.5 + rand.nextDouble() * 2 - 1, // 執行相對應的邏輯計算或設定屬性參數
        3, // 執行相對應的邏輯計算或設定屬性參數
        nextY, // 執行相對應的邏輯計算或設定屬性參數
      ); // 程式碼區塊或元件結構結束
    } // 程式碼區塊或元件結構結束
    boxPath.close(); // 封閉

    Paint fillPaint = Paint() // 執行相對應的邏輯計算或設定屬性參數
      ..color = isSelected ? AppColors.surface : AppColors.background // 設定顏色數值（Color）
      ..style = PaintingStyle.fill; // 背景筆

    canvas.drawPath( // 執行相對應的邏輯計算或設定屬性參數
      boxPath.shift(const Offset(8, 10)),  // 建立編譯期常數，優化 Flutter 渲染效能
      Paint() // 執行相對應的邏輯計算或設定屬性參數
        ..color = AppColors.primary.withOpacity(0.4) // 設定顏色數值（Color）
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.12) // 建立編譯期常數，優化 Flutter 渲染效能
    ); // 程式碼區塊或元件結構結束

    canvas.drawPath(boxPath, fillPaint); // 畫填充
  } // 程式碼區塊或元件結構結束

  @override // 標記此方法為覆寫父類別之方法
  bool shouldRepaint(HandDrawnBoxPainter oldDelegate) => // 宣告類別成員或方法內部的區域變數
      oldDelegate.isSelected != isSelected; // 狀態改變重繪
} // 程式碼區塊或元件結構結束

// ===== 圓角手繪方框繪製器 =====
class HandDrawnRoundedBoxPainter extends CustomPainter { // 定義 HandDrawnRoundedBoxPainter 類別，繼承自 CustomPainter
  // 圓角方框類
  final bool isSelected; // 宣告類別成員或方法內部的區域變數
  HandDrawnRoundedBoxPainter({this.isSelected = false}); // 執行相對應的邏輯計算或設定屬性參數

  @override // 標記此方法為覆寫父類別之方法
  void paint(Canvas canvas, Size size) { // 執行相對應的邏輯計算或設定屬性參數
    Random rand = Random(); // 執行相對應的邏輯計算或設定屬性參數
    Path path = Path(); // 執行相對應的邏輯計算或設定屬性參數
    const double cornerRadius = 12; // 建立編譯期常數，優化 Flutter 渲染效能

    path.moveTo(cornerRadius + 2, 2); // 執行相對應的邏輯計算或設定屬性參數
    for ( // 執行相對應的邏輯計算或設定屬性參數
      double x = cornerRadius + 2; // 宣告類別成員或方法內部的區域變數
      x < size.width - cornerRadius - 2; // 執行相對應的邏輯計算或設定屬性參數
      x += 12 // 執行相對應的邏輯計算或設定屬性參數
    ) { // 執行相對應的邏輯計算或設定屬性參數
      // 頂邊
      double nextX = (x + 12 > size.width - cornerRadius - 2) // 宣告類別成員或方法內部的區域變數
          ? size.width - cornerRadius - 2 // 執行相對應的邏輯計算或設定屬性參數
          : x + 12; // 執行相對應的邏輯計算或設定屬性參數
      path.quadraticBezierTo( // 執行相對應的邏輯計算或設定屬性參數
        x + 6 + rand.nextDouble(), // 執行相對應的邏輯計算或設定屬性參數
        1 + rand.nextDouble(), // 執行相對應的邏輯計算或設定屬性參數
        nextX, // 執行相對應的邏輯計算或設定屬性參數
        2, // 執行相對應的邏輯計算或設定屬性參數
      ); // 程式碼區塊或元件結構結束
    } // 程式碼區塊或元件結構結束
    path.quadraticBezierTo( // 執行相對應的邏輯計算或設定屬性參數
      size.width - 2, // 執行相對應的邏輯計算或設定屬性參數
      2, // 執行相對應的邏輯計算或設定屬性參數
      size.width - 3, // 執行相對應的邏輯計算或設定屬性參數
      cornerRadius + 2, // 執行相對應的邏輯計算或設定屬性參數
    ); // 右上角
    for ( // 執行相對應的邏輯計算或設定屬性參數
      double y = cornerRadius + 2; // 宣告類別成員或方法內部的區域變數
      y < size.height - cornerRadius - 2; // 執行相對應的邏輯計算或設定屬性參數
      y += 12 // 執行相對應的邏輯計算或設定屬性參數
    ) { // 執行相對應的邏輯計算或設定屬性參數
      // 右邊
      double nextY = (y + 12 > size.height - cornerRadius - 2) // 宣告類別成員或方法內部的區域變數
          ? size.height - cornerRadius - 2 // 執行相對應的邏輯計算或設定屬性參數
          : y + 12; // 執行相對應的邏輯計算或設定屬性參數
      path.quadraticBezierTo( // 執行相對應的邏輯計算或設定屬性參數
        size.width - 1 + rand.nextDouble(), // 執行相對應的邏輯計算或設定屬性參數
        y + 6 + rand.nextDouble(), // 執行相對應的邏輯計算或設定屬性參數
        size.width - 3, // 執行相對應的邏輯計算或設定屬性參數
        nextY, // 執行相對應的邏輯計算或設定屬性參數
      ); // 程式碼區塊或元件結構結束
    } // 程式碼區塊或元件結構結束
    path.quadraticBezierTo( // 執行相對應的邏輯計算或設定屬性參數
      size.width - 2, // 執行相對應的邏輯計算或設定屬性參數
      size.height - 2, // 執行相對應的邏輯計算或設定屬性參數
      size.width - cornerRadius - 2, // 執行相對應的邏輯計算或設定屬性參數
      size.height - 3, // 執行相對應的邏輯計算或設定屬性參數
    ); // 右下角
    for ( // 執行相對應的邏輯計算或設定屬性參數
      double x = size.width - cornerRadius - 2; // 宣告類別成員或方法內部的區域變數
      x > cornerRadius + 2; // 執行相對應的邏輯計算或設定屬性參數
      x -= 12 // 執行相對應的邏輯計算或設定屬性參數
    ) { // 執行相對應的邏輯計算或設定屬性參數
      // 底邊
      double nextX = (x - 12 < cornerRadius + 2) ? cornerRadius + 2 : x - 12; // 宣告類別成員或方法內部的區域變數
      path.quadraticBezierTo( // 執行相對應的邏輯計算或設定屬性參數
        x - 6 + rand.nextDouble(), // 執行相對應的邏輯計算或設定屬性參數
        size.height - 1 + rand.nextDouble(), // 執行相對應的邏輯計算或設定屬性參數
        nextX, // 執行相對應的邏輯計算或設定屬性參數
        size.height - 3, // 執行相對應的邏輯計算或設定屬性參數
      ); // 程式碼區塊或元件結構結束
    } // 程式碼區塊或元件結構結束
    path.quadraticBezierTo( // 執行相對應的邏輯計算或設定屬性參數
      2, // 執行相對應的邏輯計算或設定屬性參數
      size.height - 2, // 執行相對應的邏輯計算或設定屬性參數
      3, // 執行相對應的邏輯計算或設定屬性參數
      size.height - cornerRadius - 2, // 執行相對應的邏輯計算或設定屬性參數
    ); // 左下角
    for ( // 執行相對應的邏輯計算或設定屬性參數
      double y = size.height - cornerRadius - 2; // 宣告類別成員或方法內部的區域變數
      y > cornerRadius + 2; // 執行相對應的邏輯計算或設定屬性參數
      y -= 12 // 執行相對應的邏輯計算或設定屬性參數
    ) { // 執行相對應的邏輯計算或設定屬性參數
      // 左邊
      double nextY = (y - 12 < cornerRadius + 2) ? cornerRadius + 2 : y - 12; // 宣告類別成員或方法內部的區域變數
      path.quadraticBezierTo( // 執行相對應的邏輯計算或設定屬性參數
        1 + rand.nextDouble(), // 執行相對應的邏輯計算或設定屬性參數
        y - 6 + rand.nextDouble(), // 執行相對應的邏輯計算或設定屬性參數
        3, // 執行相對應的邏輯計算或設定屬性參數
        nextY, // 執行相對應的邏輯計算或設定屬性參數
      ); // 程式碼區塊或元件結構結束
    } // 程式碼區塊或元件結構結束
    path.quadraticBezierTo(2, 2, cornerRadius + 2, 2); // 左上角返航
    path.close(); // 執行相對應的邏輯計算或設定屬性參數

    Paint fillPaint = Paint() // 執行相對應的邏輯計算或設定屬性參數
      ..color = isSelected ? AppColors.surface : AppColors.background; // 設定顏色數值（Color）

    canvas.drawPath( // 執行相對應的邏輯計算或設定屬性參數
      path.shift(const Offset(8, 10)),  // 建立編譯期常數，優化 Flutter 渲染效能
      Paint() // 執行相對應的邏輯計算或設定屬性參數
        ..color = AppColors.primary.withOpacity(0.4) // 設定顏色數值（Color）
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.12) // 建立編譯期常數，優化 Flutter 渲染效能
    ); // 程式碼區塊或元件結構結束

    canvas.drawPath(path, fillPaint); // 執行相對應的邏輯計算或設定屬性參數
    canvas.drawPath(path, fillPaint); // 執行相對應的邏輯計算或設定屬性參數
  } // 程式碼區塊或元件結構結束

  @override // 標記此方法為覆寫父類別之方法
  bool shouldRepaint(HandDrawnRoundedBoxPainter oldDelegate) => // 宣告類別成員或方法內部的區域變數
      oldDelegate.isSelected != isSelected; // 執行相對應的邏輯計算或設定屬性參數
} // 程式碼區塊或元件結構結束

// ===== 手寫風格箭頭繪製器 =====
class ArrowPainter extends CustomPainter { // 定義 ArrowPainter 類別，繼承自 CustomPainter
  // 箭頭繪製類
  final String direction; // 'left' 或 'right'
  ArrowPainter({required this.direction}); // 執行相對應的邏輯計算或設定屬性參數

  @override // 標記此方法為覆寫父類別之方法
  void paint(Canvas canvas, Size size) { // 執行相對應的邏輯計算或設定屬性參數
    Paint arrowPaint = Paint() // 執行相對應的邏輯計算或設定屬性參數
      ..color = AppColors.background // 設定顏色數值（Color）
      ..strokeWidth = 3.0 // 執行相對應的邏輯計算或設定屬性參數
      ..style = PaintingStyle.stroke // 執行相對應的邏輯計算或設定屬性參數
      ..strokeCap = StrokeCap.round; // 採用白色加粗箭頭以突顯
    double cx = size.width / 2; // 中心 X
    double cy = size.height / 2; // 中心 Y

    if (direction == 'left') { // 執行相對應的邏輯計算或設定屬性參數
      // 左箭頭
      canvas.drawLine(Offset(cx + 6, cy - 10), Offset(cx - 6, cy), arrowPaint); // 執行相對應的邏輯計算或設定屬性參數
      canvas.drawLine(Offset(cx - 6, cy), Offset(cx + 6, cy + 10), arrowPaint); // 執行相對應的邏輯計算或設定屬性參數
    } else { // 程式碼區塊或元件結構結束
      // 右箭頭
      canvas.drawLine(Offset(cx - 6, cy - 10), Offset(cx + 6, cy), arrowPaint); // 執行相對應的邏輯計算或設定屬性參數
      canvas.drawLine(Offset(cx + 6, cy), Offset(cx - 6, cy + 10), arrowPaint); // 執行相對應的邏輯計算或設定屬性參數
    } // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  @override // 標記此方法為覆寫父類別之方法
  bool shouldRepaint(ArrowPainter oldDelegate) => // 宣告類別成員或方法內部的區域變數
      oldDelegate.direction != direction; // 執行相對應的邏輯計算或設定屬性參數
} // 程式碼區塊或元件結構結束

// ===== 翻頁動畫繪製器 =====
class PageFlipPainter extends CustomPainter { // 定義 PageFlipPainter 類別，繼承自 CustomPainter
  // 翻頁視覺效果
  final double progress; // 進度 0~1
  PageFlipPainter({required this.progress}); // 執行相對應的邏輯計算或設定屬性參數

  @override // 標記此方法為覆寫父類別之方法
  void paint(Canvas canvas, Size size) { // 執行相對應的邏輯計算或設定屬性參數
    double y = size.height * (1 - progress); // 翻轉邊緣線 Y
    Paint shadowPaint = Paint() // 執行相對應的邏輯計算或設定屬性參數
      ..color = Colors.black.withOpacity(progress * 0.25) // 設定顏色數值（Color）
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12); // 建立編譯期常數，優化 Flutter 渲染效能
    canvas.drawRect( // 執行相對應的邏輯計算或設定屬性參數
      Rect.fromLTWH(0, y - 30, size.width, 60), // 執行相對應的邏輯計算或設定屬性參數
      shadowPaint, // 執行相對應的邏輯計算或設定屬性參數
    ); // 畫出滾動陰影
    Paint edgePaint = Paint() // 執行相對應的邏輯計算或設定屬性參數
      ..color = Colors.white.withOpacity(progress * 0.4) // 設定顏色數值（Color）
      ..strokeWidth = 3; // 執行相對應的邏輯計算或設定屬性參數
    canvas.drawLine(Offset(0, y), Offset(size.width, y), edgePaint); // 手繪邊緣光澤
  } // 程式碼區塊或元件結構結束

  @override // 標記此方法為覆寫父類別之方法
  bool shouldRepaint(PageFlipPainter oldDelegate) => // 宣告類別成員或方法內部的區域變數
      oldDelegate.progress != progress; // 執行相對應的邏輯計算或設定屬性參數
} // 程式碼區塊或元件結構結束

// ===== 紙膠帶按鈕繪製器 =====
class WashiTapeButtonPainter extends CustomPainter { // 定義 WashiTapeButtonPainter 類別，繼承自 CustomPainter
  // 紙膠帶組件
  final String text; // 宣告類別成員或方法內部的區域變數
  WashiTapeButtonPainter({this.text = '下一頁 >'}); // 執行相對應的邏輯計算或設定屬性參數

  @override // 標記此方法為覆寫父類別之方法
  void paint(Canvas canvas, Size size) { // 執行相對應的邏輯計算或設定屬性參數
    Path baseShape = Path(); // 執行相對應的邏輯計算或設定屬性參數
    Random rand = Random(); // 執行相對應的邏輯計算或設定屬性參數
    double w = size.width; // 宣告類別成員或方法內部的區域變數
    double h = size.height; // 宣告類別成員或方法內部的區域變數

    baseShape.moveTo(0, 0); // 起點
    for (double y = 0; y < h; y += 6) { // 執行相對應的邏輯計算或設定屬性參數
      if (y + 6 < h) { // 執行相對應的邏輯計算或設定屬性參數
        baseShape.lineTo(4 + rand.nextDouble() * 2, y + 3); // 執行相對應的邏輯計算或設定屬性參數
        baseShape.lineTo(0, y + 6); // 執行相對應的邏輯計算或設定屬性參數
      } // 程式碼區塊或元件結構結束
    } // 左端鋸齒
    baseShape.lineTo(w, h); // 底邊
    for (double y = h; y > 0; y -= 6) { // 執行相對應的邏輯計算或設定屬性參數
      if (y - 6 > 0) { // 執行相對應的邏輯計算或設定屬性參數
        baseShape.lineTo(w - 4 - rand.nextDouble() * 2, y - 3); // 執行相對應的邏輯計算或設定屬性參數
        baseShape.lineTo(w, y - 6); // 執行相對應的邏輯計算或設定屬性參數
      } // 程式碼區塊或元件結構結束
    } // 右端鋸齒
    baseShape.close(); // 執行相對應的邏輯計算或設定屬性參數

    // 繪製陰影
    canvas.drawPath( // 執行相對應的邏輯計算或設定屬性參數
      baseShape.shift(const Offset(10, 12)),  // 建立編譯期常數，優化 Flutter 渲染效能
      Paint() // 執行相對應的邏輯計算或設定屬性參數
        ..color = Colors.black.withOpacity(0.55) // 設定顏色數值（Color）
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.9) // 建立編譯期常數，優化 Flutter 渲染效能
    ); // 程式碼區塊或元件結構結束

    canvas.drawPath(baseShape, Paint()..color = Colors.white); // 填充

    TextPainter textPainter = TextPainter( // 執行相對應的邏輯計算或設定屬性參數
      // 文字標註
      text: TextSpan( // 執行相對應的邏輯計算或設定屬性參數
        text: text, // 執行相對應的邏輯計算或設定屬性參數
        style: const TextStyle( // 設定文字字體大小、顏色與粗細等字型樣式（TextStyle）
          fontSize: 22, // 放大 0.4 倍
          fontWeight: FontWeight.bold, // 執行相對應的邏輯計算或設定屬性參數
          color: AppColors.textPrimary, // 設定顏色數值（Color）
        ), // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
      textDirection: TextDirection.ltr, // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
    textPainter.layout(); // 執行相對應的邏輯計算或設定屬性參數
    textPainter.paint( // 執行相對應的邏輯計算或設定屬性參數
      canvas, // 執行相對應的邏輯計算或設定屬性參數
      Offset((w - textPainter.width) / 2, (h - textPainter.height) / 2), // 執行相對應的邏輯計算或設定屬性參數
    ); // 置中繪製
  } // 程式碼區塊或元件結構結束

  @override // 標記此方法為覆寫父類別之方法
  bool shouldRepaint(WashiTapeButtonPainter oldDelegate) => // 宣告類別成員或方法內部的區域變數
      oldDelegate.text != text; // 執行相對應的邏輯計算或設定屬性參數
} // 程式碼區塊或元件結構結束

// ===== 紙膠帶紋理繪製器 (裝飾用，可選) =====
class WashiPainter extends CustomPainter { // 定義 WashiPainter 類別，繼承自 CustomPainter
  // 紋理背景實作
  @override // 標記此方法為覆寫父類別之方法
  void paint(Canvas canvas, Size size) { // 執行相對應的邏輯計算或設定屬性參數
    /* 可擴充紙膠帶條紋圖案的邏輯 */
  } // 程式碼區塊或元件結構結束
  @override // 標記此方法為覆寫父類別之方法
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false; // 宣告類別成員或方法內部的區域變數
} // 程式碼區塊或元件結構結束
// ===== 檔案結束 =====