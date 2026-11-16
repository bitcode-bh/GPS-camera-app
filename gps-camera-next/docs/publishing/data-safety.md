# Data safety — review worksheet

Updated **15 November 2026** for the intended map-enabled production app. This supersedes the earlier prepared answers. **Not ready to submit:** ArcGIS entitlement/recipient roles/retention, device-geocoder handling and final release configuration remain unverified. Developer display name: bitcode.bh.

Use Google's [current definitions](https://support.google.com/googleplay/android-developer/answer/10787469?hl=en), the actual final build and all relevant tracks/territories. Local processing is distinct from off-device collection; no developer-operated server does not mean no collection.

| Topic | Preparation | Evidence still required |
| --- | --- | --- |
| Data collected/shared overview | Prepare **Yes** for off-device location-bearing map requests | Trace the authenticated final build and actual geocoder behavior |
| Precise location | Prepare collected/functionality; high-zoom tiles can identify areas below 3 km² | Confirm all location-related requests, any system-service exclusion and optional/required definitions |
| Approximate location | Also review approximate location inferred from IP and any coarse-location paths | Do not assume precise location automatically answers every approximate-location field |
| Location shared | **Unresolved** | Service-provider exemption requires processing on the developer's behalf/instructions; otherwise disclose applicable sharing |
| Ephemeral processing | **Not established** | App-side lack of server storage does not prove providers retain data only in memory for a real-time request |
| Optional/required | Optional only if every user can opt out and still use the app under Google's definition | Verify all devices/regions and the actual core functionality |
| Encryption in transit | Direct endpoints HTTPS; cleartext blocked | Confirm all personal-data flows and device-provider handling before affirming universally |
| Photos/video/audio | No automatic upload found; local capture/playback | Review final SDKs and user-initiated sharing exception |
| Names/phone/project text | Handled locally in settings/templates/media | These fields are accessed even though not automatically uploaded |
| Crash diagnostics/device IDs | No app telemetry/ads/account SDK identified | Recheck final runtime and provider request processing |
| Deletion request | Supply real privacy contact and local/provider deletion explanation | Do not select “not applicable” merely because there is no developer server |
| Account deletion | No app account system | Reassess if accounts are added |

## Required before submission

1. Identify recipients, purposes, location precision, request metadata and retention from the final configuration. Review Esri account terms/DPA and OEM geocoder handling.
2. Set a monitored contact and public hosted privacy policy; make in-app text and Console answers consistent.
3. Review actual user-directed sharing, data-type definitions, provider exceptions and audience. Do not copy another app's declaration.
4. Confirm private backup exclusions in the merged manifest/rules; separately explain gallery backups and previously shared files.
5. Record the final answers, rationale, approver, artifact hash and submission date. No Console form has been submitted by this work.
