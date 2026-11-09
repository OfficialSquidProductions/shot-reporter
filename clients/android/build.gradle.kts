plugins { id("com.android.application"); kotlin("android"); id("org.jetbrains.kotlin.plugin.compose"); id("org.jetbrains.compose") }
android {
    namespace="org.squidproductions.camerastats"
    compileSdk=35
    defaultConfig {applicationId="org.squidproductions.camerastats";minSdk=26;targetSdk=35;versionCode=2;versionName="0.1.1";testInstrumentationRunner="androidx.test.runner.AndroidJUnitRunner"}
    buildFeatures {compose=true}
    compileOptions {sourceCompatibility=JavaVersion.VERSION_17;targetCompatibility=JavaVersion.VERSION_17}
    sourceSets["main"].java.srcDir("../shared-ui/src/main/kotlin")
    sourceSets["main"].assets.srcDir(layout.buildDirectory.dir("generated/cameraAssets"))
    sourceSets["main"].res.srcDir(layout.buildDirectory.dir("generated/cameraResources"))
    packaging {resources.merges+=setOf("META-INF/AL2.0","META-INF/LGPL2.1","META-INF/LICENSE","META-INF/NOTICE","META-INF/LICENSE.txt","META-INF/NOTICE.txt")}
}
kotlin {jvmToolchain(21);compilerOptions {jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)}}
dependencies {
    implementation(project(":core"));implementation("androidx.activity:activity-compose:1.10.1")
    implementation(compose.material3);implementation(compose.ui);implementation(compose.foundation)
    androidTestImplementation("androidx.test.espresso:espresso-intents:3.6.1");androidTestImplementation("androidx.test.ext:junit:1.2.1");androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.compose.ui:ui-test-junit4:1.8.2")
    debugImplementation("androidx.compose.ui:ui-test-manifest:1.8.2")
}
val prepareBrand by tasks.registering(Sync::class) {
    from(rootProject.projectDir.parentFile.resolve("licenses/clients/OPEN_SOURCE_NOTICES.txt")) {rename {"open-source-notices.txt"}}
    from(rootProject.projectDir.parentFile.resolve("website/assets/SP_GREEN.png")) {rename {"brand.png"}}
    into(layout.buildDirectory.dir("generated/cameraAssets"))
}
val prepareIcon by tasks.registering(Copy::class) {
    from(rootProject.projectDir.parentFile.resolve("apple/Assets.xcassets/AppIcon.appiconset/ios-1024.png")) {rename {"app_icon.png"}}
    into(layout.buildDirectory.dir("generated/cameraResources/drawable"))
}
tasks.named("preBuild") {dependsOn(prepareBrand,prepareIcon)}
