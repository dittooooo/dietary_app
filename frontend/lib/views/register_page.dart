import 'package:flutter/material.dart';
import 'success_transition_page.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _isLoading = false;

  String? _emailError;
  String? _passwordError;
  String? _confirmPasswordError;

  Future<void> _handleRegister() async {
    bool hasLocalError = false;
    setState(() {
      _emailError = null;
      _passwordError = null;
      _confirmPasswordError = null;

      if (_emailController.text.isEmpty) { _emailError = '請輸入電子郵件'; hasLocalError = true; }
      if (_passwordController.text.isEmpty) { _passwordError = '請輸入密碼'; hasLocalError = true; }
      if (_confirmPasswordController.text.isEmpty) { _confirmPasswordError = '請確認密碼'; hasLocalError = true; }
      else if (_passwordController.text != _confirmPasswordController.text) { _confirmPasswordError = '密碼不符'; hasLocalError = true; }
    });

    if (!hasLocalError) {
      setState(() => _isLoading = true);
      
      try {
        final response = await http.post(
          Uri.parse('${ApiConfig.baseUrl}/register'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': _emailController.text,
            'password': _passwordController.text,
          }),
        );
        
        if (response.statusCode == 200) {
          // 檢查後端是否把錯誤訊息包裝在 HTTP 200 裡回傳
          try {
            final errorData = jsonDecode(response.body);
            if (errorData is Map && (errorData.containsKey('error') || errorData.containsKey('email') || errorData.containsKey('password'))) {
              if (mounted) {
                setState(() {
                  _emailError = errorData['email'] ?? errorData['error']; // "已有帳號"之類的提示放email這
                  _passwordError = errorData['password'];
                });
              }
              return; // 終止
            }
          } catch (_) {
            // 解析 JSON 失敗代表是普通的字串 (例如："註冊成功")
          }

          // 註冊成功後，自動幫使用者執行登入動作以獲取 JWT Token
          try {
            final loginRes = await http.post(
              Uri.parse('${ApiConfig.baseUrl}/login'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'email': _emailController.text,
                'password': _passwordController.text,
              }),
            );
            if (loginRes.statusCode == 200) {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('jwt_token', loginRes.body);
            }
          } catch (e) {
            debugPrint('自動登入失敗: $e');
          }

          // 註冊成功且自動登入完成，跳轉至過渡動畫頁
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const SuccessTransitionPage(title: '註冊成功！')),
            );
          }
        } else {
          // 註冊失敗，系統例外狀況
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('註冊失敗: 系統錯誤'))
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('連線失敗，請檢查網路或後端伺服器'))
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
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
              // 頂部圖標
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
                '註冊',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 30),
              
              // 電子郵件輸入框
              _buildInputField(
                label: '電子郵件',
                hint: 'example@mail.com',
                controller: _emailController,
                errorText: _emailError,
                onChanged: (_) => setState(() => _emailError = null),
              ),
              
              const SizedBox(height: 20),
              
              // 密碼輸入框
              _buildInputField(
                label: '密碼',
                hint: '6-18位數密碼',
                controller: _passwordController,
                isPassword: true,
                isVisible: _isPasswordVisible,
                onToggleVisibility: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                errorText: _passwordError,
                onChanged: (_) => setState(() => _passwordError = null),
              ),

              const SizedBox(height: 20),
              
              // 確認密碼輸入框
              _buildInputField(
                label: '確認密碼',
                hint: '6-18位數密碼',
                controller: _confirmPasswordController,
                isPassword: true,
                isVisible: _isConfirmPasswordVisible,
                onToggleVisibility: () => setState(() => _isConfirmPasswordVisible = !_isConfirmPasswordVisible),
                errorText: _confirmPasswordError,
                onChanged: (_) => setState(() => _confirmPasswordError = null),
              ),

              const SizedBox(height: 30),

              // 註冊按鈕
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton(
                  onPressed: _isLoading ? null : _handleRegister,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.blue, width: 2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                  ),
                  child: _isLoading 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('註冊', style: TextStyle(color: Colors.blue, fontSize: 18)),
                ),
              ),

              const SizedBox(height: 20),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  '已有帳號？返回登入',
                  style: TextStyle(color: Colors.grey, decoration: TextDecoration.underline),
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
    bool isVisible = false,
    VoidCallback? onToggleVisibility,
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
          obscureText: isPassword && !isVisible,
          onChanged: onChanged,
          decoration: InputDecoration(
            errorText: errorText,
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.grey),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            suffixIcon: isPassword 
              ? IconButton(
                  icon: Icon(isVisible ? Icons.visibility : Icons.visibility_off),
                  onPressed: onToggleVisibility,
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

// 移除舊有的 CreateElfPage，改用統一的 SuccessTransitionPage
