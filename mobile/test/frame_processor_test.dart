import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wearcam/camera/frame_processor.dart';
import 'package:wearcam/domain/camera_source.dart';

void main() {
  test('rejects stale frames', () {
    final now = DateTime.utc(2026, 1, 1, 0, 0, 10);
    expect(
      () => const FrameProcessor().prepare(frameAt(now.subtract(const Duration(seconds: 6))), now: now),
      throwsA(isA<FrameRejected>()),
    );
  });

  test('resizes long edge while preserving aspect ratio', () {
    final now = DateTime.utc(2026);
    final source = img.Image(width: 200, height: 100);
    final frame = frameAt(now, bytes: Uint8List.fromList(img.encodeJpg(source)), width: 200, height: 100);
    final prepared = const FrameProcessor(longEdge: 100).prepare(frame, now: now);
    expect((prepared.width, prepared.height), (100, 50));
    expect(img.decodeJpg(prepared.jpegBytes), isNotNull);
  });
}

CameraFrame frameAt(DateTime capturedAt, {Uint8List? bytes, int width = 10, int height = 10}) => CameraFrame(
  jpegBytes: bytes ?? Uint8List.fromList(img.encodeJpg(img.Image(width: width, height: height))),
  capturedAt: capturedAt,
  width: width,
  height: height,
  sourceId: 'fake',
  orientation: FrameOrientation.portraitUp,
  sharpnessScore: 0,
);
