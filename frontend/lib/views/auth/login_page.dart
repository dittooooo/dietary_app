import 'package:flutter/material.dart';
import 'register_page.dart'; // 引入註冊頁面
import 'success_transition_page.dart'; // 引入跳轉頁面
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/api_config.dart';

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

  Future<void> _login() async {
    setState(() => _isLoading = true);
    
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': _emailController.text,
          'password': _passwordController.text
        }),
      );
      
      if (response.statusCode == 200) {
        // 重要修復：後端可能在 200 狀態碼中包裝錯誤訊息 (例如 {"error": "..."} 或 {"password": "..."})
        try {
          final data = jsonDecode(response.body);
          if (data is Map) {
            // 如果後端回傳的是 JSON Map，高機率是報錯訊息袋
            if (mounted) {
              setState(() {
                _emailError = data['email'];
                _passwordError = data['error'] ?? data['password']; // 捕捉各種類型的報錯文字
              });
              
              String msg = data['error'] ?? data['message'] ?? '輸入資料格式不正確';
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(msg))
              );
            }
            return; // 終止執行，即使是 200 也不視為成功
          }
        } catch (_) {
          // 如果解析 JSON 失敗，代表回傳的是「純字串」JWT Token，這是正常的成功狀況
        }

        // 登入成功，獲取 JWT Token
        String token = response.body;
        
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
        // 後端登入失敗時 (例如密碼錯誤或欄位未填)，交由後端處理並回傳 HTTP 403 或 400
        try {
          final errorData = jsonDecode(response.body);
          if (mounted) {
            setState(() {
              _emailError = errorData['email'];
              _passwordError = errorData['password'] ?? errorData['error'];
            });
            if (errorData.containsKey('message')) {
               ScaffoldMessenger.of(context).showSnackBar(
                 SnackBar(content: Text(errorData['message'].toString()))
               );
            }
          }
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('登入失敗: 帳號或密碼錯誤'))
            );
          }
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
      
      if (_emailController.text.trim().isEmpty) {
        _emailError = '請輸入電子郵件';
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
