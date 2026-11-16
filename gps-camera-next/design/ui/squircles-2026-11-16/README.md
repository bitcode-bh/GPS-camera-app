# Consistent controls and squircle navigation

These previews render the real Flutter widgets with sample data and Roboto substituted for the test font. They are not phone screenshots.

- Toggle groups share 56 dp rows, a 24 dp icon column, 12 dp label gap, consistent padding and the existing 60% switch scale. Bold/Accent settings now use the same grouped layout as stamp fields.
- Control labels use 12 dp medium text, settings use 14 dp medium text, panel titles use 16 dp and screen titles use 24 dp. Active colours change without changing font weight or label geometry.
- Panels, buttons, chips, previews, map cards and navigation use Flutter's native continuous superellipse shapes. Background colours remain unchanged; the camera shutter, map position markers and native switches retain their functional circular shapes.
- Video/Photo and Library/Map use the same fixed-size gliding indicator, a 220 ms easing curve and yellow active labels. Rapid reversal, dragging, recording locks, RTL, larger text and reduced motion are covered by tests.
- Settings controls own clipped Material ink surfaces. Ripples remain inside the tapped row and settings controls no longer scale on press. Pixel comparisons verify that ripple animation does not alter pixels outside the tapped target.

Read-only review identified a missing navigation button role, which was corrected and verified by the accessibility tests. No other actionable findings remained in the reviewed UI update.

Validation: 167 Flutter tests passed, clean analysis, successful Android debug APK build. Device installation and checks are recorded separately under `docs/device-evidence-2026-11-16/`. No iOS runtime check or performance benchmark was performed.
