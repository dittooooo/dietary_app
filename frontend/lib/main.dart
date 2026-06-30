import 'package:flutter/material.dart';
import 'package:my_project/views/auth/login_page.dart';
import 'package:my_project/color/app_colors.dart';
import 'package:my_project/core/api_client.dart'; // 匯入 ApiClient

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

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
      home: const LoginPage(),
    );
  }
}
