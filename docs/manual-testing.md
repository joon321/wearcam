# Physical-device manual test plan

Run every case on at least one current Android phone and one iPhone.

## Android setup gate

1. Build and install the debug APK using the commands in the root README. If no
   dart-define fallback is provided, confirm the setup screen appears. Enter the
   backend URL (without secrets), then relaunch and confirm the app remembers it.
   Record the URL, device model, Android version, APK commit, and whether the
   connection uses HTTPS, local Wi-Fi, or `adb reverse`.
2. Confirm the backend has `OPENAI_API_KEY` in its server-only environment and
   `GET /health` succeeds from the phone. Do not record the key or temporary
   credential. A live session additionally requires an OpenAI project authorized
   for the configured Realtime model.
3. Confirm Android Settings lists Camera and Microphone permissions for WearCam.
   Start with both ungranted so the permission flow is exercised.
4. Open Settings → Change backend, confirm the current URL is prefilled, save a
   replacement, and verify the next session uses it. Confirm a saved URL takes
   precedence over any `WEARCAM_BACKEND_URL` build fallback.
5. In a debug build, verify a reachable local HTTP URL is accepted. In a profile
   or release build, verify HTTP is rejected and HTTPS remains accepted.
6. Paste a provider key-shaped value and a URL containing user credentials into
   setup. Confirm neither can be saved. Do not use or record a real credential.

## Session cases

1. Pair Bluetooth earbuds; verify microphone input and assistant audio use them.
2. Deny, then grant, camera and microphone permissions; verify useful errors.
3. Start a conversation and confirm transcript and connected state update.
4. Interrupt assistant speech and confirm output stops promptly.
5. Ask a current visual question without touching capture. Confirm the rear camera
   captures after the tool call, the displayed image exactly matches the transmitted
   bytes, its timestamp is current, and the spoken answer is relevant.
6. Change the scene and repeat; confirm a newly captured image is sent.
7. Tap Stop looking during capture and confirm no image is transmitted.
8. Stop the session and confirm preview/capture stop, mute resets, and the last
   transmitted frame is removed.
9. Disconnect network, camera availability, and Bluetooth independently; verify
   state/error behavior and that visual mode does not silently restart.
10. Record question-to-first-spoken-answer latency; do not omit results over three
    seconds.
11. Exercise manual/current-view capture, automatic model-requested capture, and
    Stop looking. Confirm Stop looking wins over an in-flight capture and prevents
    every later transmission until visual mode is explicitly enabled again.
12. While a session is connecting and while one is connected, rapidly tap Stop
    Everything or change the backend. Confirm WearCam returns to a stable stopped
    or setup state without a native crash, including on Android 16 devices.
13. Clear app data, configure the phone-reachable backend URL, and start a visual
    conversation. Confirm the backend prints a `POST` for
    `/v1/realtime/client-secret` with status, duration, and request ID.
14. If startup fails, confirm the app returns to `disconnected` within 30 seconds,
    shows the failed stage, and offers Retry and Copy diagnostics. In a debug APK,
    open Settings → Connection diagnostics and confirm the same timestamped stages
    and backend host appear without credentials, authorization data, or SDP.
15. Stop the backend and retry to exercise `request_temporary_credentials`. Then
    restart it and retry successfully. Record the sanitized copied diagnostics and
    matching backend request ID, but never record a credential or API key.

## Voice-triggered vision controls

16. During a connected visual conversation, say "stop looking" through the
    microphone. Confirm vision is revoked (indicator changes) and voice continues.
17. After voice-stopping, say "resume looking" or "start looking." Confirm visual
    access is restored.
18. After voice-stopping, say "look at this" or "can you see the label." Confirm
    visual access is re-enabled by the direct look request.
19. Confirm "stop watching" and "vision off" also revoke visual access.
20. Confirm assistant speech containing "stop looking" does not revoke access.

## Camera lens switching

21. Open the Camera tab during an active session and tap the lens-switch button.
    Confirm the preview switches between front and rear cameras.
22. After switching to the front camera, ask a visual question. Confirm the
    transmitted image uses the front camera (sourceId should contain "front").
23. Switch back to rear. Confirm the next capture uses the rear camera.
24. Confirm the front-camera preview is mirrored and the transmitted image is
    correctly oriented (not mirrored).

## Screen wake and sleep

25. Start a visual conversation and leave the phone idle for two or more minutes.
    Confirm the screen stays on and the conversation remains active.
26. Stop the conversation and confirm the screen is allowed to sleep normally.

## Known external validation gates

- A real server-side OpenAI API key and Realtime project access are required to
  mint the temporary credential and negotiate WebRTC.
- The backend must be deployed with HTTPS or remain reachable from the phone over
  local Wi-Fi/USB as described in the README.
- Camera image relevance, microphone capture, speaker/Bluetooth routing,
  interruption latency, and Android permission recovery require a physical phone;
  automated tests cannot certify them.
