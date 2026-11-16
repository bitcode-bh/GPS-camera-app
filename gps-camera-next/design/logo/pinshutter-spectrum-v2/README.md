# PinShutter — Spectrum P refinement

Owner selected concept **01**, requested a smoother colour blend and asked for the script text on the loading screen and in the library. Applied locally; not deployed, committed or pushed.

The refined artwork retains the white script P and glass lens. A continuous teal/plum/indigo gradient plus three broad, overlapping colour fields replaces the isolated bright spots. Pale matching tints keep the wordmark legible at header sizes. All artwork is static PNG at runtime: no font package, shader, network request or animation was added for branding.

## Applied surfaces

- Android and iOS launcher icons, including an Android adaptive background/foreground and a single-colour themed icon.
- Camera loading fallback: 96 dp logo, script wordmark and existing loading feedback.
- Library header: compact script wordmark above the Library/Map switch. Both tab content insets reserve the new header height; back and device-gallery actions remain available.
- Android legacy launch background and iOS launch image: centred logo and wordmark on black. Android 12+ retains the system-managed initial splash, followed by the branded Flutter loading view. Native launch appearance has not been tested on devices.

The native and Flutter initialisation paths do not add an artificial splash delay. No library files, package IDs, album paths, capture stamps or camera controls were changed.

## Source and reproduction

`generate.py` refines the SVG outlines from `../pinshutter-stash-reference-v1/a-icon.svg` and `a-wordmark.svg`, preserving that review's source material. The original lettering was shaped from Pacifico (Copyright 2018 The Pacifico Project Authors, SIL OFL 1.1); the font file is not bundled in PinShutter. This is new static vector artwork; no Stash raster icon or shader implementation was copied into the branding assets. The existing broader ownership/clearance gate remains separate.

Run from the app root:

```sh
python3 design/logo/pinshutter-spectrum-v2/generate.py
dart run flutter_launcher_icons
```

Requires the local `rsvg-convert` executable and Pillow for export assertions. The generator verifies artwork dimensions, nonempty renders and an opaque store icon. SVG masters are retained in this folder; raster variants are exported into the app asset/native resource folders.

`refined-board.png` illustrates placement with placeholder library tiles. `loading-ui.png` and `library-ui.png`, when present, are renders of the actual Flutter widgets using an empty fake library, not device screenshots.

## Validation

- Flutter analysis: clean.
- Flutter tests: **157 passed**, including 320/390 dp branding layout checks and stable header placement when changing tabs.
- Android debug APK: built successfully.
- iOS plist and native launch XML: parsed successfully; no iOS build performed.
- No installation/device review performed for this change. Adaptive mask appearance and platform launch transitions still need device review.

## Brightness refinement — 16 November 2026

Raised the teal/coral/violet brightness slightly while preserving the broad blending, lens geometry and pale script. Regenerated all launcher, native launch and Flutter branding assets, plus the review board and actual widget previews. Asset export assertions, launcher generation, both focused layout tests and the preview export test passed; the Android debug APK rebuilt and its branding bytes match the source assets. The full 157-test suite was not repeated for this asset-only refinement. No deployment or iOS build was performed. See `brightness-validation-2026-11-16.json` for this build's evidence; `validation.json` records the earlier integration.
