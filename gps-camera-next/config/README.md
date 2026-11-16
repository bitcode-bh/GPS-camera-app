# Owner-managed release configuration

Production builds now stop without valid non-debug upload signing, a non-placeholder HTTPS privacy-policy URL, a privacy contact, authorized map access and up-to-date Android notice inventory. A build passing these checks does not prove contracts, trademark rights, hosted-policy content or Play approval.

1. The owner approved **PinShutter**, with proposed Play title **PinShutter: GPS Camera**. Complete trademark/domain clearance, create the privacy/support contact and public policy page, and finish the policy draft for bitcode.bh with the actual legal identity/recipient arrangements.
2. Configure the owner's upload keystore locally using `android/key.properties.example`. Do not put private keys/passwords in chat or version control. No upload key was created by this work.
3. Obtain the ArcGIS account/privileges and confirm rights for permanent map stamps in shared photos/videos. Set provider-supported expiry/referrers/usage controls; do not assume Android package/SHA restrictions exist for this API.
4. Copy `release.example.json` to `release.local.json` and fill the four values locally. The latter is gitignored. ESRI_REFERER is optional and must match an actual provider-supported native request configuration.
5. Run formatting, analysis and tests; regenerate native notices if the runtime graph changed. Then build using the local configuration file:

```sh
flutter build appbundle --release --dart-define-from-file=config/release.local.json
```

Do not paste tokens into tracked scripts or commit a filled local JSON file. `--dart-define` values embedded in an Android client can be extracted; use an appropriately scoped client token, never a client secret. The build guards deliberately do not print credential values.

The final owner-signed/R8/authenticated-map build still needs certificate/artifact inspection, device tests, provider/attribution review and Console verification. Debug APKs remain available for development. Old debug-signed release artifacts in build output are not upload candidates, even if a later guarded build stops.
