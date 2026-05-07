import 'package:flutter/material.dart';
import 'success_transition_page.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/api_config.dart';
import '../../services/auth_service.dart';
import '../../color/app_colors.dart';

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

      final email = _emailController.text.trim();
      final password = _passwordController.text;
      final confirmPassword = _confirmPasswordController.text;

      // 1. 檢查電子郵件
      if (email.isEmpty) {
        _emailError = '請輸入電子郵件';
        hasLocalError = true;
      } else if (!RegExp(
        r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+",
      ).hasMatch(email)) {
        _emailError = '請輸入正確的電子郵件格式';
        hasLocalError = true;
      }

      // 2. 檢查密碼
      if (password.isEmpty) {
        _passwordError = '請輸入密碼';
        hasLocalError = true;
      } else if (password.length < 6 || password.length > 18) {
        _passwordError = '密碼長度需為 6-18 位';
        hasLocalError = true;
      } else if (!RegExp(r'.*[a-z].*').hasMatch(password)) {
        _passwordError = '密碼必須包含小寫英文字母';
        hasLocalError = true;
      } else if (!RegExp(r'.*[A-Z].*').hasMatch(password)) {
        _passwordError = '密碼必須包含大寫英文字母';
        hasLocalError = true;
      } else if (!RegExp(r'.*[0-9].*').hasMatch(password)) {
        _passwordError = '密碼必須包含至少一個數字';
        hasLocalError = true;
      }

      // 3. 檢查確認密碼
      if (confirmPassword.isEmpty) {
        _confirmPasswordError = '請再次輸入密碼';
        hasLocalError = true;
      } else if (password != confirmPassword) {
        _confirmPasswordError = '確認密碼與密碼不符';
        hasLocalError = true;
      }
    });

    if (hasLocalError) return;

    setState(() => _isLoading = true);

    try {
      // 呼叫 Service 執行註冊
      final result = await AuthService().register(
        _emailController.text,
        _passwordController.text,
      );

      if (mounted) {
        if (result['success'] == true) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => const SuccessTransitionPage(title: '註冊成功！'),
            ),
          );
        } else {
          setState(() {
            _emailError = result['email'];
            _passwordError = result['password'];
          });
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(result['message'] ?? '註冊失敗')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('連線失敗')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person_outline,
                  size: 60,
                  color: AppColors.primary,
                ),
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
                onToggleVisibility: () =>
                    setState(() => _isPasswordVisible = !_isPasswordVisible),
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
                onToggleVisibility: () => setState(
                  () => _isConfirmPasswordVisible = !_isConfirmPasswordVisible,
                ),
                errorText: _confirmPasswordError,
                onChanged: (_) => setState(() => _confirmPasswordError = null),
              ),

              const SizedBox(height: 30),

              // 註冊按鈕
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleRegister,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.background,
                    elevation: 5,
                    shadowColor: AppColors.primary.withOpacity(0.3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text(
                          '註冊',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                ),
              ),

              const SizedBox(height: 20),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  '已有帳號？返回登入',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    decoration: TextDecoration.underline,
                  ),
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
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 12,
            ),
            suffixIcon: isPassword
                ? IconButton(
                    icon: Icon(
                      isVisible ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: onToggleVisibility,
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
            filled: true,
            fillColor: AppColors.surface,
            errorStyle: const TextStyle(color: AppColors.danger),
          ),
        ),
      ],
    );
  }
}

// 移除舊有的 CreateElfPage，改用統一的 SuccessTransitionPage
