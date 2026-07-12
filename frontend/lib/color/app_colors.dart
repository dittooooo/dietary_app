import 'package:flutter/material.dart'; // 匯入 material.dart 套件或模組

class AppColors {
  // 定義 AppColors 類別，封裝相關功能或資料
  // 核心色調 (僅用於點綴：如圖標、重點文字、細節裝飾)
  static const Color primary = Color(0xFF202808);
  static const Color secondary = Color(0xFF33432B);
  static const Color accent = Color(0xFFC4866D);

  // 大面積背景與色塊
  static const Color background = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFEEEEEE); // 輸入框、欄位色塊

  // 文字顏色
  static const Color textPrimary = Color(0xFF000000);
  static const Color textSecondary = Color(0xFFFFFFFF);

  // 輔助與邊框
  static const Color border = Color(0xFFD1D1D1);
  static const Color dingley = Color(0xFF6A784D); // 僅用於裝飾線
  static const Color sage = Color(0xFF9CA889);
  static const Color khaki = Color(0xFFB7A78C);

  // 特殊狀態
  static const Color danger = Color(0xFFFF0000); // 錯誤提示
  static const Color success = Color(0xFF202808);
}
