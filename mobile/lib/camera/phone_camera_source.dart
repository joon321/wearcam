import 'dart:async';

import 'package:camera/camera.dart';
import 'package:wearcam/domain/camera_source.dart';

final class PhoneCameraSource implements CameraSource {
  final _status = StreamController<CameraStatus>.broadcast();
  CameraController? _controller;

  CameraController? get controller => _controller;
  @override
  Stream<CameraStatus> get status => _status.stream;

  @override
  Future<void> connect() async {
    _status.add(CameraStatus.connecting);
    try {
      final cameras = await availableCameras();
      final rear = cameras
          .where((camera) => camera.lensDirection == CameraLensDirection.back)
          .first;
      final controller = CameraController(
        rear,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      _controller = controller;
      _status.add(CameraStatus.connected);
    } catch (_) {
      _status.add(CameraStatus.failed);
      rethrow;
    }
  }

  @override
  Future<CameraFrame> capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      throw StateError('Rear camera is not connected');
    }
    // Timestamp immediately after plugin capture completion: no preview/cached
    // frame is used.
    final file = await controller.takePicture();
    final bytes = await file.readAsBytes();
    final size = controller.value.previewSize;
    return CameraFrame(
      jpegBytes: bytes,
      capturedAt: DateTime.now().toUtc(),
      width: size?.height.round() ?? 0,
      height: size?.width.round() ?? 0,
      sourceId: 'phone-rear:${controller.description.name}',
      orientation: FrameOrientation.portraitUp,
      sharpnessScore: 0,
    );
  }

  @override
  Future<void> disconnect() async {
    final controller = _controller;
    _controller = null;
    await controller?.dispose();
    _status.add(CameraStatus.disconnected);
  }
}
