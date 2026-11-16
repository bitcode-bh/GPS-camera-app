# Automated device verification — 15 November 2026

Motorola Edge 70, USB serial `ZA223MDVR8`, Android 17 / API 37.
Tested `com.gpscamera.gps_camera_next.debug` on `feat/location-integrity`.
The user requested automated checks only; no walking or driving was performed.

Final debug APK SHA-256:
`4acdc68eff23ef1daf619ee31c0e35ba0899ebc710630e99fff4b27b0f6f9c20`.
The final build is installed. No commit, push or Play submission was made.

## Observed results

| Check | Result and evidence |
| --- | --- |
| Real-fix photo | Passed. Saved visual coordinates, EXIF coordinates and app index agree to display/EXIF rounding. Reported accuracy was about ±12.7 m. The map and Esri credit are present; the preview-only HYBRID tag is absent from the saved photo. This does not establish absolute ground-truth accuracy. |
| Android mock flag, Label policy | Passed using Android's fused test provider, not a third-party mock app. The saved photo contains `Mock Location`, the injected coordinates and ±5 m uncertainty. EXIF UserComment and the library index also retain the mock warning. |
| Android mock flag, Omit GPS policy | Passed. Saved photos contain `Mock Location · Coordinates omitted`, no map or coordinate text, no GPS EXIF entries, and no indexed coordinate. |
| Optional stamp disabled | Passed. With `Burn into capture` off and mock policy Omit GPS, the warning remains in the saved photo and video. The native video output was decoded, rather than judged only from its preview. |
| Location switch during video | Passed. Location was turned off through `cmd location` while recording and restored afterward. Decoded frames show `GPS unavailable`, without the old map or coordinates, during the outage. Clock text advances. The live app subsequently reacquired real fixes. |
| Expired fix | Passed. One mock fix was delivered and further updates withheld. A photo taken approximately 72 seconds later has no coordinates, map, GPS EXIF or indexed location, and still carries the mock warning. The exact 60-second boundary remains covered by unit tests; this device capture verifies behavior after the boundary. |
| Real fix outside accuracy preference | Passed. With a temporary 10 m preference, a real ±21.6 m fix is saved as `Location unverified · Weak GPS signal`, not suspected spoofing. Visual coordinates agree with EXIF/index; both EXIF and the index preserve uncertainty status. |
| Portrait video export | Passed for one 32.164-second clip: 1080 × 1920, 965 decoded frames, approximately 30 fps. Inspected frames at 1, 20, 25, 27, 30 and 31 seconds. The available-location frame includes the map; outage frames omit it. |
| Landscape video export | Passed for one 20.060-second clip: 1920 × 1080, 601 decoded frames, approximately 30 fps. Inspected frames at 1, 8, 15 and 19 seconds; all retain the mock/omission warning. |
| Photo orientation | Omit-policy photos taken while the phone was sideways have EXIF orientation 6 and render upright when that orientation is applied. |

## Bug found and corrected

The settings menu incorrectly described intentional mock-coordinate omission
as `Weak GPS signal · ±5 m`. `_gpsNotice` now prioritizes mock/spoof integrity
states over the generic unavailable-position notice. The installed correction
was checked on the phone: it shows **Mock location detected / GPS omitted**.
The 320 dp camera layout regression now exercises this case and rejects the
old weak-signal label.

## Saved evidence

The following new files remain in the phone's `Pictures/GPS Camera Next/`
album. Existing media was not removed. Local inspections, XML UI snapshots,
EXIF summaries and decoded frames are in `/private/tmp/gps-camera-device-test/`;
they are temporary evidence and are not added to the repository.

| File | Purpose |
| --- | --- |
| `GPS_1794684731798.jpg` | Real fix and matching visual/EXIF/index coordinates |
| `GPS_1794684946772.jpg` | Mock Label policy |
| `GPS_1794684988793.jpg` | Mock Omit GPS policy |
| `GPS_1794685056457.jpg` | Omit GPS with optional stamp off |
| `GPS_1794685412049.jpg` | Expired fix with Label policy |
| `GPS_1794685477154.jpg` | Real fix beyond the temporary 10 m preference |
| `GPS_stamped_1794684807444.mp4` | Location-switch interruption during recording |
| `GPS_stamped_1794685073193.mp4` | Landscape mock warning with optional stamp off |

## Cleanup and validation

Location is restored to enabled. Both temporary fused test providers were
removed, and the shell mock-location app-op returned to its original default
mode. Survey template and original preferences were restored, including the
default 25 m accuracy preference, Label mock policy and enabled stamp. The
capture counter was retained. The updated debug camera was left open.

After the correction: formatting completed, static analysis reported no
issues, all **132 Flutter tests passed**, and the Android debug APK built.

The real photo appeared in MediaStore roughly four seconds after its shutter
timestamp, and the 32-second video appeared roughly nine seconds after the
stop command. These are coarse observations from file/event timestamps, not
controlled latency measurements or a comparison with the previous build.

## Still unverified

Walking/driving filter lag and jitter, turning through north and compass feel,
real GNSS spoofing, third-party mock-app compatibility, urban multipath
false-positive rates, pinch zoom, tile outages, permission changes, original
retention, audio synchronization and sustained battery/thermal behavior were
not verified in this run. Device success here does not certify location
authenticity, battery efficiency or Play readiness.
