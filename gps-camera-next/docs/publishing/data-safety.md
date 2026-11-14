# Data safety form — prepared answers

Based on the code as of 14 Nov 2026 and Google's [Data safety definitions](https://support.google.com/googleplay/android-developer/answer/10787469).
Re-check after the map and geocoder changes (audit B1/B2).

## Overview questions

| Question | Answer | Why |
| --- | --- | --- |
| Does your app collect or share any of the required user data types? | **Yes** | Location leaves the device in map-tile and geocoding requests. |
| Is all user data encrypted in transit? | **Yes** | All endpoints are HTTPS (Esri, geocoder). |
| Do you provide a way for users to request that their data be deleted? | **Not applicable / No developer-held data** — explain in the privacy policy that the developer stores nothing; captures live in the user's gallery and app data is removed on uninstall or "Clear storage". |

## Data types

| Data type | Collected | Shared | Ephemeral | Required / optional | Purpose |
| --- | --- | --- | --- | --- | --- |
| Location → **Precise location** | **Yes** | **No** if Esri and the geocoder act as your service providers (ArcGIS Location Platform contract); otherwise **Yes** | **Yes** (used only to fetch tiles and an address, not stored by you) | Optional (app works without location; stamp shows "GPS unavailable") | App functionality |
| Location → Approximate location | Covered by precise | — | — | — | — |
| Photos and videos | **No** | No | — | — | Captures are written to the device gallery; nothing is uploaded. Sharing is user-initiated via the Android share sheet. |
| Audio (video soundtrack) | **No** | No | — | — | Stays in the video file on device. |
| Personal info, financial, health, messages, contacts, calendar, app activity, web history | No | No | — | — | Not accessed. |
| App info and performance (crash logs, diagnostics) | No | No | — | — | No crash/analytics SDK. |
| Device or other IDs | No | No | — | — | None read. |

Notes:
- The Nominatim fallback has been removed (audit B2). Recipients of location
  are Esri (map tiles, under your ArcGIS Location Platform account) and the
  device's own geocoder.
- User-chosen fields typed into the stamp (person name, phone number, project
  title) stay on the device and in the images the user saves; they are not
  collected.
