# Release checklist

Shot Reporter source is MIT licensed. Keep dependency notices and brand trademark rights separate from the code license.

1. Run all core, persistence, import/export and PDF tests; build supported targets from the exact release commit. Keep the full-plan acceptance ledger honest about unsupported platforms and reporting features.
2. Audit the staged source for credentials, private production reports, personal metadata, proprietary SDKs/models/fonts and build artifacts. Keep internal account/coordination notes outside the public tree.
3. Use the existing owner-approved Apple team and release workflow. Do not create new credentials, accept legal agreements or change other applications' beta assignments as part of a routine release.
4. Validate signed archives and privacy/entitlement declarations before owner-only TestFlight distribution. Record actual app/build IDs and processing status. An owner alpha is not a fully field-validated release or a public App Store launch.
5. Notarize and staple the direct Mac download; verify the downloaded artifact and checksum before linking it on the site. Publish other platform downloads only after native builds/tests pass.
6. Publish website source and verified release links with the suite's typography, compact dark layout, family credit and brand assets. Confirm HTTPS and custom-domain routing. Never add guessed TestFlight/download URLs.
