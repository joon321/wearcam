enum VisionMode { off, oneLook, visualSession }

enum VisionAuthorizationSource {
  directRequest,
  contextualConfirmation,
  captureNow,
  visualSessionApproval,
}

enum VisionEndReason {
  stoppedByUser,
  rejected,
  expired,
  completed,
  captureFailed,
  conversationEnded,
  cameraDisconnected,
  backendChanged,
  disposed,
  providerFailure,
}

enum VisualRecommendation { oneLook, visualSession }

final class VisionAuthorizationController {
  VisionAuthorizationController({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  VisionMode _mode = VisionMode.off;
  VisionMode get mode {
    _expireIfNeeded();
    return _mode;
  }

  DateTime? _expiresAt;
  VisualRecommendation? _pendingScope;
  DateTime? _pendingExpiresAt;
  String? _pendingAssistantTurnId;
  String? _lastUserTurnId;
  int _generation = 0;

  int get generation => _generation;
  VisualRecommendation? get pendingScope {
    _expireIfNeeded();
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
  }

  bool authorizeDirectOneLook({
    Duration window = const Duration(seconds: 15),
  }) => _authorizeOneLook(VisionAuthorizationSource.directRequest, window);

  bool authorizeCaptureNow() => _authorizeOneLook(
    VisionAuthorizationSource.captureNow,
    const Duration(seconds: 15),
  );

  bool authorizeDirectVisualSession({
    Duration duration = const Duration(minutes: 10),
  }) => _authorizeSession(duration);

  bool handleContextualApproval(
    String userTurnId, {
    Duration sessionDuration = const Duration(minutes: 10),
  }) {
    _expireIfNeeded();
    if (_lastUserTurnId == userTurnId ||
        _pendingScope == null ||
        _pendingAssistantTurnId == null) {
      return false;
    }
    _lastUserTurnId = userTurnId;
    final scope = _pendingScope!;
    _clearPending();
    return scope == VisualRecommendation.oneLook
        ? _authorizeOneLook(
            VisionAuthorizationSource.contextualConfirmation,
            const Duration(seconds: 15),
          )
        : _authorizeSession(sessionDuration);
  }

  /// Atomically consumes One Look before camera work begins. Sessions remain
  /// active and are still protected by the generation returned here.
  int? beginCapture() {
    _expireIfNeeded();
    if (_mode == VisionMode.oneLook) {
      _mode = VisionMode.off;
      _expiresAt = null;
      return _generation;
    }
    if (_mode == VisionMode.visualSession) return _generation;
    return null;
  }

  bool remainsValid(int generation, {required bool sessionCapture}) {
    _expireIfNeeded();
    if (generation != _generation) return false;
    return sessionCapture ? _mode == VisionMode.visualSession : true;
  }

  void reject() => revoke(VisionEndReason.rejected);

  void revoke(VisionEndReason reason) {
    _mode = VisionMode.off;
    _expiresAt = null;
    _clearPending();
    _generation += 1;
  }

  bool _authorizeOneLook(VisionAuthorizationSource source, Duration window) {
    _clearPending();
    _mode = VisionMode.oneLook;
    _expiresAt = _now().add(window);
    _generation += 1;
    return true;
  }

  bool _authorizeSession(Duration duration) {
    _clearPending();
    _mode = VisionMode.visualSession;
    _expiresAt = _now().add(duration);
    _generation += 1;
    return true;
  }

  void _expireIfNeeded() {
    final now = _now();
    if (_pendingExpiresAt != null && !now.isBefore(_pendingExpiresAt!)) {
      _clearPending();
    }
    if (_expiresAt != null && !now.isBefore(_expiresAt!)) {
      revoke(VisionEndReason.expired);
    }
  }

  void _clearPending() {
    _pendingScope = null;
    _pendingExpiresAt = null;
    _pendingAssistantTurnId = null;
  }
}
