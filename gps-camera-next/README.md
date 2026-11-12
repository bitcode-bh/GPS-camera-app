# GPS Camera Next

GPS Camera Next is a standalone Flutter field camera. The Android app ID is
`com.gpscamera.gps_camera_next`, the iOS bundle ID is
`com.gpscamera.gpsCameraNext`, and Android exports go to the **GPS Camera Next**
album. Each app has its own preferences and private storage.

## Build and install

Use Flutter 3.44.2 with Dart 3.12.2 or compatible versions, JDK 17, and an
Android SDK. Run these commands from this directory.

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

The release build uses the debug key for local installation when this project's
`android/key.properties` is absent. Configure an independent production
keystore before distribution. Distribution signing enables R8 and resource
shrinking. The Android build downloads Google Maven
dependencies for Media3 Transformer.

Android is the implementation and validation target. An iOS project with its
own identity is included. Its native Pro backend and media compositor still
need implementation and iOS-device verification.

- [Original app audit](docs/baseline-audit.md)
- [Camera design and architecture](docs/design-and-architecture.md)
- [Testing and performance](docs/verification.md)
