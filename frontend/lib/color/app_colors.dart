import 'package:flutter/material.dart';

class AppColors {
  // 基本色調：黑、白、灰
  static const Color primary = Color(0xFF000000);    // 純黑
  static const Color secondary = Color(0xFF333333);  // 深灰
  static const Color background = Color(0xFFFFFFFF); // 純白
  static const Color surface = Color(0xFFF5F5F5);    // 淺灰 (背景墊底)
  
  // 文字顏色
  static const Color textPrimary = Color(0xFF000000);
  static const Color textSecondary = Color(0xFF757575);
  
  // 邊框與裝飾
  static const Color border = Color(0xFFE0E0E0);
  static const Color accent = Color(0xFF9E9E9E);     // 中灰
  
  // 特殊狀態 (保留灰度但可區分)
  static const Color danger = Color(0xFF555555);     // 較深的灰色代表警示 (維持黑白灰風格)
  static const Color success = Color(0xFF222222);    // 接近黑色的深灰代表成功
}
