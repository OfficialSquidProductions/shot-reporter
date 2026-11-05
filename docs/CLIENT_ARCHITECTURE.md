# Android and Windows reporting clients

Apple retains its SwiftUI interface and Swift report engine. Android and Windows share a Kotlin/JVM engine and Compose screens, with deterministic cross-platform interchange fixtures.

- `clients/core`: report fields, strict stored-ZIP exchange, CRC/SHA-256 validation, conservative merges, review rules, generic CSV/HTML, and snapshot repositories.
- `clients/shared-ui`: Today, Log, Review, Saves, report preferences, demo, flags, recovery, and import preview.
- Android: system SQLite, private files, Storage Access Framework, landscape PDF, phone/tablet layout. Minimum API 26; no Internet, camera, microphone, or broad-storage permission.
- Desktop: Compose Desktop, JDBC SQLite, native file dialogs, durable file replacement, Java2D/PDFBox reports, and authenticated update support. Bundled JVM; Windows x64 is the supported release target.

Both keep the suite mark and exact shared The Last Light fixture. Demo creation opens an independent report.

## Compatibility gates

`tools/generate_cross_platform_fixtures.py` generates synthetic Swift fixtures covering Unicode, flags, additions, conflicts, tombstones, and a 1,000-take day. Kotlin must read them; Swift must accept Kotlin exports. Unknown fields, invalid bounds, unsafe paths, unsupported schema/scope, checksum errors, and duplicate IDs must fail before mutation. Inert legacy naming data remains readable and round-trips unchanged.

SQLite stores current and previous reports plus active selection in one WAL/FULL transaction. Optimistic fingerprints reject stale writers. Failed saves leave accepted reports intact. Database files are not a cloud-sync format.

## Toolchains

Pinned versions: Kotlin/Compose compiler 2.1.21, Compose Multiplatform 1.8.2, Android Gradle Plugin 8.9.2, Gradle 8.13, JDK 21 compiling Java 17 bytecode, and Android SDK 35. Android SDK licenses are not accepted automatically. Original third-party notices are retained and checked before release.

Physical device validation, full conflict resolution, extended offline/low-storage/power-loss testing, and exact school-form parity remain open. Build and installed-runtime checks must pass for the exact source before publication. Existing historical results do not certify this source revision.
