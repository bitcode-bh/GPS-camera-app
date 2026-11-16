# Wireless deployment — 16 November 2026

The brighter Spectrum P debug APK was installed successfully on Motorola Edge 70 over the explicitly selected secure Wi-Fi ADB transport. USB was used for read-only discovery only. Existing app data was retained (`install -r`). See `wireless-deployment.json` for artifact identity. No phone taps were sent.

Android reported successful cold launches and CameraX opened its camera session. Subsequent logs show an input interaction, an app-request activity finish and activity destruction, followed by a Flutter ImageReader callback attempting to schedule a frame after its JNI engine had detached. This is a real teardown crash; startup/foreground stability must not be reported as passed. No runtime fix was applied. Initial suspicion of a startup crash was narrowed by the event logs to a failure during activity teardown.

The owner then requested Stash-exact colours/background and less Pinterest resemblance. The separate PS design under `design/logo/pinshutter-stash-v3/` remains a review preview and has not been installed.

## Approved PS + bottom layout update

Superseded by the successful wireless update recorded in `ps-layout-deployment.json`. The PS logo/wordmark, safe-area bottom Library/Map switch and lower geostamp row are installed. The real library/map screen and updated wordmark were visually verified on the phone. The camera remained running in the foreground, with the new lower stamp visible behind the owner's in-app settings screen.

Back now waits for camera disposal and pending photo saves before `SystemNavigator.pop`, addressing the observed teardown race. Regression tests hold camera disposal pending and verify that repeated Back cannot detach the engine early. All 157 Flutter tests and clean analysis passed; the debug APK built. No crash entries appeared for the newly deployed process. A fully controlled fresh-camera exit/relaunch retest remains incomplete because notification/screenshot overlays took focus during the owner's review; no inputs were sent outside the debug app. The earlier failure log remains historical evidence, not a claim that every teardown path is qualified.

No iOS build, Play release, commit or push was performed. Phone screenshots containing gallery items or precise location were kept in temporary local files, not added to the repository.
