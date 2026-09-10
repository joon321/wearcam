import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wearcam/camera/phone_camera_source.dart';

void main() {
  test(
    'PhoneCameraSource preserves the selected lens before initialization',
    () async {
      final source = PhoneCameraSource();
      expect(source.preferredLens, CameraLensDirection.back);
      await source.selectLens(CameraLensDirection.front);
      expect(source.preferredLens, CameraLensDirection.front);
      expect(source.capabilities.supportsLensSwitching, isTrue);
      expect(source.displayName, 'Phone camera');
    },
  );
}
