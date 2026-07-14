---
lore_type: spec
title: "Capture: pinch-to-zoom camera + import from Photos"
status: approved
date: 2026-07-14
---

# Capture zoom + library import

Requested 2026-07-14. UIImagePickerController's camera UI cannot zoom (its
preview-transform hack doesn't affect the captured image), so:

- **CameraPicker** keeps its public API (`isAvailable`, `onCapture`,
  `onFinish`, presented full-screen) but is reimplemented on AVFoundation:
  session + photo output + preview layer, pinch gesture driving
  `videoZoomFactor` (clamped 1×–10×, capped by the device format), a live
  zoom badge, shutter/cancel controls, and a library shortcut button.
  Permission states handled explicitly (request on first use; denied shows
  an explanation instead of a black screen). Portrait-only app → capture
  connection pinned to portrait.
- **Import from Photos**: "Choose from library" joins "Take photo" in the
  Timeline + menu (reuses the existing photosPicker → downscale → review
  path that previously served only as the no-camera fallback), and the
  in-camera library button chains to the same picker via the established
  pending-flag/onDismiss pattern.
- UI-test stub path (`--uitest-stub-camera`) bypasses the camera entirely —
  unchanged. AVFoundation cannot run on CI simulators, so runtime
  verification is on-device (Suzi's TestFlight pass).
