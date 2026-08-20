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
  final needsOnboarding =
      prefs.getBool(AuthService.needsOnboardingKey) ?? false;

  Widget initialScreen = const LoginPage();

  if (token != null && token.isNotEmpty) {
    final role = prefs.getString('user_role');
    final email = prefs.getString('user_email');
    final bool isAdmin = role == 'ROLE_ADMIN' ||
        role == 'ADMIN' ||
        (email != null && email.trim().toLowerCase() == 'admin@gmail.com');

    if (isAdmin) {
      initialScreen = const HomePage();
    } else if (needsOnboarding) {
      initialScreen = const InitialInfoPage();
    } else {
      // 本地有 Token 且已完成 Onboarding，預設保持登入直接進入首頁 (HomePage)
      initialScreen = const HomePage();
      try {
        final result = await AuthService().getUserProfile();
        if (result['message'] != null &&
            result['message'].toString().contains('onboarding')) {
          initialScreen = const InitialInfoPage();
        }
      } catch (_) {
        // 發生網路波動或伺服器連線問題時，依然保持登入狀態
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
