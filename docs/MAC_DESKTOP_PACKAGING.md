# Mac reporting app packaging

The native reporting app retains application ID `org.squidproductions.camerastats` and the existing report storage. The direct candidate packager targets Apple Silicon and macOS 14+. Universal or store builds require their own exact-architecture validation.

## Prepare without signing or account access

`tools/prepare_macos_desktop_release.py` builds the native Release app or accepts a matching unsigned `--app-input`. It requires no Java runtime or external decoder tools. Output must be a fresh directory outside the checkout.

```sh
python3 tools/build_apple.py --distribution direct --version 0.2.0 --build 12
python3 tools/prepare_macos_desktop_release.py \
  --version 0.2.0-alpha.9 --build 12 \
  --output /private/new-reporting-candidate
```

Version/build must match the generated app. Choose a new monotonic release build before publication rather than reusing an existing published identity. By default source must be clean. `--allow-dirty` creates a review-only candidate whose manifest forbids release until a clean rebuild. Preparation never installs, signs, notarizes, uploads, changes feeds, reads Keychain secrets, or creates credentials.

The candidate contains the native application and Sparkle updater. Original licenses are staged in `Contents/Resources/legal`; provenance is in `Contents/Resources/DISTRIBUTION.json`. Every bundled Mach-O must include arm64, target macOS 14 or earlier, and have no unbundled absolute non-system library dependencies. Bundle symlinks must remain internal.

`--public-update-key` accepts the already authorized public Ed25519 key and stamps the fixed reviewed feed URL. Omitting it removes feed/key activation. Never supply a private key. A feed must remain unpublished until real signed upgrade/relaunch acceptance passes.

## Signing and distribution gates

Preparation writes `MAC_SIGNING_PLAN.json` and explicit entitlement profiles. A separately authorized operation using `tools/sign_macos_candidate.py` signs code and nested bundles from inside out with the existing approved identity, hardened runtime, and timestamps. It never uses deep signing. The sandboxed host retains selected-file access and Sparkle IPC exceptions. Downloader XPC uses its supported sandbox/network-client profile; Installer remains able to replace and relaunch the app. No blanket library-validation exception is added.

`tools/verify_macos_entitlements.py` checks the exported app again. Signing prompts must be handled explicitly, without changing Keychain ACLs or weakening validation. `--unsandboxed-host` is a separately selected alternative requiring report-root compatibility testing. Never merge or overwrite old report roots automatically. TestFlight/App Store variants exclude Sparkle.

Before publication, verify exact signed, notarized, stapled bytes, architecture/deployment target, notices, clean-source provenance, and report/preferences preservation. Use isolated test storage rather than replacing the owner's installed app. Signed older-to-newer installation and relaunch is a separate gate for automatic update delivery.

`tools/stage_macos_update.py` stages an authenticated appcast from an accepted archive using the approved Sparkle key account. It verifies with the public key and writes local output only. A staged feed is not publication or proof of a successful native upgrade.
