import 'package:flutter/material.dart'; // 匯入 material.dart 套件或模組

class AppColors { // 定義 AppColors 類別，封裝相關功能或資料
  // 核心色調 (僅用於點綴：如圖標、重點文字、細節裝飾)
  static const Color primary = Color(0xFF202808);    // Pine Tree (極深墨綠)
  static const Color secondary = Color(0xFF33432B);  // Kombu Green (墨綠)
  static const Color accent = Color(0xFFC4866D);     // Pale Copper (粉銅色)
  
  // 大面積背景與色塊 (改回中性色，避免視覺過於突兀)
  static const Color background = Color(0xFFFFFFFF); // 改回純白 (大面積背景)
  static const Color surface = Color(0xFFEEEEEE);    // 改回淺灰色 (輸入框、欄位色塊)
  
  // 文字顏色
  static const Color textPrimary = Color(0xFF000000);   // 改回純黑 (大面積閱讀)
  static const Color textSecondary = Color(0xFFFFFFFF); // 純白 (用於深色按鈕文字)
  
  // 輔助與邊框
  static const Color border = Color(0xFFD1D1D1);     // 改回淺灰色邊框
  static const Color dingley = Color(0xFF6A784D);    // Dingley (橄欖綠，僅用於裝飾線)
  static const Color sage = Color(0xFF9CA889);       // Sage (鼠尾草綠)
  static const Color khaki = Color(0xFFB7A78C);      // Khaki (卡其)
  
  // 特殊狀態
  static const Color danger = Color(0xFFFF0000);     // 鮮紅
  static const Color success = Color(0xFF202808); // 定義靜態常數 success，設定特定 UI 部分的顏色值
} // 程式碼區塊或結構結束
