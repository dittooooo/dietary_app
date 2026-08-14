import 'package:flutter/material.dart';

class AppColors {
  // 核心色調 (僅用於點綴：如圖標、重點文字、細節裝飾)
  static const Color primary = Color.fromARGB(255, 47, 27, 2); // 墨黑色
  static const Color secondary = Color.fromARGB(255, 61, 43, 18); // 深褐色
  static const Color accent = Color(0xFFC4866D); // 珊瑚色

  // 大面積背景與色塊
  static const Color background = Color(0xFFFCF8EC); // 米白色背景
  static const Color surface = Color.fromARGB(255, 231, 217, 177); // 淺米黃底色

  // 文字顏色
  static const Color textPrimary = Color(0xFF000000); // 純黑文字
  static const Color textSecondary = Color(0xFFFCF8EC); // 米白色文字

  // 輔助與邊框
  static const Color border = Color(0xFFD1D1D1); // 灰色邊框
  static const Color dingley = Color(0xFF6A784D); // 裝飾線 (灰綠色)
  static const Color sage = Color(0xFF9CA889); // 鼠尾草綠
  static const Color khaki = Color(0xFFB7A78C); // 卡其色

  // 特殊狀態
  static const Color danger = Color(0xFFFF0000); // 錯誤提示
  static const Color success = Color(0xFF202808); // 成功提示 (深墨綠色)
}
