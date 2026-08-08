import 'package:ai_chat_app/core/deep_link/deep_link_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseSimiDeepLink accepts first-party routes only', () {
    expect(
      parseSimiDeepLink('ai-chat://settings')?.action,
      SimiDeepLinkAction.settings,
    );
    expect(
      parseSimiDeepLink('ai-chat:///marketplace')?.action,
      SimiDeepLinkAction.marketplace,
    );
    expect(
      parseSimiDeepLink('ai-chat://new-chat')?.action,
      SimiDeepLinkAction.newChat,
    );
    expect(parseSimiDeepLink('https://example.com/settings'), isNull);
    expect(parseSimiDeepLink('ai-chat://unknown'), isNull);
  });

  test('parseSimiDeepLink opens sessions from query or path', () {
    final byQuery = parseSimiDeepLink(
      'ai-chat://chat?sessionId=Session_ABC-123',
    );
    final byPath = parseSimiDeepLink('ai-chat://session/Session_ABC-123');

    expect(byQuery?.action, SimiDeepLinkAction.session);
    expect(byQuery?.sessionId, 'Session_ABC-123');
    expect(byPath?.action, SimiDeepLinkAction.session);
    expect(byPath?.sessionId, 'Session_ABC-123');
  });

  test('parseSimiDeepLink rejects unsafe session ids', () {
    final tooLongSessionId = List.filled(129, 'a').join();
    expect(parseSimiDeepLink('ai-chat://chat?sessionId=../secret'), isNull);
    expect(parseSimiDeepLink('ai-chat://session/$tooLongSessionId'), isNull);
  });
}
