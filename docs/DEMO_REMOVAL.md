# Demo removal

The current source no longer offers The Last Light demo, its script reader, or the shared 16-shot-plan reader. Today starts with **New blank report** and retains the existing report picker. This applies to Apple and shared Android/Windows screens.

The Apple demo implementation and older synthetic fixture factory are compiled only in the test target. Android and Windows no longer package `demo-report.json` or expose demo gateway methods. Incremental resource builds remove the retired generated payload. Legacy conformance fixtures remain under `fixtures/` for interoperability and regression tests; they are not shipping resources.

No saved reports are deleted or rewritten as part of this change. Existing report IDs, database paths, schema, entries, notes, and legacy custom values still round-trip. A previously created or user-edited sample report remains available as an existing report, without restoring demo-only controls.

Validation covers blank-report creation, adding takes, persistence/reopen, legacy report preservation, PDF and portable exports, absence of bundled demo resources, and the rendered desktop reporting screens. See the current task's verification logs for build results. The source change does not publish a new release, replace an installed app, or update an App Store/TestFlight listing.
