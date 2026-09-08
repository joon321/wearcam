# Milestones 0–2 verification report

## Status

Milestones 1–2 remain provisional. The backend is verified locally, but the mobile
application is not considered complete until Flutter formatting, analysis, tests,
and the Android debug build pass.

The requested historical identifier `34b50ad` is not present in this checkout.
The imported equivalent is current `work` history commit `01dbaf1`, titled
“Scaffold WearCam project: Flutter mobile app, TypeScript backend, camera/provider
boundaries, and tests (Milestones 0–2).” The working tree was clean before this
verification pass.

## Environment blockers

- No `flutter` or `dart` executable is installed.
- The current stable release manifest and SDK cannot be downloaded: both direct
  `curl` and `mise ls-remote flutter` fail because the environment's network proxy
  rejects access to `storage.googleapis.com`.
- Official OpenAI documentation cannot be reached. The OpenAI docs resources are
  unavailable, the web lookup returns HTTP 401, and direct official-site requests
  return HTTP 403.
- No Android SDK tools (`sdkmanager` or `adb`) are installed.
- This Linux host cannot perform an iOS/Xcode build.
- The Git checkout has no remote configuration, and `gh auth status` reports no
  authenticated GitHub host. Publishing is therefore unavailable without external
  repository coordinates and credentials.

Because Flutter is unavailable, `flutter create` cannot safely regenerate the
handwritten platform folders and the Dart code cannot be formatted or compiled.
The existing Android/iOS scaffolds remain provisional; this report does not claim
that they are legitimate generated output.

## CI

GitHub Actions runs `dart format .` on its temporary checkout before validation.
With that formatting applied, `flutter analyze`, all Flutter tests, and
`flutter build apk --debug` passed using Flutter 3.35.2. Strict committed-source
formatting enforcement remains outstanding; this result does not establish that
the checked-in Dart files pass `dart format --output=none --set-exit-if-changed .`.

These automated results do not verify physical-device behavior or the OpenAI
Realtime protocol. Physical Android and iPhone tests remain outstanding, and the
iOS build still requires a macOS host with Xcode.

## Next unblock

Run the workflow in a GitHub repository, or provide an environment with access to
the pinned Flutter 3.35.2 SDK and Android SDK. Then run `flutter create` against a
temporary directory, reconcile its generated Android/iOS files, and execute every
required mobile check before changing milestone status.

## Text-only pull-request transport

The original branch diff contained six binary files: five placeholder Android PNG
launcher icons and `mobile/android/gradle/wrapper/gradle-wrapper.jar`. The icons were
replaced by the text vector resource
`mobile/android/app/src/main/res/drawable/ic_launcher.xml`, and the Android manifest
now refers to that drawable. The wrapper JAR was removed and ignored; CI and local
setup regenerate it with pinned Gradle 8.12 before building. APKs, app bundles, iOS
archives, and common archive formats are ignored so they cannot reintroduce binary
artifacts into the pull-request diff.
