# WearCam Bridge

WearCam is a Flutter mobile bridge for a low-latency spoken OpenAI Realtime
conversation that shares fresh rear-camera stills only when requested. The product
source of truth is [`WearCam_Codex_Build_Brief.md`](WearCam_Codex_Build_Brief.md).

## Repository

- `mobile/` — Flutter app (Android and iOS), camera and AI-provider boundaries.
- `backend/` — Node.js/TypeScript service that creates short-lived Realtime credentials.
- `docs/` — implementation plan, decisions, privacy notes, and manual test plan.
- `firmware/`, `hardware/`, `enclosure/` — out-of-scope placeholders only.

## Prerequisites

- Flutter stable with its bundled Dart SDK
- Android Studio/SDK for Android; Xcode and CocoaPods on macOS for iOS
- Node.js 24+ and npm
- An OpenAI project API key (backend only)

## Backend setup

```sh
cd backend
cp .env.example .env
# Add OPENAI_API_KEY only to .env; never put it in mobile configuration.
npm install
npm run dev
```

`npm run dev` automatically loads `backend/.env` and starts the service in watch
mode on port `8787` by default. Keep `OPENAI_API_KEY` only in that server-side
file. Each session asks this service for a short-lived Realtime credential; the
APK contains only the backend URL.

## Mobile setup

```sh
cd mobile
flutter pub get
flutter run
```

On first launch, enter the WearCam backend base URL in the setup screen. The app
persists only that URL on the device. A build-time default remains available for
managed/test builds, but is used only when no URL has been saved:

```sh
flutter run --dart-define=WEARCAM_BACKEND_URL=https://your-backend.example
```

Open **Settings → Change backend** to replace the saved URL. Do not enter or pass
a provider API key: permanent credentials remain in `backend/.env`, while the app
receives only a short-lived Realtime credential from the backend.

The Gradle wrapper JAR is intentionally not committed because the repository's PR
transport accepts text files only. Regenerate it after installing the pinned Gradle
8.12 toolchain:

```sh
cd mobile/android
gradle wrapper --gradle-version 8.12 --distribution-type all
```

CI performs this regeneration before the Android build. The wrapper scripts and
properties remain versioned, so the regenerated JAR is local/generated tooling and
not an application source artifact.

Grant camera and microphone permission when prompted. Pair Bluetooth earbuds in
the operating system before starting a conversation; audio routing is owned by the
OS/WebRTC stack.

## Install an Android debug prototype

Prefer an HTTPS backend deployed to a URL the phone can reach:

```sh
cd mobile
flutter build apk --debug \
  --dart-define=WEARCAM_BACKEND_URL=https://your-backend.example
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

The dart define above is optional. Without it, the installed app asks for the URL;
after setup, the locally saved value takes precedence over future build defaults.

For local Wi-Fi testing, start the backend with the phone and computer on the same
trusted network, allow inbound TCP port `8787` in the computer firewall, and use
the computer's LAN address (not `localhost`):

```sh
cd backend
# Configure OPENAI_API_KEY in backend/.env first, as described above.
npm run dev
# In another shell; replace the example address with the computer's LAN address.
cd ../mobile
flutter build apk --debug \
  --dart-define=WEARCAM_BACKEND_URL=http://192.168.1.20:8787
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

Cleartext HTTP is enabled only by the Android debug manifest for this local test
case; release builds still require HTTPS. Verify `http://<LAN-IP>:8787/health` from
the phone browser before opening WearCam. USB testing can instead use
`adb reverse tcp:8787 tcp:8787` and a debug APK built with
`WEARCAM_BACKEND_URL=http://127.0.0.1:8787`; the reverse must be recreated after
disconnecting USB or restarting ADB.

At first start, Android asks for camera access when the camera connects and
microphone access when WebRTC starts. Grant both while using the app. If denied
permanently, enable **Camera** and **Microphone** under Android Settings → Apps →
WearCam → Permissions. WebRTC also receives normal install-time permissions to
read network connectivity, request network changes, and control call audio. These
do not show runtime prompts and do not grant nearby-device discovery; the app makes
a normal Internet connection to the configured backend.

An APK built without a backend URL opens the in-app setup screen instead of
crashing. Use **Settings → Change backend** rather than rebuilding to update it.
Debug builds accept HTTP for trusted local Wi-Fi or `adb reverse` testing. Profile
and release builds require HTTPS, regardless of how the URL is supplied. Never
pass `OPENAI_API_KEY` through `--dart-define` or enter it in the app.

## Verification

```sh
(cd backend && npm run check)
(cd mobile && dart format --output=none --set-exit-if-changed .)
(cd mobile && flutter analyze && flutter test)
(cd mobile && flutter build apk --debug)
# macOS only:
(cd mobile && flutter build ios --debug --no-codesign)
```

Tests use fakes and do not require an API key. Live Realtime testing requires the
backend environment described in [`backend/.env.example`](backend/.env.example).
See [`docs/manual-testing.md`](docs/manual-testing.md) for physical-device checks.
