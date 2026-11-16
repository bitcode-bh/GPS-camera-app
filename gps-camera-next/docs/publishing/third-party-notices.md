# Third-party notices and inventory

Updated 15 November 2026. Main-reachable Dart/SDK graph: **29 packages**; **27 dev-only packages** are separately identified in the audit inventory. Federated iOS/web packages are not automatically shipped Android binaries.

| Package | Locked version | Licence classification |
| --- | --- | --- |
| async | 2.13.1 | BSD-3-Clause |
| camera | 0.12.0+1 | BSD-3-Clause |
| camera_android_camerax | 0.7.2+1 | BSD-3-Clause |
| camera_avfoundation | 0.10.1 | BSD-3-Clause |
| camera_platform_interface | 2.13.0 | BSD-3-Clause |
| camera_web | 0.3.5+4 | BSD-3-Clause |
| characters | 1.4.1 | BSD-3-Clause |
| collection | 1.19.1 | BSD-3-Clause |
| cross_file | 0.3.5+2 | BSD-3-Clause |
| csslib | 1.0.2 | BSD-3-Clause |
| flutter | 0.0.0 | BSD-3-Clause |
| flutter_plugin_android_lifecycle | 2.0.35 | BSD-3-Clause |
| flutter_web_plugins | 0.0.0 | BSD-3-Clause |
| html | 0.15.7 | MIT |
| material_color_utilities | 0.13.0 | Apache-2.0 |
| meta | 1.18.0 | BSD-3-Clause |
| path | 1.9.1 | BSD-3-Clause |
| plugin_platform_interface | 2.1.8 | BSD-3-Clause |
| sky_engine | 0.0.0 | Composite Flutter engine notices |
| source_span | 1.10.2 | BSD-3-Clause |
| stream_transform | 2.1.1 | BSD-3-Clause |
| term_glyph | 1.2.2 | BSD-3-Clause |
| vector_math | 2.2.0 | BSD-3-Clause |
| video_player | 2.14.1 | BSD-3-Clause |
| video_player_android | 2.12.2 | BSD-3-Clause |
| video_player_avfoundation | 2.12.1 | BSD-3-Clause |
| video_player_platform_interface | 6.9.0 | BSD-3-Clause |
| video_player_web | 2.4.0 | BSD-3-Clause |
| web | 1.1.1 | BSD-3-Clause |

## Android runtime

The current resolved release graph has **94 coordinates**. Guava is constrained to **33.7.2-android**, replacing the vulnerable 33.5.0-android version. CameraX camera-core 1.6.0 includes **libyuv (BSD-3-Clause)** in addition to Apache-2.0. Flutter embedding/native artifacts are covered by Flutter BSD and composite engine notices, not a blanket Apache classification.

The app licence screen registers full licence and retained AAR/JAR NOTICE texts from:

- [Packaged native notices](/Volumes/Bitcode/GitHub/GPS-camera-app/gps-camera-next/assets/legal/android-notices.json)
- [Selected runtime component inventory](/Volumes/Bitcode/GitHub/GPS-camera-app/gps-camera-next/assets/legal/android-components.json)
- [Apache-2.0 text](/Volumes/Bitcode/GitHub/GPS-camera-app/gps-camera-next/assets/legal/Apache-2.0.txt)
- [libyuv BSD text](/Volumes/Bitcode/GitHub/GPS-camera-app/gps-camera-next/assets/legal/libyuv-BSD-3-Clause.txt)

Flutter continues to supply its Dart/engine licence registry. The native generator retains notice files including notices nested in classes.jar, deduplicates identical texts and fails on an unreviewed licence category. A release gate rejects runtime coordinates absent from the generated inventory. Regenerate when dependencies or Flutter change; component identity matching is not a legal clearance of unrelated artwork, patents, contracts or source provenance.

Manual cached-POM gaps were verified against the published [Emoji2 POM](https://dl.google.com/dl/android/maven2/androidx/emoji2/emoji2/1.2.0/emoji2-1.2.0.pom), [javax.inject POM](https://repo.maven.apache.org/maven2/javax/inject/javax.inject/1/javax.inject-1.pom) and [JetBrains exact-version licence](https://github.com/JetBrains/java-annotations/blob/23.0.0/LICENSE.txt). libyuv licence source: [official source repository](https://chromium.googlesource.com/libyuv/libyuv/+/refs/heads/main/LICENSE).

Generate a releaseRuntimeClasspath dependency report with Gradle, then:

```sh
python3 tools/generate_android_notices.py --graph /path/to/resolved-release-graph.txt --gradle-cache /path/to/gradle-cache --flutter-sdk /path/to/flutter-sdk
python3 -m unittest discover -s tools
```

## Services and ownership still requiring owner action

Esri tiles/content are governed by the owner’s actual ArcGIS agreement, privileges and export rights. Runtime source credits are fetched from every actual layer’s copyrightText metadata; standalone stamp exports include a full-credit footer. No guessed provider string is substituted when metadata fails. Private media, location/index and sensitive user details are not published by the notice generator.

Stash-referenced shader/design and Trip Tracker adaptations remain in place with their reference comments. The owner is unsure of rights and asked to keep this gate open. Do not relabel them as owned or remove references as a substitute for permission. Final logo/brand and worldwide clearance are pending.
