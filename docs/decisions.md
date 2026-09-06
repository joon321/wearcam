# Engineering decisions and assumptions

## OpenAI Realtime transport

The app uses WebRTC because it provides microphone capture, remote audio playback,
and a data channel for Realtime events. The backend calls the official client-secret
endpoint and returns its response without the permanent key. The mobile app sends
its SDP to the Realtime calls endpoint using only that short-lived value.

The default model is `gpt-realtime`. Realtime event wire values are isolated in
`OpenAIRealtimeProvider`, so documentation-driven updates do not leak through the
application. Live protocol validation is still required because official OpenAI
documentation was unreachable from this build environment (HTTP 403 / docs tool
unauthorized on 2026-09-06).

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
