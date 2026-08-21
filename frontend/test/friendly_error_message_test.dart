import 'package:flutter_test/flutter_test.dart';
import 'package:my_project/utils/friendly_error_message.dart';

void main() {
  group('FriendlyErrorMessage', () {
    test('keeps companion failure text non-technical', () {
      final message = FriendlyErrorMessage.companionReply(
        'SocketException: connection failed (500)',
      );

      expect(message, '精靈暫時無法回應，請稍後再試一次。');
      expect(FriendlyErrorMessage.looksTechnical(message), isFalse);
    });

    test('detects technical messages that should not be shown to users', () {
      expect(
        FriendlyErrorMessage.looksTechnical(
          'Send companion prompt failed: SocketException 500',
        ),
        isTrue,
      );
      expect(
        FriendlyErrorMessage.looksTechnical('請稍後再試一次。'),
        isFalse,
      );
    });
  });
}
