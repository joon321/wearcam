# Physical-device manual test plan

Run every case on at least one current Android phone and one iPhone.

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
