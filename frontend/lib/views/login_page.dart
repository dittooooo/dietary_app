import 'package:flutter/material.dart';
import 'register_page.dart'; // 引入註冊頁面

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

  // 預留與 Spring Boot v4.0.1 後端進行 POST 比對的函數
  Future<void> _login() async {
    setState(() => _isLoading = true);
    
    // 模擬網路延遲
    await Future.delayed(const Duration(seconds: 2));
    
    // TODO: 實作與 Spring Boot v4.0.1 的 HTTP POST 對接
    // final response = await http.post(
    //   Uri.parse('http://your-backend-api/login'),
    //   body: jsonEncode({
    //     'username': _emailController.text,
    //     'password': _passwordController.text
    //   }),
    // );
    
    setState(() => _isLoading = false);
    
    if (mounted) {
      // 登入成功後跳轉至動畫頁
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginSuccessPage()),
      );
    }
  }

  void _handleLoginClick() {
    if (_formKey.currentState!.validate()) {
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
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '帳號錯誤';
                  }
                  // 新增：強化 Email 格式檢查
                  if (!value.contains('@')) {
                    return '電子郵件格式不正確';
                  }
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
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '密碼錯誤或格式不符';
                  }
                  return null;
                },
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
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 5),
        TextFormField(
          controller: controller,
          obscureText: isPassword && !_isPasswordVisible,
          validator: validator,
          decoration: InputDecoration(
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

// 登入成功動畫頁佔位
class LoginSuccessPage extends StatefulWidget {
  const LoginSuccessPage({super.key});

  @override
  State<LoginSuccessPage> createState() => _LoginSuccessPageState();
}

class _LoginSuccessPageState extends State<LoginSuccessPage> {
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    _animateProgress();
  }

  void _animateProgress() async {
    for (int i = 0; i <= 100; i++) {
      await Future.delayed(const Duration(milliseconds: 20));
      if (mounted) {
        setState(() => _progress = i / 100.0);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(40.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.face, size: 80), // 小精靈預留位
              const SizedBox(height: 20),
              const Text('登入成功！', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              LinearProgressIndicator(
                value: _progress,
                backgroundColor: Colors.grey[200],
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                minHeight: 10,
              ),
              const SizedBox(height: 40),
              const Icon(Icons.image, size: 100, color: Colors.grey), // 動畫預留位
              const SizedBox(height: 20),
              const Text('希望您能享受 App', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }
}
