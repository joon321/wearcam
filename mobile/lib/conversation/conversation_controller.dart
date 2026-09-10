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
  ConversationController({
    required this.camera,
    required this.provider,
    ConnectionDiagnostics? diagnostics,
    this.processor = const FrameProcessor(),
    VisionAuthorizationController? visionModes,
    CameraSourceManager? cameraSources,
    Duration minimumSessionCaptureInterval = const Duration(seconds: 2),
  }) : diagnostics =
           diagnostics ?? ConnectionDiagnostics(backendHost: 'unknown'),
       visionModes = visionModes ?? VisionAuthorizationController(),
       cameraSources = cameraSources ?? CameraSourceManager(sources: [camera]) {
    captureCoordinator = CaptureCoordinator(
      sources: this.cameraSources,
      authorization: this.visionModes,
      processor: processor,
      minimumSessionInterval: minimumSessionCaptureInterval,
    );
    _toolSubscription = provider.toolCalls.listen(_handleToolCall);
    _cameraSubscription = this.cameraSources.selectedSource.status.listen((
      state,
    ) {
      debugPrint('WearCam camera connection state: ${state.name}');
      if (state == CameraStatus.disconnected || state == CameraStatus.failed) {
        this.visionModes.revoke(VisionEndReason.cameraDisconnected);
        _privacyGeneration += 1;
        if (!_disposed) notifyListeners();
      }
    });
    _stateSubscription = provider.connectionStates.listen((state) {
      if (_disposed) return;
      connectionState = state;
      if (state == AIConnectionState.disconnected ||
          state == AIConnectionState.failed) {
        this.visionModes.revoke(
          state == AIConnectionState.failed
              ? VisionEndReason.providerFailure
              : VisionEndReason.conversationEnded,
        );
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

  final CameraSource camera;
  final AIProvider provider;
  final ConnectionDiagnostics diagnostics;
  final FrameProcessor processor;
  final VisionAuthorizationController visionModes;
  final CameraSourceManager cameraSources;
  late final CaptureCoordinator captureCoordinator;
  late final StreamSubscription<ToolCall> _toolSubscription;
  late final StreamSubscription<CameraStatus> _cameraSubscription;
  late final StreamSubscription<AIConnectionState> _stateSubscription;
  late final StreamSubscription<TranscriptTurn> _transcriptSubscription;
  AIConnectionState connectionState = AIConnectionState.disconnected;
  PreparedFrame? lastTransmittedFrame;
  final List<TranscriptTurn> _transcriptTurns = [];
  List<TranscriptTurn> get transcriptTurns =>
      List.unmodifiable(_transcriptTurns);
  String? error;
  bool microphoneMuted = false;
  bool _disposed = false;
  int _privacyGeneration = 0;
  Completer<void>? _activeToolCall;
  Future<void>? _stopInProgress;
  Future<void>? _startInProgress;

  bool get isStarting => _startInProgress != null;
  bool get isPositioning => visionModes.mode == VisionMode.oneLook;
  String get visionStatus => switch (visionModes.mode) {
    VisionMode.off =>
      visionModes.pendingScope == null
          ? 'Vision off'
          : 'Waiting for your permission',
    VisionMode.oneLook => 'Position camera',
    VisionMode.visualSession => 'Visual session active',
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
    notifyListeners();
  }

  final Set<String> _processedTranscriptIds = {};

  void _handleAuthorizationTranscript(TranscriptTurn turn) {
    if (turn.status != TranscriptStatus.completed ||
        !_processedTranscriptIds.add(turn.id)) {
      return;
    }
    final text = turn.text.toLowerCase().trim();
    if (turn.role == TranscriptRole.assistant) {
      if (_assistantRequestsSession(text)) {
        visionModes.recommend(
          VisualRecommendation.visualSession,
          assistantTurnId: turn.id,
          window: const Duration(seconds: 30),
        );
        debugPrint('WearCam model recommended scope: visual session');
      } else if (_assistantRequestsOneLook(text)) {
        visionModes.recommend(
          VisualRecommendation.oneLook,
          assistantTurnId: turn.id,
        );
        debugPrint('WearCam model recommended scope: one look');
      }
      return;
    }
    if (_isStopLooking(text) || _isRejection(text)) {
      visionModes.revoke(
        _isRejection(text)
            ? VisionEndReason.rejected
            : VisionEndReason.stoppedByUser,
      );
      debugPrint('WearCam visual authorization cancelled by user');
    } else if (_directSessionRequest(text)) {
      visionModes.authorizeDirectVisualSession();
      debugPrint('WearCam visual session authorized by direct request');
    } else if (_directOneLookRequest(text)) {
      visionModes.authorizeDirectOneLook();
      debugPrint('WearCam One Look authorized by direct request');
    } else if (_isApproval(text) &&
        visionModes.handleContextualApproval(turn.id)) {
      debugPrint('WearCam pending visual authorization approved');
    } else if (!_isApproval(text)) {
      // An unrelated turn breaks the immediate contextual confirmation chain.
      visionModes.reject();
    }
  }

  bool _assistantRequestsSession(String text) =>
      text.contains('visual session') &&
      (text.contains('may i') ||
          text.contains('permission') ||
          text.contains('?'));
  bool _assistantRequestsOneLook(String text) =>
      (text.contains('one clear view') || text.contains('one look')) &&
      (text.contains('ready') || text.contains('point the'));
  bool _directSessionRequest(String text) => RegExp(
    r'\b(start looking|keep (watching|looking|checking)|watch me|use the camera while)\b',
  ).hasMatch(text);
  bool _directOneLookRequest(String text) =>
      RegExp(
        r'\b(look at|take a look|check this|can you see|what am i looking at)\b',
      ).hasMatch(text) &&
      !_directSessionRequest(text);
  bool _isApproval(String text) => RegExp(
    r'^(yes|yes please|okay|ok|go ahead|ready|do it)[.!]?$',
  ).hasMatch(text);
  bool _isRejection(String text) =>
      RegExp(r"^(no|no thanks|do not|don't|cancel)[.!]?$").hasMatch(text);
  bool _isStopLooking(String text) =>
      RegExp(r'\b(stop looking|stop watching|vision off)\b').hasMatch(text);

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
      if (!_disposed) notifyListeners();
      if (!completion.isCompleted) completion.complete();
    }
  }

  bool _toolCallCancelled(int generation) =>
      _disposed || generation != _privacyGeneration;

  Future<void> _completeCaptureFailure(
    String callId,
    CaptureResultKind kind,
  ) => provider.completeToolCall(
    callId,
    kind == CaptureResultKind.permissionRequired
        ? {
            'ok': false,
            'error': {
              'code': 'vision_permission_required',
              'message':
                  'Explicit user authorization is required before capturing a view.',
              'allowedActions': ['request_one_look', 'request_visual_session'],
            },
          }
        : {
            'ok': false,
            'reason': switch (kind) {
              CaptureResultKind.duplicate => 'duplicate capture request',
              CaptureResultKind.rateLimited => 'capture rate limited',
              CaptureResultKind.cancelled => 'visual transmission cancelled',
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
    await provider.sendText('Visual transmission stopped. Confirm this aloud.');
  }

  void authorizeOneLook() {
    visionModes.authorizeDirectOneLook();
    notifyListeners();
  }

  void startVisualSession() {
    visionModes.authorizeDirectVisualSession();
    notifyListeners();
  }

  Future<void> captureNow() async {
    if (visionModes.mode == VisionMode.off) {
      visionModes.authorizeCaptureNow();
    }
    final generation = _privacyGeneration;
    final result = await captureCoordinator.capture(
      'capture-now-${DateTime.now().microsecondsSinceEpoch}',
    );
    if (result.kind != CaptureResultKind.sent ||
        result.frame == null ||
        generation != _privacyGeneration ||
        _disposed) {
      return;
    }
    await provider.sendImage(
      result.frame!,
      'User authorized one view with Capture now.',
    );
    if (generation != _privacyGeneration || _disposed) {
      return;
    }
    lastTransmittedFrame = result.frame;
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
    visionModes.revoke(VisionEndReason.conversationEnded);
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
    visionModes.revoke(VisionEndReason.disposed);
    unawaited(_toolSubscription.cancel());
    unawaited(_cameraSubscription.cancel());
    unawaited(_stateSubscription.cancel());
    unawaited(_transcriptSubscription.cancel());
    super.dispose();
  }
}
