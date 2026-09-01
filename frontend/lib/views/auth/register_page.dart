import 'package:flutter/material.dart';
import 'success_transition_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/auth_service.dart';
import '../../color/app_colors.dart';

/// 使用者註冊頁面 Widget。
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

/// 內部使用的 _RegisterPageState 元件與狀態處理類別。
class _RegisterPageState extends State<RegisterPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _isLoading = false;

  String? _emailError;
  String? _passwordError;
  String? _confirmPasswordError;

  /// 處理使用者註冊流程，執行信箱與密碼格式檢驗並呼叫註冊 API。
  Future<void> _handleRegister() async {
    bool hasLocalError = false;
    setState(() {
      _emailError = null;
      _passwordError = null;
      _confirmPasswordError = null;

      final email = _emailController.text.trim();
      final password = _passwordController.text;
      final confirmPassword = _confirmPasswordController.text;

      if (email.isEmpty) {
        _emailError = '請輸入電子郵件';
        hasLocalError = true;
      } else if (!RegExp(
        r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+",
      ).hasMatch(email)) {
        _emailError = '請輸入正確的電子郵件格式';
        hasLocalError = true;
      }

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
      final result = await AuthService().register(
        _emailController.text,
        _passwordController.text,
      );

      if (mounted) {
        if (result['success'] == true) {
          final prefs = await SharedPreferences.getInstance();
          final today = DateTime.now();
          final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
          final email = _emailController.text.trim();
          await prefs.setString('user_email', email);
          await prefs.setString('last_shown_summary_date_$email', todayStr);

          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => const SuccessTransitionPage(title: '註冊成功！'),
            ),
          );
        } else {
          setState(() {
            _emailError = result['email'] != null ? '請確認信箱格式或是否已註冊' : null;
            _passwordError = result['password'] != null ? '請確認密碼格式' : null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('註冊失敗，請確認資料後再試。')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('連線失敗')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 繪製並傳回當前 Widget 之 UI 畫面架構。
  @override
  /// 執行 build 業務邏輯處理方法。
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 40.0),
        child: Column(
          children: [
            const SizedBox(height: 80),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(shape: BoxShape.circle),
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
            _buildInputField(
              label: '電子郵件',
              hint: 'example@mail.com',
              controller: _emailController,
              errorText: _emailError,
              onChanged: (_) => setState(() => _emailError = null),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 20),
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
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 20),
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
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _handleRegister(),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleRegister,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.background,
                  elevation: 0.975,
                  shadowColor: AppColors.primary.withValues(alpha: 0.3),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        '註冊',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              height: 50,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    blurRadius: 2.925,
                    offset: const Offset(0, 1.56),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.background,
                  foregroundColor: AppColors.textPrimary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: const Text(
                  '已有帳號？返回登入',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }

  /// 建立登入頁面重複使用之輸入欄位 UI 元件。
  Widget _buildInputField({
    required String label,
    required String hint,
    required TextEditingController controller,
    bool isPassword = false,
    bool isVisible = false,
    VoidCallback? onToggleVisibility,
    String? errorText,
    TextInputAction? textInputAction,
    /// 執行 Function 業務邏輯處理方法。
    void Function(String)? onChanged,
    /// 執行 Function 業務邏輯處理方法。
    void Function(String)? onSubmitted,
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
          onFieldSubmitted: onSubmitted,
          textInputAction: textInputAction,
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
              borderSide: const BorderSide(
                color: AppColors.secondary,
                width: 1.5,
              ),
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
            fillColor: AppColors.background,
            errorStyle: const TextStyle(color: AppColors.danger),
          ),
        ),
      ],
    );
  }
}
