import 'package:flutter/foundation.dart';

enum VisionMode { off, visualConversation }

final class VisionAuthorizationController extends ChangeNotifier {
  VisionMode _mode = VisionMode.off;
  int _generation = 0;

  VisionMode get mode => _mode;
  bool get isEnabled => _mode == VisionMode.visualConversation;

  void enable() {
    if (isEnabled) return;
    _mode = VisionMode.visualConversation;
    _generation += 1;
    notifyListeners();
  }

  int? beginCapture() => isEnabled ? _generation : null;

  bool remainsValid(int generation) => isEnabled && generation == _generation;

  void revoke() {
    if (_mode == VisionMode.off) return;
    _mode = VisionMode.off;
    _generation += 1;
    notifyListeners();
  }
}
