import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_project/views/auth/login_page.dart';
import 'package:my_project/views/home/home_page.dart';
import 'package:my_project/views/auth/initial_info_page.dart';
import 'package:my_project/color/app_colors.dart';
import 'package:my_project/core/api_client.dart'; // 匯入 ApiClient
import 'package:my_project/services/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('jwt_token');
  
  Widget initialScreen = const LoginPage();
  
  if (token != null && token.isNotEmpty) {
    final role = prefs.getString('user_role');
    if (role == 'ROLE_ADMIN') {
      // 1. 如果是管理員，直接進入管理員首頁（管理員無須個資填寫）
      initialScreen = const HomePage();
    } else {
      try {
        // 呼叫 API 驗證 Token 是否有效，並獲取用戶資料
        final result = await AuthService().getUserProfile();
        if (result['success'] == true) {
          // 2. 如果成功獲取個人檔案 (200 OK)，代表一般用戶已完成個資設定 -> 前往首頁
          initialScreen = const HomePage();
        } else if (result['message'] != null &&
            result['message'].toString().contains('onboarding')) {
          // 3. 如果 API 回傳 404 (尚未完成 onboarding) -> 前往個資填寫頁
          initialScreen = const InitialInfoPage();
        }
      } catch (_) {
        // 若 API 連線異常，維持進入登入頁面
      }
    }
  }

  runApp(MyApp(initialScreen: initialScreen));
}

class MyApp extends StatelessWidget {
  final Widget initialScreen;
  const MyApp({super.key, this.initialScreen = const LoginPage()});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: ApiClient.navigatorKey, // 設定全域 navigatorKey
      debugShowCheckedModeBanner: false, // 移除右上角浮水印彩帶
      title: 'Food App',
      theme: ThemeData(
        primaryColor: AppColors.primary,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          primary: AppColors.primary,
          secondary: AppColors.secondary,
        ),
      ),
      home: initialScreen,
    );
  }
}
