import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

class ApiConfig {
  static const String _overrideBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const String _nutritionistBaseUrlOverride =
      String.fromEnvironment('NUTRITIONIST_API_BASE_URL');

  static String get baseUrl {
    if (_overrideBaseUrl.isNotEmpty) {
      return _overrideBaseUrl;
    }

    if (kIsWeb) {
      return 'http://localhost:8080/api';
    }

    if (Platform.isAndroid) {
      // Use 127.0.0.1 to avoid Dart IPv6 [::1] resolution failure with adb reverse
      return 'http://127.0.0.1:8080/api';
    }

    return 'http://localhost:8080/api';
  }

  static String get serverBaseUrl {
    final apiBase = baseUrl;
    return apiBase.endsWith('/api')
        ? apiBase.substring(0, apiBase.length - 4)
        : apiBase;
  }

  /// GraphRAG Nutrition Agent is called directly by the food search screen.
  static String get nutritionistBaseUrl {
    if (_nutritionistBaseUrlOverride.isNotEmpty) {
      return _nutritionistBaseUrlOverride;
    }

    final serverUri = Uri.parse(serverBaseUrl);
    return serverUri.replace(port: 8000, path: '').toString();
  }

  /// 陪伴精靈 Companion Agent 的 Base URL (Port 3000)
  static String get companionBaseUrl {
    if (kIsWeb) {
      return 'http://localhost:3000';
    }

    try {
      final uri = Uri.parse(serverBaseUrl);
      if (uri.host.isNotEmpty && uri.host != 'localhost' && uri.host != '127.0.0.1') {
        return uri.replace(port: 3000).toString();
      }
    } catch (_) {}

    if (Platform.isAndroid) {
      return 'http://127.0.0.1:3000';
    }

    return 'http://localhost:3000';
  }

  /// 陪伴精靈候選連線 URL 列表（自動容錯與多 IP 輪詢嘗試）
  static List<String> get companionCandidateBaseUrls {
    final primary = companionBaseUrl;
    final candidates = <String>[primary];

    if (kIsWeb) {
      return candidates;
    }

    if (Platform.isAndroid) {
      if (!candidates.contains('http://localhost:3000')) {
        candidates.add('http://localhost:3000');
      }
      if (!candidates.contains('http://10.0.2.2:3000')) {
        candidates.add('http://10.0.2.2:3000');
      }
      if (!candidates.contains('http://127.0.0.1:3000')) {
        candidates.add('http://127.0.0.1:3000');
      }
    } else {
      if (!candidates.contains('http://localhost:3000')) {
        candidates.add('http://localhost:3000');
      }
      if (!candidates.contains('http://127.0.0.1:3000')) {
        candidates.add('http://127.0.0.1:3000');
      }
    }

    return candidates;
  }
}


