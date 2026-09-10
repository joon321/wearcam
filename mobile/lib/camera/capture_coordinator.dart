import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wearcam/camera/frame_processor.dart';
import 'package:wearcam/domain/camera_source.dart';
import 'package:wearcam/domain/prepared_frame.dart';
import 'package:wearcam/domain/vision_mode.dart';

enum CaptureResultKind {
  sent,
  permissionRequired,
  duplicate,
  rateLimited,
  cancelled,
  failed,
}

final class CaptureResult {
  const CaptureResult(this.kind, {this.frame});
  final CaptureResultKind kind;
  final PreparedFrame? frame;
}

/// Serializes all capture paths and makes authorization the boundary immediately
/// before accessing the selected camera.
final class CaptureCoordinator {
  CaptureCoordinator({
    required this.sources,
    required this.authorization,
    this.processor = const FrameProcessor(),
    this.minimumSessionInterval = const Duration(seconds: 2),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final CameraSourceManager sources;
  final VisionAuthorizationController authorization;
  final FrameProcessor processor;
  final Duration minimumSessionInterval;
  final DateTime Function() _now;
  final Set<String> _handledCalls = {};
  Future<void> _serial = Future.value();
  DateTime? _lastSessionCapture;
  bool _capturePending = false;

  Future<CaptureResult> capture(String callId) {
    if (!_handledCalls.add(callId) || _capturePending) {
      debugPrint('WearCam duplicate capture request coalesced');
      return Future.value(const CaptureResult(CaptureResultKind.duplicate));
    }
    _capturePending = true;
    final completer = Completer<CaptureResult>();
    _serial = _serial.then((_) async {
      // Read authorization only when this queued operation actually starts.
      if (_lastSessionCapture != null &&
          _now().difference(_lastSessionCapture!) < minimumSessionInterval) {
        completer.complete(const CaptureResult(CaptureResultKind.rateLimited));
        debugPrint('WearCam visual session capture rate limited');
        return;
      }
      final generation = authorization.beginCapture();
      if (generation == null) {
        debugPrint('WearCam get_current_view denied: permission required');
        completer.complete(
          const CaptureResult(CaptureResultKind.permissionRequired),
        );
        return;
      }
      try {
        debugPrint('WearCam capture started from ${sources.selectedSource.id}');
        final captured = await sources.selectedSource.capture();
        final prepared = processor.prepare(captured);
        if (!authorization.remainsValid(generation)) {
          completer.complete(const CaptureResult(CaptureResultKind.cancelled));
          return;
        }
        _lastSessionCapture = _now();
        debugPrint('WearCam capture completed and ready for transmission');
        completer.complete(
          CaptureResult(CaptureResultKind.sent, frame: prepared),
        );
      } catch (_) {
        authorization.revoke();
        completer.complete(const CaptureResult(CaptureResultKind.failed));
      }
    });
    return completer.future.whenComplete(() => _capturePending = false);
  }

  void cancel() => authorization.revoke();
}
