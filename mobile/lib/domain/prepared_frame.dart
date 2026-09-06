import 'dart:typed_data';

final class PreparedFrame {
  const PreparedFrame({
    required this.jpegBytes,
    required this.capturedAt,
    required this.width,
    required this.height,
    required this.sourceId,
    required this.sharpnessScore,
  });
  final Uint8List jpegBytes;
  final DateTime capturedAt;
  final int width;
  final int height;
  final String sourceId;
  final double sharpnessScore;
}
