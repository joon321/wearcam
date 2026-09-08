import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wearcam/camera/frame_processor.dart';
import 'package:wearcam/domain/ai_provider.dart';
import 'package:wearcam/domain/camera_source.dart';
import 'package:wearcam/domain/prepared_frame.dart';
import 'package:wearcam/domain/vision_mode.dart';

final class ConversationController extends ChangeNotifier {
  ConversationController({
    required this.camera,
    required this.provider,
    this.processor = const FrameProcessor(),
    VisionModeController? visionModes,
  }) : visionModes = visionModes ?? VisionModeController() {
    _toolSubscription = provider.toolCalls.listen(_handleToolCall);
    _stateSubscription = provider.connectionStates.listen((state) {
      if (_disposed) return;
      connectionState = state;
      if (state == AIConnectionState.disconnected ||
          state == AIConnectionState.failed) {
        this.visionModes.onSessionClosed();
      }
      notifyListeners();
    });
    _transcriptSubscription = provider.transcript.listen((delta) {
      if (_disposed) return;
      transcript += delta;
      notifyListeners();
    });
  }

  final CameraSource camera;
  final AIProvider provider;
  final FrameProcessor processor;
  final VisionModeController visionModes;
  late final StreamSubscription<ToolCall> _toolSubscription;
  late final StreamSubscription<AIConnectionState> _stateSubscription;
  late final StreamSubscription<String> _transcriptSubscription;
  AIConnectionState connectionState = AIConnectionState.disconnected;
  PreparedFrame? lastTransmittedFrame;
  String transcript = '';
  String? error;
  bool microphoneMuted = false;
  bool _captureInFlight = false;
  bool _disposed = false;
  int _privacyGeneration = 0;
  Completer<void>? _activeToolCall;
  Future<void>? _stopInProgress;

  Future<void> get activeToolCallCompleted =>
      _activeToolCall?.future ?? Future<void>.value();

  Future<void> start() async {
    error = null;
    await camera.connect();
    if (_disposed) {
      await camera.disconnect();
      return;
    }
    try {
      await provider.startSession();
    } catch (_) {
      await camera.disconnect();
      rethrow;
    }
    if (_disposed) return;
    visionModes.startConversation();
    notifyListeners();
  }

  Future<void> _handleToolCall(ToolCall call) async {
    if (_disposed || call.name != 'get_current_view') return;
    if (!visionModes.maySendForToolCall || _captureInFlight) {
      await provider.completeToolCall(call.callId, {
        'ok': false,
        'reason': 'visual transmission disabled',
      });
      return;
    }
    _captureInFlight = true;
    final completion = Completer<void>();
    _activeToolCall = completion;
    final generation = _privacyGeneration;
    try {
      final captured = await camera.capture();
      if (_toolCallCancelled(generation)) {
        if (!_disposed) await _completePrivacyCancellation(call.callId);
        return;
      }
      final prepared = processor.prepare(captured);
      // Re-check after asynchronous capture/processing so Stop looking wins the
      // race.
      if (_toolCallCancelled(generation)) {
        await _completePrivacyCancellation(call.callId);
        return;
      }
      await provider.sendImage(
        prepared,
        'Fresh view requested by get_current_view.',
      );
      if (_toolCallCancelled(generation)) {
        if (_disposed) return;
        await _completePrivacyCancellation(call.callId);
        return;
      }
      lastTransmittedFrame = prepared;
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
      _captureInFlight = false;
      if (!_disposed) notifyListeners();
      if (!completion.isCompleted) completion.complete();
    }
  }

  bool _toolCallCancelled(int generation) =>
      _disposed ||
      !visionModes.maySendForToolCall ||
      generation != _privacyGeneration;

  Future<void> _completePrivacyCancellation(String callId) =>
      provider.completeToolCall(callId, {
        'ok': false,
        'reason': 'visual transmission cancelled',
      });

  Future<void> stopLooking() async {
    _privacyGeneration += 1;
    visionModes.stopLooking();
    lastTransmittedFrame = null;
    notifyListeners();
    await provider.sendText('Visual transmission stopped. Confirm this aloud.');
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
    visionModes.onSessionClosed();
    lastTransmittedFrame = null;
    microphoneMuted = false;
    await provider.stopSession();
    await camera.disconnect();
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _privacyGeneration += 1;
    unawaited(_toolSubscription.cancel());
    unawaited(_stateSubscription.cancel());
    unawaited(_transcriptSubscription.cancel());
    super.dispose();
  }
}
