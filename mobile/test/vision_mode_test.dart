import 'package:flutter_test/flutter_test.dart';
import 'package:wearcam/domain/vision_mode.dart';

void main() {
  test(
    'expiration notifies listeners without requiring a getter read',
    () async {
      final authorization = VisionAuthorizationController();
      var notifications = 0;
      authorization.addListener(() => notifications += 1);
      authorization.authorizeDirectOneLook(
        window: const Duration(milliseconds: 10),
      );
      final afterAuthorization = notifications;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(notifications, greaterThan(afterAuthorization));
      expect(authorization.mode, VisionMode.off);
      authorization.dispose();
    },
  );

  test('One Look is consumed exactly once and expires', () {
    var now = DateTime.utc(2026);
    final authorization = VisionAuthorizationController(now: () => now);
    authorization.authorizeDirectOneLook();
    expect(authorization.beginCapture(), isNotNull);
    expect(authorization.mode, VisionMode.off);
    expect(authorization.beginCapture(), isNull);
    authorization.authorizeDirectOneLook();
    now = now.add(const Duration(seconds: 16));
    expect(authorization.mode, VisionMode.off);
  });

  test('contextual approval requires a live pending recommendation', () {
    var now = DateTime.utc(2026);
    final authorization = VisionAuthorizationController(now: () => now);
    expect(authorization.handleContextualApproval('isolated'), isFalse);
    authorization.recommend(
      VisualRecommendation.visualSession,
      assistantTurnId: 'assistant-1',
      window: const Duration(seconds: 30),
    );
    expect(authorization.mode, VisionMode.off);
    expect(authorization.handleContextualApproval('user-1'), isTrue);
    expect(authorization.mode, VisionMode.visualSession);
    authorization.revoke();
    authorization.recommend(
      VisualRecommendation.oneLook,
      assistantTurnId: 'assistant-2',
    );
    now = now.add(const Duration(seconds: 16));
    expect(authorization.handleContextualApproval('user-2'), isFalse);
  });

  test('One Look cannot silently become a Visual Session', () {
    final authorization = VisionAuthorizationController()
      ..authorizeDirectOneLook();
    final generation = authorization.beginCapture();
    expect(generation, isNotNull);
    expect(authorization.mode, VisionMode.off);
    expect(
      authorization.remainsValid(generation!, sessionCapture: false),
      isTrue,
    );
    expect(
      authorization.remainsValid(generation, sessionCapture: true),
      isFalse,
    );
    expect(authorization.isVisualSessionActive, isFalse);
  });
}
