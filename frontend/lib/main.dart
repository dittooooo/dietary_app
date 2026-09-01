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
        await prefs.clear();
        initialScreen = const LoginPage(initialMessage: '登入憑證已失效，請重新登入');
      }
    } catch (_) {
      initialScreen = const LoginPage(initialMessage: '網路連線短暫不穩定或伺服器維護中，請重新登入');
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
