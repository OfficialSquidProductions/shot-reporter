# Platform strategy

Apple uses native SwiftUI with a UI-independent Swift report model, stored-ZIP exchange, conservative merges, and transactional SQLite persistence. Android and Windows share the Kotlin/JVM report engine and Compose screens under `clients/`. Both engines follow the same schema-1 contract and shared fictional demo.

Deterministic Swift fixtures and Kotlin-to-Swift reader checks protect compatibility. Android uses app-private system SQLite, Storage Access Framework file pickers, and native PDF. Windows uses native dialogs, JDBC SQLite, and Java2D/PDFBox on a bundled JVM. Neither uses a WebView or local web server.

Android requests no Internet, camera, microphone, or broad-storage permission and disables automatic OS backup. Export report backups deliberately. The current Windows target is x64. Android minimum API is 26; physical devices, lower API levels, Windows arm64, long field days, and exact form parity remain validation work. Shot Reporter only processes report information.
