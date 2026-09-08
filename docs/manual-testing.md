# Physical-device manual test plan

Run every case on at least one current Android phone and one iPhone.

## Android setup gate

1. Build and install the debug APK using the backend URL and commands in the root
   README. Record the exact URL (without secrets), device model, Android version,
   APK commit, and whether the connection uses HTTPS, local Wi-Fi, or `adb reverse`.
2. Confirm the backend has `OPENAI_API_KEY` in its server-only environment and
   `GET /health` succeeds from the phone. Do not record the key or temporary
   credential. A live session additionally requires an OpenAI project authorized
   for the configured Realtime model.
3. Confirm Android Settings lists Camera and Microphone permissions for WearCam.
   Start with both ungranted so the permission flow is exercised.

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

## Known external validation gates

- A real server-side OpenAI API key and Realtime project access are required to
  mint the temporary credential and negotiate WebRTC.
- The backend must be deployed with HTTPS or remain reachable from the phone over
  local Wi-Fi/USB as described in the README.
- Camera image relevance, microphone capture, speaker/Bluetooth routing,
  interruption latency, and Android permission recovery require a physical phone;
  automated tests cannot certify them.
