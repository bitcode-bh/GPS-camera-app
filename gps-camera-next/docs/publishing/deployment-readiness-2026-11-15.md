# GPS Camera Next — worldwide deployment readiness assessment

Assessment date: **15 November 2026**. Decision: **NO-GO for production release**.

> **Subsequent engineering fixes are now implemented.** Read the
> [current remediation status](/Volumes/Bitcode/GitHub/GPS-camera-app/gps-camera-next/docs/publishing/remediation-2026-11-15.md)
> for corrected signing safeguards, privacy/backup handling, map credits, notices and patched Guava.
> The artifact and findings below remain the original audit record. Worldwide production is still blocked by the documented owner/rights/configuration/qualification gates.

The app has a working camera/library/map implementation and a successful release compilation. It is not yet a verified distributable product: the inspected bundle uses an Android debug certificate, maps are disabled in the default release, privacy materials are incomplete and partly inaccurate, and branding, asset provenance and native licence obligations remain unresolved. These are specific release gates, not a finding that the developer has committed an infringement or that Google has rejected the app.

## Scope and evidence standard

The requested territory is worldwide, meaning supported Google Play distribution territories, subject to local law and service availability. The owner confirmed an existing **personal** developer account. Its creation date, this app's production eligibility and Console verification state were not inspected. The public name is still the working name **GPS Camera Next**; other proposed names in the listing draft were not cleared.

Reviewed the current working tree, resolved Dart and Android runtime dependency graphs, merged release manifest, a newly built AAB, bundled fonts/notices/native libraries, privacy/listing drafts, prior device evidence, official Google/Esri policies, and public trademark sources. The source is on `feat/location-integrity`, based on `5d5ae25b211f6a837e77c2b158aad5b330328a24`, with existing uncommitted development work. This assessment creates documentation/evidence only. No source fixes, credential creation, Console submission, publication, commit or push were performed. The older `gps_camera_pro` app is outside scope and was not changed.

**Verified** means supported by inspected source/artifact or an observed check. **Conditional** requires an owner decision, contract or Console evidence. **Not verified** is not a pass. Policy and registry observations are dated; recheck immediately before submission. This technical assessment does not provide a worldwide legal clearance opinion.

### Audited artifact

| Item | Observed result |
| --- | --- |
| Build | `flutter build appbundle --release --no-pub` succeeded |
| Package / version | `com.gpscamera.gps_camera_next` / `0.1.0+1` |
| Size / SHA-256 | 59,385,587 bytes / `ca9f97fef1e6b71082fafadfca473c8df7750d525d1c8e82a66b7e68bd79d979` |
| Minimum / target SDK | 24 / **36** |
| Release debuggable | False, manifest default |
| Signer | **Android Debug**, not a production upload identity |
| Bundle structure | Official bundletool 1.18.3 `validate` exited successfully |
| Native packaging | Bundle config requests `PAGE_ALIGNMENT_16K`; all 12 native `.so` files have ELF LOAD alignment of at least 16 KB |
| Runtime page size | Connected Motorola phone reports **4096 bytes**; no 16 KB runtime validation |
| Optimization | R8/resource shrinking disabled in this build because the upload signing properties are absent; DEX total 17,370,612 bytes |
| Map/policy build definitions | No Esri key or hosted privacy URL supplied for this audit build |

Bundletool was downloaded from Google's official GitHub release and its SHA-256 matched `a099cfa1543f55593bc2ed16a70a7c67fe54b1747bb7301f37fdfd6d91028e29` before execution. Validation proves bundle structure, not Play acceptance or final signing correctness. [Official bundletool release](https://github.com/google/bundletool/releases/tag/1.18.3).

## Prioritized risk register

Severity here measures release impact, not CVSS: **Critical** is a hard distribution gate; **High** is substantial policy/IP/licensing or material product risk; **Medium** needs bounded remediation or explicit evidence-based acceptance; **Low** is maintenance/documentation. Unknown legal rights are identified as unresolved, not asserted violations.

| ID | Severity / status | Finding and corrective action | Closure evidence / owner |
| --- | --- | --- | --- |
| R1 | **Critical — verified** | AAB is debug-signed. Gradle silently falls back to debug signing when `android/key.properties` is missing. Make distribution builds fail without valid release configuration; use the owner's upload key and Play App Signing. | Inspect final certificate, package/version and Play upload validation; owner supplies credentials, engineering validates. |
| R2 | **Critical — incomplete** | Privacy policy remains a placeholder draft; no public policy URL was verified or supplied to this build. Finish legal identity/contact, accurate practices, retention/deletion and recipient disclosures; host and link the policy in-app and Console. | Live, accessible matching policy plus app/Console review; owner and engineering. |
| R3 | **High — verified / conditional** | Release maps are disabled without the Esri definition, while the listing promises map stamps and library maps. Account entitlement and exported-photo/video map rights have not been established. Complete provider setup and validate the map-enabled release; retain existing features. | Applicable terms/account evidence, export-rights confirmation and release map tests; owner/provider and engineering. |
| R4 | **High — verified gap** | Mini-map exports show only “Esri”; hardcoded gallery source credits are not reconciled to current style/region metadata and may clip. Supply required provider credits for interactive views and standalone exported media. | All four styles and representative regions, legible full credits in photos/videos and gallery; engineering/provider. |
| R5 | **High — unsupported declarations** | Draft Data safety asserts ephemeral handling and transit encryption too broadly; service-provider sharing exemption is conditional. Establish actual recipients, retention and contracts before filing. | Data-flow/contract review and matching Console declaration for the final build; owner/privacy reviewer. |
| R6 | **High — verified wording mismatch** | In-app text says location is not stored, although the local media index stores it. EXIF-off text implies saved files contain no coordinates despite visible stamps/maps. Default Android backup may include private JSON. Correct wording and deliberately configure/disclose backup behavior. | Source/UI/policy consistency, backup/restore and deletion checks; engineering/owner. |
| R7 | **High — unresolved IP clearance** | Related US pending trademark application found; category is crowded. Worldwide name/logo clearance is incomplete. Select a distinctive final brand and obtain territory/class/common-law and figurative searches. | Documented clearance or approved rename, then consistent app/listing/icon; owner/IP counsel. |
| R8 | **High — unresolved provenance** | Shipped Stash-referenced shader/design tokens and Trip Tracker-adapted filtering lack supplied ownership/licence evidence. Verify authorship/rights or independently replace affected expression. | Provenance/assignment/licence record linked to files; owner/engineering/IP reviewer. |
| R9 | **High — licence reconciliation incomplete** | Generic native Apache credits do not establish compliance for the entire resolved graph, including CameraX's Apache/BSD declaration and engine composite notices. Reconcile complete licences and component NOTICE obligations. | Final shipped-component bill of materials, notices/credits and required source offers if any; engineering/licensing reviewer. |
| R10 | **High — release qualification incomplete** | Production-key/R8/map-enabled configuration, store assets, mandatory Console forms and app-specific access/verification are unverified. The debug device run cannot qualify this configuration. | Final release testing, Console pre-launch/app-content checks and owner eligibility evidence; engineering/owner. |
| R11 | **Medium — matched advisory** | Guava 33.5.0-android matches GHSA-xxph-c9ww-hj94. No application Java-deserialization entry point was found. Upgrade compatibly to a patched version or document complete reachability analysis and temporary acceptance. | Resolved patched graph and regression tests, or justified risk decision; engineering. |
| R12 | **Medium — unverified coverage** | No sustained thermal/battery/performance benchmark, broad OEM/OS matrix or walking/driving filter qualification. Expand release QA before a worldwide launch. | Recorded results on the final artifact; engineering/testers. |
| R13 | **Medium — territorial review incomplete** | Worldwide privacy, transfer, age and local provider-availability obligations have not been cleared country by country. Produce a launch-country applicability matrix. | Owner/legal sign-off and implemented notices/controls where applicable. |
| R14 | **Low — maintenance** | Older audit/checklist claims and dependency counts are stale; build-tool deprecation warnings remain. Update documentation and schedule compatible toolchain maintenance. | Current docs aligned to final artifact; engineering. |

## 1. Google Play compliance and publishing gates

### Technical requirements

The merged release targets **API 36**, meeting the current new-app/update requirement effective 31 August 2026; the extension date of 1 November 2026 has passed. This is a pass for the inspected artifact, not a check of a future build. [Google Play target API policy](https://support.google.com/googleplay/android-developer/answer/11926878?hl=en).

The app contains native code. ELF alignment and bundle 16 KB packaging configuration pass static checks; actual loading, camera capture, video transformation and playback on a 16 KB environment remain untested. Current Android guidance requires 16 KB support for target-35+ apps and identifies 1 February 2027 as an update-release enforcement point. Recheck the final AAB and Console rather than treating that date as permission to ship an incompatible new app. [Android page-size guidance](https://developer.android.com/guide/practices/page-sizes).

The audit AAB has over 10 MB of DEX and no R8 optimization. Google has announced February 2027 requirements of at least 25% each for optimization, obfuscation and shrinking for apps above that DEX threshold. Upload-key configuration currently turns R8 on, but that changes the tested build. Measure the final artifact and test reflection-dependent camera controls, platform channels, Media3 and playback. Do not infer compliance merely from `isMinifyEnabled=true`. Future memory-vitals thresholds also make measured background bitmap retention important. [Play technical quality requirements](https://support.google.com/googleplay/android-developer/answer/17492799?hl=en).

The production upload must use the correct upload identity and Play App Signing arrangement. Debug signing cannot close this gate. Keep the upload key/passwords outside version control, back them up securely, and verify fingerprints without publishing private credentials. [Android signing guidance](https://developer.android.com/studio/publish/app-signing).

### Permissions and app behavior

| Permission / capability | Source/artifact assessment | Release action |
| --- | --- | --- |
| Camera | Core photo/video function; declared | Test grant, denial and revocation |
| Microphone | Video soundtrack; declared | Verify silent-video path and denial messaging |
| Fine/coarse location | Core geostamping and map functions; foreground use | Test approximate-only, denial, location switch and stale fixes |
| Storage read/write | Limited to Android API 28 and below | Test legacy album save/read and denials |
| Internet/network state | Map tiles; system geocoder may use network | Disclose actual recipients and location implications |
| Wake lock | Merged runtime dependency | Confirm lifecycle/power behavior |
| Dynamic receiver permission | Signature-level internal permission | No end-user sensitive permission declaration implied |
| Background location, broad modern photo/video access, all-files access, ads ID | Not present in inspected merged manifest | Preserve this minimal scope; reassess if functionality changes |

This app reads its own MediaStore captures rather than requesting modern broad `READ_MEDIA_IMAGES`/`READ_MEDIA_VIDEO`. That avoids a broad-access declaration problem; adding a gallery is not by itself grounds for unrestricted media access. No background-location or foreground-service declaration is presently triggered by the manifest. Foreground location is expected for this GPS-camera purpose; prominent disclosure requirements depend on whether access is unexpected, not simply on the presence of GPS permission. [Photo/video permission policy](https://support.google.com/googleplay/android-developer/answer/16935362?hl=en-en), [sensitive permissions policy](https://support.google.com/googleplay/android-developer/answer/16558241?hl=en&rd=1).

### Personal account and worldwide distribution

An existing personal account does not alone establish this app's production access. If the account was created after 13 November 2023, the app generally needs a closed test with at least **12 continuously opted-in testers for 14 days**, followed by a production-access decision. If already satisfied for this app, retain the Console confirmation; do not repeat testing merely because this assessment exists. [Personal-account testing requirements](https://support.google.com/googleplay/android-developer/answer/14151465?hl=en).

Android developer verification protections began on **30 September 2026** in Brazil, Indonesia, Singapore and Thailand for participating-store installs on certified Android 7+ devices, with expansion announced for 2027. Play automatically registers most apps, but confirm this package's identity/registration state and any outstanding account verification. No second account is automatically required. [Android developer verification](https://developer.android.com/developer-verification).

Before upload, finalize the package and verify that version code 1 is acceptable for that package in the actual Console. App names can change; package identifiers are effectively permanent after publication. [Create and set up an app](https://support.google.com/googleplay/android-developer/answer/9859152?hl=en).

Complete app content: privacy URL, accurate Data safety, ads declaration, IARC content rating, intended audience, reviewer access instructions, and any Console-specific declarations. No login is implemented, so do not invent review credentials. No ads SDK or account system was found. A draft expectation of “Everyone” is not an assigned rating; answer IARC and audience questions honestly. [Prepare app content](https://support.google.com/googleplay/android-developer/answer/9859455?hl=en-en).

## 2. App name, trademarks and branding

### Actual register search

The official USPTO search was used with fielded combined-mark queries, without limiting classes/statuses:

| Query | Observed result | Meaning |
| --- | --- | --- |
| `CM:"GPS CAMERA NEXT"` | No result returned | Limited exact US search only; no inference of worldwide availability |
| `CM:("GPS CAMERA" OR "GPS MAP CAMERA")` | One result | Related active filing requiring assessment |

**GPS CAMERA - MAP TIMESTAMP CAM**, US serial **99781619**, owner **Hong Kong iArtTech Software Technology Co., Limited**, filed **23 April 2026**, was **LIVE / PENDING**, not registered, when checked. Its Class 009 goods include downloadable photo/image/video editing and photo organization/viewing software. Status date **22 September 2026** records a non-final Office action; the application remains under examination. It is a standard-character application, not a finding about the current lens-pin icon. [Official USPTO record](https://tmsearch.uspto.gov/search/search-results/99781619), [TSDR status/documents](https://tsdr.uspto.gov/#caseNumber=99781619&caseSearchType=US_APPLICATION&caseType=DEFAULT&searchType=statusSearch).

This creates a credible **clearance question**, not proof of infringement or an enforceable registration. Descriptiveness, disclaimers, priority, related goods, total commercial impression and common-law use need assessment. Adding “Next” does not automatically resolve confusion. USPTO explicitly advises searching similar marks and non-federal/common-law sources, beyond exact matches. [USPTO comprehensive clearance guidance](https://www.uspto.gov/trademarks/search/comprehensive-clearance-search-similar-trademarks).

### Existing Play products

Live listings confirm a crowded category: [GPS Camera](https://play.google.com/store/apps/details?id=com.proapp.app.gpscamera), [GPS Camera: Add Timestamp](https://play.google.com/store/apps/details?id=com.timestampcamera.map.gpscamera.pro), [GPS Map Camera - Timestamp](https://play.google.com/store/apps/details?id=com.gpslocation.timestamp.geotag.gpscamera), [GPS Map Camera: Geotag Photos](https://play.google.com/store/apps/details?id=com.gpsmapcamera.geotagginglocationonphoto.app), and related apps from [Susamp Apps](https://play.google.com/store/apps/developer?id=Susamp+Apps). Listings show marketplace similarity and possible prior use; they do not prove registered rights. Competitors' Data safety forms are not a compliance precedent.

### Worldwide search limits

| Registry / territory | Work performed / limit |
| --- | --- |
| United States / USPTO | Exact and related wordmark screening above; full legal and figurative clearance incomplete |
| India | Official public search requires OTP/CAPTCHA; no verified Indian registration/status obtained |
| WIPO Global Brand Database / Madrid | Bot challenge prevented substantive registry search; no international clearance obtained |
| EU / TMview | Search portal discovered; no completed result set establishing clearance |
| United Kingdom | Public-search access unavailable in the research tool; no clearance obtained |
| Other countries | No complete national registry, language/phonetic or common-law search |

Official portals: [IP India](https://tmrsearch.ipindia.gov.in/tmrpublicsearch/), [WIPO](https://branddb.wipo.int/), [TMview](https://www.tmdn.org/tmview/), [UK IPO](https://trademarks.ipo.gov.uk/ipo-tmtext). No challenge was bypassed. WIPO coverage does not replace relevant national/regional searches. [WIPO search guidance](https://www.wipo.int/en/web/madrid-system/how_to/search/index).

**Required:** choose a distinctive brand, search related Class 009 software and any other applicable services, phonetic/transliteration variants, figurative lens/pin marks, relevant business names/domains and common-law uses across launch territories. Obtain counsel's risk decision before investing in final assets. Play also prohibits misleading affiliation/impersonation and unauthorized IP use, independently of registry status. [Impersonation policy](https://support.google.com/googleplay/android-developer/answer/9888374?hl=en), [intellectual property policy](https://support.google.com/googleplay/android-developer/answer/9888072?hl=en).

## 3. UI, icons, fonts and design ownership

| Shipped or proposed material | Evidence and conclusion | Required closure |
| --- | --- | --- |
| Yellow lens/map-pin app icon | Local SVG and raster source exist; common geometric motif. No proof of a copied competitor asset found, but no global figurative clearance | Authorship/provenance record and similar-mark/design review for final brand |
| Grid shutter, yellow EV/zoom rails, normal camera layouts | Functionality/common patterns are not by themselves evidence of infringement; expressive artwork/code and overall appearance can still raise issues | Preserve authoring history; avoid copying another product's distinctive expression/branding |
| `stash_glass.frag` | Shipped compiled shader; source explicitly references “Stash 0.28.0 GLASS_DROP” and optics | Identify author, source and permission/ownership; replacement if rights cannot be established |
| Design palette | Source describes tokens as from Stash 0.28.0 | Same provenance check; isolated colors are not a blanket basis to allege copyright infringement |
| Position filter | Source says guards adapted from Trip Tracker estimator; referenced local project has no supplied licence/assignment evidence | Establish ownership/licence of any adapted expression; mathematical ideas alone differ from copied code |
| Material Icons | Only bundled font family in FontManifest is MaterialIcons; corresponding SDK notices present | Preserve applicable notices in final package |
| `.SF Pro Text` family name | Android build does not bundle an Apple/SF font binary | No font redistribution infringement established merely by this string |
| Premium logo concepts | Alternative design files are not currently shipped; some PNG provenance is not documented | If selected, obtain source/font/image commercial rights and final trademark review |
| Map imagery | Third-party content, not developer-owned UI artwork | Separate Esri/data-provider licence and export attribution review |

No evidence was supplied establishing that every design asset is original/owned. Conversely, file comments alone do not prove unlawful copying. Removing attribution/reference comments would not resolve missing rights. Obtain a small provenance register with creator, date, source, licence/assignment and permitted commercial distribution. Patents, registered designs and trade dress were not cleared globally. [WIPO mobile-app IP guide](https://www.wipo.int/edocs/pubdocs/en/wipo_pub_1071.pdf).

## 4. Third-party dependencies and licensing

The audit inventories **29 main-reachable Dart/SDK packages** and **27 dev-only packages**, excluding the app root, plus **94 resolved Android runtime Maven coordinates**. Federated iOS/web packages in the Dart graph are not automatically shipped Android binaries. Maven POM-only/metadata entries are similarly distinguished from present artifacts. The older sibling's cached dependencies were not treated as this app's dependencies.

Dart main graph: 26 BSD-3-Clause classifications, one MIT (`html`), one Apache-2.0 (`material_color_utilities`) and one composite Flutter engine/`sky_engine` notice set. The Flutter SDK includes Material Icons; no separate paid custom font package or proprietary stock photo bundle was identified. This graph is broader than the two top-level camera/video feature dependencies.

Native runtime includes CameraX 1.6.0, Media3 1.9.2, AndroidX components, Kotlin/coroutines, Guava 33.5.0-android and Okio 1.17.6. No Firebase, ad SDK or Google Maps SDK was identified in the resolved runtime graph. Most Maven declarations are Apache-2.0; CameraX camera-core explicitly includes libyuv under BSD-3-Clause. Seven coordinates lacked cached POM licence declarations. Follow-up retrieved official Apache-2.0 metadata for emoji2 1.2.0 and javax.inject 1 and confirmed the exact JetBrains annotations 23.0.0 Apache licence. Four Flutter engine artifacts need mapping to the composite engine/embedding notices rather than blanket classification as Apache. An unresolved cached POM field does not mean the package has no licence. [JetBrains versioned licence](https://github.com/JetBrains/java-annotations/blob/23.0.0/LICENSE.txt), [Emoji2 published POM](https://dl.google.com/dl/android/maven2/androidx/emoji2/emoji2/1.2.0/emoji2-1.2.0.pom), [javax.inject published POM](https://repo.maven.apache.org/maven2/javax/inject/javax.inject/1/javax.inject-1.pom).

The AAB contains a **1,336,467-byte** expanded Flutter notice set with full Apache text and composite engine notices, plus native META-INF notices. Therefore “the app ships no Apache licence text” would be false. However, the hand-added Android licence page groups several libraries under a short generic Apache notice and does not establish that all copyright/NOTICE/BSD conditions are satisfied. Reconcile shipped native artifacts and engine-vendored components against actual upstream licence/NOTICE files; retain required notices and licence text in accessible distribution materials. Apache's licence does not grant permission to use upstream trademarks. No copyleft package was identified in the declared Dart/POM screen, but that screen does not close every embedded native component obligation. [Apache licence](https://www.apache.org/licenses/LICENSE-2.0).

Commercial use of these permissive components is generally possible subject to their actual terms. Map content remains a separate contract/content issue. A complete final notices bundle should be generated from the **final optimized artifact**, retaining legally required notices even where binary shrinking removes unused code.

### Vulnerability review

An OSV batch query covered **116 public package/version pairs** from the relevant graphs. It returned one matched advisory: **GHSA-xxph-c9ww-hj94 / CVE-2026-102554** for Guava 33.5.0-android. The Guava publisher rates it **Moderate** and lists **33.7.2-android or later** as patched. The issue concerns attacker-controlled Java object deserialization causing excessive allocation in certain collection types. [Publisher advisory](https://github.com/google/guava/security/advisories/GHSA-xxph-c9ww-hj94).

A targeted search of app Dart/Kotlin sources found no `ObjectInputStream`/`readObject` entry point. No reachable exploit through a photo, map tile or normal camera capture was demonstrated. Treat this as a **Medium component finding**, upgrade through a compatible owning dependency/constraint and test, or document complete reachability and temporary acceptance. Do not equate a package match with a confirmed remote exploit. No other match was returned; engine-vendored C/C++ components and undisclosed vulnerabilities remain outside that assurance. [OSV API method](https://google.github.io/osv.dev/post-v1-querybatch/).

## 5. Maps, GPS and location-content compliance

### What is implemented

The app uses a custom slippy map with Esri HTTP tiles, not Google Maps. Normal/Terrain/Hybrid label layers use authenticated Static Basemap Tiles endpoints; satellite uses the imagery endpoint. Address lookup uses Android's **device Geocoder**, whose backend varies by device and is not guaranteed to be available. Do not apply Google Maps SDK licence rules or Esri Geocoding storage rules to an SDK/service the app does not use. [Android Geocoder](https://developer.android.com/reference/android/location/Geocoder).

Release drawing is gated by `ESRI_API_KEY`; the audit build has no key, so maps are unavailable. Development fallback public endpoints do not establish permission for commercial worldwide distribution. Esri's currently published E300 terms are dated **10 November 2026**; confirm the owner's actual account agreement, authentication, charges, content rights and any applicable territorial limitations before enabling release maps. No paid account or billing configuration was inspected. [Esri product-specific terms](https://www.esri.com/content/dam/esrisites/en-us/media/legal/product-specific-terms-of-use/e300.pdf), [Static Basemap Tiles service](https://developers.arcgis.com/rest/static-basemap-tiles/).

### Export and attribution gate

The photo/video mini-map burns a small “Esri” label into the saved media, without the full data-provider credits. Gallery credits use hardcoded provider names, two lines and a small font; they have not been validated against current authenticated style/region metadata. Current Static Basemap Tiles documentation names providers including TomTom, whereas the code still includes HERE for non-imagery styles. Full authoritative attribution should follow the actual services, region and style, not a guessed universal string.

Esri branding and data-source attribution are distinct requirements. A small “Esri” label can address limited-space branding guidance; it does not automatically satisfy data attribution. In-app expanded credits can help interactive views; standalone images/videos cannot rely on an inaccessible app-only credits page. Obtain provider confirmation on permanent map embedding and onward distribution in photos/videos, and include the applicable visible credits or a documented permitted alternative. No blanket prohibition on all screenshots/exports was established. [Static-map attribution](https://developers.arcgis.com/documentation/esri-and-data-attribution/static-maps/), [interactive-map attribution](https://developers.arcgis.com/documentation/esri-and-data-attribution/interactive-maps/).

No bulk/offline tile downloader was found. Normal Flutter memory image caching is not evidence of a licensed permanent offline map product. Do not advertise offline maps, guaranteed address accuracy or navigation capability.

### Key protection and service privacy

Existing comments recommending Android package/SHA restrictions for Esri are not supported by the reviewed ALP key documentation. Use provider-supported least privileges, expiry, rotation, monitoring and spending controls; validate actual native request/referrer behavior. A client-embedded API key is extractable. Do not embed client secrets or assume referrers prevent determined misuse. The current URLs contain query tokens, so keep URLs/tokens out of logs and external diagnostics. [ALP API-key credentials](https://developers.arcgis.com/documentation/security-and-authentication/api-key-authentication/api-key-credentials/location-platform/), [Esri security practices](https://developers.arcgis.com/documentation/mapping-apis-and-services/security/security-best-practices/).

Tile coordinates at high zoom, IP address and request metadata can reveal precise areas viewed. Esri's broad privacy materials discuss technical/location data, but this app does not use every Esri SDK feature. Confirm service-specific retention, processor roles and transfer terms rather than assuming either zero logs or all optional SDK telemetry. [Esri privacy statement](https://www.esri.com/en-us/privacy/privacy-statements/privacy-statement), [privacy supplement](https://www.esri.com/en-us/privacy/privacy-statements/privacy-supplement).

GPS filtering/mock flags improve presentation but do not certify authenticity, spoof resistance or surveying/legal evidentiary accuracy. Preserve the existing uncertainty warnings; do not advertise “tamper-proof” or guaranteed proof of location.

## 6. Privacy, security and provisional Data safety

### Observed data flow

| Data | Device storage / transfer observed in source | Assessment |
| --- | --- | --- |
| Photos, video, soundtrack | Saved to app-owned gallery album; optional unstamped original; no automatic developer upload endpoint found | Local processing; sharing sends the chosen file to the user-selected destination |
| Precise coordinates/place/integrity | Private `media_index.json`, optional EXIF GPS and visible stamp/map | Location is stored locally; deleting EXIF alone is not anonymization |
| User stamp fields/templates | Private JSON/settings and rendered captures | May contain names/phone/project data even without an account |
| Viewed map areas | Tile requests to Esri with request/IP metadata | Off-device location implications; final key-enabled release must be declared accurately |
| Address lookup | Coordinates passed to device Geocoder | Backend handling/transport and any applicable system-service disclosure exclusion need verification |
| Analytics/accounts/ads | No implementation/SDK found in reviewed source/runtime graph | No account-deletion-flow trigger identified; privacy/data-rights contact still required |
| OS backup/transfer | No explicit backup exclusions; Android default may include app-private JSON | User OS backup is distinct from an app upload, but absolute “never leaves phone” claims are unsafe |

Source review found direct map HTTPS URLs and no app TLS certificate-validation bypass. This is not a penetration test or packet capture. Device Geocoder transport and third-party processing were not verified end to end. App-private JSON is not app-level encrypted; Android sandbox/device encryption must not be described as bespoke app encryption. Sharing uses content URIs and temporary read permission, rather than publicly exposing private file paths.

Android Auto Backup normally includes private files unless deliberately excluded; define separate cloud/device-transfer rules appropriate to supported OS versions and test restore/deletion effects. Uninstall/clear-storage removes app-private data, while exported gallery media can remain. [Android backup behavior](https://developer.android.com/identity/data/autobackup).

### Required corrections

1. Replace “we do not store your location” with an accurate distinction between local index/media storage and developer-operated servers. State what is retained, where, why and how to delete it.
2. Explain that “Embed GPS” changes photo metadata only. Visible coordinates, addresses and maps still disclose location unless separately omitted. Verify both stamped and optional-original paths.
3. Resolve backup behavior, provider logging/retention and contact details; align in-app summary, policy and listing. Provide meaningful location/microphone choices, including denial/revocation behavior.
4. Host an active public, non-PDF, non-geofenced privacy policy identifying the app/developer and contact, purposes, recipients, retention/deletion and safeguards. Link it in Console and provide practical in-app access. The current optional URL is only selectable text and is absent in this build. [Play user-data policy](https://support.google.com/googleplay/android-developer/answer/10144311?hl=en).

### Provisional declaration — do not submit the old draft unchanged

Google's definitions concern off-device collection even when the developer has no server. Ephemeral handling is not established merely because the app keeps no server copy; the service-provider sharing exception requires the relevant processing relationship. Under Play's definition an area below 3 km² is precise, which high-zoom tile requests can reveal. [Data safety definitions](https://support.google.com/googleplay/android-developer/answer/10787469?hl=en).

| Console topic | Evidence-based preparation for final map-enabled release |
| --- | --- |
| Location collected | Prepare **Yes / precise location**, functionality, optional if the complete app genuinely operates without it; reconcile system Geocoder rules and all actual requests |
| Location shared | **Unresolved**: verify contractual service-provider exclusion; otherwise disclose applicable sharing |
| Ephemeral | **Not established**: obtain actual recipient retention evidence; do not use “Yes” based solely on no developer server |
| Encrypted in transit | Direct app endpoints are HTTPS; validate all personal-data transmissions and Geocoder handling before affirming universally |
| Photos/video/audio | No automatic off-device upload found; review user-directed sharing exception and final providers/features |
| Names/other stamp fields | Local source path only found; do not claim the app never handles these fields |
| Crash logs/IDs/other types | No telemetry/identifier SDK found; confirm final runtime, provider behavior and definitions |
| Retention/deletion/account questions | Describe local/OS/provider distinctions and actual contact/process; no app account system, so do not invent an account deletion mechanism |

The keyless audit AAB and intended map-enabled production AAB have different network behavior. Submit declarations for the product actually distributed, covering relevant versions/tracks and regions. Keep a dated data-flow and recipient/contract record. No Data safety form was submitted in this assessment.

### Worldwide privacy applicability

| Territory | Required applicability review; current evidence limit |
| --- | --- |
| EU/EEA | Assess GDPR territorial scope, roles, lawful basis, transparent notice, recipient/processor terms, rights, retention/security and non-EEA transfers. Consent, representatives and DPOs are not universally required in every app scenario. [GDPR official text](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32016R0679) |
| UK | Separately assess UK GDPR and applicable transfer/children rules; an EU review alone is not UK clearance. [UK legislation](https://www.legislation.gov.uk/eur/2016/679/body/2026-09-30) |
| India | DPDP Rules were notified in November 2025 with phased commencement; major operational rules have an 18-month phase. Confirm the Act/rules applicable on the actual launch date rather than saying the entire framework is already operative. [MeitY official notification](https://www.meity.gov.in/static/uploads/2025/11/53450e6e5dc0bfa85ebd78686cadad39.pdf) |
| US | Assess applicable state thresholds and precise-location/sensitive-data rules. No ads/sales does not itself settle all privacy duties. COPPA depends on child-directed use/actual knowledge, not just an IARC rating. [California privacy FAQ](https://cppa.ca.gov/faq.html), [FTC COPPA guidance](https://www.ftc.gov/business-guidance/resources/complying-coppa-frequently-asked-questions) |
| Brazil | Assess LGPD roles/basis/notices and applicable transfer safeguards; ANPD has specific international-transfer rules. [ANPD Resolution 19/2024](https://www.gov.br/anpd/pt-br/acesso-a-informacao/institucional/atos-normativos/regulamentacoes_anpd/resolucao-cd-anpd-no-19-de-23-de-agosto-de-2024) |
| Singapore | Assess PDPA consent/notification, accountability and transfer limitation for applicable overseas processing. [PDPC key-concepts guidance](https://www.pdpc.gov.sg/-/media/files/pdpc/pdf-files/advisory-guidelines/ag-on-key-concepts/advisory-guidelines-on-key-concepts-in-the-pdpa-17-may-2022.pdf) |
| Remaining worldwide territories | Canada, Australia, Japan, Korea, Indonesia, Thailand and other launch jurisdictions require an applicability/service-availability matrix. No comprehensive local legal opinion or complete national-law review was obtained. |

Choose and document the intended audience. If targeting children, reassess Families, provider suitability and local child-data requirements before enabling that audience. A camera utility is not automatically child-directed, and a personal developer account is not a general privacy-law exemption.

## 7. Stability, performance, listing and release qualification

### What has evidence

Fresh release compilation and bundle structural validation succeeded. Fresh static analysis is clean and **all 145 automated Flutter tests passed**. Prior development checks exercised the camera/library, location-switch outage during recording, real/mocked/stale location handling, portrait/landscape exports, fixed overlay geometry, gallery map-style selection and reduced-motion/lifecycle animation behavior.

The latest documented debug animation smoke clip contains **352 decoded frames over 11.7315 seconds**, approximately 30 fps; maximum observed frame gap was about 35.78 ms. That is one short encoded-video sample, not proof of unaffected live preview FPS, recording quality, battery efficiency or all-device performance. The connected phone is a Motorola Edge 70 running API 37 with 4 KB memory pages. Prior tests were debug builds using development map behavior, not this keyless release or a final owner-signed build.

### Required release QA

- Install the final upload-key/R8/map-enabled artifact through an appropriate test track; run camera, focus, EV, zoom presets/continuous zoom, white balance, flash, timer, each aspect ratio, orientations, original retention and capture failure paths.
- Test both permission states and transitions: camera/audio/location denial, permanent denial, approximate-only, revocation, location off/on, stale fixes and app background/foreground. Retest silent video, audio synchronization and interrupted export.
- Cover API 24/28 legacy storage, API 29 scoped storage, API 33+ permissions, API 36 target changes, API 37 and a real/emulated 16 KB environment. Include other OEMs and lower-memory devices.
- Exercise all four authenticated map styles, pan/pinch zoom, style changes without viewport jumps, token expiry/invalid key, network loss/rate limiting, attribution and saved-photo/video map rendering. Use non-sensitive test locations.
- Test large libraries, deletion/index reconciliation, failed writes/full storage, long videos, low memory, restore/backup, repeated captures, startup/resume and process death. Measure preview/recording/export separately, plus sustained thermal/battery behavior.
- Qualify GPS walking/driving lag, stillness and course behavior with physical movement; compass/tilt transitions through north and map multi-touch remain manual coverage. Automated USB checks cannot supply these results.
- Review Play pre-launch report, accessibility, crashes/ANRs and final manifest/dependencies. No production crash/vitals history exists in this evidence set.

### Listing assets and claims

The repository has a 512×512 icon candidate; final brand selection remains open. Feature graphic and release screenshots are still marked to do. Prepare the 1024×500 feature graphic and at least two compliant phone screenshots. Raw Motorola captures at 1220×2712 exceed the permitted 2:1 screenshot dimension ratio and need compliant composition; do not stretch the UI or expose real private coordinates. [Play listing assets](https://support.google.com/googleplay/android-developer/answer/9866151?hl=en).

Use a title within 30 characters, short description within 80 and full description within 4,000. The draft promises maps and says files stay on the phone; verify maps in release and qualify third-party requests/OS backup. Avoid unsupported weather, offline maps, guaranteed GPS, “proof”, security or affiliation claims. Ensure current icon, app label, licence screen, privacy policy and listing agree on the final name and developer identity. [Metadata policy](https://support.google.com/googleplay/android-developer/answer/9898842?hl=en).

## 8. Release decision and required corrections

**NO-GO now.** The recommendation is driven by identifiable unmet gates rather than a prediction of automatic rejection. Passing tests and target SDK checks cannot close signing, disclosure, contract or ownership gaps.

Recommended order:

1. **Owner identity/rights decisions:** final distinctive name/package, trademark review, provenance evidence, Esri commercial/export terms and privacy contact/audience. Do not choose any alternative draft name without screening it.
2. **Engineering corrections:** fail-closed production signing, accurate local-storage/EXIF/backup wording, deliberate backup rules, complete accessible policy, current map attribution, final notices and supported Guava remediation. Preserve the existing camera/library/map features.
3. **Owner configuration:** upload key and Play App Signing, least-privilege Esri credentials/usage controls, hosted policy, reviewed Data safety, mandatory app content and listing assets. Do not commit credentials or accept provider contracts on the owner's behalf.
4. **Final artifact qualification:** build with the actual intended settings, record hash/certificate/version, inspect manifest/notice/dependency/SCA changes, exercise R8/authenticated maps and the release QA matrix, then review Console eligibility/pre-launch findings.

**Go criteria:** R1–R10 are closed with evidence; R11–R13 are remediated or explicitly accepted based on documented applicability/reachability and release scope; final mandatory Console checks show no blocking issues; the owner approves the actual listing and final release. Worldwide rollout requires the territory review, not merely selecting every country checkbox. Consider staged rollout after qualification, with a monitored rollback plan.

Only Google can confirm review/availability in Console. This report records **no submission, acceptance or approval**.

## Evidence and source locators

Audit outputs:

- [Artifact identity, permissions, fonts and ELF checks](/Volumes/Bitcode/GitHub/GPS-camera-app/gps-camera-next/docs/publishing/evidence-2026-11-15/release-artifact.json)
- [Merged release manifest](/Volumes/Bitcode/GitHub/GPS-camera-app/gps-camera-next/docs/publishing/evidence-2026-11-15/release-merged-manifest.xml)
- [Signing certificate summary](/Volumes/Bitcode/GitHub/GPS-camera-app/gps-camera-next/docs/publishing/evidence-2026-11-15/release-signing-certificate.txt)
- [Dart dependency inventory](/Volumes/Bitcode/GitHub/GPS-camera-app/gps-camera-next/docs/publishing/evidence-2026-11-15/dart-dependencies.csv)
- [Android runtime inventory](/Volumes/Bitcode/GitHub/GPS-camera-app/gps-camera-next/docs/publishing/evidence-2026-11-15/android-runtime-dependencies.csv)
- [OSV result and triage](/Volumes/Bitcode/GitHub/GPS-camera-app/gps-camera-next/docs/publishing/evidence-2026-11-15/osv-results.json)
- [Bundle configuration](/Volumes/Bitcode/GitHub/GPS-camera-app/gps-camera-next/docs/publishing/evidence-2026-11-15/bundle-config.json)
- [Check summary and evidence limits](/Volumes/Bitcode/GitHub/GPS-camera-app/gps-camera-next/docs/publishing/evidence-2026-11-15/README.md)
- [USPTO observed search](/Volumes/Bitcode/GitHub/GPS-camera-app/gps-camera-next/docs/publishing/evidence-2026-11-15/uspto-related-search.txt)

![Official USPTO related-name search, showing a live pending application](/Volumes/Bitcode/GitHub/GPS-camera-app/gps-camera-next/docs/publishing/evidence-2026-11-15/uspto-related-search.jpg)

Primary source files for findings:

- [Signing/build configuration](/Volumes/Bitcode/GitHub/GPS-camera-app/gps-camera-next/android/app/build.gradle.kts)
- [Map service/authentication/credit strings](/Volumes/Bitcode/GitHub/GPS-camera-app/gps-camera-next/lib/models/map_kind.dart)
- [Tile map and mini-map credits](/Volumes/Bitcode/GitHub/GPS-camera-app/gps-camera-next/lib/widgets/tile_map.dart)
- [Gallery map](/Volumes/Bitcode/GitHub/GPS-camera-app/gps-camera-next/lib/screens/library/media_map.dart)
- [In-app privacy/native licence text](/Volumes/Bitcode/GitHub/GPS-camera-app/gps-camera-next/lib/screens/settings/legal.dart)
- [Local location index](/Volumes/Bitcode/GitHub/GPS-camera-app/gps-camera-next/lib/services/media_library.dart)
- [Position-filter provenance](/Volumes/Bitcode/GitHub/GPS-camera-app/gps-camera-next/lib/services/position_filter.dart)
- [Shader provenance](/Volumes/Bitcode/GitHub/GPS-camera-app/gps-camera-next/shaders/stash_glass.frag)
- [Palette provenance](/Volumes/Bitcode/GitHub/GPS-camera-app/gps-camera-next/lib/core/design/palette.dart)
- [Earlier device verification](/Volumes/Bitcode/GitHub/GPS-camera-app/gps-camera-next/docs/device-verification-2026-11-15.md)
- [Later UI/animation evidence](/Volumes/Bitcode/GitHub/GPS-camera-app/gps-camera-next/docs/ui-refinements-2026-11-15.md)

This report supersedes conflicting historical observations in the 14 November compliance audit: there is now a release map gate, device Geocoder instead of Nominatim, some Esri attribution and packaged Apache/engine notices. Those improvements are acknowledged; they do not prove final licence/contract/privacy compliance. Older claims that every asset is “Owned” or all location processing is ephemeral remain unsupported. All external references above were researched for this assessment date.
