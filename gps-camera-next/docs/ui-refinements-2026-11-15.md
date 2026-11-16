# Camera overlays and gallery map styles — 15 November 2026

Implemented on `feat/location-integrity`, without committing or pushing.

- GPS integrity notices use a fixed, text-scaled area above the geostamp.
  Showing or hiding a warning does not change the stamp row's geometry.
  Required warnings render immediately in saved photos and video frames.
- Transient camera messages float above the stamp, outside its video snapshot.
  Photo capture removes them immediately, including any outgoing fade.
- Camera notifications and REC use text/shadows without a background. REC's
  idle animation is disabled when not recording.
- EV/zoom overlays start hidden, appear on viewfinder/control interaction,
  remain visible during a held adjustment, and fade after three idle seconds.
  Hidden overlays do not intercept touches or accessibility focus. The top-bar
  adjustment buttons remain available.
- The gallery Map tab now has a layers button above the fit-all button, offering
  Normal, Satellite, Hybrid and Terrain. It uses the existing shared map-style
  preference, including the camera mini-map, without resetting map center,
  zoom, markers or selection.

## Validation

Formatting completed; analysis is clean; all **134 tests pass**; the debug APK
built and was installed on Motorola Edge 70 (`ZA223MDVR8`). Tests cover warning
placement and fixed stamp/map bounds, adjustment inactivity, stable shutter and
gallery positions at 320/390/600 dp, and all four tile styles with saved
preferences and unchanged viewport/markers.

On-device screenshots confirm hidden idle EV/zoom hints, their appearance after
a tap and disappearance after inactivity, and plain GPS warnings above the
stamp. The shutter, settings and gallery rectangles are identical before and
after the warning. Terrain, Normal and satellite imagery render in the gallery;
the original Satellite selection was restored after exercising the picker.

`GPS_1794687588422.jpg` and the decoded video
`GPS_stamped_1794687597970.mp4` retain the mock warning above the stamp. The clip
is 41.020 seconds with 1229 decoded frames at approximately 30 fps. These test
files remain in the app album. Temporary screenshots and inspections are in
`/private/tmp/gps-camera-device-test/` and are not repository assets.

The temporary mock provider was removed and the shell mock-location app-op
restored to default. Existing media and user template settings were retained.
No sustained battery/thermal or new walking/driving measurements were performed.

## Approved fine-pixel controls deployed

The circular shutter retains its 76 dp white ring and 62 dp inner disk in every
state. Taking a photo, recording, and video processing use a yellow pixel fill
with the same 1.7 dp cells and 2.5 dp pitch as the adjustment rails. State fades
keep the disk size fixed; idle photo/video retain their white/red fills. The
rails now use yellow pixels and markers without the capsule backing.

The top zoom button cycles the minimum supported zoom, 1× and 2× where these
values fall inside the active camera's range. The side rail and pinch gesture
retain continuous zoom. This uses CameraX's reported range, not a verified copy
of the manufacturer's private camera-app presets or a new lens-switching path.

Formatting is complete, analysis is clean, and all **136 tests pass**, including
zoom wrapping, supported-range limits, and stable capture/gallery geometry.
Debug APK SHA-256:
`9ba1d956272865f52cf8b9b42e152629680ce25fb85b0a92c13a3ea982ed277b`.
It was installed with `adb install -r` on `ZA223MDVR8` without clearing app data.
On-device checks confirmed 1× → 2× → 1×, yellow EV pixels without a backing,
the full-size grid during a photo and recording, and return to ready states.
A test photo and a 4.998-second clip were saved; the clip was not decoded again
in this pass. No fatal/Flutter runtime errors were found in the current debug
process log. The app was left in Photo at 1×; no commits or pushes were made.

Local evidence: `/private/tmp/gps-camera-device-test/controls-*` and
`controls-deployment-logcat.txt`. No new movement, driving, battery or thermal
measurements were performed.

## Approved pixel motion deployed

The dim, unfilled pixels in EV/zoom bars now cross-fade between muted yellow
shades on a 1.8-second cycle. Filled pixels and the marker remain solid accent
yellow. The shade range responds to zoom and EV magnitude. The existing
three-second auto-hide stays in place; the proposal's keep-visible review
option is not an app setting.

During recording, the full-size shutter grid cross-fades between randomized
yellow/red targets with about 80% red pixels. Photo capture and video processing
retain a static yellow grid. The 76 dp ring and 62 dp disk are unchanged, and
pixel spacing is centered evenly on both axes. Grid background painting is
bounded to the disk.

Motion uses local CustomPainter repaints inside RepaintBoundary layers, capped
at 30 updates/second without rebuilding the camera widget tree. Pattern targets
are cached per cycle. Tickers stop when hidden, inactive, covered by TickerMode,
or when reduced motion is requested. No dependencies or native capture paths
were added or changed for this motion.

Formatting completed; analysis is clean; all **145 tests pass**. Pixel-rendering
tests cover steady filled cells and markers, changing dim cells for positive
and negative EV and zoom, recording's red majority, unchanged size, paint bounds,
and idle/hidden/reduced-motion/inactive pauses. Camera interaction tests use
bounded transition pumping because visible pixel animations intentionally keep
ticking.

Final debug APK SHA-256:
`9b3b1af4de4cb158ea66dca9aa649f88987d702e4d870fb23f1a5c1ed77917a2`.
Installed with `adb install -r` on Motorola Edge 70 (`ZA223MDVR8`). On-device
screenshots confirm dim EV pixel changes, a steady marker, the centered red/
yellow recording grid, zoom changes while recording, and white/red ready
states afterward. Test photo MediaStore ID `55416` and video
`GPS_stamped_1794728834544.mp4` (ID `55415`) remain in the app album.

The 11.7315-second, 1920×1080 video decoded completely on macOS: 352 frames,
nominal 30.0047 FPS, maximum adjacent-frame timestamp gap 35.78 ms, and no
non-increasing timestamps. No fatal/Flutter runtime errors were found in the
current debug process log. The app was left in Photo mode at 1×; settings and
existing media were retained. No commits or pushes were made.

Android `uiautomator dump` reported `could not get idle state` while the live
screen was updating, leaving an older XML file behind. The final device check
therefore used fresh screenshots and saved-media checks, with a debug-app
foreground guard before every tap. Local evidence is under
`/private/tmp/gps-camera-device-test/motion-visible-*`, with decode results in
`motion-video-decode.json` and runtime logs in `motion-deployment-logcat.txt`.

This is a functional and short-clip smoke check. Sustained battery/thermal
measurements and a comparative camera-preview FPS benchmark were not performed.
