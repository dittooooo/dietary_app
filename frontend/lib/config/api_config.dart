import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

class ApiConfig {
  static const String _overrideBaseUrl = String.fromEnvironment('API_BASE_URL');

  static String get baseUrl {
    if (_overrideBaseUrl.isNotEmpty) {
      return _overrideBaseUrl;
    }

    if (kIsWeb) {
      return 'http://localhost:8080/api';
    }

    if (Platform.isAndroid) {
      // Android emulator reaches the host machine via 10.0.2.2.
      // For a real device, override with:
      // --dart-define=API_BASE_URL=http://<your-lan-ip>:8080/api
      return 'http://10.0.2.2:8080/api';
    }

    return 'http://localhost:8080/api';
  }

  static String get serverBaseUrl {
    final apiBase = baseUrl;
    return apiBase.endsWith('/api')
        ? apiBase.substring(0, apiBase.length - 4)
        : apiBase;
  }
}
