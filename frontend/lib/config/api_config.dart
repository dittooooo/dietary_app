import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

class ApiConfig {
  /// 根據當前執行的環境，動態取得後端 API 的 Base URL
  static String get baseUrl {
    if (kIsWeb) {
      // 如果是在網頁瀏覽器 (Chrome/Edge) 執行
      return 'http://localhost:8080/api';
    } else if (Platform.isAndroid) {
      // 在實體手機或模擬器上執行，我們使用 adb reverse tcp:8080 tcp:8080 將手機 8080 導向電腦 8080
      return 'http://10.0.2.2:8080/api';
    } else {
      // 其他平台 (如 Windows 桌面版、iOS 模擬器)
      return 'http://localhost:8080/api';
    }
  }
}

