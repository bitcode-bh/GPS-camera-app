# Google Play store listing — draft

Written to match what the app does today. Do not add weather, cloud backup,
offline maps or "most accurate" claims — none are implemented or verified.

## Title (≤30 characters)

**PinShutter: GPS Camera** (22 characters).

App display name: **PinShutter**. Developer display name: **bitcode.bh**.
The owner explicitly approved this branding on 15 November 2026.
Trademark/domain clearance remains pending; this is the approved local listing
draft, not a published Play listing. Earlier name suggestions are superseded.

## Short description (≤80 characters)

`Add time, location and maps to photos and videos. No ads or account.`

## Full description (≤4,000 characters)

PinShutter adds time and available location to photos and videos.
Captures are saved to your device gallery without automatic media uploads
to a developer-operated server.

**Stamp what matters**
• Date and time, coordinates, address and a small map on each capture
• Choose a template, edit fields, and place the map left or right
• Video gets the same stamp as photos; sideways clips are saved upright
• Optional location in photo metadata (EXIF); visible stamp fields are separate

**A camera that stays out of the way**
• Photo and video modes with zoom, exposure and white-balance controls
• Self-timer, grid and aspect ratios
• Keeps the original, unstamped photo too, if you want it

**Your Library**
• Photos and videos together, newest first, with pinch-to-resize grid
• Full-screen viewer with zoom, details and in-app video playback
• Map view of your latest geotagged captures

**Private by design**
• Captures are saved to your phone's gallery — no app account
• No ads, no analytics
• Location is used while the camera is active; capture locations are indexed locally
• Map requests can reveal precise viewed areas to Esri; addresses use your device geocoder
• Sharing and separate gallery/backup apps can send saved files off device

Maps powered by Esri. Map and address data come from third-party services and
may be inaccurate; do not use them for navigation or emergencies.

## Category and tags

Category: **Photography**. Tags: camera, GPS, timestamp, geotag.
Content rating: complete IARC and the intended-audience declaration; no rating is assigned by this draft.
Map claims require the final authenticated release to pass provider/attribution/export checks.

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
