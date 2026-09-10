import 'dart:async';

import 'package:flutter/foundation.dart';

enum VisionMode { off, oneLook, visualSession }

enum VisualRecommendation { oneLook, visualSession }

final class VisionAuthorizationController extends ChangeNotifier {
  VisionAuthorizationController({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  VisionMode _mode = VisionMode.off;
  DateTime? _expiresAt;
  VisualRecommendation? _pendingScope;
  DateTime? _pendingExpiresAt;
  String? _pendingAssistantTurnId;
  String? _lastUserTurnId;
  int _generation = 0;
  Timer? _expirationTimer;

  VisionMode get mode {
    _expireIfNeeded(notify: false);
    return _mode;
  }

  int get generation => _generation;
  VisualRecommendation? get pendingScope {
    _expireIfNeeded(notify: false);
    return _pendingScope;
  }

  bool get isVisualSessionActive => mode == VisionMode.visualSession;

  void recommend(
    VisualRecommendation scope, {
    required String assistantTurnId,
    Duration window = const Duration(seconds: 15),
  }) {
    _pendingScope = scope;
    _pendingAssistantTurnId = assistantTurnId;
    _pendingExpiresAt = _now().add(window);
    _scheduleExpiration();
    notifyListeners();
  }

  bool authorizeDirectOneLook({
    Duration window = const Duration(seconds: 15),
  }) => _authorizeOneLook(window);

  bool authorizeCaptureNow() => _authorizeOneLook(const Duration(seconds: 15));

  bool authorizeDirectVisualSession({
    Duration duration = const Duration(minutes: 10),
  }) => _authorizeSession(duration);

  bool handleContextualApproval(
    String userTurnId, {
    Duration sessionDuration = const Duration(minutes: 10),
  }) {
    _expireIfNeeded(notify: false);
    if (_lastUserTurnId == userTurnId ||
        _pendingScope == null ||
        _pendingAssistantTurnId == null) {
      return false;
    }
    _lastUserTurnId = userTurnId;
    final scope = _pendingScope!;
    clearPending();
    return scope == VisualRecommendation.oneLook
        ? _authorizeOneLook(const Duration(seconds: 15))
        : _authorizeSession(sessionDuration);
  }

  int? beginCapture() {
    _expireIfNeeded(notify: false);
    if (_mode == VisionMode.oneLook) {
      _mode = VisionMode.off;
      _expiresAt = null;
      _scheduleExpiration();
      notifyListeners();
      return _generation;
    }
    if (_mode == VisionMode.visualSession) return _generation;
    return null;
  }

  bool remainsValid(int generation, {required bool sessionCapture}) {
    _expireIfNeeded(notify: false);
    if (generation != _generation) return false;
    return sessionCapture ? _mode == VisionMode.visualSession : true;
  }

  void clearPending() {
    if (_pendingScope == null && _pendingExpiresAt == null) return;
    _pendingScope = null;
    _pendingExpiresAt = null;
    _pendingAssistantTurnId = null;
    _scheduleExpiration();
    notifyListeners();
  }

  void revoke() {
    _mode = VisionMode.off;
    _expiresAt = null;
    _clearPendingWithoutNotification();
    _generation += 1;
    _scheduleExpiration();
    notifyListeners();
  }

  bool _authorizeOneLook(Duration window) {
    _clearPendingWithoutNotification();
    _mode = VisionMode.oneLook;
    _expiresAt = _now().add(window);
    _generation += 1;
    _scheduleExpiration();
    notifyListeners();
    return true;
  }

  bool _authorizeSession(Duration duration) {
    _clearPendingWithoutNotification();
    _mode = VisionMode.visualSession;
    _expiresAt = _now().add(duration);
    _generation += 1;
    _scheduleExpiration();
    notifyListeners();
    return true;
  }

  void _expireIfNeeded({bool notify = true}) {
    final now = _now();
    var changed = false;
    if (_pendingExpiresAt != null && !now.isBefore(_pendingExpiresAt!)) {
      _clearPendingWithoutNotification();
      changed = true;
    }
    if (_expiresAt != null && !now.isBefore(_expiresAt!)) {
      _mode = VisionMode.off;
      _expiresAt = null;
      _generation += 1;
      changed = true;
    }
    if (changed) {
      _scheduleExpiration();
      if (notify) notifyListeners();
    }
  }

  void _scheduleExpiration() {
    _expirationTimer?.cancel();
    final deadlines = [_expiresAt, _pendingExpiresAt].whereType<DateTime>();
    if (deadlines.isEmpty) return;
    final deadline = deadlines.reduce((a, b) => a.isBefore(b) ? a : b);
    final delay = deadline.difference(_now());
    _expirationTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      _expireIfNeeded,
    );
  }

  void _clearPendingWithoutNotification() {
    _pendingScope = null;
    _pendingExpiresAt = null;
    _pendingAssistantTurnId = null;
  }

  @override
  void dispose() {
    _expirationTimer?.cancel();
    super.dispose();
  }
}
