import 'package:flutter_test/flutter_test.dart';
import 'package:wearcam/domain/vision_mode.dart';

void main() {
  test('visual conversation authorization lasts until revoked', () {
    final authorization = VisionAuthorizationController();
    expect(authorization.beginCapture(), isNull);
    authorization.enable();
    final generation = authorization.beginCapture();
    expect(generation, isNotNull);
    expect(authorization.beginCapture(), generation);
    expect(authorization.remainsValid(generation!), isTrue);
    authorization.revoke();
    expect(authorization.mode, VisionMode.off);
    expect(authorization.remainsValid(generation), isFalse);
  });

  test('enabling and revoking notify only on state transitions', () {
    final authorization = VisionAuthorizationController();
    var notifications = 0;
    authorization.addListener(() => notifications += 1);
    authorization.enable();
    authorization.enable();
    authorization.revoke();
    authorization.revoke();
    expect(notifications, 2);
  });
}
