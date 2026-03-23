import 'package:flutter/material.dart';
import 'register_page.dart'; // 引入註冊頁面
import 'success_transition_page.dart'; // 引入跳轉頁面
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  
  bool _isPasswordVisible = false;
  bool _isLoading = false;

  String? _emailError;
  String? _passwordError;

  // 預留與 Spring Boot v4.0.1 後端進行 POST 比對的函數
  Future<void> _login() async {
    setState(() => _isLoading = true);
    
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/login'), // 向後端呼叫的組合網址: http://localhost:8080/login
        headers: {'Content-Type': 'application/json'}, // 聲明請求類型是 JSON
        body: jsonEncode({
          'email': _emailController.text,
          'password': _passwordController.text
        }), // 傳送 JSON 格式的帳密
      );
      
      if (response.statusCode == 200) {
        // 檢查後端是否把錯誤訊息包裝在 HTTP 200 裡回傳 (例如: {"error": "密碼錯誤"})
        try {
          final errorData = jsonDecode(response.body);
          if (errorData is Map && (errorData.containsKey('error') || errorData.containsKey('email') || errorData.containsKey('password'))) {
            if (mounted) {
              setState(() {
                _emailError = errorData['email'];
                // 如果是一般錯誤 'error'，統一顯示在密碼下方
                _passwordError = errorData['error'] ?? errorData['password']; 
              });
            }
            return; // 終止，不要當作成功
          }
        } catch (_) {
          // 解析 json 失敗或是其他字串，代表是正常獲取 JWT Token (因為後端成功是直接給字串)
        }

        // 登入成功，獲取 JWT Token (後端直接回傳字串)
        String token = response.body;
        
        // 儲存至 Local Storage (SharedPreferences)
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('jwt_token', token);
        
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => const SuccessTransitionPage(
                title: '登入成功！',
                shouldNavigate: true,
              ),
            ),
          );
        }
      } else {
        // 登入失敗狀態碼異常時
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('登入失敗: 系統錯誤'))
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('連線失敗，請檢查後端是否啟動'))
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleLoginClick() {
    bool hasLocalError = false;
    setState(() {
      _emailError = null;
      _passwordError = null;
      if (_emailController.text.isEmpty) {
        _emailError = '請輸入帳號';
        hasLocalError = true;
      }
      if (_passwordController.text.isEmpty) {
        _passwordError = '請輸入密碼';
        hasLocalError = true;
      }
    });

    if (!hasLocalError) {
      _login();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 40.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              const SizedBox(height: 80),
              // 頂部圓形圖標
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black, width: 1),
                ),
                child: const Icon(Icons.person_outline, size: 60, color: Colors.black),
              ),
              const SizedBox(height: 10),
              const Text(
                '登入',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 30),
              
              // 帳號輸入框
              _buildInputField(
                label: '帳號',
                hint: 'example@mail.com',
                controller: _emailController,
                errorText: _emailError,
                onChanged: (value) => setState(() => _emailError = null),
              ),
              
              const SizedBox(height: 20),
              
              // 密碼輸入框
              _buildInputField(
                label: '密碼',
                hint: '6-18位數密碼',
                controller: _passwordController,
                isPassword: true,
                errorText: _passwordError,
                onChanged: (value) => setState(() => _passwordError = null),
              ),

              const SizedBox(height: 30),

              // 登入按鈕
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton(
                  onPressed: _isLoading ? null : _handleLoginClick,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.blue, width: 2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                  ),
                  child: _isLoading 
                    ? const SizedBox(
                        width: 20, 
                        height: 20, 
                        child: CircularProgressIndicator(strokeWidth: 2)
                      )
                    : const Text('登入', style: TextStyle(color: Colors.blue, fontSize: 18)),
                ),
              ),

              const SizedBox(height: 15),

              // 尚未註冊按鈕
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton(
                  onPressed: () {
                    // 跳轉至註冊頁面
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const RegisterPage()),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.black, width: 2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                  ),
                  child: const Text('尚未註冊', style: TextStyle(color: Colors.black, fontSize: 18)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputField({
    required String label,
    required String hint,
    required TextEditingController controller,
    bool isPassword = false,
    String? errorText,
    void Function(String)? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 5),
        TextFormField(
          controller: controller,
          obscureText: isPassword && !_isPasswordVisible,
          onChanged: onChanged,
          decoration: InputDecoration(
            errorText: errorText,
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.grey),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            suffixIcon: isPassword 
              ? IconButton(
                  icon: Icon(_isPasswordVisible ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                )
              : null,
            enabledBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Colors.black, width: 1),
            ),
            focusedBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Colors.blue, width: 2),
            ),
            errorBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Colors.red, width: 1),
            ),
            focusedErrorBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Colors.red, width: 2),
            ),
            errorStyle: const TextStyle(color: Colors.red),
          ),
        ),
      ],
    );
  }
}

// 移除舊有的 LoginSuccessPage 佔位，改用統一的 SuccessTransitionPage
