# Shot Reporter

**A Squid Productions Software**

Local shot, camera, and script-supervisor reporting for iPhone, iPad, Mac, Android, and Windows. Previously Camera Stats; existing application identities and report storage are preserved. See [compatibility notes](docs/REBRAND.md).

## Reporting workflow

- Record project and crew information, scene/shot/take labels, camera and recording settings, lens/measurement information, flags, and circle takes.
- Keep camera, DP, continuity, and editorial notes separate.
- Use Quick, Standard, and Full take views without losing recorded fields.
- Check missing fields and self-review the report before handoff.
- Preview landscape PDFs, export CSV/HTML, and exchange editable `.camreport` files.
- Open the independent fictional The Last Light demo with its eight-scene script and 16-shot plan. Creating a demo never overwrites an existing report.

The current source is focused on reporting. The product scope and compatibility safeguards are described in [reporting scope](docs/REPORTING_SCOPE.md). The reporting-only desktop alpha is available in [release 0.2.0-alpha.6](https://github.com/OfficialSquidProductions/shot-reporter/releases/tag/v0.2.0-alpha.6).

## Local saves and imports

Every accepted edit commits a validated report snapshot to a local SQLite database with WAL journaling and synchronous FULL durability, retaining the preceding snapshot in the same transaction. Failed or stale saves preserve the accepted in-memory report. The active document selection commits with its report. Previous snapshot files remain available for recovery. Export independent report backups regularly.

`.camreport` schema 1 is a ZIP archive containing `manifest.json` and `report.json`, checked with CRCs and SHA-256. Imports show project/revision/device, additions, and conflicts. Independent additions merge by stable ID; repeated package imports are idempotent. Omitted records never mean deletion. Competing edits can be opened separately. Unsupported fields and corrupt archives are rejected before local changes. Legacy naming fields remain inert compatibility data so existing reports can round-trip safely.

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

Reporting-only 0.2.0-alpha.6 is available for Apple Silicon on macOS 14+ and Windows 10+ x64. The Mac archive is signed/notarized; the Windows MSI is an unsigned manual installer with native upgrade validation. [Downloads and platform status](https://shotreporter.squidproductions.org). Mobile binaries and automatic update feeds remain unchanged. Release receipts include exact source commits, checksums, and validation limits.

Physical device/field testing, a 12-hour offline day, low-storage/power-loss checks, full conflict resolution, and exact supplied report-form parity remain open. See [requirements](docs/REQUIREMENTS.md), [validation history](docs/VALIDATION.md), and [release checklist](docs/RELEASE.md). Source is MIT licensed; third-party components retain their licenses, and the supplied SP mark remains unchanged.
