import org.jetbrains.compose.desktop.application.dsl.TargetFormat
plugins { kotlin("jvm"); id("org.jetbrains.kotlin.plugin.compose"); id("org.jetbrains.compose") }
kotlin { jvmToolchain(21); compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) }; sourceSets.main { kotlin.srcDir("../shared-ui/src/main/kotlin") } }
java { sourceCompatibility=JavaVersion.VERSION_17; targetCompatibility=JavaVersion.VERSION_17 }
dependencies {
    implementation(project(":core")); implementation(project(":jdbc"));implementation(project(":updates"));implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.8.1")
    implementation(compose.desktop.currentOs);implementation(compose.material3)
    implementation("de.rototor.pdfbox:graphics2d:3.0.5")
    testImplementation(kotlin("test"));testImplementation(compose.desktop.uiTestJUnit4)
    testImplementation("org.junit.jupiter:junit-jupiter:5.11.4");testRuntimeOnly("org.junit.vintage:junit-vintage-engine:5.11.4")
}
tasks.processResources {
    // Remove the retired generated resource even on an incremental build from an older checkout.
    doFirst { delete(destinationDir.resolve("demo-report.json")) }
    from(rootProject.projectDir.parentFile.resolve("licenses/clients/OPEN_SOURCE_NOTICES.txt")) {rename {"open-source-notices.txt"}}
    from(rootProject.projectDir.parentFile.resolve("website/assets/SP_GREEN.png")) {rename {"brand.png"}}
    from(rootProject.projectDir.parentFile.resolve("apple/Assets.xcassets/AppIcon.appiconset/mac-128-2.png")) {rename {"icon.png"}}
}
tasks.test { useJUnitPlatform();systemProperty("fixtures",rootProject.projectDir.parentFile.resolve("fixtures/camreport").absolutePath);systemProperty("java.awt.headless","false") }
compose.desktop {
    application {
        mainClass="org.squidproductions.camerastats.desktop.MainKt"
        nativeDistributions {
            targetFormats(TargetFormat.Msi,TargetFormat.Exe)
            packageName="Shot Reporter";packageVersion="0.2.2";description="Local camera reporting by Squid Productions";vendor="Squid Productions"
            modules("java.sql","java.desktop","java.logging","java.naming","jdk.unsupported","jdk.crypto.ec")
            windows {iconFile.set(project.file("src/main/resources/icon.ico"));menuGroup="Squid Productions";shortcut=true;upgradeUuid="c3774fda-7962-4264-a9bc-c428176d12b4"}
        }
    }
}
