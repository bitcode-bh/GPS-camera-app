# Existing GPS Camera audit

The working Flutter source in the original `gps_camera_pro` project supplied
the baseline. Its source and signing material were left in place. The previous
Android device audit in that project describes measurements for the baseline.

| Area | Baseline behavior |
| --- | --- |
| App and state | Flutter Material UI, persisted SettingsController and TemplateController preferences, Android CameraX-backed Auto and Camera2 Pro, edge-to-edge portrait layout. |
| Camera | Photo and Video share the Flutter controller. Pro uses a native preview texture and still capture. Tap focus, long-press lock, zoom and exposure, timer, flash, aspect ratio, grid and level, front/back camera, idle release and lifecycle resume. |
| Pro | Capability discovery, ISO, shutter, white balance, manual focus, metering and histogram on supported hardware. Several assist effects and capture format labels had incomplete underlying behavior. |
| GPS | High-accuracy foreground Geolocator stream, compass, platform reverse geocoding and Nominatim fallback, Esri/OSM map tiles, location warning and retry. The baseline stored a display timestamp and could retain a stale fix. |
| Stamps | Nine presets, project title, note and contact information, map side and type, coordinate and unit formats, location and time fields, size, placement, palette, opacity, live time and tap-to-enlarge map. |
| Still export | Android JPEG capture plus Flutter raster or native Pro compositing. Optional original, configurable GPS EXIF, MediaStore album, private recent-photo cache, gallery reference for deletion. |
| Video | Captures audio and video through the Flutter camera plugin, finalizes on backgrounding and exports to the device gallery. The baseline video is unstamped. |
| Navigation | Camera → quick tools or all tools. Gear → Stamp, Display & Units, or About. Stamp → Templates → Custom Template. Gallery → swipeable photo viewer with zoom, share and delete, plus system gallery. |
| Dependencies | Flutter camera, geolocator, geocoding, flutter_map, latlong2, intl, gal, path_provider, shared_preferences, share_plus, flutter_compass and sensors_plus. Native Android uses Camera2, MediaStore and EXIF APIs. |
| Platform limits | The original includes an iOS host but relies on Android channels for its photo compositor, MediaStore, hardware detection and Pro mode. |

Baseline source areas reviewed include the app entry point, camera screen and
controls, native Android camera and export handlers, GPS service, stamp model
and rendering, settings, template editor, gallery flow and prior QA notes.
