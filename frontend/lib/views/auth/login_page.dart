import 'package:flutter/material.dart'; // 匯入 material.dart 元件庫或套件
import 'register_page.dart'; // 引入註冊頁面
import 'success_transition_page.dart'; // 引入跳轉頁面
import 'package:http/http.dart' as http; // 匯入 http.dart 元件庫或套件
import 'dart:convert'; // 匯入 dart:convert 元件庫或套件
import 'package:shared_preferences/shared_preferences.dart'; // 匯入 shared_preferences.dart 元件庫或套件
import '../../config/api_config.dart'; // 匯入 api_config.dart 元件庫或套件
import '../../services/auth_service.dart'; // 匯入 auth_service.dart 元件庫或套件
import '../../color/app_colors.dart'; // 匯入 app_colors.dart 元件庫或套件

class LoginPage extends StatefulWidget { // 定義 LoginPage 類別，繼承自 StatefulWidget
  const LoginPage({super.key}); // 建立編譯期常數，優化 Flutter 渲染效能

  @override // 標記此方法為覆寫父類別之方法
  State<LoginPage> createState() => _LoginPageState(); // 執行相對應的邏輯計算或設定屬性參數
} // 程式碼區塊或元件結構結束

class _LoginPageState extends State<LoginPage> { // 定義 _LoginPageState 類別，繼承自 State
  final _formKey = GlobalKey<FormState>(); // 宣告類別成員或方法內部的區域變數
  final _emailController = TextEditingController(); // 宣告類別成員或方法內部的區域變數
  final _passwordController = TextEditingController(); // 宣告類別成員或方法內部的區域變數
  
  bool _isPasswordVisible = false; // 宣告類別成員或方法內部的區域變數
  bool _isLoading = false; // 宣告類別成員或方法內部的區域變數

  String? _emailError; // 執行相對應的邏輯計算或設定屬性參數
  String? _passwordError; // 執行相對應的邏輯計算或設定屬性參數

Future<void> _login() async { // 定義非同步方法（Future），執行耗時操作
    setState(() => _isLoading = true); // 更新狀態數據並通知 UI 重新渲染畫面
    
    try { // 執行相對應的邏輯計算或設定屬性參數
      // 呼叫 Service 執行登入
      final result = await AuthService().login( // 宣告類別成員或方法內部的區域變數
        _emailController.text,  // 執行相對應的邏輯計算或設定屬性參數
        _passwordController.text // 執行相對應的邏輯計算或設定屬性參數
      ); // 程式碼區塊或元件結構結束
      
      if (mounted) { // 執行相對應的邏輯計算或設定屬性參數
        if (result['success'] == true) { // 執行相對應的邏輯計算或設定屬性參數
          // 儲存 Email 到本地，供 ProfilePage 使用
          final prefs = await SharedPreferences.getInstance(); // 宣告類別成員或方法內部的區域變數
          await prefs.setString('user_email', _emailController.text.trim()); // 執行相對應的邏輯計算或設定屬性參數
          await prefs.setString('user_password', _passwordController.text);
          
          Navigator.pushReplacement( // 導航路由跳轉：開啟並推入新頁面
            context, // 執行相對應的邏輯計算或設定屬性參數
            MaterialPageRoute( // 執行相對應的邏輯計算或設定屬性參數
              builder: (context) => const SuccessTransitionPage(title: '登入成功！', shouldNavigate: true), // 建立編譯期常數，優化 Flutter 渲染效能
            ), // 執行相對應的邏輯計算或設定屬性參數
          ); // 程式碼區塊或元件結構結束
        } else { // 程式碼區塊或元件結構結束
          // 顯示後端回傳的錯誤欄位
          setState(() { // 更新狀態數據並通知 UI 重新渲染畫面
            _emailError = result['email']; // 執行相對應的邏輯計算或設定屬性參數
            _passwordError = result['error'] ?? result['password']; // 執行相對應的邏輯計算或設定屬性參數
          }); // 程式碼區塊或元件結構結束
          ScaffoldMessenger.of(context).showSnackBar( // 執行相對應的邏輯計算或設定屬性參數
            SnackBar(content: Text(result['message'] ?? result['error'] ?? '登入失敗')) // 建立文字顯示元件（Text）
          ); // 程式碼區塊或元件結構結束
        } // 程式碼區塊或元件結構結束
      } // 程式碼區塊或元件結構結束
    } catch (e) { // 執行相對應的邏輯計算或設定屬性參數
      if (mounted) { // 執行相對應的邏輯計算或設定屬性參數
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('連線失敗，請檢查網路'))); // 建立文字顯示元件（Text）
      } // 程式碼區塊或元件結構結束
    } finally { // 執行相對應的邏輯計算或設定屬性參數
      if (mounted) setState(() => _isLoading = false); // 更新狀態數據並通知 UI 重新渲染畫面
    } // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  void _handleLoginClick() { // 執行相對應的邏輯計算或設定屬性參數
    bool hasLocalError = false; // 宣告類別成員或方法內部的區域變數
    setState(() { // 更新狀態數據並通知 UI 重新渲染畫面
      _emailError = null; // 執行相對應的邏輯計算或設定屬性參數
      _passwordError = null; // 執行相對應的邏輯計算或設定屬性參數
      
      if (_emailController.text.trim().isEmpty) { // 執行相對應的邏輯計算或設定屬性參數
        _emailError = '請輸入電子郵件'; // 執行相對應的邏輯計算或設定屬性參數
        hasLocalError = true; // 執行相對應的邏輯計算或設定屬性參數
      } // 程式碼區塊或元件結構結束
      if (_passwordController.text.isEmpty) { // 執行相對應的邏輯計算或設定屬性參數
        _passwordError = '請輸入密碼'; // 執行相對應的邏輯計算或設定屬性參數
        hasLocalError = true; // 執行相對應的邏輯計算或設定屬性參數
      } // 程式碼區塊或元件結構結束
    }); // 程式碼區塊或元件結構結束

    if (!hasLocalError) { // 執行相對應的邏輯計算或設定屬性參數
      _login(); // 執行相對應的邏輯計算或設定屬性參數
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
              // 頂部圓形圖標
              Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
                padding: const EdgeInsets.all(10), // 設定外邊距或內邊距的數值大小（EdgeInsets）
                decoration: BoxDecoration( // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
                  shape: BoxShape.circle, // 執行相對應的邏輯計算或設定屬性參數
                  color: AppColors.background, // 設定顏色數值（Color）
                  boxShadow: [ // 執行相對應的邏輯計算或設定屬性參數
                    BoxShadow( // 設定容器的陰影效果，包括顏色、模糊半徑與偏移量
                      color: AppColors.primary.withOpacity(0.25), // 設定顏色數值（Color）
                      blurRadius: 3.9, // 執行相對應的邏輯計算或設定屬性參數
                      offset: const Offset(0, 1.95), // 建立編譯期常數，優化 Flutter 渲染效能
                    ), // 執行相對應的邏輯計算或設定屬性參數
                  ], // 執行相對應的邏輯計算或設定屬性參數
                ), // 執行相對應的邏輯計算或設定屬性參數
                child: const Icon(Icons.person_outline, size: 60, color: AppColors.primary), // 設定顏色數值（Color）
              ), // 執行相對應的邏輯計算或設定屬性參數
              const SizedBox(height: 10), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
              const Text( // 建立文字顯示元件（Text）
                '登入', // 執行相對應的邏輯計算或設定屬性參數
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary), // 設定文字字體大小、顏色與粗細等字型樣式（TextStyle）
              ), // 執行相對應的邏輯計算或設定屬性參數
              const SizedBox(height: 30), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
              
              // 帳號輸入框
                _buildInputField( // 執行相對應的邏輯計算或設定屬性參數
                  label: '帳號', // 執行相對應的邏輯計算或設定屬性參數
                  hint: 'example@mail.com', // 執行相對應的邏輯計算或設定屬性參數
                  controller: _emailController, // 執行相對應的邏輯計算或設定屬性參數
                  errorText: _emailError, // 執行相對應的邏輯計算或設定屬性參數
                  onChanged: (_) => setState(() => _emailError = null), // 更新狀態數據並通知 UI 重新渲染畫面
                  textInputAction: TextInputAction.next, // 執行相對應的邏輯計算或設定屬性參數
                ), // 執行相對應的邏輯計算或設定屬性參數
                const SizedBox(height: 15), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
                _buildInputField( // 執行相對應的邏輯計算或設定屬性參數
                  label: '密碼', // 執行相對應的邏輯計算或設定屬性參數
                  hint: '6-18位數密碼', // 執行相對應的邏輯計算或設定屬性參數
                  controller: _passwordController, // 執行相對應的邏輯計算或設定屬性參數
                  isPassword: true, // 執行相對應的邏輯計算或設定屬性參數
                  errorText: _passwordError, // 執行相對應的邏輯計算或設定屬性參數
                  onChanged: (_) => setState(() => _passwordError = null), // 更新狀態數據並通知 UI 重新渲染畫面
                  textInputAction: TextInputAction.done, // 執行相對應的邏輯計算或設定屬性參數
                  onSubmitted: (_) => _handleLoginClick(), // 執行相對應的邏輯計算或設定屬性參數
                ), // 執行相對應的邏輯計算或設定屬性參數

              const SizedBox(height: 30), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）

              Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
                width: double.infinity, // 執行相對應的邏輯計算或設定屬性參數
                height: 50, // 執行相對應的邏輯計算或設定屬性參數
                decoration: BoxDecoration( // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
                  borderRadius: BorderRadius.circular(15), // 設定容器的圓角弧度半徑大小
                  boxShadow: [ // 執行相對應的邏輯計算或設定屬性參數
                    BoxShadow( // 設定容器的陰影效果，包括顏色、模糊半徑與偏移量
                      color: AppColors.primary.withOpacity(0.2), // 設定顏色數值（Color）
                      blurRadius: 2.925, // 執行相對應的邏輯計算或設定屬性參數
                      offset: const Offset(0, 1.56), // 建立編譯期常數，優化 Flutter 渲染效能
                    ), // 執行相對應的邏輯計算或設定屬性參數
                  ], // 執行相對應的邏輯計算或設定屬性參數
                ), // 執行相對應的邏輯計算或設定屬性參數
                child: ElevatedButton( // 建立常規按鈕（ElevatedButton），點擊時觸作相對應事件
                  onPressed: _isLoading ? null : _handleLoginClick, // 執行相對應的邏輯計算或設定屬性參數
                  style: ElevatedButton.styleFrom( // 執行相對應的邏輯計算或設定屬性參數
                    backgroundColor: AppColors.primary, // 設定顏色數值（Color）
                    foregroundColor: AppColors.background, // 設定顏色數值（Color）
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), // 設定容器的圓角弧度半徑大小
                    elevation: 0,  // 執行相對應的邏輯計算或設定屬性參數
                  ), // 執行相對應的邏輯計算或設定屬性參數
                  child: _isLoading  // 執行相對應的邏輯計算或設定屬性參數
                    ? const SizedBox( // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
                        width: 20,  // 執行相對應的邏輯計算或設定屬性參數
                        height: 20,  // 執行相對應的邏輯計算或設定屬性參數
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.background) // 設定顏色數值（Color）
                      ) // 執行相對應的邏輯計算或設定屬性參數
                    : const Text('登入', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), // 建立文字顯示元件（Text）
                ), // 執行相對應的邏輯計算或設定屬性參數
              ), // 執行相對應的邏輯計算或設定屬性參數

              const SizedBox(height: 15), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）

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
                    onPressed: () { // 執行相對應的邏輯計算或設定屬性參數
                      Navigator.push( // 導航路由跳轉：開啟並推入新頁面
                        context, // 執行相對應的邏輯計算或設定屬性參數
                        MaterialPageRoute(builder: (context) => const RegisterPage()), // 建立編譯期常數，優化 Flutter 渲染效能
                      ); // 程式碼區塊或元件結構結束
                    }, // 程式碼區塊或元件結構結束
                    style: ElevatedButton.styleFrom( // 執行相對應的邏輯計算或設定屬性參數
                      backgroundColor: AppColors.background, // 設定顏色數值（Color）
                      foregroundColor: AppColors.textPrimary, // 設定顏色數值（Color）
                      elevation: 0, // 執行相對應的邏輯計算或設定屬性參數
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), // 設定容器的圓角弧度半徑大小
                    ), // 執行相對應的邏輯計算或設定屬性參數
                    child: const Text('尚未註冊', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)), // 建立文字顯示元件（Text）
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
    String? errorText, // 執行相對應的邏輯計算或設定屬性參數
    TextInputAction? textInputAction, // 執行相對應的邏輯計算或設定屬性參數
    void Function(String)? onChanged, // 執行相對應的邏輯計算或設定屬性參數
    void Function(String)? onSubmitted, // 執行相對應的邏輯計算或設定屬性參數
  }) { // 執行相對應的邏輯計算或設定屬性參數
    return Column( // 建立垂直排列元件（Column），縱向排列多個子元件
      crossAxisAlignment: CrossAxisAlignment.start, // 執行相對應的邏輯計算或設定屬性參數
      children: [ // 執行相對應的邏輯計算或設定屬性參數
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)), // 建立文字顯示元件（Text）
        const SizedBox(height: 5), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
        TextFormField( // 執行相對應的邏輯計算或設定屬性參數
          controller: controller, // 執行相對應的邏輯計算或設定屬性參數
          obscureText: isPassword && !_isPasswordVisible, // 執行相對應的邏輯計算或設定屬性參數
          onChanged: onChanged, // 執行相對應的邏輯計算或設定屬性參數
          onFieldSubmitted: onSubmitted, // 執行相對應的邏輯計算或設定屬性參數
          textInputAction: textInputAction, // 執行相對應的邏輯計算或設定屬性參數
          decoration: InputDecoration( // 建立輸入框樣式裝飾（InputDecoration）
            errorText: errorText, // 執行相對應的邏輯計算或設定屬性參數
            hintText: hint, // 執行相對應的邏輯計算或設定屬性參數
            hintStyle: TextStyle(color: AppColors.textPrimary.withOpacity(0.4)), // 設定文字字體大小、顏色與粗細等字型樣式（TextStyle）
            contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15), // 設定外邊距或內邊距的數值大小（EdgeInsets）
            suffixIcon: isPassword  // 執行相對應的邏輯計算或設定屬性參數
              ? IconButton( // 建立點擊圖示按鈕（IconButton）
                  icon: Icon(_isPasswordVisible ? Icons.visibility : Icons.visibility_off), // 顯示預設的圖示元件（Icon）
                  onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible), // 更新狀態數據並通知 UI 重新渲染畫面
                ) // 執行相對應的邏輯計算或設定屬性參數
              : null, // 執行相對應的邏輯計算或設定屬性參數
            enabledBorder: OutlineInputBorder( // 執行相對應的邏輯計算或設定屬性參數
              borderRadius: BorderRadius.circular(12), // 設定容器的圓角弧度半徑大小
              borderSide: BorderSide.none, // 執行相對應的邏輯計算或設定屬性參數
            ), // 執行相對應的邏輯計算或設定屬性參數
            focusedBorder: OutlineInputBorder( // 執行相對應的邏輯計算或設定屬性參數
              borderRadius: BorderRadius.circular(12), // 設定容器的圓角弧度半徑大小
              borderSide: const BorderSide(color: AppColors.secondary, width: 1.5), // 設定顏色數值（Color）
            ), // 執行相對應的邏輯計算或設定屬性參數
            errorBorder: OutlineInputBorder( // 執行相對應的邏輯計算或設定屬性參數
              borderRadius: BorderRadius.circular(12), // 設定容器的圓角弧度半徑大小
              borderSide: const BorderSide(color: AppColors.danger, width: 1), // 設定顏色數值（Color）
            ), // 執行相對應的邏輯計算或設定屬性參數
            focusedErrorBorder: OutlineInputBorder( // 執行相對應的邏輯計算或設定屬性參數
              borderRadius: BorderRadius.circular(12), // 設定容器的圓角弧度半徑大小
              borderSide: const BorderSide(color: AppColors.danger, width: 1.5), // 設定顏色數值（Color）
            ), // 執行相對應的邏輯計算或設定屬性參數
            errorStyle: const TextStyle(color: AppColors.danger), // 設定文字字體大小、顏色與粗細等字型樣式（TextStyle）
            filled: true, // 執行相對應的邏輯計算或設定屬性參數
            fillColor: AppColors.background, // 設定顏色數值（Color）
          ), // 執行相對應的邏輯計算或設定屬性參數
        ), // 執行相對應的邏輯計算或設定屬性參數
      ], // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束
} // 程式碼區塊或元件結構結束

// 移除舊有的 LoginSuccessPage 佔位，改用統一的 SuccessTransitionPage
