# ── GPS Camera Pro — R8/ProGuard keep rules ──────────────────────────────────
# Flutter's Gradle plugin already supplies engine keep rules; these are
# defensive keeps for code reached via the platform method/event channels and
# JNI, which R8 can't see through static analysis.

# Native platform-channel classes (MainActivity, ProCamera2). Referenced by
# name from the Flutter engine / Camera2 callbacks, so keep them whole.
-keep class com.gpscamera.gps_camera_pro.** { *; }

# Flutter embedding + plugin registrant.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.**

# Android Camera2 callbacks are invoked reflectively by the framework.
-keep class android.hardware.camera2.** { *; }

# Keep annotations and Kotlin metadata so reflection-based plugins behave.
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod
-keep class kotlin.Metadata { *; }

# Silence notes for optional desugar/Play Core classes some plugins reference.
-dontwarn com.google.android.play.core.**
