import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android manifest declares every permission required by WebRTC', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    for (final permission in [
      'android.permission.INTERNET',
      'android.permission.ACCESS_NETWORK_STATE',
      'android.permission.CHANGE_NETWORK_STATE',
      'android.permission.MODIFY_AUDIO_SETTINGS',
      'android.permission.RECORD_AUDIO',
    ]) {
      expect(
        manifest,
        contains('android:name="$permission"'),
        reason: '$permission is required before native WebRTC starts',
      );
    }
  });

  test('cleartext remains enabled only in the debug manifest', () {
    final mainManifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final debugManifest = File(
      'android/app/src/debug/AndroidManifest.xml',
    ).readAsStringSync();

    expect(mainManifest, isNot(contains('usesCleartextTraffic="true"')));
    expect(debugManifest, contains('usesCleartextTraffic="true"'));
  });
}
