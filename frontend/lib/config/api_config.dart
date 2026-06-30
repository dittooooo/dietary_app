import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

class ApiConfig {
  /// 根據當前執行的環境，動態取得後端 API 的 Base URL
  static String get baseUrl {
    // 定義 baseUrl 靜態 Getter，依運行環境回傳對應的 API 伺服器網址
    // 如果是在網頁瀏覽器 (Chrome/Edge) 執行
    if (kIsWeb) {
      // 執行相對應的程式邏輯運算或欄位宣告設定
      // 動態取得網頁當前的 Host (例如 localhost 或 192.168.x.x)，方便在手機上用區網測試
      final host = Uri.base.host.isNotEmpty
          ? Uri.base.host
          : 'localhost'; // 宣告類別屬性或方法內部的區域變數
      return 'http://127.0.0.1:8080/api';
    } // 程式碼區塊或結構結束
    // 如果是在 Android 模擬器執行
    else if (Platform.isAndroid) {
      // 執行相對應的程式邏輯運算或欄位宣告設定
      return 'http://127.0.0.1:8080/api'; //改成電腦IP
    }
    // 其他平台 (例如 Windows 桌面版、iOS 模擬器)
    else {
      return 'http://localhost:8080/api';
    }
  }
}
