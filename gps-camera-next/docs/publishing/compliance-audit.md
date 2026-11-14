# Google Play pre-publication compliance audit — GPS Camera Next

Audited: branch `claude/gps-camera-next-production-be862f`, package
`com.gpscamera.gps_camera_next`, version `0.1.0+1`, on 14 Nov 2026.
Method: source inspection (every network endpoint, dependency, asset and
permission), dependency licence scan, and research against primary policy and
provider pages (linked per finding). Third-party summaries are marked as such.

> This is an engineering compliance review, not legal advice. Trademark
> clearance and the privacy policy should be confirmed by a qualified IP /
> privacy professional before launch.

## Verdict

**NOT READY FOR PUBLICATION.** Five blockers: unlicensed use of Esri map
tiles, Nominatim use that breaks its usage policy, no privacy policy, no
upload signing key, and an undeclared Data safety form. None needs a rewrite;
all are fixable in days. Details and fixes below.

## What the app actually uses (from the code)

| Service | Where in code | What is sent | Key / account |
| --- | --- | --- | --- |
| Esri World Street Map, World Imagery, World Topo, Reference labels — `server.arcgisonline.com` | `lib/models/map_kind.dart`; used by `lib/widgets/mini_map.dart` (live stamp + popup) and `lib/screens/library/media_map.dart` | Tile requests (z/x/y around the user's position, i.e. precise location) + IP + user agent `com.gpscamera.gps_camera_next` | **None** |
| OpenStreetMap Nominatim reverse geocoding — `nominatim.openstreetmap.org` | `lib/services/location_service.dart:279` | Exact lat/lon, IP, user agent `gps_camera_next/1.0` (no contact) | None |
| Android platform Geocoder (via `geocoding` plugin) | `lib/services/location_service.dart:239` | Lat/lon to the device's geocoder backend (Google Play services on most phones) | None |
| Map tiles **burned into saved photos and videos** (stamp mini-map) | `lib/widgets/geo_stamp.dart`, video stamp overlay | Esri imagery becomes part of user content that users share | — |

No analytics, ads, crash reporting, accounts or developer servers exist. Photos
and videos stay on the device (MediaStore) unless the user shares them.

## Final compliance report

| Area | Verification | Risk | Required action |
| --- | --- | --- | --- |
| Application name | Play and web similarity search | **Medium** | "GPS Camera Next" sits among dozens of "GPS Camera …" / "GPS Map Camera …" apps; descriptive, weakly distinctive, high confusion. Rebrand to a distinctive name (shortlist below). |
| Trademark | Registry verification | **Medium (unverified)** | No exact registered mark found in web-indexed sources; official IP India and WIPO searches were **not** performed (they require an interactive search with CAPTCHA). Owner must run them (steps below). |
| Copyright | Asset and dependency audit | **Low–Medium** | All 109 shipped Dart packages and native libraries are permissive (Apache-2.0/BSD/MIT); no GPL. Missing in-app licence notices. Competitor-derived comments and an "inspired-by" template set need cleanup. |
| Map licensing | Provider terms | **High → BLOCKER** | Keyless Esri tile use in a public commercial app is not covered by Esri terms; attribution missing on the stamp map. |
| Tile usage | Server policy compliance | **High → BLOCKER** | Nominatim use is periodic (every 25 m of movement) and app-wide traffic will exceed 1 req/s; no remote kill switch. |
| Privacy | Data handling | **High** | Precise location goes to Esri and OSMF; no privacy policy, no Data safety declaration, no in-app disclosure. |
| Play Store | Publishing policy | **High** | Privacy policy URL, Data safety, signing key, accurate listing (no weather claims), OSS notices. |

## Findings by severity

### BLOCKER

**B1 · Esri basemaps used without authentication in a commercial app.**
*Evidence:* `lib/models/map_kind.dart` requests `server.arcgisonline.com/.../tile/{z}/{y}/{x}` with no token. Esri Product-Specific Terms (E300, 10 Nov 2026) footnote 89: revenue-generating apps "are required to use Authentication when accessing ArcGIS Location Platform"; footnote 74 limits the Public Plan to personal use. Esri's developer FAQ (as quoted on Esri Community) requires an access token for all location services, basemaps included.
*Policy:* [Esri E300 Product-Specific Terms](https://www.esri.com/content/dam/esrisites/en-us/media/legal/product-specific-terms-of-use/e300.pdf); [Esri Community — commercial use](https://community.esri.com/t5/developers-questions/commercial-use-with-quot-essentials-quot-of-arcgis/td-p/1147360); [Esri Community — basemaps free?](https://community.esri.com/t5/arcgis-javascript-maps-sdk-questions/are-esri-basemaps-free-to-use/td-p/1198118).
*Remediation:* Create an ArcGIS Location Platform account and use an API key on every tile request (2M free basemap tiles/month, then about $0.15 per 1,000, per [Esri's pricing post](https://www.esri.com/arcgis-blog/products/developers/developers/arcgis-hosted-services-terms-of-use-pricing-differences) and [pricing page](https://location.arcgis.com/pricing/)). Set a billing cap. Restrict the key to the app's package/SHA-1. Get Esri's written confirmation (or use the Static Basemap Tiles service) for **tiles composited into saved photos/videos**, since those images persist and are redistributed by users.

**B2 · Nominatim used against its usage policy.**
*Evidence:* `location_service.dart` calls Nominatim automatically whenever the user moves >25 m and the platform geocoder is empty — not an end-user search. The policy treats "periodic requests from apps" as bulk geocoding, applies the 1 req/s cap per application (all users combined), requires the ability to switch the service off "without requiring a software update", and asks for an identifying user agent. The app has none of these safeguards.
*Policy:* [OSMF Nominatim Usage Policy](https://operations.osmfoundation.org/policies/nominatim/).
*Remediation:* Remove the Nominatim fallback before launch. Keep the on-device Android Geocoder as the only free path, and add an optional paid geocoder whose terms allow **storing** results (burning an address into a photo stores it — note Esri footnote 66 only allows stored geocodes on a paid subscription). Whatever provider is chosen, add a remote kill switch (e.g. a small JSON config on a domain you control).

**B3 · No privacy policy.**
*Evidence:* No policy link in the app (`app_settings.dart` About section) or repo. Google requires a policy URL in Play Console **and** inside the app, on a public non-PDF page, naming the developer and covering collection, sharing, retention and deletion.
*Policy:* [Play User Data policy](https://support.google.com/googleplay/android-developer/answer/10144311).
*Remediation:* Publish `docs/publishing/privacy-policy.md` (draft supplied) at a stable URL; add a "Privacy policy" row to Settings → About.

**B4 · Data safety form not prepared.**
*Evidence:* Coordinates leave the device (tile and geocoding requests), so precise location is "collected" under Google's definition (any transmission off device by the app or its libraries).
*Policy:* [Data safety form guidance](https://support.google.com/googleplay/android-developer/answer/10787469).
*Remediation:* Use `docs/publishing/data-safety.md` (prepared answers).

**B5 · No upload signing key.**
*Evidence:* No `android/key.properties`; release builds fall back to debug signing (see `docs/production-readiness.md`). Play rejects debug-signed bundles.
*Remediation:* Create an upload keystore, enrol in Play App Signing, keep the keystore out of git.

### HIGH

**H1 · Map attribution missing or wrong.** The live stamp mini-map and the saved photo/video stamp show **no** credit; Settings shows "© Esri World Imagery". Esri requires "Powered by Esri" on or near the map (at minimum the word "Esri" when space is tight) plus data attribution ([Esri static-map attribution](https://developers.arcgis.com/documentation/esri-and-data-attribution/static-maps/), [interactive maps](https://developers.arcgis.com/documentation/esri-and-data-attribution/interactive-maps/)). *Fix:* draw a small "Esri" credit inside the stamp mini-map (also in saved media), "Powered by Esri" + the data sources returned by the service's attribution endpoint on the Library map, and correct the About entry.

**H2 · Brand: weak, crowded name and a confusable package prefix.** Google prohibits titles and icons "so similar to those of existing products … that users may be misled" ([Impersonation](https://support.google.com/googleplay/android-developer/answer/9888374)). "GPS Camera" is used by at least ten Play listings, several with the same `com.gpscamera.` prefix ([1](https://play.google.com/store/apps/details?id=com.gpscamera.timestamp.geotagcamera.location.map), [2](https://play.google.com/store/apps/details?id=com.gpscamera.geotag.photos), [3](https://play.google.com/store/apps/details?id=com.gpscamera.map.location.geotagphotos)). *Fix:* choose a distinctive name; decide the application ID **before the first upload** (it can never change), ideally reversed from a domain you own.

**H3 · Trademark clearance not completed.** See the registry steps below. Do not file or launch until the chosen name is searched in classes 9 and 42 in India (and any launch markets).

**H4 · Open-source licence notices not shown.** Apache-2.0, BSD and MIT all require keeping the copyright/licence notice. The app has no licences screen. *Fix:* add Settings → About → "Open-source licences" (Flutter `showLicensePage`) and add Android library notices (Google `oss-licenses` Gradle plugin, or a generated notices file). Inventory: `docs/publishing/third-party-notices.md`.

**H5 · Unused dependency `graphify` (MIT) pulls in WebView packages.** Not imported anywhere in `lib/`. It adds attack surface and Data-safety ambiguity (WebView). *Fix:* remove from `pubspec.yaml`.

### MEDIUM

**M1 · Competitor-derived design notes.** Comments in `map_kind.dart`, `coordinates.dart`, `geo_data.dart` and `template.dart` say the feature "mirrors the reference app"; earlier builds defaulted the stamp title to "GPS Map Camera" (a competitor's name; now migrated away in `template_controller.dart:44`). Names like "Classic"/"Advanced" are generic and not copyright-protectable, but a template set copied as a whole invites trade-dress or impersonation complaints. *Fix:* remove the comments, review each template's layout for originality, and keep competitor names out of code, metadata and screenshots.

**M2 · "Weather" template with no weather source.** Temperature/wind/humidity/pressure appear only in sample previews (`GeoData.demo()`); live captures have none. *Fix:* hide the Weather template and weather fields until a licensed weather API exists, and never mention weather in the listing.

**M3 · No in-app explanation before the location prompt.** `location_service.dart:85` calls `requestPermission()` directly. Foreground location is expected for a GPS camera, so a disclosure is not strictly mandated, but coordinates go to third parties. *Fix:* a one-screen explanation before the system prompt (draft below), per the [User Data policy](https://support.google.com/googleplay/android-developer/answer/10144311) recommendation.

**M4 · Geotags leak home locations when users share files.** EXIF GPS and visible stamps travel with shared media. The app has an "Embed GPS in photo metadata" switch. *Fix:* mention it in onboarding and the privacy policy; consider a "remove location before sharing" option.

**M5 · India DPDP Act 2023.** The developer decides the purpose of sending location to Esri/OSMF, so it is likely a data fiduciary for that processing. *Fix:* have counsel confirm notice, consent and grievance-contact requirements under the [DPDP Act](https://www.meity.gov.in/data-protection-framework) and its rules.

**M6 · Version shown in About is hard-coded "1.0.0"** while the build is 0.1.0 (code 1). *Fix:* read it from the package info; set a version code above anything previously uploaded.

**M7 · New personal developer accounts must run a closed test before production** (Google's stated requirement has been 12 testers for 14 days). *Verify* the current rule in Play Console for your account type before planning dates.

### LOW

**L1 · User agent without contact.** Add a contact URL/email (OSMF and good practice for any provider).
**L2 · No monochrome icon layer** for Android 13+ themed icons ([adaptive icons](https://developer.android.com/develop/ui/views/launch/icon_design_adaptive)).
**L3 · Tile caching.** Respect `Cache-Control`; never prefetch or offer offline download of hosted tiles (prohibited by the [OSM tile policy](https://operations.osmfoundation.org/policies/tiles/) and Esri programmatic-use terms, E300 footnote 10).

## Copyright and IP audit

| Asset | Origin | Licence / status | Risk | Action |
| --- | --- | --- | --- | --- |
| App icon (flat lens pin) | Created in this project (`design/logo/`), rsvg render of hand-written SVG | Owned | Low | Compare visually with top-20 category icons; pin+camera motifs are common, so keep the lens-in-pin + colour distinctive |
| Premium logo concepts | `design/logo/premium*/` | Script previews use macOS Snell Roundhand — **not cleared for logos**; not shipped | Medium if adopted | Redraw script in an OFL font (Great Vibes / Pinyon Script) before use |
| UI fonts | System font (`.SF Pro Text` falls back to Roboto on Android); no font files bundled | Platform | Low | None |
| Icons | Material Icons (Apache-2.0), Cupertino Icons (MIT) | Notices required | Low | Licences screen (H4) |
| Shader `shaders/stash_glass.frag` | Owner's own Stash design code (confirm) | Owner | Low | Confirm ownership |
| Camera UI, gestures, layout | Original Flutter code; common category patterns | Owner | Low–Med | M1 cleanup |
| Map imagery and labels | Esri and its data providers | Licensed only via an Esri plan | **High** | B1, H1 |
| Address text | Android geocoder / OSM (ODbL) | ODbL needs attribution and share-alike for databases; single addresses in photos are low risk | Medium | B2; credit "© OpenStreetMap contributors" if OSM data is kept |
| Third-party images or media | None bundled (`assets/icons` only) | — | None | — |

**Dependency licences** (all shipped packages, scanned from `LICENSE` files): Apache-2.0 ×4, BSD ×80, MIT ×25; MPL-2.0 ×3 are Linux-only and not in the Android build. Native: CameraX, Media3, AndroidX, ExifInterface, Kotlin stdlib — Apache-2.0. No copyleft obligations for the Android app.

### Duplicate name vs trademark vs copyright

- **Duplicate name:** another app uses the same or similar title. Not illegal by itself; Google acts only when it misleads users (impersonation/metadata policy).
- **Trademark conflict:** a registered or well-known *mark* for the same or related goods/services (e.g. Nice classes 9 software, 42 SaaS) that consumers could confuse with yours. Enforced through registries and courts, and Play's IP complaint process.
- **Copyright infringement:** copying protected *expression* — code, artwork, icons, screenshots, text, map imagery. Names and short phrases are generally not protected by copyright; logos and graphics are.

## Name and brand verification

Play/web search of "GPS Camera" titles shows the space is saturated ([GPS Map Camera — Timestamp](https://play.google.com/store/apps/details?id=com.gpslocation.timestamp.geotag.gpscamera), [GPS Camera: Timestamp, Geotag](https://play.google.com/store/apps/details?id=com.gpscamera.timestamp.geotagcamera.location.map), [GPS Camera: Geotag Photos](https://play.google.com/store/apps/details?id=com.gpscamera.geotag.photos), [GPS Camera Pro: Map & Geotag](https://play.google.com/store/apps/details?id=com.gpscampro), [Timestamp Camera — GPS Camera](https://play.google.com/store/apps/details?id=timestamp.camera.gpsmapcamera.geotagphoto) and more). A third-party aggregator reports an Indian registration for "247GPS Map Camera" ([trademarking.in](https://trademarking.in/details/247gps-Map-Camera-5623367.html), unverified). No exact registration for "GPS Map Camera" or "GPS Camera Next" surfaced; this does **not** prove none exists.

**Rejected candidates (conflicts found):** GeoFrame (two existing apps, [App Store](https://apps.apple.com/app/id6760257659), [Android](https://chrome-stats.com/d/com.geoframe.app)), TrueMark Camera ([existing app](https://appgoblin.info/apps/com.truemark.camera)), Groundmark ([iOS app](https://appshunter.io/ios/app/groundmark/id6759274969)), TerraFrame ([registered US mark, class 42](https://trademarks.justia.com/864/60/terraframe-86460676.html)), Locinote ([existing app](https://mwm.ai/apps/locinote/6787135502)).

**Shortlist — no app, company or mark found in web-indexed sources (registry search still required):**

| # | Name | Play title (≤30) | Len | Notes |
| --- | --- | --- | --- | --- |
| 1 | **Wherelight** | Wherelight: GPS Photo Stamp | 27 | Coined, evocative; no hits ([search](https://www.google.com/search?q=%22Wherelight%22)) |
| 2 | **Fieldproof** | Fieldproof: GPS Photo Proof | 27 | Speaks to inspectors/field work; similar-concept apps exist (Solocator, Lens) but no same name |
| 3 | **Placelight** | Placelight: GPS Camera | 22 | No hits; check "Lumo"/"Luma" marks are not close in your market |
| 4 | **Plotmark** | Plotmark: Geotag Camera | 23 | No hits; "-mark" suffix is common (PhotoMark, SnapMark) |
| 5 | **Wayproof** | Wayproof: Photo Location | 24 | No hits; "Waylens" (dash cams) is nearby — check class 9 |

Avoid in all titles: "Official", rankings, prices, "#1", competitor names.

**Registry steps for the owner (cannot be automated — CAPTCHA/interactive):**
1. IP India public search: <https://tmrsearch.ipindia.gov.in/estatus> and <https://ipindiaonline.gov.in/tmrpublicsearch/> — search **Wordmark** "contains" and **Phonetic** for the name, classes **9** and **42**.
2. WIPO Global Brand Database: <https://branddb.wipo.int> — similar-name search, classes 9/42.
3. USPTO: <https://tmsearch.uspto.gov> (and EUIPO eSearch if selling in the EU).
4. Search Google Play and the App Store for the exact name and phonetic variants.
5. Check the `.com`/`.app` domain and social handles; register the domain to anchor the application ID.

## Map provider assessment and recommended configuration

| Provider | Licence for this use | Key / billing | Attribution | Caching / offline | Verdict |
| --- | --- | --- | --- | --- | --- |
| Esri (current, keyless) | Not covered for commercial apps (E300 fn 74, 89) | None today | Missing | Programmatic export prohibited (fn 10) | **Must change** |
| Esri via ArcGIS Location Platform + API key | Commercial apps allowed with authentication (fn 89) | 2M tiles/month free, then ~$0.15/1k; billing cap available | "Powered by Esri" + data sources, on/near map | No bulk/offline export | **Recommended** (keeps satellite imagery) |
| OSM public tiles (tile.openstreetmap.org) | Allowed but best-effort, may be blocked without notice; commercial users warned | None | "© OpenStreetMap contributors", visible | No prefetch/offline/bulk | Not suitable as production backbone ([policy](https://operations.osmfoundation.org/policies/tiles/)) |
| MapTiler / Stadia free tiers | Non-commercial only ([MapTiler terms](https://www.maptiler.com/terms/cloud/), [Stadia FAQ](https://stadiamaps.com/faqs/)) | Paid plans for commercial | Required | Plan-specific | Paid plan only |
| Self-hosted Protomaps (PMTiles, OSM data) | OSM data ODbL; PMTiles BSD-3 ([Protomaps FAQ](https://protomaps.com/faq)) | Hosting cost only | "© OpenStreetMap contributors" | You control it | Good for street maps; **no satellite** |
| Android Geocoder (platform) | Platform API | None | None required by app | On-device | Keep as primary geocoder |
| Nominatim (public) | Policy forbids this pattern | None | ODbL credit | Must cache | **Remove** |

**Recommended configuration:** Esri basemaps through ArcGIS Location Platform with a restricted API key and billing cap (street, imagery, topo, labels); the attribution fixes in H1; Android Geocoder for addresses, with an optional paid geocoder whose terms permit stored results; remote config to switch any provider off; no offline tile download. If satellite imagery is not essential, self-hosted Protomaps removes per-tile fees entirely.

## Privacy and liability

**Data inventory:** precise location (GPS) is used on device for the stamp and EXIF, and transmitted to Esri (tile coordinates) and to the geocoder. Photos, videos and audio stay on device in the user's gallery; the app index of capture locations is stored in app-private storage and deleted with the app. No background location (`ACCESS_BACKGROUND_LOCATION` is not requested — verified in the merged manifest). No accounts, analytics, ads or developer servers.

**Draft in-app disclosure (before the location prompt):**
> **Location for your stamp.** GPS Camera Next uses your location to add coordinates, an address and a small map to the photos and videos you take. To draw the map and look up the address, your approximate position is sent to our map provider (Esri) and your device's address service. We don't store or sell your location. You can turn location off at any time in Settings.
> [Continue] [Not now]

**Map accuracy disclaimer (Settings → About and listing):**
> Maps, addresses and coordinates come from GPS signals and third-party services and can be inaccurate, incomplete or out of date. Do not rely on them for navigation, surveying, legal or emergency purposes.

**Third-party services acknowledgement:**
> Map tiles: Powered by Esri; imagery and map data © their respective providers (shown on the map). Addresses: your device's geocoding service. These services are provided by third parties under their own terms and may change or become unavailable.

These disclaimers inform users; they do **not** remove obligations under Play policy, provider terms or data-protection law, and they do not limit liability where the law does not allow it.

## Release gate

| ID | Finding | Gate |
| --- | --- | --- |
| B1 | Esri keyless tiles | **BLOCKER** |
| B2 | Nominatim policy breach | **BLOCKER** |
| B3 | No privacy policy | **BLOCKER** |
| B4 | Data safety not declared | **BLOCKER** |
| B5 | No upload key | **BLOCKER** |
| H1 | Map attribution missing (live and in saved media) | HIGH |
| H2 | Crowded name, confusable package prefix | HIGH |
| H3 | Trademark registry searches outstanding | HIGH |
| H4 | No open-source licence notices | HIGH |
| H5 | Unused `graphify` + WebView | HIGH |
| M1–M7 | Competitor comments/templates, weather template, location disclosure, EXIF sharing, DPDP, hard-coded version, closed-test rule | MEDIUM |
| L1–L3 | User agent contact, monochrome icon, caching | LOW |

**Assessment: NOT READY FOR PUBLICATION.** Unresolved dependencies on the
owner: Esri account and key, trademark searches, chosen name and application
ID, privacy-policy hosting and developer contact details, upload keystore, and
Play Console account checks (closed testing). Code-side fixes (B2, H1, H4, H5,
M1–M3, M6, L1–L2) can be done in this repository.

## Sources

- Google Play: [Impersonation](https://support.google.com/googleplay/android-developer/answer/9888374), [Metadata](https://support.google.com/googleplay/android-developer/answer/9898842), [User Data](https://support.google.com/googleplay/android-developer/answer/10144311), [Data safety](https://support.google.com/googleplay/android-developer/answer/10787469), [Icon specs](https://developer.android.com/distribute/google-play/resources/icon-design-specifications), [Adaptive icons](https://developer.android.com/develop/ui/views/launch/icon_design_adaptive)
- Esri: [E300 Product-Specific Terms](https://www.esri.com/content/dam/esrisites/en-us/media/legal/product-specific-terms-of-use/e300.pdf), [Esri and data attribution](https://developers.arcgis.com/documentation/esri-and-data-attribution/), [Static maps attribution](https://developers.arcgis.com/documentation/esri-and-data-attribution/static-maps/), [Location Platform pricing](https://location.arcgis.com/pricing/), [Hosted services terms and pricing](https://www.esri.com/arcgis-blog/products/developers/developers/arcgis-hosted-services-terms-of-use-pricing-differences)
- OpenStreetMap Foundation: [Nominatim usage policy](https://operations.osmfoundation.org/policies/nominatim/), [Tile usage policy](https://operations.osmfoundation.org/policies/tiles/), [Attribution guidelines](https://osmfoundation.org/wiki/Licence/Attribution_Guidelines)
- Alternatives: [MapTiler Cloud terms](https://www.maptiler.com/terms/cloud/), [Stadia Maps FAQ](https://stadiamaps.com/faqs/), [Protomaps FAQ](https://protomaps.com/faq)
- Trademark registries: [IP India](https://ipindiaonline.gov.in/tmrpublicsearch/), [WIPO Global Brand Database](https://branddb.wipo.int), [USPTO](https://tmsearch.uspto.gov)
