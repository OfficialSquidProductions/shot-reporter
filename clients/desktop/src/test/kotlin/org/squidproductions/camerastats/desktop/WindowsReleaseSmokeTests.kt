package org.squidproductions.camerastats.desktop

import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.nio.file.*
import kotlin.test.*

class WindowsReleaseSmokeTests {
    @TempDir lateinit var output:Path
    @Test fun releaseSmokeExercisesReportPersistenceAndEveryExport() {
        val destination=output.resolve("fresh-smoke")
        windowsDesktopReleaseSmoke(destination)
        assertTrue(Files.readString(destination.resolve("PASS.txt")).contains("PDF, CSV and HTML"))
        for(extension in listOf("camreport","pdf","csv","html")) {
            assertTrue(Files.size(destination.resolve("package-test.$extension"))>0)
        }
        assertFails {windowsDesktopReleaseSmoke(destination)}
    }
}
