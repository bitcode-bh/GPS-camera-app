# Yellow accents and settings switches

The Custom Template and Display & Units screenshots showed the old periwinkle UI accent. Shared interaction tokens, theme buttons, enabled cycle controls and selected segmented labels now use the camera’s `#FFDB55` yellow. Dark surfaces, inactive choices, disabled controls and user-selected stamp palettes are retained.

One shared native switch row replaces the previous text/chip toggles for stamp visibility, original saving, photo GPS metadata, 24-hour time, bold/accent text and field visibility. ON uses a yellow track with a dark thumb; OFF uses the existing dark surface and neutral thumb. Every row has a consistent minimum 56 dp touch area; native state-change animations avoid per-frame application callbacks. Existing preference keys and values are unchanged.

Map styles, GPS accuracy, coordinate formats, mock-location policy, address formats and measurement units remain explicit choices. No dead or unimplemented settings were added.

Validation: clean analysis, **160 Flutter tests passed**, narrow-screen settings checks, stable switch bounds and persisted-time checks. Actual widget previews with sample data are under `design/ui/yellow-switches-2026-11-16/`. The debug APK was installed successfully over secure Wi-Fi; Android reported successful launch, the app remained foreground/running and its process crash buffer was empty. No switch settings were changed through device automation. No iOS build, runtime performance benchmark, commit or push was performed. See `docs/device-evidence-2026-11-16/yellow-switches-deployment.json`.
