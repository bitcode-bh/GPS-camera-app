# Evidence — 15 November 2026

Supports the [deployment readiness report](/Volumes/Bitcode/GitHub/GPS-camera-app/gps-camera-next/docs/publishing/deployment-readiness-2026-11-15.md). This directory contains audit evidence, not a distribution package or approval record.

## Fresh checks

| Check | Result |
| --- | --- |
| `flutter analyze` | Exit 0, no issues, 4.4 seconds |
| `flutter test` | Exit 0, 145 tests passed |
| `flutter build appbundle --release --no-pub` | Exit 0, 53.9 seconds; default release configuration |
| JDK keytool certificate inspection | Android Debug certificate; production signing absent |
| Official bundletool 1.18.3 `validate` | Exit 0 |
| Official bundletool `dump config` | Native uncompressed packaging requests 16 KB alignment |
| ELF program-header inspection | All 12 shipped native libraries have LOAD alignment >=16 KB |
| `adb -s ZA223MDVR8 shell getconf PAGE_SIZE` | 4096; the connected phone does not establish 16 KB runtime support |
| OSV public package/version query | 116 entries, one matched Guava advisory; no pagination indicated |
| App-source deserialization/TLS-bypass search | No `ObjectInputStream`, `readObject(` or `badCertificateCallback` match in app Dart/Kotlin source |

Flutter 3.44.2 / Dart 3.12.2; JDK 17.0.19+10. These checks did not change product source. No additional device captures or movement tests were performed for this audit. Device results discussed in the report are explicitly prior debug checks documented elsewhere.

The inspected AAB SHA-256 is `ca9f97fef1e6b71082fafadfca473c8df7750d525d1c8e82a66b7e68bd79d979`. The artifact remains in the local build directory; future builds can overwrite it. Its identity, manifest/certificate/configuration and relevant measurements are preserved here. The bundle was built without `ESRI_API_KEY` or `PRIVACY_POLICY_URL`, without the owner's upload key, and without R8. Do not upload this artifact.

## Inventory method and limitations

- Dart: `flutter pub deps --json`, transitive walk from main dependencies, locked version and package licence file inspection. 29 main-reachable packages, 27 dev-only, excluding app root. The SDK root licence is used where appropriate; sky_engine is kept as composite notices. This is a graph inventory, not a claim every federated platform package ships on Android.
- Android: Gradle `:app:dependencies --configuration releaseRuntimeClasspath`, resolving selected versions and excluding constraint-only nodes. 94 unique coordinates. POM licences (including inherited parent declarations) and AAR/JAR notice entries were inspected from the matching cache entries. POM-only entries are identified by `artifact_present`; cache absence alone does not prove absence from the final artifact. Unrelated cache artifacts were not enumerated as dependencies.
- Native ELF: parsed each AAB `base/lib/*/*.so` program header for LOAD segment alignment. Bundle configuration is separate evidence. No APK zipalign or 16 KB runtime execution was performed.
- Notices: inspected Flutter `NOTICES.Z`, FontManifest and native META-INF notice entries. Full per-component notice reconciliation, engine-vendored component version matching and legal interpretation remain open.
- OSV: `osv-query.json` contains only public ecosystem/name/version queries. `osv-response.json` preserves the service response; `osv-results.json` adds app-specific triage. Neither source code nor keys/private locations were sent. No exploit test was run. No result is not proof of no vulnerabilities.
- `source-sha256.csv` fingerprints 116 relevant source/test/config/icon files in the current working tree, including uncommitted work. It does not include secrets/signing files or the old app. These fingerprints bind the audit to actual files more precisely than HEAD alone.

## Native licence follow-up

The Android CSV records what was available in the cached POM, not every manual resolution:

| Cached-metadata gap | Follow-up |
| --- | --- |
| `androidx.emoji2:emoji2:1.2.0` | Official Google Maven POM retrieved; Apache-2.0, preserved as `emoji2-1.2.0.pom` |
| `javax.inject:javax.inject:1` | Published Maven POM retrieved; Apache-2.0, preserved as `javax.inject-1.pom` |
| `org.jetbrains:annotations:23.0.0` | Exact upstream tag licence verified: [Apache-2.0](https://github.com/JetBrains/java-annotations/blob/23.0.0/LICENSE.txt) |
| Four `io.flutter` release artifacts | Engine composite notices exist in SDK/package; exact embedding/native-component obligations must be mapped, not assigned a single guessed licence |

The camera-core 1.6.0 POM explicitly states that the library includes libyuv and declares Apache-2.0 plus BSD-3-Clause. A single Apache-only screen is not enough evidence that all notices are satisfied. This finding does not assume a licence fee or prohibit commercial use.

## Trademark evidence

`trademark-screening.json` records the query/result distinction and relevant pending US application without copying unnecessary public addresses. `uspto-related-search.txt` and its screenshot preserve the official related query showing one LIVE/PENDING result. Exact query `CM:"GPS CAMERA NEXT"` returned no result; broad unfielded OR-like results were discarded as exact-match evidence. Full worldwide, figurative and common-law clearance remains open. Registry challenges were not bypassed.

## Reproduction outline

Use the locked source/toolchain and the same build definitions, then:

```sh
flutter analyze
flutter test
flutter build appbundle --release --no-pub
flutter pub deps --json
```

From the Android project, resolve `:app:dependencies --configuration releaseRuntimeClasspath` using the matching Gradle cache/toolchain. Use the official verified bundletool with `validate --bundle=...` and `dump config --bundle=...`. Inspect the merged release manifest, signer and each native ELF header. Compare source/artifact hashes before treating old results as current.

The production build must use owner-managed signing and actual approved service/policy configuration, then repeat relevant checks. No Play Console account access, pre-launch report, submission decision, provider contract, global trademark clearance or worldwide legal opinion is represented by these files.
