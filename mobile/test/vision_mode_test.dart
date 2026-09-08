import 'package:flutter_test/flutter_test.dart';
import 'package:wearcam/domain/vision_mode.dart';

void main() {
  test('visual mode starts off and session closure always stops it', () {
    final modes = VisionModeController();
    expect(modes.mode, VisionMode.off);
    modes.startConversation();
    expect(modes.maySendForToolCall, true);
    modes.onSessionClosed();
    expect(modes.mode, VisionMode.off);
    expect(modes.maySendForToolCall, false);
  });

  test('manual mode does not permit model-requested upload', () {
    final modes = VisionModeController()..selectManual();
    expect(modes.maySendForToolCall, false);
    modes.stopLooking();
    expect(modes.mode, VisionMode.off);
  });
}
