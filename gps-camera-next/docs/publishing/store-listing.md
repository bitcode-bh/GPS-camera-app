# Google Play store listing — draft

Written to match what the app does today. Do not add weather, cloud backup,
offline maps or "most accurate" claims — none are implemented or verified.

## Title (≤30 characters)

Pick one after trademark checks (audit §Name):
`Wherelight: GPS Photo Stamp` (27) · `Fieldproof: GPS Photo Proof` (27) ·
`Placelight: GPS Camera` (22) · `Plotmark: Geotag Camera` (23) ·
`Wayproof: Photo Location` (24). Current working name: `GPS Camera Next` (15).

## Short description (≤80 characters)

`Stamp photos and videos with time, place and map. Files stay on your phone.` (75)

## Full description (≤4,000 characters)

[App name] adds when and where to every photo and video you take — clearly,
and without uploading your pictures anywhere.

**Stamp what matters**
• Date and time, coordinates, address and a small map on each capture
• Choose a template, edit fields, and place the map left or right
• Video gets the same stamp as photos; sideways clips are saved upright
• Optional location in photo metadata (EXIF), on or off

**A camera that stays out of the way**
• Photo and video modes with zoom, exposure and white-balance controls
• Self-timer, grid and aspect ratios
• Keeps the original, unstamped photo too, if you want it

**Your Library**
• Photos and videos together, newest first, with pinch-to-resize grid
• Full-screen viewer with zoom, details and in-app video playback
• Map view of your latest geotagged captures

**Private by design**
• Captures are saved to your phone's gallery — no account, no cloud upload
• No ads, no analytics
• Location is used only while the app is open

Maps powered by Esri. Map and address data come from third-party services and
may be inaccurate; do not use them for navigation or emergencies.

## Category and tags

Category: **Photography**. Tags: camera, GPS, timestamp, geotag.
Content rating: complete the IARC questionnaire (no user-to-user content, no
ads → expected "Everyone").

## Graphics

| Asset | Spec | Status |
| --- | --- | --- |
| App icon | 512×512 PNG, full square, no rounded corners or shadow ([spec](https://developer.android.com/distribute/google-play/resources/icon-design-specifications)) | `design/logo/play_store_512.png` (flat lens pin) — redo after final brand |
| Feature graphic | 1024×500 PNG/JPEG | To do |
| Phone screenshots | 2–8, real app UI; ≥1080 px recommended | To capture from a release build; no competitor names, no fake data presented as real places of other people |

## Permissions and justifications

| Permission | Why |
| --- | --- |
| CAMERA | Take photos and videos |
| RECORD_AUDIO | Sound for videos (optional; videos record silently if denied) |
| ACCESS_FINE_LOCATION / ACCESS_COARSE_LOCATION | Coordinates, address and map in the stamp, while the app is open |
| INTERNET, ACCESS_NETWORK_STATE | Map tiles and address lookup |
| WRITE/READ_EXTERNAL_STORAGE (Android ≤ 9 only) | Save to and read the app's album on old Android versions |
| WAKE_LOCK | Added by the video player library to keep playback running |

No background location, contacts, phone, SMS or accessibility permissions.
