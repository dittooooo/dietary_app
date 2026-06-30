import 'package:flutter/material.dart'; // 匯入 material.dart 元件庫或套件
import 'package:model_viewer_plus/model_viewer_plus.dart'; // 匯入 model_viewer_plus.dart 元件庫或套件

Widget createWebModelView({ // 定義用於重複使用的 UI 封裝建構方法
  required String colorScheme, // 執行相對應的邏輯計算或設定屬性參數
  required bool autoSpin, // 執行相對應的邏輯計算或設定屬性參數
  required double scale, // 執行相對應的邏輯計算或設定屬性參數
  String? src, // 執行相對應的邏輯計算或設定屬性參數
  bool cameraControls = true, // 宣告類別成員或方法內部的區域變數
  String? cameraOrbit = '0deg 75deg auto', // 執行相對應的邏輯計算或設定屬性參數
  String? animationName, // 新增動畫名稱參數
  bool autoPlay = true, // 新增自動播放參數
}) { // 執行相對應的邏輯計算或設定屬性參數
  // On mobile emulator platforms, we ignore the web Base64 Data URI if it is passed,
  // and load the local asset directly for unmatched reliability and zero CORS issues!
  final String resolvedSrc = (src != null && !src.startsWith('data:')) // 宣告類別成員或方法內部的區域變數
      ? src // 執行相對應的邏輯計算或設定屬性參數
      : 'assets/images/dog_rigged.glb'; // 執行相對應的邏輯計算或設定屬性參數

  final double fovDeg = (45.0 / scale).clamp(15.0, 90.0); // 宣告類別成員或方法內部的區域變數

  return ModelViewer( // 回傳建構完成的元件或方法計算結果
    key: ValueKey('mobile_mascot_3d_viewer_${resolvedSrc}'), // 靜態 Key，避免重建
    src: resolvedSrc, // 執行相對應的邏輯計算或設定屬性參數
    alt: "3D Mascot Pet", // 執行相對應的邏輯計算或設定屬性參數
    autoRotate: false, // 執行相對應的邏輯計算或設定屬性參數
    cameraControls: cameraControls, // 執行相對應的邏輯計算或設定屬性參數
    cameraOrbit: cameraOrbit, // 執行相對應的邏輯計算或設定屬性參數
    backgroundColor: Colors.transparent, // 設定顏色數值（Color）
    fieldOfView: '${fovDeg.toInt()}deg', // 執行相對應的邏輯計算或設定屬性參數
    animationName: animationName, // 設定動畫名稱
    autoPlay: autoPlay, // 設定自動播放
  ); // 程式碼區塊或元件結構結束
}
