import 'package:flutter/material.dart';
import 'register_page.dart'; // 引入註冊頁面
import 'success_transition_page.dart'; // 引入跳轉頁面
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/api_config.dart';
import '../../services/auth_service.dart';
import '../../color/app_colors.dart';

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
      // 呼叫 Service 執行登入
      final result = await AuthService().login(
        _emailController.text, 
        _passwordController.text
      );
      
      if (mounted) {
        if (result['success'] == true) {
          // 儲存 Email 到本地，供 ProfilePage 使用
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('user_email', _emailController.text.trim());
          
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => const SuccessTransitionPage(title: '登入成功！', shouldNavigate: true),
            ),
          );
        } else {
          // 顯示後端回傳的錯誤欄位
          setState(() {
            _emailError = result['email'];
            _passwordError = result['error'] ?? result['password'];
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result['message'] ?? result['error'] ?? '登入失敗'))
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('連線失敗，請檢查網路')));
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
                  color: AppColors.background,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.25),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: const Icon(Icons.person_outline, size: 60, color: AppColors.primary),
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

              Container(
                width: double.infinity,
                height: 50,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.2),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleLoginClick,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.background,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    elevation: 0, 
                  ),
                  child: _isLoading 
                    ? const SizedBox(
                        width: 20, 
                        height: 20, 
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.background)
                      )
                    : const Text('登入', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),

              const SizedBox(height: 15),

              Container(
                width: double.infinity,
                height: 50,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.15),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const RegisterPage()),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.background,
                      foregroundColor: AppColors.textPrimary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                    child: const Text('尚未註冊', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
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
            contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
            suffixIcon: isPassword 
              ? IconButton(
                  icon: Icon(_isPasswordVisible ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                )
              : null,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.secondary, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.danger, width: 1),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.danger, width: 1.5),
            ),
            errorStyle: const TextStyle(color: AppColors.danger),
            filled: true,
            fillColor: AppColors.surface,
          ),
        ),
      ],
    );
  }
}

// 移除舊有的 LoginSuccessPage 佔位，改用統一的 SuccessTransitionPage
