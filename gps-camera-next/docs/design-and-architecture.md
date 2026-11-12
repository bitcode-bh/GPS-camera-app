# Camera design and architecture

Apple’s Camera documentation describes a dominant shutter, mode switching near
the viewfinder, tap focus, touch-and-hold AE/AF lock, vertical exposure
adjustment, and contextual composition controls. This design uses those
interaction patterns with Flutter Material icons. The live Apple guide includes
newer hardware-specific controls, so it serves as a reference for the shared
camera interactions. The supplied screenshots informed the glass surfaces.
[Camera basics](https://support.apple.com/guide/iphone/camera-basics-iph263472f78/ios)
and [Camera tools](https://support.apple.com/guide/iphone/use-camera-tools-iph3dc593597/ios).

| Component | GPS Camera Next behavior |
| --- | --- |
| Header | Black camera chrome with flash, Live, Night and JPEG resolution. Live and Night are marked unavailable because the current capture backend does not implement them. The nine-dot button opens the three-column smoke-glass menu. |
| Viewfinder | Uses the original ratio-aware camera layer and focus reticle. Pinch zooms. Drag vertically for exposure in Auto. Double-tap switches cameras in Auto and resets the selected control in Pro. |
| Adjustment rail | Continuous vertical zoom stays on the right edge. Exposure opens on the left from the menu or a vertical preview gesture and hides after four seconds. Values use the active camera limits. |
| Mode dock | Swipe or tap Video, Photo and Pro inside a neutral pill with a yellow selected label. Gallery and flip flank the modes. GPS Stamp and the menu flank the centered white shutter. Photo and Video share the Auto backend. |
| Stamp | New configurations use the compact Minimal stamp, aligned left. Saved configurations remain available. The stamp sheet controls burn-in, template and top/bottom placement, with access to the full editor and display settings. Styles opens the stamp editor. |
| Orientation | The inherited portrait capture interface stays locked upright. Full landscape reflow and capture alignment require separate work. |

## Data flow

- `CameraScreen` owns camera lifecycle, gesture state and capture orchestration.
  Pro requests use the separate native Camera2 backend.
- `LocationService` rejects stale, future-dated, malformed, out-of-order and
  implausibly displaced fixes. Its GPS stream is foreground-only. A fix
  expires after 60 seconds. Reverse geocoding is distance-throttled and timed
  out, and address fields are cleared when the lookup location changes.
- The camera checks freshness and the selected accuracy limit at the shutter
  before drawing GPS data or writing photo GPS EXIF. The default is 25 m.
  Poor or expired fixes show a status message.
- `TemplateConfig` and `GeoStamp` drive both live and still-image rendering.
  Templates can be saved by name, reloaded or reset in the editor. The editor
  uses labelled sample data for its preview.
- Android video export uses Media3 Transformer on the recorded file. Frame
  presentation time drives the timestamp and selects the recording's location
  sample. The video overlay uses a compact text layout with coordinates and
  accuracy when enabled in the template. The capture controller can release
  independently of export. If rendering fails, the app explicitly reports
  that the original clip was saved.
  [Android Media3 effects](https://developer.android.com/media/implement/editing-app).
