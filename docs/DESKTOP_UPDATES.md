# Desktop updates: implementation and release gates

Shot Reporter retains bundle/application ID `org.squidproductions.camerastats`, Windows MSI UpgradeCode `c3774fda-7962-4264-a9bc-c428176d12b4`, and existing report storage. No application/source footprint moves reports into a new branding directory.

The update implementation does **not** enable live updates by itself. Desktop releases require the platform checks below; publication does not activate an unconfigured feed. A dedicated Mac Sparkle key has been created with explicit owner approval; only its public key is in source. No Windows publisher certificate or live update feed is configured. Current Windows downloads are unsigned. Development builds explain this state and cannot automatically install them.

## Existing suite behavior inspected

Read-only references were Scenic `windows/main.cjs`, `windows/updates.cjs`, `macos/Updates.swift`, and Production Desk `desktop/windows/main.cjs`, `desktop/Updates.swift`. Those apps use electron-updater on Windows and Sparkle on macOS. Their UX includes automatic launch checks, manual checks, available-version notices, release details, an explicit download/install decision, failed-save refusal, and relaunch. No reference application, update feed or QA helper was modified/launched.

Shot Reporter adopts those interactions with a desktop Updates control, automatic checks after the initial window task on Mac, after 15 seconds on Windows, and daily thereafter, Stable/Alpha channels, release notes, Download Update, Keep Working/Cancel and Save, Install and Restart. Windows displays release notes as plain Compose text; supplied HTML or script text cannot execute. macOS uses native Sparkle UI with signed, self-contained release notes.

## macOS

The native app uses pinned Sparkle 2.10. `tools/build_apple.py --distribution development|direct|testflight|appstore` distinguishes distribution; development is the default. Store/TestFlight variants omit Sparkle binaries entirely and direct the user to the appropriate distribution surface. These builds must never replace themselves from a direct-download feed.

Direct distribution checks the current stable bundle identity and Apple Team `FZ298DXLS3`; unsigned hosts are disallowed. Signed archive verification occurs before extraction. `SURequireSignedFeed` is enabled and `SUSignedFeedFailureExpirationInterval` is explicitly numeric zero: failed feed authentication never becomes acceptable after a waiting period. The delegate also rejects any item whose feed-signing validation did not succeed. Appcast and release notes must be authenticated with the dedicated Shot Reporter Ed25519 key through Sparkle's official tooling. Numeric monotonic `CFBundleVersion` orders updates; semantic display versions are separate. Stable excludes alpha; Alpha accepts alpha and stable.

The tentative feed address is `https://raw.githubusercontent.com/OfficialSquidProductions/shot-reporter/main/updates/macos/appcast.xml`. It has not been published. The dedicated public key is recorded in the direct-build generator; release packaging omits feed/key activation unless explicitly enabled after acceptance. An unconfigured distributed package therefore fails closed. The direct-distribution release process must package and sign the Sparkle components and notarize the host correctly before activation. The owner approved the dedicated Mac key separately; its private material remains in Keychain.

## Windows trust protocol

The desktop-only `:updates` module has no mobile dependency. The installed app may bundle `/windows-update-policy.json` with:

- `feedURL`: HTTPS signed feed URL.
- `publicKey`: base64 DER SubjectPublicKeyInfo Ed25519 public key (not a secret).
- `allowedHosts`: exact lowercase HTTPS hosts, including every approved artifact redirect host.
- `signerSHA256`: SHA-256 of the dedicated trusted Authenticode leaf certificate's DER bytes.
- `currentVersion`, `currentBuild`, `currentMSIVersion`, and `defaultChannel` (`alpha` or `stable`).

No development environment override or feed-controlled key/publisher rotation is supported. Missing/malformed configuration disables automatic installation. The feed cannot select another app, arbitrary host, publisher, MSI identity or schema. A publisher/key rotation requires a reviewed app release and renewed upgrade validation.

A feed is a UTF-8 JSON envelope with exactly `payload` and `signature`, both base64. Signature is Ed25519 over the **exact decoded payload bytes**, not reparsed/canonicalized JSON. The signed payload has:

```json
{
  "schema": 1,
  "appID": "org.squidproductions.camerastats",
  "generatedAt": "2026-10-19T12:00:00Z",
  "expiresAt": "2026-10-20T12:00:00Z",
  "releases": [{
    "version": "0.2.0-alpha.1",
    "build": 4,
    "channel": "alpha",
    "releaseNotes": "Plain text release notes",
    "windowsX64": {
      "url": "https://APPROVED-HOST/Shot-Reporter.msi",
      "size": 123,
      "sha256": "64_HEXADECIMAL_CHARACTERS",
      "upgradeCode": "c3774fda-7962-4264-a9bc-c428176d12b4",
      "signerSHA256": "64_HEXADECIMAL_CHARACTERS",
      "msiVersion": "0.2.0"
    }
  }]
}
```

This example is documentation, not a usable or signed feed. Maximum envelope is 1 MiB, payload 512 KiB, 100 releases, release-note text 100,000 characters and installer 4 GiB. Dates expire within 31 days and reject materially future timestamps. Checks enforce semantic version ordering and increasing numeric build; the highest authenticated offered build is durably retained locally to block replay of an older still-valid feed. Stable releases cannot contain prerelease identifiers; Alpha accepts both channels. MSI ProductVersion must also increase, including successive alpha builds: Windows Installer considers the first three fields, so changing a display suffix alone is insufficient. It must remain within the Windows MSI numeric bounds.

Downloads use system TLS, bounded connect/read timeouts and at most five redirects. Every redirect is revalidated against the bundled exact-host HTTPS allowlist; credentials, nonstandard ports and fragments are rejected. A new owned attempt directory receives a partial file, immutable journal, exact byte count and SHA-256 check, then an atomic staging rename. Failed/cancelled partial files never become installable. Existing files are not reused or overwritten. Cancellation retains diagnostic/recovery files rather than deleting data.

Before installation the app checks the staged hash/length again, verifies every accepted report is durable, and writes consistent SQLite snapshots using `VACUUM INTO`. `quick_check` verifies snapshots. A local manifest maps backup filenames to original relative database paths. Save failure, pending import, stale report state, insufficient backup space or helper failure keeps the app open.

A fresh per-install attempt ticket launches the system Windows PowerShell helper, without execution-policy bypass. The helper verifies the package's trusted Authenticode signature and pinned leaf certificate, MSI UpgradeCode, ProductName, ProductVersion and x64 template **before acknowledging readiness**. It also refuses other running Shot Reporter/Camera Stats instances. A prepared handoff holds the save guard but cannot install. The UI must publish an atomically renamed durable commit marker before requesting exit; disposal before commit publishes cancellation and releases the guard. Interrupted helper readiness waits cancel and terminate the helper. The UI exits only after acknowledgement, and the helper waits for actual process exit. Parent exit without a valid commit marker never starts MSI. It holds a read-only file lock across package verification and installation, repeats package validation, invokes system Windows Installer with basic cancellable UI, suppresses reboot, retains verbose logs and an install result, and relaunches the known installed Shot Reporter path. MSI owns transaction rollback; the updater never passes report storage paths to it. A failed install reopens the previous installed path where it still exists and displays retained outcome/log information. No automatic database restore is attempted because that could overwrite newer user work. Pre-update snapshots remain for reviewed manual recovery.

## Validation and unresolved gates

Local JVM tests exercise authentic and tampered signatures, app/publisher/host mismatch, expiration, channels, semantic ordering, persisted replay watermark, exact/truncated/oversize/changed/cancelled downloads, staging tamper, failed save, helper failure and retained save guard. SQLite integration tests reopen unchanged report snapshots; pending imports and stale report states block install. Legacy application databases are left untouched and are not required for installation. Regression tests cover competing commit/dispose operations and missing accepted revision-zero reports. UI-thread state capture keeps save checks consistent across report selection or edits. Compose UI tests verify an unconfigured build cannot offer installation. All fixtures are synthetic and isolated from owner data.

The native Windows PowerShell/COM/MSI elevation, publisher check, actual package rollback, installed-process close and relaunch are **not validated on this Mac**. There is no local Windows VM. The dedicated desktop release workflow now prepares native Windows rejection checks and an isolated manual-MSI upgrade; successful signed automatic installation remains a separate gate. An older-to-newer signed MSI upgrade must run in isolated Windows storage before enabling a live feed, including same identity/UpgradeCode, alpha progression, non-ASCII paths, user cancellation, network failure, modified installer, reboot-required result and disk-full backup failure. Verify every report snapshot, history, preferences, and legacy application data after relaunch. Existing reporting-only MSI upgrade evidence does not certify this new helper.

Mac tests cover update policy/save/cancel, native Sparkle delegate gates and isolated old/new recovery fixtures. Ephemeral fixture Ed25519 signatures and directory swaps are not a real Sparkle installation. A dedicated signed/notarized older-to-newer update and relaunch remains a release gate.

Before activation: obtain user authorization for a persistent dedicated signing identity/key if needed, approve any certificate purchase, configure trusted public metadata, produce signed/notarized platform builds, validate native upgrade/recovery, review release notes and request publication/feed authorization. This reporting-only source change does not authorize publication, feed activation, mobile/TestFlight changes, or new signing services. Unfulfilled native signing/upgrade gates still block feed activation.

Primary platform references: [Windows Installer ProductVersion](https://learn.microsoft.com/en-us/windows/win32/msi/productversion), [major upgrades](https://learn.microsoft.com/en-us/windows/win32/msi/major-upgrades), [installer options](https://learn.microsoft.com/en-us/windows/win32/msi/standard-installer-command-line-options), [Authenticode verification](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.security/get-authenticodesignature), [read-only MSI database access](https://learn.microsoft.com/en-us/windows/win32/msi/installer-opendatabase).


## Windows desktop release candidate workflow

`.github/workflows/desktop-release.yml` runs on main or manual dispatch with an exact reviewed source SHA. It has read-only repository permissions, no Android/TestFlight job and no release/feed publication step. It builds the reporting client, checks report export/import and persistence, and includes dependency notices and the bundled JVM corresponding-source archive. The JVM is pinned to the exact Temurin release matching its full source archive.

Native Windows tests must reject the actual unsigned installer and same-length tampered bytes before helper readiness or MSI invocation. An isolated profile exercises the previous public 0.1.1 MSI, report snapshots/history/preferences, and the new installed reporting runtime, including PDF/CSV/HTML and editable report export. Curated evidence contains XML, logs and synthetic-test PASS markers only. A manual unsigned MSI may be published only after this workflow passes; automatic installation remains disabled without trusted signing/feed configuration. This native rejection coverage does not certify successful signed auto-update.

## Bootstrap and staged feed tooling

The public Mac 0.1.1/build 2 archive has no Sparkle framework or update keys. The alpha2/build4 candidate intentionally omits feed/key activation. Released Windows alpha 2 has no bundled trusted policy and its MSI is unsigned. Publishing a feed cannot activate any of these copies; each needs one manual installation of a properly configured bootstrap release. This is not an accepted end-to-end automatic upgrade yet.

Mac alpha 3/build 5 preparation includes the existing approved public key, zero signed-feed-failure fallback, and the same sandbox. Sparkle's signed Downloader XPC already owns the outbound network entitlement; the host does not gain network access. `tools/stage_macos_update.py` inspects an exact signed/notarized/stapled archive, its clean provenance, matching public key/feed, and protected metadata, then uses Sparkle's official `sign_update --account shot-reporter` without exporting the private key. Release notes are plain text embedded as escaped HTML in the signed feed; architecture is restricted to arm64/macOS 14+. Output stays outside Git and is never published by the tool. `tools/verify_macos_update.swift` authenticates feeds and artifacts with the public key only, including exact byte lengths and rejection of modified/duplicate/trailing signature blocks.

Do not copy a staged appcast to the production `updates/macos/appcast.xml` path until report picker/reopen acceptance and a genuinely signed bootstrap→newer native install/relaunch have passed. Public URLs, archive lengths/hashes/signatures, notes, save/postpone gates and report recovery data must match that exact accepted release. Windows additionally needs a trusted publisher and service-compatible identity policy; see [Windows signing setup](WINDOWS_SIGNING_SETUP.md). No reference application's disabled publisher verification is inherited.

## November 9, 2026 repair status

The published alpha.6/build 9 Mac release removes Footage, video review, clip matching, renamed-copy workflows, and naming-template controls. An alpha.5/build 8 installation still contains those features. The production `updates/macos/appcast.xml` path was confirmed absent through the connected GitHub API on November 9; a published ZIP alone does not make it an in-app update.

The existing alpha.6 archive and staged appcast both passed public-key signature verification. The archive matched the published GitHub asset digest, and Apple signature, notarization and stapling checks passed. A local manual upgrade from build 8 to build 9 preserved report fields and takes; this does **not** count as native Sparkle installation acceptance. Existing no-op focus/reopen changes can still increment revision/history. No new release or feed was published during this repair.

The updater repair source now:

- Starts the updater for an early manual check instead of silently ignoring it, and permits retry after startup failure.
- Keeps ordinary no-new-update and user-cancellation outcomes out of failure diagnostics.
- Offers Update Status and, for trusted direct copies, View Available Downloads in the app menu.
- Distinguishes offline, unavailable feed/download, and signature-validation failures without relaxing authentication, channel, archive-host or save gates.

Verification: 52 Swift tests and 23 Python packaging/staging tests passed. The macOS Debug build passed from a fresh temporary DerivedData directory. The isolated preview displayed Update Status, dismissed normally, handled a repeated manual check, and closed normally. Existing Desktop DerivedData locations produced Xcode build-database disk I/O errors; no owner data was deleted to repair them. Xcode also reported an out-of-date CoreSimulator runtime, so no simulator validation is claimed for this Mac-only change.

These source changes are not in the published build 9. Any release containing them must use a newer monotonic build number, new exact-source signing/notarization evidence, and the normal publication process. The production feed remains inactive until genuine signed older-to-newer Sparkle download/install/relaunch acceptance, including report preservation and failure/cancel behavior, passes. Do not replace a public build's bytes or treat this manual upgrade as satisfying that gate.

## Alpha.7 build 10 acceptance and feed activation

The combined demo-removal and updater-repair release is version 0.2.0-alpha.7, Apple build 10, from clean source commit `43e51d75086674c6d696960cff8de460394631c2`. Its Mac ZIP is Developer ID signed, notarized, stapled, and Gatekeeper accepted. The anonymous public ZIP SHA-256 is `7cecc4e2dfae4bfb1e7d41b6dbf586a902e10857f6426c8e4d5aabd77b602310`.

A separate exact signed alpha.6/build 9 app copy authenticated a staged signed feed, downloaded this public archive through Sparkle, honored cancel and Keep Working, then installed and relaunched build 10. The installed code signature matches the published app. Synthetic current/previous report snapshots and active selection stayed byte-for-byte unchanged. The normal-root reports retained their prior snapshots; the existing focus/reopen no-op behavior appended a revision to one report without losing its prior snapshot. The owner installed app was not replaced during this isolated acceptance.

The accepted signed appcast is now at `updates/macos/appcast.xml` for production Mac delivery. The existing pinned key, channel, archive-host, signed-feed, signature-before-extraction, and save gates remain enabled. Copies without Sparkle/feed support still require a manual bootstrap install. Store/TestFlight builds exclude Sparkle and use their own delivery channel. Windows automatic updates remain gated on a dedicated trusted publisher certificate and successful native signed automatic installation.

Validation: 55 Swift tests and 26 packaging tests passed; the exact release source passed both GitHub desktop development and native Windows candidate workflows. iOS and universal Mac TestFlight version 0.2.0/build 10 uploaded and processed, with only the existing Owner Testing group assigned.
