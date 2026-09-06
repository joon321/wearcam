# WearCam Bridge App — Codex Build Brief

## Product goal

Build a cross-platform mobile bridge application that enables a hands-free spoken conversation with an AI assistant while selectively sharing current camera images automatically.

The initial MVP uses the phone's rear camera. A later milestone adds a Seeed Studio XIAO ESP32S3 Sense wearable camera without changing the conversation or AI-provider layers.

The application must not upload a continuous video stream. It maintains a local camera preview and sends fresh still images only when the conversation or active guidance mode requires them.

## Primary user experience

1. User connects Bluetooth earbuds and opens the app.
2. User starts a visual conversation.
3. The app opens a low-latency spoken OpenAI Realtime session.
4. User asks a visual question, such as, "Which product is healthier?"
5. The model calls the app tool `get_current_view`.
6. The app captures a fresh image from the active camera source.
7. The app validates, rotates, resizes and compresses the image.
8. The app adds the image to the same conversation.
9. The model answers aloud through the earbuds.
10. The user can say "start looking" for temporary guidance mode or "stop looking" to stop image transmission immediately.

No typing and no repeated manual photo uploads should be required.

## Initial use cases

- Home-repair and assembly guidance
- Shopping and product comparison
- Education and worksheet tutoring

The platform may eventually support additional workflows, but the MVP must remain general-purpose and must not contain workflow-specific business logic.

## Technology

- Mobile UI: Flutter and Dart
- Android-specific integrations: Kotlin only where required
- iOS-specific integrations: Swift only where required
- Backend: Node.js and TypeScript
- Initial AI provider: OpenAI Realtime API
- Later AI provider: Anthropic Messages API plus speech-to-text and text-to-speech
- Initial camera source: phone rear camera
- Later camera source: XIAO ESP32S3 Sense over local Wi-Fi
- Repository: Git with a private remote

## Repository layout

```text
wearcam/
├── AGENTS.md
├── README.md
├── mobile/
├── backend/
├── firmware/
├── hardware/
├── enclosure/
└── docs/
```

Only `mobile/`, `backend/`, project documentation and tests are in scope for the first implementation milestone. Create placeholder README files for later directories; do not design firmware, PCB or enclosure yet.

## Architecture requirements

### Camera abstraction

The conversation layer must not depend directly on a phone camera or XIAO camera.

```dart
abstract interface class CameraSource {
  Future<void> connect();
  Future<CameraFrame> capture();
  Stream<CameraStatus> get status;
  Future<void> disconnect();
}
```

Implement `PhoneCameraSource` first. Reserve `XiaoCameraSource` for a later milestone.

Every frame must include:

- JPEG bytes
- Capture timestamp
- Width and height
- Camera source identifier
- Orientation
- Sharpness score

### AI-provider abstraction

Provider-specific code must remain behind an interface.

```dart
abstract interface class AIProvider {
  Future<void> startSession();
  Future<void> sendText(String text);
  Future<void> sendImage(PreparedFrame frame, String context);
  Future<void> stopSession();
}
```

Implement `OpenAIRealtimeProvider` first. Do not implement Claude until the OpenAI milestones pass.

### Backend boundary

- Permanent provider API keys must never be stored in the mobile app.
- The backend issues short-lived OpenAI client credentials.
- Secrets must come from environment variables.
- Do not commit `.env` files or credentials.
- Add basic request validation, rate limiting and structured error responses.

## AI tools exposed by the bridge

Register these tool definitions with the spoken AI session:

- `get_current_view()` — capture and return one fresh frame
- `capture_high_resolution_view()` — capture a higher-detail frame for text or small objects
- `start_visual_guidance(duration_seconds, minimum_interval_ms)` — enable temporary automatic sampling
- `stop_visual_guidance()` — stop all automatic image transmission
- `get_camera_status()` — report camera availability without capturing an image

The session instructions must require a fresh view whenever the user refers to the current environment or indicates that the view changed. The model must not answer a current visual question using a stale frame.

## Vision modes

```dart
enum VisionMode { off, manual, conversation, guidance }
```

- `off`: no image may leave the device.
- `manual`: explicit UI or hardware trigger only.
- `conversation`: model tool calls request fresh images.
- `guidance`: app evaluates frames locally and selectively supplies meaningful updates until stopped or timed out.

Visual mode must never silently restart after disconnection, relaunch or session recovery.

## Frame processing

Before upload:

1. Verify the frame is fresh.
2. Correct orientation.
3. Measure blur/sharpness.
4. Reject unusable frames and request a replacement.
5. Resize to approximately 1024–1280 pixels on the long edge.
6. Compress as JPEG at an initial quality target of 75–85%.
7. Avoid submitting duplicates.
8. Attach capture time and source context.

During guidance mode:

- Evaluate preview frames locally.
- Begin with a one-second sampling interval.
- Use a simple grayscale thumbnail difference or perceptual-hash comparison.
- Upload only a sharp frame with meaningful visual change.
- Keep no more than three pending frames.
- Discard obsolete background frames in favor of the newest frame.
- A direct AI request or user action has higher priority than a background scene-change event.

## Privacy requirements

- Persistent indicator whenever visual mode is active
- Separate indicator showing the last image-transmission time
- Immediate `Stop looking` control
- Spoken confirmation when visual transmission stops
- No permanent image storage by default
- Temporary images deleted when the session ends
- Configurable guidance timeout
- Preview frames must not be uploaded automatically outside guidance mode
- Microphone mute and full session-stop controls
- Clear camera, microphone and local-network permission explanations

## Mobile screens

### Home

- Camera status
- Internet status
- AI-provider status
- Start conversation
- Start guidance
- Stop everything

### Camera

- Local preview
- Take test image
- Orientation control
- Sharpness/quality result
- Current camera-source selection

### Conversation

- Current provider
- Transcript
- Vision-mode indicator
- Last transmitted-frame thumbnail and timestamp
- Microphone mute

### Settings

- Provider selection placeholder
- Image quality
- Guidance interval and timeout
- Retention setting
- Diagnostics

## Connection states

Track camera, internet, Bluetooth audio and AI-provider connectivity independently. A connected camera does not mean the AI service is available.

Implement explicit reconnecting and failed states, bounded exponential retry, useful user-facing errors and diagnostic logging without retaining image content.

## Milestones

### Milestone 0 — scaffold

- Create repository structure.
- Create Flutter project supporting Android and iOS.
- Create TypeScript backend.
- Add formatting, linting and test commands.
- Add setup documentation.
- Add `AGENTS.md` with build, test, security and scope rules.

### Milestone 1 — spoken conversation

- Start an OpenAI Realtime session using a temporary backend-issued credential.
- Capture microphone input and play spoken output.
- Support Bluetooth audio routing where available.
- Support user interruption.
- Display connection state and transcript.

### Milestone 2 — automatic current view

- Implement `PhoneCameraSource`.
- Show a local rear-camera preview.
- Register `get_current_view`.
- Handle the tool call by capturing and preparing a fresh image.
- Add the image to the pending spoken conversation.
- Receive and play the model's visual answer.
- Show the exact transmitted frame and timestamp.

This is the critical MVP milestone.

### Milestone 3 — visual guidance

- Implement `start_visual_guidance` and `stop_visual_guidance`.
- Add local blur and scene-change checks.
- Add bounded frame queue and rate limiting.
- Stop on voice command, UI action, timeout, camera failure or AI-session closure.
- Instruct the AI to remain silent unless it observes a relevant change, safety concern or required correction.

### Milestone 4 — field hardening

- Test shopping comparison, home repair and worksheet tutoring.
- Test network loss and recovery.
- Test Bluetooth disconnection.
- Test permission denial.
- Measure question-to-audio latency, image uploads per minute and stale-frame errors.
- Document results and unresolved limitations.

### Later milestones — explicitly out of current scope

- XIAO ESP32S3 camera firmware and `XiaoCameraSource`
- BLE Wi-Fi provisioning
- Claude provider
- Wearable enclosure
- Custom PCB
- User accounts, subscriptions and cloud image history

## Required tests

- Unit tests for frame freshness, resizing, orientation and queue priority
- Unit tests for vision-mode transitions and mandatory stop behavior
- Backend tests verifying that permanent API credentials are never returned
- Integration test with a fake AI provider issuing `get_current_view`
- Integration test proving a new frame is captured rather than a cached frame
- Integration test proving no image is uploaded while vision mode is `off`
- Recovery tests for camera, network and provider disconnection

## Definition of done for the first MVP

The first MVP is complete only when all of the following work on at least one physical Android phone and one physical iPhone:

1. User starts a spoken AI conversation.
2. User asks a visual question without typing or touching the capture control.
3. The AI requests the current view through a tool call.
4. The app captures a fresh phone-camera image automatically.
5. The app displays the exact transmitted image and timestamp.
6. The AI gives a relevant spoken response.
7. The user can interrupt the response.
8. `Stop looking` immediately prevents further image transmission.
9. Temporary images are removed at session termination.
10. Automated tests, formatting, static analysis and documented build commands pass.

Target question-to-spoken-answer latency is approximately three seconds under a good network, but record actual measurements rather than hiding failures to meet the target.

## Implementation rules for Codex

- Begin by producing an implementation plan and identifying uncertain SDK/API details.
- Verify current official OpenAI Realtime documentation before selecting packages or event schemas.
- Do not invent SDK methods. Wrap verified provider APIs behind project-owned interfaces.
- Keep pull requests and commits aligned to one milestone at a time.
- Run tests, formatter, linter and platform builds after material changes.
- Record assumptions and limitations in `docs/decisions.md`.
- Prefer a simple working path over speculative abstraction, except for the required camera and provider boundaries.
- Do not begin XIAO firmware, PCB, enclosure or Claude work until Milestones 1–3 pass.

## First instruction to Codex

Use this specification as the product source of truth. First inspect the working directory, then create a milestone-based implementation plan. Scaffold Milestone 0 only, verify the generated Flutter Android/iOS projects and TypeScript backend build successfully, and report blockers before starting Milestone 1. Do not add wearable firmware, Claude integration or custom hardware work yet.
