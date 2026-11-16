# Yellow controls and consistent switches

Rendered from the real Flutter widgets with sample settings, not device screenshots. The template render deliberately shows Bold text ON and Accent text OFF; Display & Units shows 24-hour time ON. These render settings do not alter the phone's preferences.

The previous blue/periwinkle interaction tokens now point to the same `#FFDB55` yellow as the camera. Enabled action buttons, style icons and selected segmented options use yellow. Unselected choices and disabled actions retain neutral theme colours.

A shared native switch row now handles Show stamp/Burn into capture, Save original, Embed GPS in photo metadata, 24-hour time, Bold text, Accent text and individual stamp fields. Switches have a yellow ON track, a dark OFF track, native state-change animations and one consistent full-row tap target (at least 56 dp). Row positions and switch bounds remain stable during transitions. Native switch controls retain keyboard, drag and accessibility behaviour.

Map styles, accuracy, coordinate format, mock-location policy and units remain explicit choices. Existing preference keys and capture behaviour are preserved. No new packages, runtime shaders or animation timers were added.

Validation: clean Flutter analysis, **160 passing Flutter tests**, actual widget render check and successful Android debug build. `docs/device-evidence-2026-11-16/yellow-switches-deployment.json` records the wirelessly installed artifact and device observations. No iOS build or runtime performance benchmark was performed.
