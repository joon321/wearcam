import 'dart:async';

import 'package:camera/camera.dart';
import 'package:wearcam/domain/camera_source.dart';

final class PhoneCameraSource implements CameraSource {
  final _status = StreamController<CameraStatus>.broadcast();
  CameraController? _controller;
  CameraLensDirection _preferredLens = CameraLensDirection.back;
  CameraStatus _connectionState = CameraStatus.disconnected;
  Future<void> _operations = Future<void>.value();

  @override
  String get id => 'phone-camera';
  @override
  String get displayName => 'Phone camera';
  @override
  CameraStatus get connectionState => _connectionState;
  @override
  CameraCapabilities get capabilities => const CameraCapabilities(
    supportsPreview: true,
    supportsLensSwitching: true,
    isHeadMounted: false,
    supportsContinuousPreview: true,
  );
  CameraLensDirection get preferredLens => _preferredLens;

  Future<void> selectLens(CameraLensDirection direction) => _enqueue(() async {
    if (_preferredLens == direction) return;
    final reconnect = _controller != null;
    if (reconnect) await _disconnect();
    final previousLens = _preferredLens;
    _preferredLens = direction;
    if (reconnect) {
      try {
        await _connect();
      } catch (_) {
        _preferredLens = previousLens;
        rethrow;
      }
    }
  });

  CameraController? get controller => _controller;
  @override
  Stream<CameraStatus> get status => _status.stream;

  @override
  Future<void> connect() => _enqueue(_connect);

  Future<void> _connect() async {
    if (_controller != null) return;
    _connectionState = CameraStatus.connecting;
    _status.add(CameraStatus.connecting);
    try {
      final cameras = await availableCameras();
      final selected = cameras
          .where((camera) => camera.lensDirection == _preferredLens)
          .first;
      final controller = CameraController(
        selected,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      _controller = controller;
      _connectionState = CameraStatus.connected;
      _status.add(CameraStatus.connected);
    } catch (_) {
      _connectionState = CameraStatus.failed;
      _status.add(CameraStatus.failed);
      rethrow;
    }
  }

  @override
  Future<CameraFrame> capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      throw StateError('Phone camera is not connected');
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
      sourceId:
          'phone-${controller.description.lensDirection.name}:${controller.description.name}',
      orientation: FrameOrientation.portraitUp,
      sharpnessScore: 0,
    );
  }

  @override
  Future<void> disconnect() => _enqueue(_disconnect);

  Future<void> _disconnect() async {
    final controller = _controller;
    _controller = null;
    await controller?.dispose();
    _connectionState = CameraStatus.disconnected;
    _status.add(CameraStatus.disconnected);
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _operations = _operations.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}
