enum VisionMode { off, manual, conversation, guidance }

final class VisionModeController {
  VisionMode _mode = VisionMode.off;
  VisionMode get mode => _mode;
  bool get maySendForToolCall => _mode == VisionMode.conversation;

  void startConversation() => _mode = VisionMode.conversation;
  void selectManual() => _mode = VisionMode.manual;
  void stopLooking() => _mode = VisionMode.off;
  void onSessionClosed() => _mode = VisionMode.off;

  void startGuidance() {
    throw UnsupportedError('Guidance belongs to Milestone 3');
  }
}
