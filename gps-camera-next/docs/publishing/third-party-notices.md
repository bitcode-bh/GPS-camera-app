# Third-party notices

Shipped Dart/Flutter packages (28, resolved versions) and native Android libraries. Shown in-app under Settings → About → Open-source licences.

| Package | Version | Licence |
| --- | --- | --- |
| async | 2.13.1 | BSD |
| camera | 0.12.0+1 | BSD |
| camera_android_camerax | 0.7.2+1 | BSD |
| camera_avfoundation | 0.10.1 | BSD |
| camera_platform_interface | 2.13.0 | BSD |
| camera_web | 0.3.5+4 | BSD |
| characters | 1.4.1 | BSD |
| collection | 1.19.1 | BSD |
| cross_file | 0.3.5+2 | BSD |
| csslib | 1.0.2 | BSD |
| flutter | 0.0.0 | BSD |
| flutter_plugin_android_lifecycle | 2.0.35 | BSD |
| flutter_web_plugins | 0.0.0 | Flutter SDK (BSD) |
| html | 0.15.7 | MIT |
| material_color_utilities | 0.13.0 | Apache-2.0 |
| meta | 1.18.0 | BSD |
| path | 1.9.1 | BSD |
| plugin_platform_interface | 2.1.8 | BSD |
| sky_engine | 0.0.0 | Apache-2.0 |
| source_span | 1.10.2 | BSD |
| stream_transform | 2.1.1 | BSD |
| term_glyph | 1.2.2 | BSD |
| vector_math | 2.2.0 | BSD |
| video_player | 2.14.1 | BSD |
| video_player_android | 2.12.2 | BSD |
| video_player_avfoundation | 2.12.1 | BSD |
| video_player_web | 2.4.0 | BSD |
| web | 1.1.1 | BSD |

Direct dependencies: `camera` (+ `camera_android_camerax`, `camera_platform_interface`) and `video_player`. Everything else the app needs — location, geocoding, sensors, folders, version, gallery, settings storage, date formatting and the tile map — is the app's own code (`PlatformChannel.kt`, `LocationChannel.kt`, `MediaLibrary.kt`, `lib/state/prefs.dart`, `lib/core/date_format.dart`, `lib/widgets/tile_map.dart`).

## Native Android libraries

| Library | Licence |
| --- | --- |
| androidx.camera (CameraX) 1.6.0 | Apache-2.0 |
| androidx.media3 transformer/effect/exoplayer 1.9.x | Apache-2.0 |
| androidx.exifinterface, other AndroidX | Apache-2.0 |
| Kotlin standard library | Apache-2.0 |

## Data and services

| Source | Terms | Attribution |
| --- | --- | --- |
| Esri basemaps (street, imagery, outdoor, labels) | ArcGIS Location Platform terms (API key required for published apps) | "Powered by Esri" + data sources, on or near every map, including stamp maps in saved media |
| Address lookup | Android platform geocoder | — |
