# Privacy policy — PinShutter

**Release draft, updated 15 November 2026.** The owner approved the PinShutter name. Trademark/domain clearance remains pending. Do not publish with unfinished contact fields or before confirming provider terms.

Developer display name: **bitcode.bh**
Effective date: [set when published]
Privacy contact: [owner must provide a monitored email]
Public policy URL: [owner must provide a hosted HTTPS page]

## What the app does

PinShutter captures photos and videos and can add time, coordinates, addresses, maps and user-entered stamp details. There is no app account, advertising SDK, analytics SDK or automatic upload of captures to a developer-operated server. We do not sell your location.

## Data and purposes

| Data | Processing and storage | Off-device handling |
| --- | --- | --- |
| Camera, photos and videos | Capture, stamp, display and playback; saved to the device gallery, including an optional original | No automatic media upload by the app; sharing is your choice |
| Microphone/audio | Optional video soundtrack stored in the video file | No automatic audio upload |
| Precise/approximate location and accuracy/integrity information | Foreground geostamping, optional photo GPS metadata and local capture-location index for the Library map | Map requests can reveal precise areas viewed; coordinates are passed to the device address service |
| Addresses/place labels | Visible stamp and local index | Device geocoder may contact its backend |
| Stamp details, such as name, phone or project title | App-private preferences/templates and visible media | Included in files you choose to share |
| Network/request information | Fetching map imagery and provider copyright metadata | Esri receives requests, IP address and app/request headers; tiles identify viewed areas |

Location is used while the camera interface is active, not for background tracking. The app remains usable without location permission. Microphone denial allows silent video. Android permission settings let you deny or revoke access.

## Recipients and services

- **Maps:** Esri ArcGIS services receive map and service-metadata requests. Requests for high-zoom tiles can reveal precise location. See [Esri's privacy statement](https://www.esri.com/en-us/privacy/privacy-statements/privacy-statement) and [privacy supplement](https://www.esri.com/en-us/privacy/privacy-statements/privacy-supplement).
- **Addresses:** Android's device Geocoder may use an OEM/system-provider backend. Availability, handling and privacy terms depend on the device. The app does not use a separate Google Maps SDK or Esri geocoding API.
- **Sharing:** the destination app you select receives the file and any visible stamp, soundtrack and retained metadata. The destination's handling is governed by its own terms.
- **Other gallery/backup apps:** your separately configured gallery or cloud services may back up saved media independently of this app.

Provider contract roles, retention periods and international transfer arrangements must be confirmed by bitcode.bh before this draft is published. Do not describe processing as memory-only or assume providers keep no logs.

## Location choices and sharing

“Embed GPS in photo metadata” controls EXIF GPS only. Disabling it does **not** remove location printed into the visible stamp/map or existing local index entries. Review the stamp fields and saved file before sharing; omit location-bearing fields/maps if you do not want them visible. Once burned into an image or video, visible text cannot be removed by deleting EXIF. Copies already shared are outside the app's control.

## Storage, retention and deletion

Captures are saved to the gallery album `Pictures/GPS Camera Next/`, which retains its earlier name so existing captures remain together. The app keeps a private local index of captured coordinates/place/integrity and private preferences/templates. These remain until the relevant entry is deleted, app storage is cleared or the app is uninstalled. Delete captures through the Library or gallery. Android may require confirmation for some deletions.

Clearing app storage or uninstalling removes app-private settings/index; gallery media can remain and must be deleted separately. It does not erase files already shared or copies held by other backup apps/providers.

The app is configured to exclude private files/preferences/indexes from Android cloud backup and device transfer. This does not retract old backups or control separate gallery backups or every OEM's transfer tools. Provider-side retention/deletion requests must follow the applicable provider relationship and privacy terms; do not promise an unverified deletion period.

## Security

Direct app network endpoints use HTTPS and the app blocks cleartext network traffic. Private JSON is protected by Android's app sandbox and device security; it is not separately encrypted by this app. We do not claim end-to-end encryption of map/geocoder processing. Shared files can disclose sensitive places such as your home or workplace.

## Rights, audience and international processing

Contact the privacy email above for questions or applicable access, correction, deletion or grievance requests. The developer must verify the request and respond as required by the applicable law. There is no app account to delete. Do not claim that a missing developer server removes all privacy obligations.

Before publication, confirm the intended audience and country-specific lawful basis, notices, child-data rules and cross-border safeguards with the actual service arrangements. No child-directed or worldwide legal-compliance claim is made by this draft.

## Changes

Material changes to data handling will be reflected in the in-app explanation, this policy and the Google Play Data safety declaration as applicable. Set the effective date and maintain a reachable contact before launch.
