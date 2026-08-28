import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_project/color/app_colors.dart';
import 'package:my_project/core/api_client.dart';
import 'package:my_project/services/auth_service.dart';
import 'package:my_project/views/auth/initial_info_page.dart';
import 'package:my_project/views/auth/login_page.dart';
import 'package:my_project/views/home/home_page.dart';

import 'package:flutter/services.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ),
  );

  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString(AuthService.accessTokenKey);

  Widget initialScreen = const LoginPage();

  if (token != null && token.isNotEmpty) {
    try {
      final result = await AuthService().getUserProfile();
      if (result['success'] == true) {
        final data = result['data'];
        final String? userRole = data?['user']?['role'] ?? data?['role'] ?? prefs.getString('user_role');
        final String? userEmail = (data?['email'] ?? data?['user']?['email'] ?? prefs.getString('user_email'))?.toString().trim().toLowerCase();
        final bool isAdmin = userRole == 'ROLE_ADMIN' || userRole == 'ADMIN' || userEmail == 'admin@gmail.com';

        if (isAdmin) {
          initialScreen = const HomePage();
        } else {
          initialScreen = const HomePage();
        }
      } else {
        // 後端驗證失敗（例如資料庫已重置/Token失效），自動清除本機快取並導回登入頁
        await prefs.clear();
        initialScreen = const LoginPage();
      }
    } catch (_) {
      // 連線異常或 Token 無效時，導回登入頁面
      initialScreen = const LoginPage();
    }
  } else {
    initialScreen = const LoginPage();
  }

  runApp(MyApp(initialScreen: initialScreen));
}

class MyApp extends StatelessWidget {
  final Widget initialScreen;

  const MyApp({super.key, this.initialScreen = const LoginPage()});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: ApiClient.navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Food App',
      theme: ThemeData(
        appBarTheme: const AppBarTheme(
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
            statusBarBrightness: Brightness.light,
          ),
        ),
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
