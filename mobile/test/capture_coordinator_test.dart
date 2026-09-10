import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wearcam/camera/capture_coordinator.dart';
import 'package:wearcam/domain/camera_source.dart';
import 'package:wearcam/domain/vision_mode.dart';

void main() {
  test(
    'cancel invalidates a request before its serialized work starts',
    () async {
      final camera = _FakeCamera();
      final authorization = VisionAuthorizationController()..enable();
      final coordinator = CaptureCoordinator(
        sources: CameraSourceManager(sources: [camera]),
        authorization: authorization,
        minimumSessionInterval: Duration.zero,
      );

      final pending = coordinator.capture('queued');
      coordinator.cancel();

      expect((await pending).kind, CaptureResultKind.cancelled);
      expect(camera.captureCount, 0);
    },
  );
}

final class _FakeCamera implements CameraSource {
  final _status = StreamController<CameraStatus>.broadcast();
  int captureCount = 0;

  @override
  CameraCapabilities get capabilities => const CameraCapabilities(
    supportsPreview: true,
    supportsLensSwitching: false,
    isHeadMounted: false,
    supportsContinuousPreview: true,
  );
  @override
  CameraStatus get connectionState => CameraStatus.connected;
  @override
  String get displayName => 'Fake camera';
  @override
  String get id => 'fake';
  @override
  Stream<CameraStatus> get status => _status.stream;
  @override
  Future<void> connect() async {}
  @override
  Future<void> disconnect() async {}
  @override
  Future<CameraFrame> capture() async {
    captureCount += 1;
    final image = img.Image(width: 20, height: 20);
    return CameraFrame(
      jpegBytes: Uint8List.fromList(img.encodeJpg(image)),
      capturedAt: DateTime.now().toUtc(),
      width: 20,
      height: 20,
      sourceId: id,
      orientation: FrameOrientation.portraitUp,
      sharpnessScore: 1,
    );
  }
}
