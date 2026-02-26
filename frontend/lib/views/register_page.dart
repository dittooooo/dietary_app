import 'package:flutter/material.dart';

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


  Future<void> _handleRegister() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      
      // 模擬異步註冊請求
      await Future.delayed(const Duration(seconds: 2));
      
      setState(() => _isLoading = false);
      
      if (mounted) {
        // 註冊成功後導向小精靈創建頁面 (Placeholder)
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const CreateElfPage()),
        );
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
                validator: (value) {
                  if (value == null || value.isEmpty) return '請輸入電子郵件';
                  if (!value.contains('@')) return '電子郵件格式不正確';
                  return null;
                },
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
                validator: (value) {
                  if (value == null || value.isEmpty) return '請輸入密碼';
                  if (value.length < 6 || value.length > 18) return '長度需為 6-18 位';
                  // 新增：密碼強度檢查邏輯
                  if (!value.contains(RegExp(r'[A-Z]'))) {
                    return '密碼必須包含大寫英文字母';
                  }
                  if (!value.contains(RegExp(r'[a-z]'))) {
                    return '密碼必須包含小寫英文字母';
                  }
                  return null;
                },
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
                validator: (value) {
                  if (value == null || value.isEmpty) return '請確認密碼';
                  if (value != _passwordController.text) return '密碼不符';
                  return null;
                },
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
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 5),
        TextFormField(
          controller: controller,
          obscureText: isPassword && !isVisible,
          validator: validator,
          decoration: InputDecoration(
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

// 小精靈創建頁面 (Placeholder)
class CreateElfPage extends StatelessWidget {
  const CreateElfPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('創建小精靈')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.auto_awesome, size: 100, color: Colors.orange),
            const SizedBox(height: 20),
            const Text('歡迎來到小精靈模組', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const Padding(
              padding: EdgeInsets.all(20.0),
              child: Text('在此設定您的身高、體重與目標來創建您的小精靈。', textAlign: TextAlign.center),
            ),
            ElevatedButton(
              onPressed: () {
                // 跳轉至首頁等邏輯
              },
              child: const Text('開始創建'),
            )
          ],
        ),
      ),
    );
  }
}
