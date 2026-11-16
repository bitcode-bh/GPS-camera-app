# Production-readiness fixes — 15 November 2026

> Subsequent owner-approved branding: **PinShutter**, with proposed Play title **PinShutter: GPS Camera**. See the [branding record](/Volumes/Bitcode/GitHub/GPS-camera-app/gps-camera-next/docs/publishing/branding-2026-11-15.md). Statements below about a pending name selection describe the earlier remediation checkpoint; legal clearance remains pending.

**Engineering fixes implemented; worldwide production remains NO-GO pending owner/service/rights gates.** Work branch: `fix/production-readiness-20261115`, at the original main commit with prior uncommitted development work preserved. No commit, push, Play upload or new device installation was made. The older `gps_camera_pro` app was not changed.

Owner clarification: developer display name **bitcode.bh**; final name should have an Indian/Sanskrit resemblance. The owner is unsure of Stash/Trip Tracker rights and explicitly asked to keep that gate open. ArcGIS setup/export permission is not yet available. Privacy contact/hosting will be created after name selection. These facts must not be replaced with invented approvals or credentials.

No app name, package ID, album name or public listing title was changed. **Explicit owner confirmation is required before applying a proposed name.**

## Implemented

| Assessment item | Changes and evidence | Remaining limit |
| --- | --- | --- |
| R1 — release signing | Removed debug fallback. Release pre-build validates complete signing fields, an existing readable keystore/key, certificate validity and a non-Android-Debug identity. Missing credentials were tested and correctly block the build. | Owner supplies the actual upload identity and Play App Signing configuration; positive production signing remains untested. |
| R2/R5 — policy and Data safety | Corrected in-app privacy, consent and worksheets; added bitcode.bh display identity, monitored-contact build field and native HTTPS browser action. Consent is scrollable. Build requires non-placeholder policy URL/contact. | The owner must provide/publish/review the actual policy and contact. URL syntax checks do not verify hosted content or legal compliance. |
| R4 — map credits | Fetches copyrightText from every actual style/layer's service metadata. Hybrid retains both lists. Gallery and popup have accessible full-credit dialogs. Standalone stamp exports reserve a fixed full-credit footer; imagery is withheld if credits are missing or cannot fit legibly, rather than clipping or substituting guessed names. | Test all authenticated styles/regions with the owner's real entitlement and confirm export rights. Service-wide metadata attribution is implemented; contractual adequacy still requires provider review. |
| R4 — async/UI behavior | Verified cached credits render synchronously in a fresh capture frame. Style changes/retries discard previous snapshots; superseded requests cannot refill the active cache. The retry banner is below the credits button, so offline errors cannot obstruct attribution. | This does not constitute new live-camera FPS, battery or release-device qualification. |
| R6 — privacy/security | Text now distinguishes local index storage, developer servers, EXIF-only controls and visible stamps. Private files/preferences/database/external-app files and device-protected domains are excluded from cloud backup and device transfer. Android allowBackup is false; cleartext traffic is blocked. | Rules/manifest are compiled and packaged; actual backup/restore across OEMs was not exercised. Gallery/previous backups/shared files remain separately controlled. |
| R9 — native notices | Added full Apache text, libyuv BSD notice, retained AAR/JAR/class-JAR notices, Flutter BSD/composite engine notices and all 94 selected runtime coordinates. The in-app registry loads the bundled notices. Release checks reject runtime coordinates missing from the inventory. A repeatable generator and two tests cover selected-version parsing and nested notices. | Regenerate when dependencies change. This closes the generic native-notice implementation gap, not unrelated artwork/contract/patent/ownership rights. Final release packaging still needs inspection. |
| R11 — Guava | Added a compatible runtime constraint; resolved release graph now selects **33.7.2-android**. Debug compilation succeeds. Post-fix OSV query of 120 public package/version pairs returned **zero advisory matches**, including no match for the prior Guava advisory. | No exploit was demonstrated before or after. OSV absence is not a security guarantee; engine-vendored component version matching and a full penetration test remain outside scope. |
| R14 — documentation | Corrected privacy policy/Data safety/listing/notices; historical audit/readiness documents link to current status. Added owner configuration examples and a gitignored local release JSON path. No feature/library/map tab was removed. | Flutter-template legacy AGP/Kotlin compatibility settings remain; migrate with a compatible Flutter/toolchain update rather than an unrelated risky upgrade. |

Map tokens now travel in authorization headers instead of tile URL query strings. Optional ESRI_REFERER is an owner-configured provider setting; comments no longer promise unsupported Android package/SHA key restrictions. Keys embedded in a native client remain extractable. No client secret or API key was created or committed.

## Verification actually run

| Check | Result |
| --- | --- |
| Dart format | Completed across lib/test; final pass made no changes |
| Flutter analyze | **No issues found** |
| Flutter test | **155 passed** |
| Python notice-generator tests | **2 passed** |
| Debug APK build | Successful, 11.7 seconds |
| Production release attempt | **Stopped as intended**, before packaging, for missing owner upload credentials |
| Dependency resolution | Release graph selects Guava 33.7.2-android; 94 native coordinates inventoried |
| OSV post-fix scan | 120 package/version queries; zero matches; no pagination |
| Final debug artifact inspection | Target API 36; allowBackup=false; usesCleartextTraffic=false; both backup XML resources packaged; bundled native-notice/inventory bytes equal source |
| Public development map metadata | All four actual layer copyrightText fields returned successfully with TLS verification; the long terrain list passes a narrow-width/real-Roboto regression test |
| Whitespace/secret-file tracking | git diff --check clean; config/release.local.json and android/key.properties ignored |

Final debug APK SHA-256: `29572bea074240387d12dc1ff1c4b6ba1cdb58cc9d06ffd30d2974823e689e8b`, package `com.gpscamera.gps_camera_next.debug`, 171,334,408 bytes. The debug certificate is expected for this development artifact. No new production AAB was qualified. Old debug-signed release bundles can remain in build output and must not be uploaded.

The connected phone was asleep/outside the debug app when inspected. No taps, installation or new device smoke result is claimed. Earlier device evidence remains historical. A final owner-signed/R8/authenticated-map build, 16 KB runtime execution, walking/driving/compass, multi-touch and sustained performance/thermal/battery checks remain open.

Evidence: [machine-readable checks](/Volumes/Bitcode/GitHub/GPS-camera-app/gps-camera-next/docs/publishing/remediation-evidence-2026-11-15/checks.json), [release safeguard result](/Volumes/Bitcode/GitHub/GPS-camera-app/gps-camera-next/docs/publishing/remediation-evidence-2026-11-15/release-guard.txt), [post-fix OSV request](/Volumes/Bitcode/GitHub/GPS-camera-app/gps-camera-next/docs/publishing/remediation-evidence-2026-11-15/osv-query.json), [response](/Volumes/Bitcode/GitHub/GPS-camera-app/gps-camera-next/docs/publishing/remediation-evidence-2026-11-15/osv-response.json).

## Owner and external gates — still open

1. Choose the final name, complete Indian/worldwide similar-mark/phonetic/common-law and logo checks, then update public branding/package decisions. [Indian/Sanskrit-inspired shortlist and search limits](/Volumes/Bitcode/GitHub/GPS-camera-app/gps-camera-next/docs/publishing/name-shortlist-2026-11-15.md).
2. Supply the actual legal/privacy identity as applicable, monitored contact, effective date and hosted HTTPS policy; review recipients/retention/transfers/audience. The supplied display name alone does not establish every required legal identity detail.
3. Configure the owner's upload key locally and verify this app's Play production access, version code and developer/package verification. No private signing material should be sent through chat.
4. Obtain ArcGIS entitlement and written/applicable contractual assurance for permanent exported photo/video maps; configure least privileges/referrers/expiry/usage controls and test the native requests. No account, contract acceptance or payment was performed.
5. Establish rights to the Stash-referenced shader/design and Trip Tracker adaptations or approve a replacement scope. References remain; comments were not removed to disguise provenance.
6. Complete actual Data safety/IARC/audience/ads/app-content forms, final branded store assets and release-device/pre-launch QA. The app has no account system; do not invent a rating, account-deletion flow or Console approval.
7. Complete the territory applicability review for worldwide distribution and monitor the final rollout only after the gates close.

Use [release configuration instructions](/Volumes/Bitcode/GitHub/GPS-camera-app/gps-camera-next/config/README.md). Build guards check concrete configuration and component identity; they do **not** grant map rights, resolve ownership, clear trademarks or certify a privacy policy. The [original assessment](/Volumes/Bitcode/GitHub/GPS-camera-app/gps-camera-next/docs/publishing/deployment-readiness-2026-11-15.md) retains its original artifact evidence; this document is the current remediation status.
