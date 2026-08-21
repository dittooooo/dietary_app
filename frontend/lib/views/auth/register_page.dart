import 'package:flutter/material.dart'; // 匯入 material.dart 元件庫或套件
import 'success_transition_page.dart'; // 匯入 success_transition_page.dart 元件庫或套件
import 'package:http/http.dart' as http; // 匯入 http.dart 元件庫或套件
import 'dart:convert'; // 匯入 dart:convert 元件庫或套件
import 'package:shared_preferences/shared_preferences.dart'; // 匯入 shared_preferences.dart 元件庫或套件
import '../../config/api_config.dart'; // 匯入 api_config.dart 元件庫或套件
import '../../services/auth_service.dart'; // 匯入 auth_service.dart 元件庫或套件
import '../../color/app_colors.dart'; // 匯入 app_colors.dart 元件庫或套件

class RegisterPage extends StatefulWidget { // 定義 RegisterPage 類別，繼承自 StatefulWidget
  const RegisterPage({super.key}); // 建立編譯期常數，優化 Flutter 渲染效能

  @override // 標記此方法為覆寫父類別之方法
  State<RegisterPage> createState() => _RegisterPageState(); // 執行相對應的邏輯計算或設定屬性參數
} // 程式碼區塊或元件結構結束

class _RegisterPageState extends State<RegisterPage> { // 定義 _RegisterPageState 類別，繼承自 State
  final _formKey = GlobalKey<FormState>(); // 宣告類別成員或方法內部的區域變數
  final _emailController = TextEditingController(); // 宣告類別成員或方法內部的區域變數
  final _passwordController = TextEditingController(); // 宣告類別成員或方法內部的區域變數
  final _confirmPasswordController = TextEditingController(); // 宣告類別成員或方法內部的區域變數

  bool _isPasswordVisible = false; // 宣告類別成員或方法內部的區域變數
  bool _isConfirmPasswordVisible = false; // 宣告類別成員或方法內部的區域變數
  bool _isLoading = false; // 宣告類別成員或方法內部的區域變數

  String? _emailError; // 執行相對應的邏輯計算或設定屬性參數
  String? _passwordError; // 執行相對應的邏輯計算或設定屬性參數
  String? _confirmPasswordError; // 執行相對應的邏輯計算或設定屬性參數

  Future<void> _handleRegister() async { // 定義非同步方法（Future），執行耗時操作
    bool hasLocalError = false; // 宣告類別成員或方法內部的區域變數
    setState(() { // 更新狀態數據並通知 UI 重新渲染畫面
      _emailError = null; // 執行相對應的邏輯計算或設定屬性參數
      _passwordError = null; // 執行相對應的邏輯計算或設定屬性參數
      _confirmPasswordError = null; // 執行相對應的邏輯計算或設定屬性參數

      final email = _emailController.text.trim(); // 宣告類別成員或方法內部的區域變數
      final password = _passwordController.text; // 宣告類別成員或方法內部的區域變數
      final confirmPassword = _confirmPasswordController.text; // 宣告類別成員或方法內部的區域變數

      // 1. 檢查電子郵件
      if (email.isEmpty) { // 執行相對應的邏輯計算或設定屬性參數
        _emailError = '請輸入電子郵件'; // 執行相對應的邏輯計算或設定屬性參數
        hasLocalError = true; // 執行相對應的邏輯計算或設定屬性參數
      } else if (!RegExp( // 執行相對應的邏輯計算或設定屬性參數
        r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+", // 執行相對應的邏輯計算或設定屬性參數
      ).hasMatch(email)) { // 執行相對應的邏輯計算或設定屬性參數
        _emailError = '請輸入正確的電子郵件格式'; // 執行相對應的邏輯計算或設定屬性參數
        hasLocalError = true; // 執行相對應的邏輯計算或設定屬性參數
      } // 程式碼區塊或元件結構結束

      // 2. 檢查密碼
      if (password.isEmpty) { // 執行相對應的邏輯計算或設定屬性參數
        _passwordError = '請輸入密碼'; // 執行相對應的邏輯計算或設定屬性參數
        hasLocalError = true; // 執行相對應的邏輯計算或設定屬性參數
      } else if (password.length < 6 || password.length > 18) { // 執行相對應的邏輯計算或設定屬性參數
        _passwordError = '密碼長度需為 6-18 位'; // 執行相對應的邏輯計算或設定屬性參數
        hasLocalError = true; // 執行相對應的邏輯計算或設定屬性參數
      } else if (!RegExp(r'.*[a-z].*').hasMatch(password)) { // 執行相對應的邏輯計算或設定屬性參數
        _passwordError = '密碼必須包含小寫英文字母'; // 執行相對應的邏輯計算或設定屬性參數
        hasLocalError = true; // 執行相對應的邏輯計算或設定屬性參數
      } else if (!RegExp(r'.*[A-Z].*').hasMatch(password)) { // 執行相對應的邏輯計算或設定屬性參數
        _passwordError = '密碼必須包含大寫英文字母'; // 執行相對應的邏輯計算或設定屬性參數
        hasLocalError = true; // 執行相對應的邏輯計算或設定屬性參數
      } else if (!RegExp(r'.*[0-9].*').hasMatch(password)) { // 執行相對應的邏輯計算或設定屬性參數
        _passwordError = '密碼必須包含至少一個數字'; // 執行相對應的邏輯計算或設定屬性參數
        hasLocalError = true; // 執行相對應的邏輯計算或設定屬性參數
      } // 程式碼區塊或元件結構結束

      // 3. 檢查確認密碼
      if (confirmPassword.isEmpty) { // 執行相對應的邏輯計算或設定屬性參數
        _confirmPasswordError = '請再次輸入密碼'; // 執行相對應的邏輯計算或設定屬性參數
        hasLocalError = true; // 執行相對應的邏輯計算或設定屬性參數
      } else if (password != confirmPassword) { // 執行相對應的邏輯計算或設定屬性參數
        _confirmPasswordError = '確認密碼與密碼不符'; // 執行相對應的邏輯計算或設定屬性參數
        hasLocalError = true; // 執行相對應的邏輯計算或設定屬性參數
      } // 程式碼區塊或元件結構結束
    }); // 程式碼區塊或元件結構結束

    if (hasLocalError) return; // 執行相對應的邏輯計算或設定屬性參數

    setState(() => _isLoading = true); // 更新狀態數據並通知 UI 重新渲染畫面

    try { // 執行相對應的邏輯計算或設定屬性參數
      // 呼叫 Service 執行註冊
      final result = await AuthService().register( // 宣告類別成員或方法內部的區域變數
        _emailController.text, // 執行相對應的邏輯計算或設定屬性參數
        _passwordController.text, // 執行相對應的邏輯計算或設定屬性參數
      ); // 程式碼區塊或元件結構結束

      if (mounted) { // 執行相對應的邏輯計算或設定屬性參數
        if (result['success'] == true) { // 執行相對應的邏輯計算或設定屬性參數
          // 儲存 Email 到本地並標記新註冊用戶今日不跳出昨日總結
          final prefs = await SharedPreferences.getInstance();
          final today = DateTime.now();
          final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
          await prefs.setString('user_email', _emailController.text.trim());
          await prefs.setString('last_shown_summary_date', todayStr);
          
          Navigator.pushReplacement( // 導航路由跳轉：開啟並推入新頁面
            context, // 執行相對應的邏輯計算或設定屬性參數
            MaterialPageRoute( // 執行相對應的邏輯計算或設定屬性參數
              builder: (context) => const SuccessTransitionPage(title: '註冊成功！'), // 建立編譯期常數，優化 Flutter 渲染效能
            ), // 執行相對應的邏輯計算或設定屬性參數
          ); // 程式碼區塊或元件結構結束
        } else { // 程式碼區塊或元件結構結束
          setState(() { // 更新狀態數據並通知 UI 重新渲染畫面
            _emailError = result['email']; // 執行相對應的邏輯計算或設定屬性參數
            _passwordError = result['password']; // 執行相對應的邏輯計算或設定屬性參數
          }); // 程式碼區塊或元件結構結束
          ScaffoldMessenger.of( // 執行相對應的邏輯計算或設定屬性參數
            context, // 執行相對應的邏輯計算或設定屬性參數
          ).showSnackBar(SnackBar(content: Text(result['message'] ?? '註冊失敗'))); // 建立文字顯示元件（Text）
        } // 程式碼區塊或元件結構結束
      } // 程式碼區塊或元件結構結束
    } catch (e) { // 執行相對應的邏輯計算或設定屬性參數
      if (mounted) { // 執行相對應的邏輯計算或設定屬性參數
        ScaffoldMessenger.of( // 執行相對應的邏輯計算或設定屬性參數
          context, // 執行相對應的邏輯計算或設定屬性參數
        ).showSnackBar(const SnackBar(content: Text('連線失敗'))); // 建立文字顯示元件（Text）
      } // 程式碼區塊或元件結構結束
    } finally { // 執行相對應的邏輯計算或設定屬性參數
      if (mounted) setState(() => _isLoading = false); // 更新狀態數據並通知 UI 重新渲染畫面
    } // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  @override // 標記此方法為覆寫父類別之方法
  Widget build(BuildContext context) { // 建立畫面的主要 build 方法，返回元件樹
    return Scaffold( // 建立頁面的基礎 Scaffold 骨架，提供頁面基本版面佈局
      backgroundColor: AppColors.surface, // 設定顏色數值（Color）
      body: SingleChildScrollView( // 設定頁面的主要內容區域（body）
        padding: const EdgeInsets.symmetric(horizontal: 40.0), // 設定外邊距或內邊距的數值大小（EdgeInsets）
        child: Form( // 執行相對應的邏輯計算或設定屬性參數
          key: _formKey, // 執行相對應的邏輯計算或設定屬性參數
          child: Column( // 建立垂直排列元件（Column），縱向排列多個子元件
            children: [ // 執行相對應的邏輯計算或設定屬性參數
              const SizedBox(height: 80), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
              // 頂部圖標
              Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
                padding: const EdgeInsets.all(10), // 設定外邊距或內邊距的數值大小（EdgeInsets）
                decoration: const BoxDecoration(shape: BoxShape.circle), // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
                child: const Icon( // 顯示預設的圖示元件（Icon）
                  Icons.person_outline, // 執行相對應的邏輯計算或設定屬性參數
                  size: 60, // 執行相對應的邏輯計算或設定屬性參數
                  color: AppColors.primary, // 設定顏色數值（Color）
                ), // 執行相對應的邏輯計算或設定屬性參數
              ), // 執行相對應的邏輯計算或設定屬性參數
              const SizedBox(height: 10), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
              const Text( // 建立文字顯示元件（Text）
                '註冊', // 執行相對應的邏輯計算或設定屬性參數
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold), // 設定文字字體大小、顏色與粗細等字型樣式（TextStyle）
              ), // 執行相對應的邏輯計算或設定屬性參數
              const SizedBox(height: 30), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）

              // 電子郵件輸入框
              _buildInputField( // 執行相對應的邏輯計算或設定屬性參數
                label: '電子郵件', // 執行相對應的邏輯計算或設定屬性參數
                hint: 'example@mail.com', // 執行相對應的邏輯計算或設定屬性參數
                controller: _emailController, // 執行相對應的邏輯計算或設定屬性參數
                errorText: _emailError, // 執行相對應的邏輯計算或設定屬性參數
                onChanged: (_) => setState(() => _emailError = null), // 更新狀態數據並通知 UI 重新渲染畫面
                textInputAction: TextInputAction.next, // 執行相對應的邏輯計算或設定屬性參數
              ), // 執行相對應的邏輯計算或設定屬性參數

              const SizedBox(height: 20), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）

              // 密碼輸入框
              _buildInputField( // 執行相對應的邏輯計算或設定屬性參數
                label: '密碼', // 執行相對應的邏輯計算或設定屬性參數
                hint: '6-18位數密碼', // 執行相對應的邏輯計算或設定屬性參數
                controller: _passwordController, // 執行相對應的邏輯計算或設定屬性參數
                isPassword: true, // 執行相對應的邏輯計算或設定屬性參數
                isVisible: _isPasswordVisible, // 執行相對應的邏輯計算或設定屬性參數
                onToggleVisibility: () => // 執行相對應的邏輯計算或設定屬性參數
                    setState(() => _isPasswordVisible = !_isPasswordVisible), // 更新狀態數據並通知 UI 重新渲染畫面
                errorText: _passwordError, // 執行相對應的邏輯計算或設定屬性參數
                onChanged: (_) => setState(() => _passwordError = null), // 更新狀態數據並通知 UI 重新渲染畫面
                textInputAction: TextInputAction.next, // 執行相對應的邏輯計算或設定屬性參數
              ), // 執行相對應的邏輯計算或設定屬性參數

              const SizedBox(height: 20), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）

              // 確認密碼輸入框
              _buildInputField( // 執行相對應的邏輯計算或設定屬性參數
                label: '確認密碼', // 執行相對應的邏輯計算或設定屬性參數
                hint: '6-18位數密碼', // 執行相對應的邏輯計算或設定屬性參數
                controller: _confirmPasswordController, // 執行相對應的邏輯計算或設定屬性參數
                isPassword: true, // 執行相對應的邏輯計算或設定屬性參數
                isVisible: _isConfirmPasswordVisible, // 執行相對應的邏輯計算或設定屬性參數
                onToggleVisibility: () => setState( // 更新狀態數據並通知 UI 重新渲染畫面
                  () => _isConfirmPasswordVisible = !_isConfirmPasswordVisible, // 執行相對應的邏輯計算或設定屬性參數
                ), // 執行相對應的邏輯計算或設定屬性參數
                errorText: _confirmPasswordError, // 執行相對應的邏輯計算或設定屬性參數
                onChanged: (_) => setState(() => _confirmPasswordError = null), // 更新狀態數據並通知 UI 重新渲染畫面
                textInputAction: TextInputAction.done, // 執行相對應的邏輯計算或設定屬性參數
                onSubmitted: (_) => _handleRegister(), // 執行相對應的邏輯計算或設定屬性參數
              ), // 執行相對應的邏輯計算或設定屬性參數

              const SizedBox(height: 30), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）

              // 註冊按鈕
              SizedBox( // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
                width: double.infinity, // 執行相對應的邏輯計算或設定屬性參數
                height: 50, // 執行相對應的邏輯計算或設定屬性參數
                child: ElevatedButton( // 建立常規按鈕（ElevatedButton），點擊時觸作相對應事件
                  onPressed: _isLoading ? null : _handleRegister, // 執行相對應的邏輯計算或設定屬性參數
                  style: ElevatedButton.styleFrom( // 執行相對應的邏輯計算或設定屬性參數
                    backgroundColor: AppColors.primary, // 設定顏色數值（Color）
                    foregroundColor: AppColors.background, // 設定顏色數值（Color）
                    elevation: 0.975, // 執行相對應的邏輯計算或設定屬性參數
                    shadowColor: AppColors.primary.withOpacity(0.3), // 設定顏色數值（Color）
                    shape: RoundedRectangleBorder( // 執行相對應的邏輯計算或設定屬性參數
                      borderRadius: BorderRadius.circular(15), // 設定容器的圓角弧度半徑大小
                    ), // 執行相對應的邏輯計算或設定屬性參數
                  ), // 執行相對應的邏輯計算或設定屬性參數
                  child: _isLoading // 執行相對應的邏輯計算或設定屬性參數
                      ? const SizedBox( // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
                          width: 20, // 執行相對應的邏輯計算或設定屬性參數
                          height: 20, // 執行相對應的邏輯計算或設定屬性參數
                          child: CircularProgressIndicator( // 執行相對應的邏輯計算或設定屬性參數
                            strokeWidth: 2, // 執行相對應的邏輯計算或設定屬性參數
                            color: Colors.white, // 設定顏色數值（Color）
                          ), // 執行相對應的邏輯計算或設定屬性參數
                        ) // 執行相對應的邏輯計算或設定屬性參數
                      : const Text( // 建立文字顯示元件（Text）
                          '註冊', // 執行相對應的邏輯計算或設定屬性參數
                          style: TextStyle( // 設定文字字體大小、顏色與粗細等字型樣式（TextStyle）
                            fontSize: 18, // 執行相對應的邏輯計算或設定屬性參數
                            fontWeight: FontWeight.bold, // 執行相對應的邏輯計算或設定屬性參數
                          ), // 執行相對應的邏輯計算或設定屬性參數
                        ), // 執行相對應的邏輯計算或設定屬性參數
                ), // 執行相對應的邏輯計算或設定屬性參數
              ), // 執行相對應的邏輯計算或設定屬性參數

              const SizedBox(height: 20), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
              Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
                width: double.infinity, // 執行相對應的邏輯計算或設定屬性參數
                height: 50, // 執行相對應的邏輯計算或設定屬性參數
                decoration: BoxDecoration( // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
                  borderRadius: BorderRadius.circular(15), // 設定容器的圓角弧度半徑大小
                  boxShadow: [ // 執行相對應的邏輯計算或設定屬性參數
                    BoxShadow( // 設定容器的陰影效果，包括顏色、模糊半徑與偏移量
                      color: AppColors.primary.withOpacity(0.15), // 設定顏色數值（Color）
                      blurRadius: 2.925, // 執行相對應的邏輯計算或設定屬性參數
                      offset: const Offset(0, 1.56), // 建立編譯期常數，優化 Flutter 渲染效能
                    ), // 執行相對應的邏輯計算或設定屬性參數
                  ], // 執行相對應的邏輯計算或設定屬性參數
                ), // 執行相對應的邏輯計算或設定屬性參數
                child: ElevatedButton( // 建立常規按鈕（ElevatedButton），點擊時觸作相對應事件
                  onPressed: () => Navigator.pop(context), // 導航路由返回：關閉當前頁面並返回上一頁
                  style: ElevatedButton.styleFrom( // 執行相對應的邏輯計算或設定屬性參數
                    backgroundColor: AppColors.background, // 設定顏色數值（Color）
                    foregroundColor: AppColors.textPrimary, // 設定顏色數值（Color）
                    elevation: 0, // 執行相對應的邏輯計算或設定屬性參數
                    shape: RoundedRectangleBorder( // 執行相對應的邏輯計算或設定屬性參數
                      borderRadius: BorderRadius.circular(15), // 設定容器的圓角弧度半徑大小
                    ), // 執行相對應的邏輯計算或設定屬性參數
                  ), // 執行相對應的邏輯計算或設定屬性參數
                  child: const Text( // 建立文字顯示元件（Text）
                    '已有帳號？返回登入', // 執行相對應的邏輯計算或設定屬性參數
                    style: TextStyle( // 設定文字字體大小、顏色與粗細等字型樣式（TextStyle）
                      color: AppColors.textPrimary, // 設定顏色數值（Color）
                      fontSize: 18, // 執行相對應的邏輯計算或設定屬性參數
                      fontWeight: FontWeight.bold, // 執行相對應的邏輯計算或設定屬性參數
                    ), // 執行相對應的邏輯計算或設定屬性參數
                  ), // 執行相對應的邏輯計算或設定屬性參數
                ), // 執行相對應的邏輯計算或設定屬性參數
              ), // 執行相對應的邏輯計算或設定屬性參數
              const SizedBox(height: 50), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
            ], // 執行相對應的邏輯計算或設定屬性參數
          ), // 執行相對應的邏輯計算或設定屬性參數
        ), // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Widget _buildInputField({ // 定義用於重複使用的 UI 封裝建構方法
    required String label, // 執行相對應的邏輯計算或設定屬性參數
    required String hint, // 執行相對應的邏輯計算或設定屬性參數
    required TextEditingController controller, // 執行相對應的邏輯計算或設定屬性參數
    bool isPassword = false, // 宣告類別成員或方法內部的區域變數
    bool isVisible = false, // 宣告類別成員或方法內部的區域變數
    VoidCallback? onToggleVisibility, // 執行相對應的邏輯計算或設定屬性參數
    String? errorText, // 執行相對應的邏輯計算或設定屬性參數
    TextInputAction? textInputAction, // 執行相對應的邏輯計算或設定屬性參數
    void Function(String)? onChanged, // 執行相對應的邏輯計算或設定屬性參數
    void Function(String)? onSubmitted, // 執行相對應的邏輯計算或設定屬性參數
  }) { // 執行相對應的邏輯計算或設定屬性參數
    return Column( // 建立垂直排列元件（Column），縱向排列多個子元件
      crossAxisAlignment: CrossAxisAlignment.start, // 執行相對應的邏輯計算或設定屬性參數
      children: [ // 執行相對應的邏輯計算或設定屬性參數
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)), // 建立文字顯示元件（Text）
        const SizedBox(height: 5), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
        TextFormField( // 執行相對應的邏輯計算或設定屬性參數
          controller: controller, // 執行相對應的邏輯計算或設定屬性參數
          obscureText: isPassword && !isVisible, // 執行相對應的邏輯計算或設定屬性參數
          onChanged: onChanged, // 執行相對應的邏輯計算或設定屬性參數
          onFieldSubmitted: onSubmitted, // 執行相對應的邏輯計算或設定屬性參數
          textInputAction: textInputAction, // 執行相對應的邏輯計算或設定屬性參數
          decoration: InputDecoration( // 建立輸入框樣式裝飾（InputDecoration）
            errorText: errorText, // 執行相對應的邏輯計算或設定屬性參數
            hintText: hint, // 執行相對應的邏輯計算或設定屬性參數
            hintStyle: const TextStyle(color: Colors.grey), // 設定文字字體大小、顏色與粗細等字型樣式（TextStyle）
            contentPadding: const EdgeInsets.symmetric( // 設定外邊距或內邊距的數值大小（EdgeInsets）
              horizontal: 10, // 執行相對應的邏輯計算或設定屬性參數
              vertical: 12, // 執行相對應的邏輯計算或設定屬性參數
            ), // 執行相對應的邏輯計算或設定屬性參數
            suffixIcon: isPassword // 執行相對應的邏輯計算或設定屬性參數
                ? IconButton( // 建立點擊圖示按鈕（IconButton）
                    icon: Icon( // 顯示預設的圖示元件（Icon）
                      isVisible ? Icons.visibility : Icons.visibility_off, // 執行相對應的邏輯計算或設定屬性參數
                    ), // 執行相對應的邏輯計算或設定屬性參數
                    onPressed: onToggleVisibility, // 執行相對應的邏輯計算或設定屬性參數
                  ) // 執行相對應的邏輯計算或設定屬性參數
                : null, // 執行相對應的邏輯計算或設定屬性參數
            enabledBorder: OutlineInputBorder( // 執行相對應的邏輯計算或設定屬性參數
              borderRadius: BorderRadius.circular(12), // 設定容器的圓角弧度半徑大小
              borderSide: BorderSide.none, // 執行相對應的邏輯計算或設定屬性參數
            ), // 執行相對應的邏輯計算或設定屬性參數
            focusedBorder: OutlineInputBorder( // 執行相對應的邏輯計算或設定屬性參數
              borderRadius: BorderRadius.circular(12), // 設定容器的圓角弧度半徑大小
              borderSide: const BorderSide( // 建立編譯期常數，優化 Flutter 渲染效能
                color: AppColors.secondary, // 設定顏色數值（Color）
                width: 1.5, // 執行相對應的邏輯計算或設定屬性參數
              ), // 執行相對應的邏輯計算或設定屬性參數
            ), // 執行相對應的邏輯計算或設定屬性參數
            errorBorder: OutlineInputBorder( // 執行相對應的邏輯計算或設定屬性參數
              borderRadius: BorderRadius.circular(12), // 設定容器的圓角弧度半徑大小
              borderSide: const BorderSide(color: AppColors.danger, width: 1), // 設定顏色數值（Color）
            ), // 執行相對應的邏輯計算或設定屬性參數
            focusedErrorBorder: OutlineInputBorder( // 執行相對應的邏輯計算或設定屬性參數
              borderRadius: BorderRadius.circular(12), // 設定容器的圓角弧度半徑大小
              borderSide: const BorderSide(color: AppColors.danger, width: 1.5), // 設定顏色數值（Color）
            ), // 執行相對應的邏輯計算或設定屬性參數
            filled: true, // 執行相對應的邏輯計算或設定屬性參數
            fillColor: AppColors.background, // 設定顏色數值（Color）
            errorStyle: const TextStyle(color: AppColors.danger), // 設定文字字體大小、顏色與粗細等字型樣式（TextStyle）
          ), // 執行相對應的邏輯計算或設定屬性參數
        ), // 執行相對應的邏輯計算或設定屬性參數
      ], // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束
} // 程式碼區塊或元件結構結束

// 移除舊有的 CreateElfPage，改用統一的 SuccessTransitionPage
