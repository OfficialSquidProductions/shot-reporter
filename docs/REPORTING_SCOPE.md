# Reporting scope

As of November 5, 2026, Shot Reporter is focused on shot information and script-supervisor information: project/crew details, camera settings, scene/shot/take logging, circling, flags, camera/DP/continuity/editorial notes, report checks, and report handoffs.

The Apple and Windows navigation contains only the reporting workflow. Report self-review remains: it checks the entered report rather than playing video. Appearance, detail, profile, and position preferences remain in Today. Movie/TV metadata such as season and episode remains editable as report information.

## Compatibility and preservation

Existing bundle/application identities, report database locations, stable report/entry IDs, snapshots, history, deleted-take recovery, and `.camreport` schema 1 remain intact. Legacy `namingTemplate` and optional `namingSettings` fields are retained when reading and writing old reports. They are compatibility data, not controls exposed in the interface. Existing report-export filename behavior remains compatible.

The retired video review, source-folder registration, slate matching, copy/rename, decoder, and native helper paths are removed from the application and packaging. There is no startup cleanup or destructive migration. Old external source files, copied assets, preferences, and legacy databases are not opened or deleted by this removal. The updater still verifies durable report saves and keeps report snapshots before installation.

## Local preview

`tools/prepare_settings_preview.py` prepares a fresh, isolated development app from a built report-only app. It refuses existing output/profile paths, pins an absolute `ShotReporterTest-*` profile, disables updates, and removes production document associations. It never replaces the owner-installed app or copies the owner's report library.

No release, feed, website deployment, App Store submission, or installed-app replacement is included in this scope change. Native Windows installer and signed Mac upgrade acceptance remain separate release gates.

## Validation on November 5, 2026

- 49 Swift tests passed, including report-only navigation/rendering, archive round trips, prior snapshots, and untouched legacy application data.
- Unsigned macOS and generic iOS Simulator Xcode builds passed.
- 40 Kotlin/JVM tests passed across core, JDBC, desktop UI, and updater modules; 2 Windows-only checks were skipped on macOS. Desktop JAR built with no retired workspace classes.
- 23 Python packaging/signing/update tests passed, including rejection of stale retired runtime payloads before packaging.
- Native subprocess SIGKILL test recovered the committed report and all three takes. Fresh cross-platform fixtures validated without changing the checked-in golden fixtures.
- Isolated native Mac preview opened the demo, added take 4, opened/dismissed the PDF, and retained the four takes after quit/relaunch. Only Today, Log, Review, and Saves were present.
- Website source build, ESM validation, canonical/legacy-host routing, and asset checks passed locally. Nothing was deployed.

Android assembly could not run because the local SDK is missing. Android instrumentation, native Windows MSI install/upgrade, physical devices, and signed Mac update/relaunch were not run. These checks remain required for their respective release claims.

An existing no-op edit behavior was observed during native QA: focusing/navigating can advance report revision/history even when field values do not change. It predates this removal and remains unchanged.
