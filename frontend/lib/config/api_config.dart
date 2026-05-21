import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

class ApiConfig {
  /// 根據當前執行的環境，動態取得後端 API 的 Base URL
  static String get baseUrl {
    // 如果是在網頁瀏覽器 (Chrome/Edge) 執行
    if (kIsWeb) {
      // 動態取得網頁當前的 Host (例如 localhost 或 192.168.x.x)，方便在手機上用區網測試
      final host = Uri.base.host.isNotEmpty ? Uri.base.host : 'localhost';
      return 'http://$host:8080/api';
    } 
    // 如果是在 Android 模擬器執行
    else if (Platform.isAndroid) {
      return 'http://10.0.2.2:8080/api';
    } 
    // 其他平台 (例如 Windows 桌面版、iOS 模擬器)
    else {
      return 'http://localhost:8080/api'; 
    }
  }
}
