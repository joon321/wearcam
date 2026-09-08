import 'dart:typed_data';

enum CameraStatus { disconnected, connecting, connected, failed }

enum FrameOrientation {
  portraitUp,
  portraitDown,
  landscapeLeft,
  landscapeRight,
}

final class CameraFrame {
  const CameraFrame({
    required this.jpegBytes,
    required this.capturedAt,
    required this.width,
    required this.height,
    required this.sourceId,
    required this.orientation,
    required this.sharpnessScore,
  });

  final Uint8List jpegBytes;
  final DateTime capturedAt;
  final int width;
  final int height;
  final String sourceId;
  final FrameOrientation orientation;
  final double sharpnessScore;
}

abstract interface class CameraSource {
  Future<void> connect();
  Future<CameraFrame> capture();
  Stream<CameraStatus> get status;
  Future<void> disconnect();
}
