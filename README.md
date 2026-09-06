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
# Set OPENAI_API_KEY in .env; never put it in mobile configuration.
npm install
npm run dev
```

The service listens on `http://127.0.0.1:8787` by default. Expose it through a
development TLS proxy or tunnel before starting the mobile app: WearCam requires
`WEARCAM_BACKEND_URL` to be an HTTPS URL reachable from the device. Never embed a
permanent provider credential in that URL or in the mobile configuration.

## Mobile setup

```sh
cd mobile
flutter pub get
flutter run --dart-define=WEARCAM_BACKEND_URL=https://your-backend.example
```

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
