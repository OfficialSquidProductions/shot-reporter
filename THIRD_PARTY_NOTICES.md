# Third-party and asset notices

Shot Reporter application source is MIT licensed, Copyright (c) 2026 Squid Productions.

The Apple builds link system frameworks supplied by Apple, including SwiftUI, Foundation, PDFKit, CoreGraphics, CoreText, CryptoKit, Observation and the operating system's SQLite library. Frameworks and platform fonts are not copied into this repository; use remains subject to the platform's terms. SQLite itself is in the public domain; see <https://sqlite.org/copyright.html>.

`assets/brand/SP_GREEN.png` is the user-supplied Squid Productions mark. Keep this source file unchanged. The site banner is the existing Squid Productions suite banner. Names and marks are trademarks of their owner, and the MIT code license grants no trademark rights.

The built-in “The Last Light” fictional test script is the supplied Production Desk sample, reused at the owner's explicit request. Demo camera settings and report entries are fictional fixtures created for Shot Reporter. No personal production report is bundled.

The direct Mac updater uses pinned Sparkle 2.10.0 under its original permissive license and retained component notices. Its original `LICENSE` is preserved in the Mac app's `Contents/Resources/legal/Sparkle-LICENSE.txt`; official source is <https://github.com/sparkle-project/Sparkle/tree/2.10.0>. Store/TestFlight variants exclude Sparkle. Direct-distribution packages retain these notices and must pass signature, notarization and native upgrade gates before update delivery is activated.


## Android / Windows development clients

The first Windows installer bundles Temurin/OpenJDK 21.0.12.1+1 (setup-java normalizes this to 21.0.12+101.0). Its corresponding original source archive, `OpenJDK21U-jdk-sources_21.0.12.1_1.tar.gz`, official metadata and checksum are supplied alongside the release downloads. Preserve the bundled runtime's legal files and provide corresponding source for the actual runtime version when making future binary releases.

The new clients use Kotlin and kotlinx.serialization (Apache-2.0), Jetpack Compose / AndroidX and Compose Multiplatform (Apache-2.0), Skiko/Skia and their transitive notices, Xerial SQLite JDBC (Apache-2.0 / BSD notices; SQLite is public domain), Apache PDFBox/FontBox and pdfbox-graphics2d (Apache-2.0), and the bundled Eclipse Temurin/OpenJDK runtime (GPL-2.0 with the Classpath Exception). Original dependency license/notice resources are retained in their JARs; Android packaging merges duplicate notice texts rather than excluding them. Additional pinned original notices are preserved under `licenses/clients` and bundled in both new clients, accessible through Today → Open-source notices. `sources.json` records original locations and SHA-256 digests; `tools/build_client_notices.py` verifies and assembles them without network access. The Windows JVM retains its own `runtime/legal` files. This software is based in part on the work of the Independent JPEG Group. No proprietary font is bundled. Build/test tools and their original licenses remain separate from the MIT application source.

Primary license sources: [Kotlin](https://github.com/JetBrains/kotlin/blob/master/license/LICENSE.txt), [kotlinx.serialization](https://github.com/Kotlin/kotlinx.serialization/blob/master/LICENSE.txt), [Compose Multiplatform](https://github.com/JetBrains/compose-multiplatform/blob/master/LICENSE.txt), [AndroidX](https://android.googlesource.com/platform/frameworks/support/+/androidx-main/LICENSE.txt), [SQLite JDBC](https://github.com/xerial/sqlite-jdbc/blob/master/LICENSE), [PDFBox](https://github.com/apache/pdfbox/blob/trunk/LICENSE.txt), [pdfbox-graphics2d](https://github.com/rototor/pdfbox-graphics2d/blob/master/LICENSE), [OpenJDK license and Classpath Exception](https://openjdk.org/legal/gplv2+ce.html).
