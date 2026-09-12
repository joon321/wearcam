import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:wearcam/ai/connection_diagnostics.dart';
import 'package:wearcam/camera/capture_coordinator.dart';
import 'package:wearcam/camera/frame_processor.dart';
import 'package:wearcam/domain/ai_provider.dart';
import 'package:wearcam/domain/camera_source.dart';
import 'package:wearcam/domain/capture_mode.dart';
import 'package:wearcam/domain/chat_mode.dart';
import 'package:wearcam/domain/image_annotation.dart';
import 'package:wearcam/domain/prepared_frame.dart';
import 'package:wearcam/domain/transcript_turn.dart';
import 'package:wearcam/domain/vision_mode.dart';

Future<void> _setWakelock(bool enabled) async {
  try {
    await (enabled ? WakelockPlus.enable() : WakelockPlus.disable());
  } on PlatformException {
    debugPrint('WearCam wakelock unavailable on this platform');
  } on MissingPluginException {
    debugPrint('WearCam wakelock plugin not registered on this platform');
  }
}

enum CaptureState { idle, previewing }

final class ConversationController extends ChangeNotifier
    with WidgetsBindingObserver {
  static const connectionGreetingChatty =
      "Hi, I'm ready. Tell me what you're working on, and I'll look when it would help.";
  static const connectionGreetingChill = 'Ready when you are.';

  static const _chattyInstructions =
      'Respond in a natural, conversational tone. Keep answers concise but friendly. NEVER speak unless the user speaks to you first. Do not initiate conversation, ask unprompted questions, offer unsolicited commentary, or act on your own. Wait silently until the user says something.';
  static const _chillInstructions =
      'Respond with the absolute minimum words necessary. One to five words max when possible. No filler, no pleasantries, no elaboration unless the user explicitly asks for detail. Be direct and terse. NEVER speak unless the user speaks to you first.';
  ConversationController({
    required this.camera,
    required this.provider,
    ConnectionDiagnostics? diagnostics,
    this.processor = const FrameProcessor(),
    VisionAuthorizationController? visionModes,
    CameraSourceManager? cameraSources,
    Duration minimumSessionCaptureInterval = const Duration(seconds: 2),
    CaptureMode captureMode = CaptureMode.auto,
    ChatMode chatMode = ChatMode.chatty,
    double vadThreshold = 0.85,
    this.captureAutoDelay = const Duration(seconds: 2),
  }) : diagnostics =
           diagnostics ?? ConnectionDiagnostics(backendHost: 'unknown'),
       visionModes = visionModes ?? VisionAuthorizationController(),
       _ownsVisionModes = visionModes == null,
       _captureMode = captureMode,
       _chatMode = chatMode,
       _vadThreshold = vadThreshold,
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
        if (_chatMode == ChatMode.chill) {
          unawaited(provider.updateSessionInstructions(_chillInstructions));
        }
        unawaited(provider.sendGreeting(connectionGreeting));
        unawaited(_setWakelock(true));
      }
      if (state == AIConnectionState.disconnected ||
          state == AIConnectionState.failed) {
        this.visionModes.revoke();
        unawaited(_setWakelock(false));
      }
      notifyListeners();
    });
    _transcriptSubscription = provider.transcript.listen((turn) {
      if (_disposed) return;
      _upsertTranscriptTurn(turn);
      _handleAuthorizationTranscript(turn);
      notifyListeners();
    });
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {}
  }

  void _bindCameraStatus(CameraSource source) {
    unawaited(_cameraSubscription?.cancel());
    _cameraSubscription = source.status.listen((state) {
      debugPrint('WearCam camera connection state: ${state.name}');
      if (state == CameraStatus.disconnected || state == CameraStatus.failed) {
        visionModes.revoke();
        _privacyGeneration += 1;
        _cancelManualCapture();
        if (!_disposed) notifyListeners();
      }
    });
  }

  void _handleAuthorizationChanged() {
    if (!_disposed) notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        connectionState == AIConnectionState.connected) {
      unawaited(_setWakelock(true));
    }
  }

  final CameraSource camera;
  final AIProvider provider;
  final ConnectionDiagnostics diagnostics;
  final FrameProcessor processor;
  final VisionAuthorizationController visionModes;
  final bool _ownsVisionModes;
  final CameraSourceManager cameraSources;
  CaptureMode _captureMode;
  ChatMode _chatMode;
  double _vadThreshold;
  final Duration captureAutoDelay;

  CaptureMode get captureMode => _captureMode;
  set captureMode(CaptureMode mode) {
    if (_captureMode == mode) return;
    _captureMode = mode;
    notifyListeners();
  }

  double get vadThreshold => _vadThreshold;
  set vadThreshold(double value) {
    final clamped = value.clamp(0.0, 1.0);
    if (_vadThreshold == clamped) return;
    _vadThreshold = clamped;
    unawaited(provider.updateVadThreshold(clamped));
    notifyListeners();
  }

  ChatMode get chatMode => _chatMode;
  set chatMode(ChatMode mode) {
    if (_chatMode == mode) return;
    _chatMode = mode;
    if (connectionState == AIConnectionState.connected) {
      unawaited(provider.updateSessionInstructions(
        mode == ChatMode.chill ? _chillInstructions : _chattyInstructions,
      ));
    }
    notifyListeners();
  }

  String get connectionGreeting => _chatMode == ChatMode.chill
      ? connectionGreetingChill
      : connectionGreetingChatty;
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
  CaptureState captureState = CaptureState.idle;
  bool microphoneMuted = false;
  bool _disposed = false;
  bool _greetedThisSession = false;
  int _privacyGeneration = 0;
  Completer<void>? _activeToolCall;
  Completer<void>? _manualCaptureSignal;
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

  void triggerCapture() {
    final signal = _manualCaptureSignal;
    if (signal != null && !signal.isCompleted) signal.complete();
  }

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
      } catch (_) {}
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
      unawaited(_notifyVisionResumed());
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
    if (_disposed) return;
    if (call.name == 'highlight_object') {
      await _handleHighlightObject(call);
      return;
    }
    if (call.name == 'show_reference_image') {
      await _handleShowReferenceImage(call);
      return;
    }
    if (call.name != 'get_current_view') return;
    final completion = Completer<void>();
    _activeToolCall = completion;
    final generation = _privacyGeneration;
    try {
      captureState = CaptureState.previewing;
      notifyListeners();

      if (captureMode == CaptureMode.manual) {
        final signal = Completer<void>();
        _manualCaptureSignal = signal;
        await signal.future;
        _manualCaptureSignal = null;
      } else {
        await Future<void>.delayed(captureAutoDelay);
      }

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
      _upsertTranscriptTurn(TranscriptTurn(
        id: 'capture-${call.callId}',
        role: TranscriptRole.user,
        text: '',
        status: TranscriptStatus.completed,
        createdAt: prepared.capturedAt,
        imageBytes: prepared.jpegBytes,
      ));
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
      captureState = CaptureState.idle;
      _manualCaptureSignal = null;
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

  Future<void> _handleHighlightObject(ToolCall call) async {
    final frame = lastTransmittedFrame;
    if (frame == null) {
      await provider.completeToolCall(call.callId, {
        'ok': false,
        'reason': 'no image has been captured yet',
      });
      return;
    }
    final rawRegions = call.arguments['regions'];
    if (rawRegions is! List || rawRegions.isEmpty) {
      await provider.completeToolCall(call.callId, {
        'ok': false,
        'reason': 'regions parameter is required',
      });
      return;
    }
    final annotations = <ImageAnnotation>[];
    for (final r in rawRegions) {
      if (r is! Map<String, dynamic>) continue;
      final x = (r['x'] as num?)?.toDouble();
      final y = (r['y'] as num?)?.toDouble();
      final w = (r['width'] as num?)?.toDouble();
      final h = (r['height'] as num?)?.toDouble();
      final label = r['label'] as String?;
      if (x == null || y == null || w == null || h == null || label == null) {
        continue;
      }
      annotations.add(
        ImageAnnotation(x: x, y: y, width: w, height: h, label: label),
      );
    }
    if (annotations.isEmpty) {
      await provider.completeToolCall(call.callId, {
        'ok': false,
        'reason': 'no valid regions provided',
      });
      return;
    }
    _upsertTranscriptTurn(TranscriptTurn(
      id: 'highlight-${call.callId}',
      role: TranscriptRole.assistant,
      text: '',
      status: TranscriptStatus.completed,
      createdAt: DateTime.now().toUtc(),
      imageBytes: frame.jpegBytes,
      annotations: annotations,
    ));
    notifyListeners();
    await provider.completeToolCall(call.callId, {
      'ok': true,
      'highlighted': annotations.length,
    });
  }

  Future<void> _handleShowReferenceImage(ToolCall call) async {
    final query = call.arguments['query'] as String?;
    if (query == null || query.trim().isEmpty) {
      await provider.completeToolCall(call.callId, {
        'ok': false,
        'reason': 'query parameter is required',
      });
      return;
    }
    final result = await provider.searchImage(query.trim());
    if (result == null) {
      await provider.completeToolCall(call.callId, {
        'ok': false,
        'reason': 'no reference image found for "$query"',
      });
      return;
    }
    _upsertTranscriptTurn(TranscriptTurn(
      id: 'reference-${call.callId}',
      role: TranscriptRole.assistant,
      text: result.title,
      status: TranscriptStatus.completed,
      createdAt: DateTime.now().toUtc(),
      imageBytes: result.imageBytes,
    ));
    notifyListeners();
    await provider.completeToolCall(call.callId, {
      'ok': true,
      'title': result.title,
      'source': result.sourceUrl,
    });
  }

  void _cancelManualCapture() {
    final signal = _manualCaptureSignal;
    if (signal != null && !signal.isCompleted) signal.complete();
  }

  Future<void> stopLooking() async {
    _privacyGeneration += 1;
    _cancelManualCapture();
    captureCoordinator.cancel();
    lastTransmittedFrame = null;
    notifyListeners();
    await provider.sendText(
      'Looking is now off. Continue the voice conversation without using the camera.',
    );
  }

  Future<void> resumeLooking() async {
    visionModes.enable();
    notifyListeners();
    await _notifyVisionResumed();
  }

  Future<void> _notifyVisionResumed() async {
    try {
      await provider.sendText(
        'Looking is back on. You can use the camera again when it would help.',
      );
    } catch (e) {
      debugPrint('WearCam failed to notify AI of vision resume: $e');
    }
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
    _cancelManualCapture();
    visionModes.revoke();
    lastTransmittedFrame = null;
    microphoneMuted = false;
    unawaited(_setWakelock(false));
    await provider.stopSession();
    await cameraSources.selectedSource.disconnect();
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _privacyGeneration += 1;
    _cancelManualCapture();
    unawaited(_setWakelock(false));
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}
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
