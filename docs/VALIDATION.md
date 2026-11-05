> Historical validation for the named releases. Re-run relevant checks for the current [reporting scope](REPORTING_SCOPE.md) before any new release.

# 0.1.0 owner-test field alpha

Validated on 2026-10-19 with Xcode 26.6 / Swift 6.3.3.

- 23 XCTest cases passed: report snapshots, numbering, archive schema/CRC/SHA-256 validation, malformed packages, conservative merges, PDF/CSV/HTML, transactional SQLite recovery, failed saves and stale writers.
- Separate native subprocess committed the demo, received SIGKILL without closing SQLite, and reopened all three completed takes successfully.
- iPhone 17e / iOS 26.5 Simulator: opened the shared demo; previewed and saved its PDF through Files; saved a `.camreport`; imported the actual saved file; verified its integrity preview and opened a separate editable report. The saved archive contained three 3A takes and circle take 2.
- iPad mini / iPadOS 26.5 Simulator: inspected portrait layout, the shared circled take 2 and editable report fields; added take 4 with inherited settings; terminated and relaunched the app; verified take 4 remained.
- Canonical demo script SHA-256: `84b4bea90b72a1d3d09be8925b07cdf696e9bc579386ed21c3255bb305336f87`. Eight scenes and 16 planned shots match Scenic and Production Desk; completed sample takes are 3A/1–3, circle 2. Existing reports are never reset by the demo button.
- Suite icon comparison verified the rounded white Mac tile and green mark geometry against Scenic and Production Desk. The original supplied brand asset remains unchanged.
- Signed iPhone/iPad and universal arm64/x86_64 Mac archives uploaded to App Store Connect. Both 0.1.0 (1) builds processed successfully and are marked Testing in the manual Owner Testing internal group, with one owner tester. This is not a public App Store submission.
- Direct Mac artifact: Developer ID signature, hardened runtime, notarization, stapled ticket and Gatekeeper assessment verified.

## Remaining validation

Physical iPhone/iPad use and full interactive Mac document workflows need owner testing. Shot Reporter reports entered production information; no camera hardware support is claimed.

The first Mac TestFlight upload warned that debug symbols were missing. Upload succeeded, but native Mac crash symbolication is limited in build 1; future archives must include dSYMs.

## Android / Windows field clients

- Twenty JVM/native desktop tests passed locally and on Windows: unchanged Swift fixture reading, CRC/SHA/ZIP/schema rejection, Unicode and 1,000-take roundtrips, conservative merges, SQLite reopen/full/stale/interrupted transactions and subprocess crash recovery, rejected-save UI preservation, protected exports, native PDF rendering and the rendered shared demo flow.
- Windows x64 EXE/MSI packages were built on Windows Server 2025 CI. Both the packaged JVM app and the actual MSI-installed app passed native SQLite reopen, report roundtrip, PDF and image-resource checks. The installers are unsigned. Physical Windows 10/11 and arm64 validation remain outstanding.
- Each API 35 Pixel 6 phone and Pixel C tablet passed three instrumentation tests: exact demo/next-take inheritance, activity recreation and rotation; system SQLite reopen/prior snapshot and native PDF rendering; actual Storage Access Framework result-byte export/import into a separate report. Picker callbacks use test-owned MediaStore URIs; interactive navigation through every third-party document provider remains owner validation.
- Native Android and Windows demo PDFs were rendered as four complete landscape pages; retained screenshots/pages were inspected. The new layout includes full fields and continuation pages; exact school-form parity remains unfinished.
- The actual non-debuggable Android release APK was inspected for package/version, minimum API 26, target API 35, disabled OS backup and absence of Internet/camera/microphone/broad-storage permissions. The generated signature-level receiver permission is retained.
- The owner approved a dedicated local Android signing identity. V2/V3 signatures and the expected public certificate were verified. Exact signed APK smoke checks passed on phone and tablet: installation, opening the shared demo, process reopening, reinstall with report preservation, and landscape layout. No private signing material is sent to CI.
- Unchanged local Swift reader accepted actual Windows JVM exports: original three-take revision 4 and edited four-take revision 5. This proves interchange parsing, not complete physical cross-device handoff workflows.
- Full native/interoperability run [39303095878](https://github.com/OfficialSquidProductions/shot-reporter/actions/runs/39303095878) passed on source `9ed917c1ca18dbd389a7af1317883747fa2fcb6c`, including all 23 unchanged Apple regression tests and actual Windows-exported package reads. Signed-release run [39303095861](https://github.com/OfficialSquidProductions/shot-reporter/actions/runs/39303095861) passed both device sizes. Final source's unsigned Android APK is byte-identical to the input used for the tested signed candidate.
- Original dependency notice resources are retained; additional pinned notices are bundled and locally viewable. Windows checkout must preserve original notice bytes and the checker must stop the build on failure.

No physical Android device, lower Android API baseline, 12-hour field day, full-storage power interruption or camera hardware certification is claimed.
