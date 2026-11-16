# Verification and performance

Location-integrity implementation and its current device-validation limits are
documented in [location-integrity.md](location-integrity.md). The dated results
below describe earlier builds.

The subsequent physical-phone run is documented in
[device-verification-2026-11-15.md](device-verification-2026-11-15.md), including
saved photo metadata, decoded video frames, the corrected settings notice,
cleanup and remaining field-test limits.

## Automated cases

Run `flutter analyze` and `flutter test` from the project directory. The
tests cover swipe and tap across all three camera modes at 320, 390, and 600 dp,
recording locks, dial flings, coordinate formats, stale and future GPS fixes,
jump and antimeridian handling, named template persistence, field order, all
preset layouts at narrow width, and rendering a stamp when GPS is unavailable.

**Execution on 9 November 2026.** Static analysis passed, all 17 Flutter tests
passed, and the ARM64 Android APK built and installed on an API 35 emulator.
The final APK launched into Photo mode with a live virtual-scene preview, a
ready shutter, and a visible timestamp and missing-GPS indicator. Android's
cold activity launch took 7.1 seconds in one emulator run. That timing covers
the activity launch and cannot establish time to a camera-ready preview.

The emulator stalled during accessibility inspection. A separate direct-input
attempt did not obtain a capture-ready state consistently enough to export
test files. Burned-in video frames, GPS EXIF on Next's exported photos,
original comparison, and capture/export latency therefore still require
device validation. The test emulator was shut down.

**Design implementation on 10 November 2026.** The approved black camera chrome,
yellow mode pill, continuous vertical zoom/exposure rails, round shutter and
three-column smoke-glass menu are implemented. Automated coverage now includes
continuous upward slider drags and the complete menu/stamp-sheet flows at 320,
390 and 600 dp. Static analysis and all 22 tests pass. The final ARM64 release
installed and launched on the Motorola Edge
70 over wireless ADB. Device interaction checks are pending an unlocked screen.
Live Photo and Night mode are explicitly unavailable in this backend. Styles
opens the stamp style editor.

## Android device test matrix

| Area | Procedure and expected outcome |
| --- | --- |
| Camera | Start in Photo. Try focus, AE/AF lock, pinch, both vertical controls, both cameras, flash and each aspect ratio. Compare capture framing to the preview and check auto-hide. |
| Mode transitions | Tap and swipe between Video, Photo and Pro. Photo and Video reuse the Auto controller. Check preview recovery at both native Pro handoffs and while returning from the background. |
| GPS | Try a valid fix, weak fix, denied permission, disabled provider, stale fix, and movement across the configured jump boundary. Validate that stale coordinates are omitted, weak/retained coordinates are explicitly unverified, mock policies retain their warning, and stamp/map/EXIF use one snapshot. Repeat without a network and check address fallback. |
| Photo output | Shoot each preset and an edited template. Compare date, field order, width, map and top/bottom positioning to the export. Repeat on front/rear cameras, with EXIF and original retention on/off, and at each supported aspect ratio. |
| Video output | Capture a clip with a moving fix and audible cue. Decode multiple timestamps from the exported file and verify the timestamp progresses, GPS changes with the fix, and audio is synchronized. Verify interruption finalizes the clip and failed rendering yields a clearly identified original. |
| Gallery | Check zoom, paging, share, delete cancellation, export to the device album, photo details and map access. |
| Sustained workload | Measure cold time-to-preview, shutter-to-gallery latency, decoded video duration and export time. Repeat rapid captures and record for at least 15 minutes, then check frame pacing, memory, temperature and battery. Compare against the original app on the same device. |

## Current limits

The interface is portrait-first. Full landscape handling, native iOS Pro and
media stamping, in-app video playback,
restamping, verified FPS controls and burst/stabilization coverage remain
open. Android video uses a compact timestamp and GPS text overlay. Still
capture supports the full photo template. Auto JPEGs use the configured
viewfinder raster tier, while the native Pro path can composite at sensor
resolution. Full sensor-resolution Auto compositing is still open. EXIF GPS, selected capture EXIF tags, and original retention are available.
The photo viewer can compare a retained original with the stamped copy.
Preservation of all camera EXIF tags still needs verification.

No physical device was available during the earlier emulator run. Emulator results cover
simulated camera and location only. They cannot establish physical autofocus,
audio synchronization, camera initialization latency, weak-signal behavior,
thermal throttling, or battery consumption.
