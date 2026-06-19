# GPS Camera Pro — Important Info

## Release Build — v1.0.0 (June 19 2026)

| Item | Value |
|------|-------|
| APK | `imp/gps_camera_pro_release_v1.0.0.apk` (54 MB) |
| Package | `com.gpscamera.gps_camera_pro` |
| Version name | 1.0.0 |
| Version code | 1 |
| Min SDK | 24 (Android 7.0+) |
| Target SDK | Flutter default (34) |
| Signing | Release keystore (NOT debug) — see below |
| R8 minify | Enabled |
| Resource shrink | Enabled |
| Build date | 2026-06-19 |

---

## ⚠️ Release Keystore — KEEP THIS SAFE

Losing the keystore or passwords makes it impossible to push signed updates.

| Item | Value |
|------|-------|
| Keystore file | `android/app/upload-keystore.jks` |
| Key properties | `android/key.properties` |
| Store password | `6rOewm2iEVzKF4s34D3tpVZmtFmJ` |
| Key password | `6rOewm2iEVzKF4s34D3tpVZmtFmJ` |
| Key alias | `upload` |
| Algorithm | RSA 2048-bit |
| Validity | 10 000 days (~27 years) |
| Subject DN | CN=GPS Camera Pro, OU=Mobile, O=GPS Camera, C=IN |

Both `android/key.properties` and `android/app/upload-keystore.jks` are **gitignored** — they will NOT be committed. Back them up externally (iCloud, password manager, encrypted drive).

---

## Rebuild from Source

```bash
# 1. Make sure key.properties + upload-keystore.jks are in place (see above)
# 2. Build
cd gps_camera_pro
flutter build apk --release

# Output: build/app/outputs/flutter-apk/app-release.apk

# 3. Install on device
adb install -r build/app/outputs/flutter-apk/app-release.apk
# or
flutter install -d <device-id>
```

---

## Key Files

| File | Purpose |
|------|---------|
| `lib/main.dart` | App entry point |
| `lib/screens/camera/camera_screen.dart` | Main camera screen (all state) |
| `lib/screens/camera/widgets/camera_chrome.dart` | UI chrome widgets (ProControlSelector, ZoomBar, etc.) |
| `lib/screens/camera/widgets/camera_tool_strip.dart` | Camera Settings panel |
| `lib/widgets/geo_stamp.dart` | Geostamp widget |
| `lib/services/capture_service.dart` | Photo/video save, gallery listing |
| `lib/services/camera_capability_service.dart` | Hardware feature detection |
| `lib/services/pro_camera_controller.dart` | Native Camera2 backend (Pro mode) |
| `lib/state/settings_controller.dart` | App-wide settings singleton |
| `lib/state/template_controller.dart` | Stamp template singleton |
| `android/app/build.gradle.kts` | Android build config (signing, R8) |
| `android/app/proguard-rules.pro` | R8 keep rules for native channel classes |

---

## Device Tested

| | |
|-|-|
| Device | Samsung SM-M045F |
| Serial | R9ZW202PC7W |
| OS | Android 14 |

---

## What Changed in This Build

- **Stamp swipe fixed:** horizontal swipe on the minimap now moves it left/right
- **Gallery optimized:** downscaled image decode (`cacheWidth`), async file listing, neighbor prefetch, bounded memory
- **Release signing:** real keystore, not debug keys
- **R8 minify + resource shrink:** enabled with ProGuard keep rules for Camera2/Flutter
