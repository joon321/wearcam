# Flutter 3.35.2 platform reconciliation

Reconciled on 2026-09-08 against the Flutter 3.35.2 `flutter create` layout. CI
generates a clean baseline with that pinned SDK and checks the corresponding
platform configuration files. The checked-in directories retain WearCam's `com.wearcam.bridge`
Android application ID and iOS bundle ID, Kotlin/Swift entry points, camera and
microphone usage descriptions, and Android camera, microphone, and Internet
permissions.

The project intentionally differs from the stock template in these reviewed ways:

- The minimum Android SDK is 23 because `flutter_webrtc` requires it.
- WearCam privacy permissions and explanations are additive to the templates.
- The launcher is a checked-in vector rather than generated PNGs so pull-request
  transport remains text-only.
- The Gradle wrapper JAR is regenerated with Gradle 8.12 in CI rather than
  committed.
- CocoaPods configuration is retained for the camera and WebRTC plugins.

The reconciliation restored the template debug/profile Android manifests and the
iOS Profile CocoaPods configuration. CI is the authoritative Android compilation
environment; iOS compilation remains a macOS/Xcode check.
