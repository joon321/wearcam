import 'dart:math' as math;

import 'package:image/image.dart' as img;
import 'package:wearcam/domain/camera_source.dart';
import 'package:wearcam/domain/prepared_frame.dart';

final class FrameRejected implements Exception {
  const FrameRejected(this.reason);
  final String reason;
  @override
  String toString() => 'FrameRejected: $reason';
}

final class FrameProcessor {
  const FrameProcessor({this.maxAge = const Duration(seconds: 5), this.longEdge = 1280});
  final Duration maxAge;
  final int longEdge;

  PreparedFrame prepare(CameraFrame frame, {DateTime? now}) {
    final current = now ?? DateTime.now().toUtc();
    if (current.difference(frame.capturedAt.toUtc()) > maxAge ||
        frame.capturedAt.toUtc().isAfter(current.add(const Duration(seconds: 1)))) {
      throw const FrameRejected('Frame is not fresh');
    }
    final decoded = img.decodeJpg(frame.jpegBytes);
    if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
      throw const FrameRejected('Invalid JPEG');
    }
    var oriented = img.bakeOrientation(decoded);
    final maxDimension = math.max(oriented.width, oriented.height);
    if (maxDimension > longEdge) {
      final scale = longEdge / maxDimension;
      oriented = img.copyResize(
        oriented,
        width: (oriented.width * scale).round(),
        height: (oriented.height * scale).round(),
        interpolation: img.Interpolation.average,
      );
    }
    final sharpness = _laplacianVariance(oriented);
    if (!sharpness.isFinite) throw const FrameRejected('Could not measure sharpness');
    return PreparedFrame(
      jpegBytes: img.encodeJpg(oriented, quality: 82),
      capturedAt: frame.capturedAt.toUtc(),
      width: oriented.width,
      height: oriented.height,
      sourceId: frame.sourceId,
      sharpnessScore: sharpness,
    );
  }

  double _laplacianVariance(img.Image image) {
    final sample = image.width > 160 || image.height > 160
        ? img.copyResize(image, width: 160, maintainAspect: true)
        : image;
    final values = <double>[];
    for (var y = 1; y < sample.height - 1; y++) {
      for (var x = 1; x < sample.width - 1; x++) {
        double luminance(int px, int py) => img.getLuminance(sample.getPixel(px, py)).toDouble();
        values.add(
          4 * luminance(x, y) -
              luminance(x - 1, y) -
              luminance(x + 1, y) -
              luminance(x, y - 1) -
              luminance(x, y + 1),
        );
      }
    }
    if (values.isEmpty) return 0;
    final mean = values.reduce((a, b) => a + b) / values.length;
    return values.fold<double>(0, (sum, value) => sum + math.pow(value - mean, 2)) / values.length;
  }
}
