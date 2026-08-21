class FriendlyErrorMessage {
  static const String companion =
      '精靈暫時無法回應，請稍後再試一次。';
  static const String dietRecord =
      '飲食紀錄暫時無法處理，請檢查網路或稍後再試。';
  static const String upload =
      '上傳暫時失敗，請檢查網路或稍後再試。';
  static const String camera =
      '相機暫時無法使用，請確認權限後再試。';
  static const String generic =
      '目前服務暫時無法使用，請稍後再試。';

  static String companionReply([Object? _]) => companion;

  static String forAction(String action, [Object? _]) {
    switch (action) {
      case 'companion':
        return companion;
      case 'dietRecord':
        return dietRecord;
      case 'upload':
        return upload;
      case 'camera':
        return camera;
      default:
        return generic;
    }
  }

  static bool looksTechnical(String message) {
    final lower = message.toLowerCase();
    return RegExp(
          r'\b(exception|socket|timeout|stacktrace|http|statuscode|status code|failed|error|null|undefined)\b',
        )
            .hasMatch(lower) ||
        RegExp(r'\b\d{3}\b').hasMatch(message) ||
        message.contains('{') ||
        message.contains('}') ||
        message.contains('=>');
  }
}
