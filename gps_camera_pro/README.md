# GPS Camera Pro

A premium, **glassmorphism** rebuild of a GPS Map Camera app, built in Flutter.
Capture photos with a live, customisable geostamp — address, coordinates, a live
satellite map, date/time, weather and environmental metrics — burned into the
image, with an enterprise-grade modern UI.

> Built from scratch as a clean, performant replacement. Camera, GPS and the map
> are wired to real device plugins; on a simulator/emulator without a camera the
> viewfinder falls back to a painted scene so the UI always looks real.

![Camera](docs/screenshots/01_camera_live_preview.png)

## Highlights

- **Premium glassmorphism design system** — an "aurora" brand gradient
  (teal → cyan → indigo) over deep navy ink, frosted surfaces with a specular
  sheen + hairline borders, tabular-figure numerics, one emphasised motion curve,
  springy press feedback and an animated aurora backdrop.
- **Live viewfinder** — pinch-to-zoom, tap-to-focus reticle, flash cycle,
  rule-of-thirds grid, zoom selector, Photo/Video mode strip, a hero shutter and
  an isolated ticking clock.
- **Dynamic geostamp** — rebuilds instantly from the chosen template + settings;
  the same widget renders the live preview, the template thumbnails and the
  burned-in capture.
- **6 templates + custom editor** — Advanced, Classic, Date & Time, Scan
  Location, Reporting, Navigation; 22 toggleable fields, size/position/map-side/
  accent and custom text.
- **Settings** — map type (Normal / Satellite / Hybrid / Terrain), coordinate
  format (Decimal / DMS / UTM / MGRS / Plus Code), address format, units,
  temperature and time format. All persisted across launches.
- **Gallery** — grid of geostamped captures, full-screen pinch-zoom viewer,
  share and delete.

## Performance by design

The previous build was slow; this one avoids the two biggest culprits:

- **No whole-tree ticks.** The clock rebuilds only itself (`TickingBuilder`)
  instead of `setState`-ing the camera + map every second.
- **Blur used sparingly.** Real `BackdropFilter` blur is reserved for ~4 major
  surfaces; the dozens of small chips use a cheap translucent `FrostedChip`.
- **No map storms.** Template/editor previews render a painted static map, so the
  gallery never spins up a dozen live tile engines at once; the live map is keyed
  to coarse coordinates so GPS jitter doesn't reload tiles.

## Architecture

```
lib/
├── main.dart                     Entry, immersive chrome, controller init
├── core/
│   ├── design/                   palette · tokens · text styles
│   ├── theme.dart
│   ├── glass.dart                GlassSurface · FrostedChip · GlassIconButton
│   └── widgets/                  pressable · aurora_background · ticking_builder
│                                 transitions · controls · glass_scaffold
├── models/                       geo_data · coordinates · plus_code · template
│                                 map_kind · capture
├── state/                        settings · template · capture_store (persisted)
├── services/                     location_service · capture_service
├── widgets/                      geo_stamp · mini_map
└── screens/
    ├── camera/                   camera_screen + chrome/layer widgets
    ├── templates/                templates_screen · custom_template_editor
    ├── settings/                 settings_screen
    └── gallery/                  gallery_screen · photo_view_screen
```

State is held in three tiny `ChangeNotifier` singletons consumed with
`ListenableBuilder` for granular rebuilds — no extra state-management dependency.

## Run

```bash
flutter pub get
flutter run            # on a connected Android/iOS device or emulator
```

Permissions are already declared (camera, location, internet). A **physical
device** is recommended for live camera + GPS; on an emulator you'll see the
painted fallback scene and demo geodata.

## Attribution

Map tiles © Esri (World Imagery / Street / Topo). Respect Esri's terms for
production use, or swap the tile URLs in `lib/models/map_kind.dart`.
