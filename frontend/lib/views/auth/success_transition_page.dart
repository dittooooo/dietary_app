import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/api_config.dart';
import '../../color/app_colors.dart';
import '../home/home_page.dart';
import 'initial_info_page.dart';

class SuccessTransitionPage extends StatefulWidget {
  final String title;
  final bool shouldNavigate;
  const SuccessTransitionPage({
    super.key, 
    this.title = '登入成功！',
    this.shouldNavigate = true,
  });

  @override
  State<SuccessTransitionPage> createState() => _SuccessTransitionPageState();
}

class _SuccessTransitionPageState extends State<SuccessTransitionPage> {
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    _animateProgress();
  }

  void _animateProgress() async {
    // 預先檢查使用者是否已完成 onboarding
    bool alreadyOnboarded = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      if (token != null) {
        final response = await http.get(
          Uri.parse('${ApiConfig.baseUrl}/user/profile'),
          headers: {'Authorization': 'Bearer $token'},
        ).timeout(const Duration(seconds: 5));
        
        // 如果能抓到 Profile (200 OK)，代表已經完成過 onboarding 了
        if (response.statusCode == 200) {
          alreadyOnboarded = true;
        }
      }
    } catch (e) {
      debugPrint('檢查 onboarding 狀態失敗: $e');
    }

    for (int i = 0; i <= 100; i++) {
      await Future.delayed(const Duration(milliseconds: 15));
      if (mounted) {
        setState(() => _progress = i / 100.0);
      }
    }

    if (mounted && widget.shouldNavigate) {
      if (alreadyOnboarded) {
        // 已完成者 -> 直接進首頁
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomePage()),
        );
      } else {
        // 未完成者 -> 進個資填寫頁面
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const InitialInfoPage()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(40.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.face, size: 80, color: AppColors.primary), 
              const SizedBox(height: 20),
              Text(
                widget.title, 
                style: const TextStyle(
                  fontSize: 24, 
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary
                )
              ),
              const SizedBox(height: 20),
              LinearProgressIndicator(
                value: _progress,
                backgroundColor: AppColors.surface,
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                minHeight: 10,
              ),
              const SizedBox(height: 40),
              const Icon(Icons.image, size: 100, color: AppColors.secondary), 
              const SizedBox(height: 20),
              const Text(
                '希望您能享受 App', 
                textAlign: TextAlign.center, 
                style: TextStyle(color: AppColors.textPrimary)
              ),
            ],
          ),
        ),
      ),
    );
  }
}
