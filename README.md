# Shot Reporter

**A Squid Productions Software**

Local shot, camera, and script-supervisor reporting for iPhone, iPad, Mac, Android, and Windows. Previously Camera Stats; existing application identities and report storage are preserved. See [compatibility notes](docs/REBRAND.md).

## Reporting workflow

- Record project and crew information, scene/shot/take labels, camera and recording settings, lens/measurement information, flags, and circle takes.
- Keep camera, DP, continuity, and editorial notes separate.
- Use Quick, Standard, and Full take views without losing recorded fields. All responsibilities are always available; no job selection is required.
- Enter camera, media, recording, and lens details in Log. Values carry forward between takes, including changes to recorded settings. Return to defaults resets the next-take fields to the app’s starting values without changing earlier takes.
- Open appearance and support from Settings at the bottom of the sidebar or tab bar.
- Check missing fields and self-review the report before handoff.
- Preview landscape PDFs, export CSV/HTML, and exchange editable `.camreport` files.
- Start with a blank report or reopen an existing local report.
- Delete unneeded reports in Saves and restore them from Recently Deleted.
- Choose Movie (default) or TV in Settings for each report. TV shows Season and Episode; switching modes keeps their values. Digital reports omit camera roll/reel.

The current source is focused on reporting. The product scope and compatibility safeguards are described in [reporting scope](docs/REPORTING_SCOPE.md). The signed Mac update is available in [release 0.2.0-alpha.10](https://github.com/OfficialSquidProductions/shot-reporter/releases/tag/v0.2.0-alpha.10). The Windows installer remains in [release 0.2.0-alpha.6](https://github.com/OfficialSquidProductions/shot-reporter/releases/tag/v0.2.0-alpha.6).

## Local saves and imports

Every accepted edit commits a validated report snapshot to a local SQLite database with WAL journaling and synchronous FULL durability, retaining the preceding snapshot in the same transaction. Failed or stale saves preserve the accepted in-memory report. The active document selection commits with its report. Previous snapshot files remain available for recovery. Export independent report backups regularly.

`.camreport` schema 1 is a ZIP archive containing `manifest.json` and `report.json`, checked with CRCs and SHA-256. Imports show project/revision/device, additions, and conflicts. Independent additions merge by stable ID; repeated package imports are idempotent. Omitted records never mean deletion. Competing edits can be opened separately. Unsupported fields and corrupt archives are rejected before local changes. Legacy naming fields and previously saved demo report data remain inert compatibility data so existing reports can round-trip safely. The current source does not bundle a demo script, sample report, or demo-only controls.

## Build and test

Open `apple/CameraStats.xcodeproj`, choose `CameraStats`, and build for macOS 14+ or iOS/iPadOS 17+. Device distribution requires an authorized signing team.

```sh
python3 tools/build_apple.py
swift test --package-path app
python3 tools/verify_crash.py
xcodebuild -project apple/CameraStats.xcodeproj -scheme CameraStats -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project apple/CameraStats.xcodeproj -scheme CameraStats -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

The Android/Windows clients share a Kotlin/JVM report engine and Compose screens, native SQLite adapters, file pickers, and platform PDF renderers. See [client build instructions](clients/README.md). JDK 21 and the pinned Gradle wrapper are required; Android uses an SDK whose terms the owner has already accepted. Windows installers bundle their JVM. Apple and Kotlin readers share the [format contract](docs/CAMREPORT.md).

## Validation and releases

Mac 0.2.0-alpha.10/build 13 is available for Apple Silicon on macOS 14+, with Developer ID signing, notarization and an authenticated Sparkle feed. A real public alpha.9 → alpha.10 install and automatic relaunch preserved active and deleted report snapshots through local database schema 2 → 3 migration. Trash cleanup has a fresh 14-day grace period for existing deleted reports. PDFs use labeled per-take sections, and a native iOS Simulator/Mac full-project handoff passed. Universal Mac TestFlight build 13 is Testing in Owner Testing. The iOS build 13 upload succeeded but remains Processing in App Store Connect, so phone availability and group assignment are pending Apple processing. Windows and Android binaries are unchanged. See the release's curated acceptance and handoff receipts for exact checks and limits.

Physical device/field testing, a 12-hour offline day, low-storage/power-loss checks, full conflict resolution, and exact supplied report-form parity remain open. See [requirements](docs/REQUIREMENTS.md), [validation history](docs/VALIDATION.md), and [release checklist](docs/RELEASE.md). Source is MIT licensed; third-party components retain their licenses, and the supplied SP mark remains unchanged.
