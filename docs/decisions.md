# Engineering decisions and assumptions

## Runtime backend configuration

- The mobile app stores only the WearCam backend base URL in platform-local
  preferences. It never asks for or persists a permanent provider credential.
- Resolution order is a locally saved URL first, then the optional
  `WEARCAM_BACKEND_URL` dart define. With neither, setup is mandatory before the
  camera, microphone, or provider runtime is constructed.
- HTTP is accepted only when Flutter is running in debug mode. Release and profile
  configurations require HTTPS; Android cleartext access remains isolated to the
  debug manifest.
- Changing the backend stops the active conversation and disconnects media before
  returning to setup, preserving the existing Stop Looking and session privacy
  boundaries.

## OpenAI Realtime transport

The app uses WebRTC because it provides microphone capture, remote audio playback,
and a data channel for Realtime events. The backend calls the official client-secret
endpoint and returns its response without the permanent key. The mobile app sends
its SDP to the Realtime calls endpoint using only that short-lived value.

The default model is `gpt-realtime`. Realtime event wire values are isolated in
`OpenAIRealtimeProtocol`, so documentation-driven updates do not leak through the
application. The protocol was reviewed on 2026-09-08 against these official pages:

- https://developers.openai.com/api/docs/guides/realtime-webrtc
- https://developers.openai.com/api/docs/guides/realtime-conversations
- https://developers.openai.com/api/docs/guides/realtime-model-capabilities

The reviewed flow uses `POST /v1/realtime/client_secrets` on the backend, sends the
offer as `application/sdp` to `POST /v1/realtime/calls` with the ephemeral value,
and installs the returned SDP answer. Conversation images use an `input_image`
content part with a JPEG data URL. Tool arguments are accepted only from
`response.function_call_arguments.done`, and outputs use `function_call_output`
followed by `response.create`. Interruption sends `response.cancel` and clears the
WebRTC output audio buffer so already-buffered speech does not continue playing.

No live credential was used for this review. The permanent `OPENAI_API_KEY` remains
exclusively in the backend environment.

## Images and privacy

Captured and prepared frames remain in memory. A tool call takes a fresh capture;
preview frames are never reused. The exact prepared JPEG sent is retained only as
the last-transmission UI value and is cleared on stop. No cloud image storage or
filesystem cache is introduced.

## Frame preparation

The camera plugin supplies JPEG capture and applies device orientation metadata.
The app decodes it, bakes orientation into pixels, resizes the long edge to at most
1280, computes a grayscale Laplacian-variance sharpness score, and encodes at JPEG
quality 82. Frames older than five seconds or with invalid dimensions are rejected.

## Platform assumptions

Flutter's `camera` plugin owns the rear-camera lifecycle. `flutter_webrtc` owns
microphone capture, audio routing, peer connection, and data channel. Bluetooth
routing is selected by Android/iOS; the MVP does not force a private audio route.
