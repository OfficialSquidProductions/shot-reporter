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
- Start with a blank report or reopen an existing local report. Edit Production title in Today to name it; the picker, header and saved-report label follow the title. Blank titles display “Untitled production.”
- Delete unneeded reports in Saves and restore them from Recently Deleted.
- Choose Movie (default) or TV in Settings for each report. TV shows Season and Episode; switching modes keeps their values. Digital reports omit camera roll/reel.

The current source is focused on reporting. The product scope and compatibility safeguards are described in [reporting scope](docs/REPORTING_SCOPE.md). The signed Mac update is available in [release 0.2.0-alpha.11](https://github.com/OfficialSquidProductions/shot-reporter/releases/tag/v0.2.0-alpha.11). The Windows installer remains in [release 0.2.0-alpha.6](https://github.com/OfficialSquidProductions/shot-reporter/releases/tag/v0.2.0-alpha.6).

## Local saves and imports

Every accepted edit commits a validated report snapshot to a local SQLite database with WAL journaling and synchronous FULL durability, retaining the preceding snapshot in the same transaction. Failed or stale saves preserve the accepted in-memory report. The active document selection commits with its report. Previous snapshot files remain available for recovery. Export independent report backups regularly.

The default iPhone/Mac `.camreport` schema 2 bundles the complete open report with explicitly added media, attachments, preferences and recovery copies using streamed ZIP64 and verified SHA-256 payloads. Both devices need build 14 or newer. File names typed into take fields do not include their bytes: add the files in Saves first. Import creates a separate report and preserves the destination’s existing reports. All preferences are retained as data; only reviewed appearance/detail settings can apply. See the [format and limits](docs/CAMREPORT.md).

The explicitly labeled report-data-only legacy export uses `.camreport` schema 1, a ZIP archive containing `manifest.json` and `report.json`, checked with CRCs and SHA-256. Imports show project/revision/device, additions, and conflicts. Independent additions merge by stable ID; repeated package imports are idempotent. Omitted records never mean deletion. Competing edits can be opened separately. Unsupported fields and corrupt archives are rejected before local changes. Legacy naming fields and previously saved demo report data remain inert compatibility data so existing reports can round-trip safely. The current source does not bundle a demo script, sample report, or demo-only controls.

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

Mac 0.2.0-alpha.12/build 15 is published for Apple Silicon on macOS 14+, Developer ID signed, notarized and stapled. Its authenticated production Sparkle feed is live. A real public alpha.11 → alpha.12 install and automatic relaunch preserved all active/deleted reports and current/previous snapshots without a database schema change. The exact signed Mac UI passed live title changes, blank-title fallback and persistence after restart. Native iOS Simulator/Mac rename and complete-archive tests passed; 82 Swift tests and 26 packaging checks passed. iPhone and universal Mac TestFlight 0.2.0/build 15 are Testing in the existing one-person Owner Testing group, with test instructions saved. Physical iPhone UI and AirDrop remain owner field checks. Windows/Android binaries are unchanged and use the legacy report-data-only format.

Physical device/field testing, a 12-hour offline day, low-storage/power-loss checks, full conflict resolution, and exact supplied report-form parity remain open. See [requirements](docs/REQUIREMENTS.md), [validation history](docs/VALIDATION.md), and [release checklist](docs/RELEASE.md). Source is MIT licensed; third-party components retain their licenses, and the supplied SP mark remains unchanged.
