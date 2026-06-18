# GPS Camera Pro — AI Project Context

> **How to use:** Paste this entire file (or relevant sections) into any AI chat as system context, a project brief, or the first message before asking for help. It describes what the app is, how it is structured, and the conventions to follow when changing it.

---

## 1. Project summary

**GPS Camera Pro** is a Flutter mobile app (Android-first; iOS supported) that captures photos and videos with a live, customizable **geostamp** burned into the image. The stamp can show address, coordinates, a satellite map, date/time, compass, and environmental metrics.

The UI is a premium **glassmorphism** design: aurora brand gradient (teal → cyan → indigo) over deep navy ink, frosted glass surfaces, springy press feedback, and an animated aurora backdrop.

This is a **clean rebuild** of a reference GPS Map Camera app — focused on performance, maintainability, and a modern design system. Camera, GPS, and maps use real device plugins; simulators/emulators without a camera show a painted fallback scene with demo geodata.

**Package name:** `gps_camera_pro`  
**Dart SDK:** `^3.12.2`  
**Entry point:** `lib/main.dart` → `CameraScreen`

---

## 2. Tech stack

| Layer | Choice |
|-------|--------|
| Framework | Flutter (Material, portrait-only, edge-to-edge) |
| Language | Dart 3 |
| State | 2 singleton `ChangeNotifier`s + `ListenableBuilder` (no Provider/Riverpod/Bloc) |
| Persistence | `shared_preferences` |
| Camera | `camera` plugin |
| Location | `geolocator` + `geocoding` (+ Nominatim fallback) |
| Maps | `flutter_map` + Esri tile URLs (no API key) |
| Gallery save | Android `MediaStore` via platform channel; `gal` for video |
| Share | `share_plus` |
| Compass | `flutter_compass` |
| Sensors | `sensors_plus` (level overlay) |

---

## 3. Architecture

```
lib/
├── main.dart                          App entry, immersive chrome, controller init
├── core/
│   ├── design/                        palette · tokens · text_styles
│   ├── theme.dart                     AppTheme.dark()
│   ├── glass.dart                     GlassSurface · FrostedChip · GlassIconButton
│   └── widgets/                       pressable · aurora_background · ticking_builder
│                                      transitions · controls · glass_scaffold
├── models/
│   ├── geo_data.dart                  Snapshot of everything a stamp can render
│   ├── coordinates.dart               Decimal/DMS/UTM/MGRS/Plus Code formatting
│   ├── plus_code.dart                 Open Location Code encoder
│   ├── template.dart                  StampTemplate · StampField · TemplateConfig
│   ├── map_kind.dart                  Map tile URLs (Esri)
│   ├── capture_options.dart           CaptureRatio, timer, etc.
│   └── camera_resolution.dart         Hardware resolution tiers
├── state/
│   ├── settings_controller.dart       App-wide display/capture preferences (persisted)
│   └── template_controller.dart       Selected stamp template + field toggles (persisted)
├── services/
│   ├── location_service.dart          GPS stream + throttled reverse geocoding
│   ├── capture_service.dart           Rasterize, save to gallery, local capture cache
│   └── camera_capability_service.dart Android Camera2 capability detection
├── widgets/
│   ├── geo_stamp.dart                 The geostamp widget (preview + burned capture)
│   └── mini_map.dart                  Live or painted map thumbnail
└── screens/
    ├── camera/
    │   ├── camera_screen.dart         Main screen: viewfinder, capture, in-app gallery
    │   └── widgets/                   camera_chrome · camera_layer · camera_tool_strip · level_overlay
    ├── templates/
    │   ├── templates_screen.dart      Template picker
    │   └── custom_template_editor.dart
    └── settings/
        └── app_settings.dart          Settings strip + popups (not a separate route)
```

**Note:** There is no separate `gallery_screen.dart` or `capture_store` — the in-app swipeable gallery viewer and local capture storage live inside `camera_screen.dart` and `CaptureService`.

---

## 4. State management

Two persisted singleton controllers:

### `SettingsController` (`lib/state/settings_controller.dart`)
- Map kind, coordinate format, address format, units, temperature, 24h clock
- Capture options: ratio, resolution index, timer, mirror, grid, shutter sound, save original
- Map zoom level
- Pattern: `SettingsController.instance.update(() { ... })` then auto-persist + `notifyListeners()`

### `TemplateController` (`lib/state/template_controller.dart`)
- Active `TemplateConfig` (template preset, enabled fields, size, position, accent, custom text)
- Pattern: `selectTemplate()`, `toggleField()`, `update((c) => ...)`, `bumpPhotoNumber()`

**UI listens with `ListenableBuilder(listenable: SettingsController.instance, ...)`** — never wrap the whole camera tree in a ticking `setState`.

---

## 5. Core data flow

### Location → stamp
1. `LocationService.watch()` streams `GeoData` from GPS (or `GeoData.demo()` on denial/simulator).
2. Reverse geocoding runs only when moved >25 m (platform geocoder, then Nominatim fallback).
3. `CameraScreen` merges live compass heading into `_stampGeo` via `GeoData.copyWith(heading: ...)`.
4. `GeoStamp` renders from `geo` + `TemplateConfig` + `SettingsController`.

### Capture pipeline
1. Camera preview lives in a `RepaintBoundary` keyed by `_freezeKey`.
2. `CaptureService.rasterize()` → PNG via Flutter → JPEG via Android `pngToJpeg` channel.
3. Save to device gallery (`saveImageToGallery`) → returns MediaStore URI/path.
4. Cache locally in `Documents/captures/` with companion `.ref` file for gallery deletion.
5. Optionally save unstamped original when `saveOriginal` is enabled.

### Platform channel
Channel: `com.gpscamera.gps_camera_pro/gallery`  
Implemented in `android/app/src/main/kotlin/.../MainActivity.kt`

Methods: `detectCapabilities`, `pngToJpeg`, `saveImage`, `deleteImage`

---

## 6. Design system (must follow)

### Palette (`lib/core/design/palette.dart`)
- Always **dark UI** — never follow system light mode for camera chrome.
- Brand: teal `#2DE0C8`, cyan `#38BDF8`, indigo `#818CF8` on ink `#05070D`.
- Active/selected controls use **neutral frosted glass** (`selectionFill`, `selectionStroke`) — not brand-colored pills.

### Glass surfaces (`lib/core/glass.dart`)
- **`GlassSurface`**: real `BackdropFilter` blur — use sparingly (~4 major panels: bottom bar, geostamp, sheets).
- **`FrostedChip`**: cheap translucent fill, no blur — use for small chips/buttons.
- **`GlassIconButton`**, **`GlassScaffold`**: standard chrome wrappers.

### Motion & widgets
- **`Pressable`**: springy scale feedback on taps.
- **`TickingBuilder`**: isolated clock ticks — only the date/time line rebuilds each second.
- **`AuroraBackground`**: animated blobs for non-camera screens.
- Tokens in `lib/core/design/tokens.dart` (radii, blurs, spacing, durations).

### Typography
- Tabular figures for numeric readouts (`lib/core/design/text_styles.dart`).

---

## 7. Performance rules (critical)

These constraints exist because a previous build was slow. **Do not regress them:**

1. **No whole-tree ticks.** Never `setState` the camera screen every second for the clock. Use `TickingBuilder` inside `GeoStamp`.
2. **Blur sparingly.** Do not add `BackdropFilter` to lists of chips or gallery thumbnails.
3. **No map storms.** Template/editor previews pass `realMap: false` to `GeoStamp`/`MiniMap` (painted placeholder). Only the live viewfinder uses a real tile map.
4. **Coarse map keys.** Live map should not reload tiles on every GPS jitter — key by rounded coordinates.
5. **Throttled geocoding.** Do not reverse-geocode on every position update.

---

## 8. Geostamp system

### Templates (`StampTemplate`)
`advance`, `classic`, `dateTime`, `scanLocation`, `reporting`, `navigationCompass`

### Toggleable fields (`StampField`) — 22 total
map, addresses, flag, coordinates, plus code, date/time, timezone, numbering, logo, note, person, contact, temperature, compass, magnetic field, wind, humidity, pressure, altitude, accuracy, speed

### `GeoStamp` modes
| Prop | Purpose |
|------|---------|
| `preview: true` | Smaller stamp for template gallery thumbnails |
| `live: false` | Static date/time (thumbnails) |
| `realMap: false` | Painted map instead of live tiles |

The **same `GeoStamp` widget** renders live preview, template thumbnails, and the burned-in capture — keep it data-driven from `config` + `settings`.

---

## 9. Settings & formats

| Setting | Enum / type | Location |
|---------|-------------|----------|
| Map type | `MapKind` (normal/satellite/hybrid/terrain) | `map_kind.dart` |
| Coordinates | `CoordFormat` (decimal/DMS/UTM/MGRS/plus code) | `coordinates.dart` |
| Address | `AddressFormat` (long/short) | `geo_data.dart` |
| Units | `UnitSystem` metric/imperial | `geo_data.dart` |
| Temperature | `TempUnit` celsius/fahrenheit | `geo_data.dart` |

Map tiles are Esri World Imagery / Street / Topo — respect Esri terms for production or swap URLs in `map_kind.dart`.

---

## 10. Coding conventions

- **Minimal diffs.** Match existing style; don't refactor unrelated code.
- **No extra state libraries.** Use existing singleton controllers + `ListenableBuilder`.
- **Singleton services.** `LocationService` is per-screen; `CaptureService`, `CameraCapabilityService` are `instance` singletons.
- **Comments.** Only for non-obvious business logic (geocoding fallbacks, performance rationale).
- **Lints.** `flutter_lints` via `analysis_options.yaml`.
- **Error handling.** Services fail gracefully with fallbacks (demo geo, empty gallery, cached resolutions) — don't crash the camera UI.
- **Portrait only.** Enforced in `main.dart`.

---

## 11. Android specifics

- **Permissions** (AndroidManifest): camera, fine/coarse location, internet, record audio, read media images, write external storage (≤API 28).
- **Gallery integration:** custom MediaStore save/delete — not a third-party photo library for JPEG saves.
- **Camera capabilities:** detected once via Camera2 API; resolution tiers deduplicated in `CameraCapabilityService`.
- **Physical device recommended** for real camera + GPS testing.

---

## 12. Common tasks — where to edit

| Task | Primary files |
|------|---------------|
| Add a stamp field | `template.dart` (enum + defaults), `geo_stamp.dart` (render), `custom_template_editor.dart` (toggle UI) |
| Change map tiles | `map_kind.dart` |
| New setting | `settings_controller.dart`, `app_settings.dart`, possibly `geo_data.dart` / `geo_stamp.dart` |
| Capture quality/format | `capture_service.dart`, `MainActivity.kt`, `camera_screen.dart` |
| Camera UI chrome | `camera_chrome.dart`, `camera_tool_strip.dart`, `camera_layer.dart` |
| Template presets | `template.dart` → `TemplateConfig.defaultsFor()` |
| Gallery behavior | `camera_screen.dart` (viewer), `capture_service.dart` (storage) |
| Design tokens/colors | `palette.dart`, `tokens.dart`, `glass.dart` |

---

## 13. Build & run

```bash
flutter pub get
flutter run          # connected device or emulator
flutter analyze      # static analysis
```

Release APK builds to `build/app/outputs/flutter-apk/`.

---

## 14. Out of scope / known gaps

- README mentions separate gallery/settings screens — current code uses embedded gallery in `camera_screen.dart` and settings popups in `app_settings.dart`.
- Environmental metrics (wind, humidity, pressure) have model fields but may show placeholders unless wired to a weather API.
- iOS gallery uses `gal` for video; photo save path is Android MediaStore-focused — verify iOS parity before shipping iOS gallery features.
- No automated test suite beyond default `flutter_test` scaffold.

---

## 15. Prompt template for other models

Copy and fill in when starting a new chat:

```
You are helping me work on GPS Camera Pro, a Flutter GPS geostamp camera app.

Before making changes, follow the architecture, performance rules, and design
system in PROJECT_CONTEXT.md. Key constraints:
- Use ListenableBuilder + existing singleton controllers (no new state libs)
- Don't add BackdropFilter blur to small widgets
- GeoStamp is shared for preview and capture — keep it data-driven
- Minimize diff scope; match existing code style

My task: [describe what you want done]
```
