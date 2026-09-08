# Milestone implementation plan

## Milestone 0 — scaffold

Create the documented directory layout, Flutter Android/iOS project, typed Node
service, formatting/lint/test configuration, contributor rules, and local setup
documentation.

## Milestone 1 — spoken conversation

Create a backend endpoint that exchanges the permanent server credential for a
short-lived Realtime client secret. Establish WebRTC on mobile, attach microphone
audio, play remote audio, support interruption/mute, and surface connection state
and transcript events.

## Milestone 2 — automatic current view

Implement the rear-camera abstraction and preview, register `get_current_view`,
capture a new frame per call, validate/resize/compress it, add it to the same
conversation, and show the exact bytes and timestamp sent. Enforce vision-mode and
session-stop privacy invariants with unit and integration tests.

## Later (not part of this implementation)

Milestone 3 guidance sampling and Milestone 4 field hardening remain follow-up
work. Firmware, external camera, hardware, enclosure, Claude, subscriptions, and
cloud image retention are explicitly excluded.
