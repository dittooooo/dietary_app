import 'package:flutter/material.dart';
import 'register_page.dart';
import 'success_transition_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/auth_service.dart';
import '../../color/app_colors.dart';

/// 使用者登入頁面 Widget。
class LoginPage extends StatefulWidget {
  final String? initialMessage;
  const LoginPage({super.key, this.initialMessage});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

/// 內部使用的 _LoginPageState 元件與狀態處理類別。
class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isPasswordVisible = false;
  bool _isLoading = false;

  String? _emailError;
  String? _passwordError;

  /// 初始化 Widget 狀態與訂閱生命週期。
  @override
  void initState() {
    super.initState();
    if (widget.initialMessage != null && widget.initialMessage!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.initialMessage!,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: AppColors.secondary,
            duration: const Duration(seconds: 4),
          ),
        );
      });
    }
  }

  /// 執行使用者登入驗證，向後端發送帳號密碼並儲存會話憑證。
  Future<void> _login() async {
    setState(() => _isLoading = true);

    try {
      await AuthService().clearSession(); // 非同步請求
      final result = await AuthService().login( _emailController.text.trim(), _passwordController.text.trim(), );

      if (mounted) {
        if (result['success'] == true) {
          final prefs = await SharedPreferences.getInstance();
          final userEmail = _emailController.text.trim().toLowerCase();
          await prefs.setString('user_email', userEmail);
          final role = result['role']?.toString() ?? result['data']?['role']?.toString();
          final bool isAdmin = role == 'ROLE_ADMIN';
          if (isAdmin) { await prefs.setString('user_role', 'ROLE_ADMIN'); }
          else { await prefs.setString('user_role', 'ROLE_USER'); }

          // 登入回應中的 needsOnboarding 可能與既有 profile 的狀態不同步。
          // 重新向後端讀取 profile，避免已完成資料填寫的使用者登出後再次進入 onboarding。
          final profileResult = await AuthService().getUserProfile();
          if (profileResult['success'] == true) { await prefs.setBool(AuthService.needsOnboardingKey, false); }
          else if (profileResult['statusCode'] == 404) { await prefs.setBool(AuthService.needsOnboardingKey, true); }

          if (!mounted) return; // 檢查 widget 是否仍然掛載
          Navigator.pushReplacement(
            context,
            MaterialPageRoute( builder: (context) => const SuccessTransitionPage( title: '登入成功！', shouldNavigate: true, ), ),
          );
        } else {
          setState(() { // 非同步請求回傳結果
            _emailError = result['email'] != null ? '請確認帳號格式或內容' : null;
            _passwordError = result['error'] != null || result['password'] != null ? '請確認密碼是否正確' : null;
          });
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('登入失敗，請確認帳號密碼後再試。')));
        }
      }
    } catch (_) {
      debugPrint('登入請求失敗');
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('無法連線至伺服器，請確認網路連線或稍後再試。')));}
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 處理點擊登入按鈕事件，執行輸入欄位本機格式驗證。
  void _handleLoginClick() {
    FocusManager.instance.primaryFocus?.unfocus(); // 關閉鍵盤
    bool hasLocalError = false;
    setState(() {
      _emailError = null; _passwordError = null;
      if (_emailController.text.trim().isEmpty) { _emailError = '請輸入電子郵件'; hasLocalError = true; }
      if (_passwordController.text.isEmpty) { _passwordError = '請輸入密碼'; hasLocalError = true; }
    });
    if (!hasLocalError) { _login(); }
  }

  /// 繪製並傳回當前 Widget 之 UI 畫面架構。
  @override
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
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.background,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.25),
                    blurRadius: 3.9,
                    offset: const Offset(0, 1.95),
                  ),
                ],
              ),
              child: const Icon(
                Icons.person_outline,
                size: 60,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '登入',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 30),
            _buildInputField(
              label: '帳號',
              hint: 'example@mail.com',
              controller: _emailController,
              errorText: _emailError,
              onChanged: (_) => setState(() => _emailError = null),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 15),
            _buildInputField(
              label: '密碼',
              hint: '6-18位數密碼',
              controller: _passwordController,
              isPassword: true,
              errorText: _passwordError,
              onChanged: (_) => setState(() => _passwordError = null),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _handleLoginClick(),
            ),
            const SizedBox(height: 30),
            Container(
              width: double.infinity,
              height: 50,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.2),
                    blurRadius: 2.925,
                    offset: const Offset(0, 1.56),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleLoginClick,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.background,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  elevation: 0,
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.background,
                        ),
                      )
                    : const Text(
                        '登入',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
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
                    color: AppColors.primary.withValues(alpha: 0.15),
                    blurRadius: 2.925,
                    offset: const Offset(0, 1.56),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const RegisterPage(),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.background,
                  foregroundColor: AppColors.textPrimary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: const Text(
                  '尚未註冊',
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
    String? errorText,
    TextInputAction? textInputAction,
    void Function(String)? onChanged,
    void Function(String)? onSubmitted,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 5),
        TextFormField(
          controller: controller,
          obscureText: isPassword && !_isPasswordVisible,
          onChanged: onChanged,
          onFieldSubmitted: onSubmitted,
          textInputAction: textInputAction,
          decoration: InputDecoration(
            errorText: errorText,
            hintText: hint,
            hintStyle: TextStyle(
              color: AppColors.textPrimary.withValues(alpha: 0.4),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 15,
              vertical: 15,
            ),
            suffixIcon: isPassword
                ? IconButton(
                    icon: Icon(
                      _isPasswordVisible
                          ? Icons.visibility
                          : Icons.visibility_off,
                    ),
                    onPressed: () => setState(
                      () => _isPasswordVisible = !_isPasswordVisible,
                    ),
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
            errorStyle: const TextStyle(color: AppColors.danger),
            filled: true,
            fillColor: AppColors.background,
          ),
        ),
      ],
    );
  }
}
