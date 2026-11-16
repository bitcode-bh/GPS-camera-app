# Location integrity for camera geotagging

Implemented on `feat/location-integrity`, 15 November 2026. Not committed or
submitted to Google Play. Physical validation remains required.

Subsequent automated checks on the connected Motorola are recorded in
[device-verification-2026-11-15.md](device-verification-2026-11-15.md). Those
checks verify real/mock/expired/uncertain photos and two exported videos;
moving field tests and sustained performance measurements remain open.

## Existing paths reviewed

- `LocationChannel.kt`: foreground `LocationManager`, fused high accuracy on
  supported Android devices, GPS/network fallback, 5-second requests, recent seed.
- `location_service.dart`: validation, asynchronous device geocoding and status.
- `position_filter.dart`: existing two-state Kalman position filter, altitude
  filter, standstill weighting, accuracy/outlier gates and course-trust ramp.
- `PlatformChannel.kt` and `camera_screen.dart`: foreground compass and
  accelerometer subscriptions and orientation/heading low-pass filters.
- `geo_stamp.dart` / `mini_map.dart` / `tile_map.dart`: the same `GeoData` drives
  the coordinate text and north-up Esri map, including the marker's heading.
- `camera_screen.dart` / `capture_service.dart` / `MainActivity.kt`: shutter
  snapshot, camera JPEG, raster composition, EXIF, MediaStore and original copy.
- `VideoStamp.kt`: Media3 picture overlays with timestamp/location text fallback.

Reviewed the OG Trip Tracker's `PositionEstimator.kt` and
`SensorHealthMonitor.kt`. Retained the already adapted Kalman filter and adopted
the principle that sensor evidence needs recent, continuous samples. No trip
detection, tracking engine or background tracking was copied. No package added.

## Policy and behavior

The five states are Trusted, Low Accuracy, Suspected Mock, Suspected Spoofing
and Unavailable. Trusted means *passed the available heuristic checks*, not
authenticated or certified GNSS. There is no verified/authentic badge.

- Native `Location.isMock` (legacy `isFromMockProvider` before API 31) is
  preserved alongside monotonic measurement time and fix age at receipt.
  [Android Location reference](https://developer.android.com/reference/android/location/Location).
- Invalid, expired, future, non-monotonic and implausibly fast updates do not
  advance the filtered position or its measurement timestamp. Duplicate fixes
  do not count as suspicious. Raw fixes remain available separately in status;
  each filtered snapshot retains its own source coordinates and raw accuracy.
- A single position jump is unverified, not proof of spoofing. Repeated precise
  impossible jumps, or a jump corroborated by conflicting speed and a continuous
  quiet accelerometer/gyroscope window, produce suspected spoofing. Quiet IMU
  alone cannot distinguish a still phone from a phone in a moving vehicle.
  Missing/stale IMU data is ignored. The existing foreground accelerometer
  channel carries optional low-rate gyroscope evidence; both stop on cancel.
- Three clean updates are required to clear mock/spoof suspicion. Invalid data
  cannot downgrade these warnings. Mock-to-real transitions reset the Kalman
  filter so mocked coordinates do not contaminate real estimates. An address
  lookup completing after a rejected fix cannot erase that fix's warning.
- Display settings offer **Android mock locations: Label / Omit GPS**. Label
  is the default. Both policies retain a mandatory `Mock Location` stamp;
  Omit GPS removes coordinates, map and GPS metadata. The preferred accuracy
  threshold is also configurable.
- Poor reception is shown as `Location unverified`, with uncertainty. A recent
  acceptable indoor fallback is explicitly labeled `Last acceptable fix`.
  Retained fixes at least 15 seconds old show their age and are unverified.
  At 60 seconds coordinates are omitted. Turning location off or losing access
  does not keep an earlier fix on screen. No predicted position is emitted as
  a new measurement.
- Warnings are independent of template fields. If geolocation would otherwise
  be saved without a visual stamp, questionable integrity forces the warning
  stamp on. The no-location state remains captureable with `GPS unavailable`.
- A photo selects one immutable snapshot before `takePicture`; coordinates,
  mini-map, EXIF and library index all use it, including when newer fixes arrive
  while decoding or rasterising. EXIF UserComment includes integrity, accuracy,
  measurement time and the fallback note, including on an optional original.
- Videos use immutable samples once per second and on status changes. Every
  map/text frame refers to the same sample. Superseded or missing picture frames
  use that interval's text, including its warning; earlier pictures never cover
  a newer warning. Pending writes finish before export. Export failure retains
  the existing explicitly announced, separately named original-video fallback.
  The library's one video map point is labeled **Recording start location**;
  changing positions/integrity belong to the burned-in timeline, not a single
  claimed point for the whole clip.
- Existing tile failure handling, Esri attribution, north-up orientation and
  zoom are retained. Release maps still require the owner's restricted Esri key.

## Verification and remaining limits

Local execution on 15 November 2026: `dart format lib test` completed;
`flutter analyze --no-pub` reported no issues; `flutter test --no-pub` passed
all **132 tests**; `flutter build apk --debug --no-pub` produced the debug APK.
These checks do not validate decoded media on a physical device.

Automated tests exercise still/walking/driving streams, indoor uncertainty,
urban drift, jumps, conflicting clocks, mock flags and recovery, continuous vs
missing IMU evidence, raw/filtered separation, delayed geocoding, immutable
capture snapshots, policy persistence and mandatory warnings in every template.
These are simulations, not field tests or evidence of spoofing-detection rates.

On-device work remains: walk/drive and stationary before/after comparisons,
course-trust lag, real mock apps with both policies, weak/urban GNSS reception,
switch/permission changes, photos during location updates, decoded video
frames through integrity changes, original/EXIF inspection, map tile outages,
pinch zoom, rotation through north, shutter latency and sustained battery/thermal
measurement. ADB listed no attached device during the initial implementation;
the subsequent device run above completed a subset of this matrix.

Thresholds need field calibration. Slow, coherent or sophisticated GNSS spoofing
can evade these checks. Sensors and Android mock flags do not provide location
authentication. Video picture sampling now runs at up to 1 Hz plus status
changes; its storage, export cost and frame pacing need measurement on the phone.
