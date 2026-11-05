# Shot Reporter — Android / Windows field clients

Development clients. **No new platform is advertised as available until its recorded build and runtime checks pass.** Existing Apple releases remain separate and unchanged.

Use JDK 21 and the checksum-pinned wrapper. For core/desktop development on a machine without Android SDK:

```sh
./gradlew -PskipAndroid=true :core:test :jdbc:test :desktop:test
./gradlew -PskipAndroid=true :desktop:run
```

For Android, use the SDK 35 platform/build tools already installed under an Android SDK whose terms the owner has accepted. This project never accepts SDK terms automatically:

```sh
./gradlew :android:assembleDebug :android:connectedDebugAndroidTest
```

Run `:desktop:createDistributable :desktop:packageExe :desktop:packageMsi` on Windows x64 to build bundled-runtime installers. Windows code signing is not configured. A dedicated owner-approved Android release identity is kept outside the repository with its password in macOS Keychain. Debug CI keys remain temporary; CI never receives the private release identity. `SignAndroidRelease.java` uses pinned Google apksig 8.9.2 for local signing and verification; `InspectAndroidRelease.java` checks the compiled release manifest. Keep an independent protected backup of the release identity for future Android updates.

The UI supports offline project/crew and per-take fields, inherited camera defaults, flags, review, separate demo reports, `.camreport` import/export with conflict preview, native PDF and generic CSV/HTML. The desktop does not run a web server; Android declares no network permission. Local SQLite is WAL/FULL, with prior snapshots and stale-writer protection. Deliberately export an independent backup.

See [architecture and acceptance gates](../docs/CLIENT_ARCHITECTURE.md). These clients focus on shot and scripty reporting.
