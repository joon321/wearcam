# WearCam contributor instructions

## Source of truth and scope

- Read `WearCam_Codex_Build_Brief.md` before changing product behavior.
- Keep AI-provider code behind `AIProvider` and camera code behind `CameraSource`.
- Do not implement Claude, XIAO firmware, external cameras, hardware, enclosures,
  subscriptions, accounts, or cloud image storage in Milestones 0–2.

## Security and privacy

- Never commit API keys, `.env` files, credentials, captured images, or transcripts.
- Mobile code may receive only short-lived credentials from the backend. Permanent
  `OPENAI_API_KEY` values must remain server-side.
- Images are in-memory by default. `VisionMode.off` and Stop looking must prevent
  all transmission immediately.

## Required checks

- Backend: `cd backend && npm run check`
- Mobile: `cd mobile && dart format --output=none --set-exit-if-changed .`
- Mobile: `cd mobile && flutter analyze && flutter test`
- Android build: `cd mobile && flutter build apk --debug`
- iOS compile check (macOS only): `cd mobile && flutter build ios --debug --no-codesign`

If a toolchain or platform is unavailable, document that limitation rather than
claiming the check passed. Do not weaken tests, linting, typing, or secret handling
to make checks green.
