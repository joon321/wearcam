import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wearcam/ai/connection_diagnostics.dart';
import 'package:wearcam/camera/capture_coordinator.dart';
import 'package:wearcam/camera/frame_processor.dart';
import 'package:wearcam/domain/ai_provider.dart';
import 'package:wearcam/domain/camera_source.dart';
import 'package:wearcam/domain/prepared_frame.dart';
import 'package:wearcam/domain/transcript_turn.dart';
import 'package:wearcam/domain/vision_mode.dart';

final class ConversationController extends ChangeNotifier {
  static const connectionGreeting =
      "Hi, I’m ready. Tell me what you’re working on, and I’ll look when it would help.";
  ConversationController({
    required this.camera,
    required this.provider,
    ConnectionDiagnostics? diagnostics,
    this.processor = const FrameProcessor(),
    VisionAuthorizationController? visionModes,
    CameraSourceManager? cameraSources,
    Duration minimumSessionCaptureInterval = const Duration(seconds: 2),
    this.positioningDelay = const Duration(milliseconds: 750),
  }) : diagnostics =
           diagnostics ?? ConnectionDiagnostics(backendHost: 'unknown'),
       visionModes = visionModes ?? VisionAuthorizationController(),
       _ownsVisionModes = visionModes == null,
       cameraSources = cameraSources ?? CameraSourceManager(sources: [camera]) {
    captureCoordinator = CaptureCoordinator(
      sources: this.cameraSources,
      authorization: this.visionModes,
      processor: processor,
      minimumSessionInterval: minimumSessionCaptureInterval,
    );
    _toolSubscription = provider.toolCalls.listen(_handleToolCall);
    _bindCameraStatus(this.cameraSources.selectedSource);
    _cameraSelectionSubscription = this.cameraSources.selectionChanges.listen(
      _bindCameraStatus,
    );
    this.visionModes.addListener(_handleAuthorizationChanged);
    _stateSubscription = provider.connectionStates.listen((state) {
      if (_disposed) return;
      connectionState = state;
      if (state == AIConnectionState.connected && !_greetedThisSession) {
        _greetedThisSession = true;
        unawaited(provider.sendGreeting(connectionGreeting));
      }
      if (state == AIConnectionState.disconnected ||
          state == AIConnectionState.failed) {
        this.visionModes.revoke();
      }
      notifyListeners();
    });
    _transcriptSubscription = provider.transcript.listen((turn) {
      if (_disposed) return;
      _upsertTranscriptTurn(turn);
      _handleAuthorizationTranscript(turn);
      notifyListeners();
    });
  }

  void _bindCameraStatus(CameraSource source) {
    unawaited(_cameraSubscription?.cancel());
    _cameraSubscription = source.status.listen((state) {
      debugPrint('WearCam camera connection state: ${state.name}');
      if (state == CameraStatus.disconnected || state == CameraStatus.failed) {
        visionModes.revoke();
        _privacyGeneration += 1;
        if (!_disposed) notifyListeners();
      }
    });
  }

  void _handleAuthorizationChanged() {
    if (!_disposed) notifyListeners();
  }

  final CameraSource camera;
  final AIProvider provider;
  final ConnectionDiagnostics diagnostics;
  final FrameProcessor processor;
  final Duration positioningDelay;
  final VisionAuthorizationController visionModes;
  final bool _ownsVisionModes;
  final CameraSourceManager cameraSources;
  late final CaptureCoordinator captureCoordinator;
  late final StreamSubscription<ToolCall> _toolSubscription;
  StreamSubscription<CameraStatus>? _cameraSubscription;
  late final StreamSubscription<CameraSource> _cameraSelectionSubscription;
  late final StreamSubscription<AIConnectionState> _stateSubscription;
  late final StreamSubscription<TranscriptTurn> _transcriptSubscription;
  AIConnectionState connectionState = AIConnectionState.disconnected;
  PreparedFrame? lastTransmittedFrame;
  final List<TranscriptTurn> _transcriptTurns = [];
  List<TranscriptTurn> get transcriptTurns =>
      List.unmodifiable(_transcriptTurns);
  String? error;
  String? positioningGuidance;
  bool microphoneMuted = false;
  bool _disposed = false;
  bool _greetedThisSession = false;
  int _privacyGeneration = 0;
  Completer<void>? _activeToolCall;
  Future<void>? _stopInProgress;
  Future<void>? _startInProgress;

  bool get isStarting => _startInProgress != null;
  String get visionStatus => visionStatusFor(visionModes.mode);
  String visionStatusFor(VisionMode mode) => switch (mode) {
    VisionMode.off => 'Vision off',
    VisionMode.visualConversation => 'Visual access enabled',
  };

  Future<void> get activeToolCallCompleted =>
      _activeToolCall?.future ?? Future<void>.value();

  Future<void> start() {
    final existing = _startInProgress;
    if (existing != null) return existing;
    final starting = _start();
    late final Future<void> tracked;
    tracked = starting.whenComplete(() {
      if (identical(_startInProgress, tracked)) {
        _startInProgress = null;
        if (!_disposed) notifyListeners();
      }
    });
    _startInProgress = tracked;
    notifyListeners();
    return tracked;
  }

  Future<void> _start() async {
    _transcriptTurns.clear();
    _processedTranscriptIds.clear();
    _greetedThisSession = false;
    notifyListeners();
    debugPrint(
      'WearCam camera source selected: ${cameraSources.selectedSource.id}',
    );
    await cameraSources.selectedSource.connect();
    if (_disposed) {
      await cameraSources.selectedSource.disconnect();
      return;
    }
    try {
      await provider.startSession();
    } on ProviderConnectionException catch (failure) {
      try {
        await cameraSources.selectedSource.disconnect();
      } catch (cleanupError) {
        diagnostics.record(
          failure.stage,
          'camera_cleanup_failed',
          message: 'Camera cleanup failed (${cleanupError.runtimeType}).',
        );
      }
      error = failure.displayMessage;
      connectionState = AIConnectionState.disconnected;
      notifyListeners();
      return;
    } catch (caught) {
      try {
        await cameraSources.selectedSource.disconnect();
      } catch (_) {
        // Preserve the provider failure below; camera cleanup is best-effort.
      }
      error = 'connection failed (${caught.runtimeType})';
      connectionState = AIConnectionState.disconnected;
      notifyListeners();
      return;
    }
    if (_disposed) return;
    error = null;
    visionModes.enable();
    notifyListeners();
  }

  final Set<String> _processedTranscriptIds = {};

  void _handleAuthorizationTranscript(TranscriptTurn turn) {
    if (turn.status != TranscriptStatus.completed ||
        !_processedTranscriptIds.add(turn.id)) {
      return;
    }
    final text = turn.text.toLowerCase().trim();
    if (turn.role != TranscriptRole.user) return;
    if (_isStopLooking(text)) {
      visionModes.revoke();
      _privacyGeneration += 1;
      debugPrint('WearCam visual access stopped by user');
    } else if (_isResumeLooking(text) || _directLookRequest(text)) {
      visionModes.enable();
      debugPrint('WearCam visual access resumed by user');
    }
  }

  bool _isStopLooking(String text) =>
      RegExp(r'\b(stop looking|stop watching|vision off)\b').hasMatch(text);
  bool _isResumeLooking(String text) => RegExp(
    r'\b(resume looking|start looking|turn vision on)\b',
  ).hasMatch(text);
  bool _directLookRequest(String text) => RegExp(
    r'\b(look at|take a look|check this|can you see)\b',
  ).hasMatch(text);

  void _upsertTranscriptTurn(TranscriptTurn turn) {
    final index = _transcriptTurns.indexWhere(
      (existing) => existing.id == turn.id,
    );
    if (index >= 0) {
      _transcriptTurns[index] = turn;
      return;
    }
    final insertionIndex = _transcriptTurns.indexWhere(
      (existing) => existing.createdAt.isAfter(turn.createdAt),
    );
    if (insertionIndex < 0) {
      _transcriptTurns.add(turn);
    } else {
      _transcriptTurns.insert(insertionIndex, turn);
    }
    if (_transcriptTurns.length > 100) _transcriptTurns.removeAt(0);
  }

  Future<void> _handleToolCall(ToolCall call) async {
    if (_disposed || call.name != 'get_current_view') return;
    final completion = Completer<void>();
    _activeToolCall = completion;
    final generation = _privacyGeneration;
    try {
      positioningGuidance =
          cameraSources.selectedSource.capabilities.isHeadMounted
          ? 'Look directly at the object for a moment.'
          : 'Point your phone camera at the object and hold still.';
      notifyListeners();
      await Future<void>.delayed(positioningDelay);
      if (_toolCallCancelled(generation)) {
        await _completePrivacyCancellation(call.callId);
        return;
      }
      final result = await captureCoordinator.capture(call.callId);
      if (result.kind != CaptureResultKind.sent || result.frame == null) {
        await _completeCaptureFailure(call.callId, result.kind);
        return;
      }
      final prepared = result.frame!;
      if (_toolCallCancelled(generation)) {
        await _completePrivacyCancellation(call.callId);
        return;
      }
      await provider.sendImage(
        prepared,
        'Fresh view requested by get_current_view.',
      );
      if (_disposed || generation != _privacyGeneration) {
        if (_disposed) return;
        await _completePrivacyCancellation(call.callId);
        return;
      }
      lastTransmittedFrame = prepared;
      debugPrint('WearCam image transmission succeeded');
      await provider.completeToolCall(call.callId, {
        'ok': true,
        'captured_at': prepared.capturedAt.toIso8601String(),
        'source': prepared.sourceId,
      });
    } catch (caught) {
      if (_disposed) return;
      error = caught.toString();
      await provider.completeToolCall(call.callId, {
        'ok': false,
        'reason': 'fresh frame unavailable',
      });
    } finally {
      positioningGuidance = null;
      if (!_disposed) notifyListeners();
      if (!completion.isCompleted) completion.complete();
    }
  }

  bool _toolCallCancelled(int generation) =>
      _disposed || generation != _privacyGeneration;

  Future<void> _completeCaptureFailure(String callId, CaptureResultKind kind) =>
      provider.completeToolCall(
        callId,
        kind == CaptureResultKind.permissionRequired
            ? {
                'ok': false,
                'error': {
                  'code': 'vision_disabled',
                  'message': 'Looking is currently off.',
                  'allowedActions': ['resume_looking'],
                },
              }
            : {
                'ok': false,
                'reason': switch (kind) {
                  CaptureResultKind.duplicate => 'duplicate capture request',
                  CaptureResultKind.rateLimited => 'capture rate limited',
                  CaptureResultKind.cancelled =>
                    'visual transmission cancelled',
                  _ => 'fresh frame unavailable',
                },
              },
      );

  Future<void> _completePrivacyCancellation(String callId) =>
      provider.completeToolCall(callId, {
        'ok': false,
        'reason': 'visual transmission cancelled',
      });

  Future<void> stopLooking() async {
    _privacyGeneration += 1;
    captureCoordinator.cancel();
    lastTransmittedFrame = null;
    notifyListeners();
    await provider.sendText(
      'Looking is now off. Continue the voice conversation without using the camera.',
    );
  }

  void resumeLooking() {
    visionModes.enable();
    notifyListeners();
  }

  Future<void> toggleMute() async {
    microphoneMuted = !microphoneMuted;
    await provider.setMicrophoneMuted(microphoneMuted);
    if (!_disposed) notifyListeners();
  }

  Future<void> stopEverything() {
    final existing = _stopInProgress;
    if (existing != null) return existing;
    final stopping = _stopEverything();
    _stopInProgress = stopping;
    return stopping.whenComplete(() {
      if (identical(_stopInProgress, stopping)) _stopInProgress = null;
    });
  }

  Future<void> _stopEverything() async {
    _privacyGeneration += 1;
    visionModes.revoke();
    lastTransmittedFrame = null;
    microphoneMuted = false;
    await provider.stopSession();
    await cameraSources.selectedSource.disconnect();
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _privacyGeneration += 1;
    visionModes.removeListener(_handleAuthorizationChanged);
    visionModes.revoke();
    if (_ownsVisionModes) visionModes.dispose();
    unawaited(_toolSubscription.cancel());
    unawaited(_cameraSubscription?.cancel());
    unawaited(_cameraSelectionSubscription.cancel());
    unawaited(_stateSubscription.cancel());
    unawaited(_transcriptSubscription.cancel());
    super.dispose();
  }
}
