# esp_iot

ESP IoT Android foundation

## Release builds

Debug builds install as `com.samir.esp_iot.debug`. The signed public package is
`com.samir.esp_iot`. An older debug installation using the public package ID
cannot be updated by a release signed with the distribution key. Keep that
installation until its data is no longer needed.

Release signing reads `android/key.properties` (gitignored) or the `ESP_IOT_RELEASE_*`
environment variables. Supply all four signing values to produce signed release artifacts.

From this directory, run:

```powershell
pwsh -NoProfile -File .\tool\android_release.ps1 -ExpectedSignerSha256 eb6168b8fc0abc08d542eb5ae55c14ac3db83801fee45ef803c7670bec7852ff
```

The script builds the universal APK and Play AAB, verifies the package ID, embedded
version and signatures, then writes the files and prints their SHA-256 hashes in
`build/distribution/`. Use `-BundletoolJar <path>` to supply a standalone bundletool
release JAR if the matching bundletool is unavailable in the local Gradle cache.

See the [install guide](../docs/ESP_IOT_INSTALL_GUIDE.md) for sharing the APK and
the [Google Play checklist](../docs/GOOGLE_PLAY_SUBMISSION.md) for submitting the AAB.
The earlier builds in `dist/` are recorded in the
[historical release report](../docs/ESP_IOT_FINAL_RELEASE_REPORT.md).
