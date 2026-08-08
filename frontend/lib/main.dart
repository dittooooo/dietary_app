import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_project/color/app_colors.dart';
import 'package:my_project/core/api_client.dart';
import 'package:my_project/services/auth_service.dart';
import 'package:my_project/views/auth/initial_info_page.dart';
import 'package:my_project/views/auth/login_page.dart';
import 'package:my_project/views/home/home_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString(AuthService.accessTokenKey);
  final needsOnboarding =
      prefs.getBool(AuthService.needsOnboardingKey) ?? false;

  Widget initialScreen = const LoginPage();

  if (token != null && token.isNotEmpty) {
    final role = prefs.getString('user_role');
    if (role == 'ROLE_ADMIN') {
      initialScreen = const HomePage();
    } else if (needsOnboarding) {
      initialScreen = const InitialInfoPage();
    } else {
      try {
        final result = await AuthService().getUserProfile();
        if (result['success'] == true) {
          initialScreen = const HomePage();
        } else if ((result['message'] ?? '').toString().contains('onboarding')) {
          initialScreen = const InitialInfoPage();
        }
      } catch (_) {
        initialScreen = const LoginPage();
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
