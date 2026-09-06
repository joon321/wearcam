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
      connectionState = state;
      if (state == AIConnectionState.disconnected || state == AIConnectionState.failed) {
        visionModes.onSessionClosed();
      }
      notifyListeners();
    });
    _transcriptSubscription = provider.transcript.listen((delta) {
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
  int _privacyGeneration = 0;

  Future<void> start() async {
    error = null;
    await camera.connect();
    await provider.startSession();
    visionModes.startConversation();
    notifyListeners();
  }

  Future<void> _handleToolCall(ToolCall call) async {
    if (call.name != 'get_current_view') return;
    if (!visionModes.maySendForToolCall || _captureInFlight) {
      await provider.completeToolCall(call.callId, {'ok': false, 'reason': 'visual transmission disabled'});
      return;
    }
    _captureInFlight = true;
    final generation = _privacyGeneration;
    try {
      final captured = await camera.capture();
      final prepared = processor.prepare(captured);
      // Re-check after asynchronous capture/processing so Stop looking wins the race.
      if (!visionModes.maySendForToolCall || generation != _privacyGeneration) return;
      await provider.sendImage(prepared, 'Fresh view requested by get_current_view.');
      if (!visionModes.maySendForToolCall || generation != _privacyGeneration) return;
      lastTransmittedFrame = prepared;
      await provider.completeToolCall(call.callId, {
        'ok': true,
        'captured_at': prepared.capturedAt.toIso8601String(),
        'source': prepared.sourceId,
      });
    } catch (caught) {
      error = caught.toString();
      await provider.completeToolCall(call.callId, {'ok': false, 'reason': 'fresh frame unavailable'});
    } finally {
      _captureInFlight = false;
      notifyListeners();
    }
  }

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
    notifyListeners();
  }

  Future<void> stopEverything() async {
    _privacyGeneration += 1;
    visionModes.onSessionClosed();
    lastTransmittedFrame = null;
    microphoneMuted = false;
    await provider.stopSession();
    await camera.disconnect();
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_toolSubscription.cancel());
    unawaited(_stateSubscription.cancel());
    unawaited(_transcriptSubscription.cancel());
    super.dispose();
  }
}
