# PinShutter

PinShutter (formerly GPS Camera Next) is a standalone Flutter field camera by
**bitcode.bh**. Approved Play Store title: **PinShutter: GPS Camera**.
The Android app ID is
`com.gpscamera.gps_camera_next`, the iOS bundle ID is
`com.gpscamera.gpsCameraNext`, and Android exports go to the **GPS Camera Next**
album to preserve access to existing captures. Each app has its own preferences
and private storage. The Dart package and platform identifiers remain unchanged.

## Build and install

Use Flutter 3.44.2 with Dart 3.12.2 or compatible versions, JDK 17, and an
Android SDK. Run these commands from this directory.

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug --target-platform android-arm64
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

Release builds require owner-managed signing, published policy/contact and
authorized map configuration; missing upload credentials block the build.
Release always enables R8/resource shrinking. Follow the
[release configuration instructions](/Volumes/Bitcode/GitHub/GPS-camera-app/gps-camera-next/config/README.md).
Trademark/domain clearance and the remaining owner/service gates are still
pending; name approval does not establish legal clearance. The Android build
downloads Google Maven dependencies for Media3 Transformer.

Android is the implementation and validation target. An iOS project with its
own identity is included. Its native Pro backend and media compositor still
need implementation and iOS-device verification.

- [Original app audit](docs/baseline-audit.md)
- [Camera design and architecture](docs/design-and-architecture.md)
- [Testing and performance](docs/verification.md)
