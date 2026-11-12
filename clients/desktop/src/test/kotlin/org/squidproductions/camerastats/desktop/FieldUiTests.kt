package org.squidproductions.camerastats.desktop

import androidx.compose.ui.test.*
import androidx.compose.ui.graphics.asSkiaBitmap
import org.jetbrains.skia.Image
import org.jetbrains.skia.EncodedImageFormat
import java.io.File
import androidx.compose.ui.test.junit4.createComposeRule
import org.junit.Rule
import org.junit.Test
import kotlin.test.*
import java.nio.file.Files
import org.squidproductions.camerastats.core.*
import org.squidproductions.camerastats.storage.JdbcDriver
import org.squidproductions.camerastats.ui.*

class FieldUiTests {
    @get:Rule val ui=createComposeRule()
    @Test fun desktopBlankReportNextTakeAndDraftReview() {
        val root=Files.createTempDirectory("camera-ui-test");val host=DesktopGateway(root);val repo=Repository(JdbcDriver(root.resolve("reports.sqlite3")));val state=AppState(repo,host)
        try {
            ui.setContent {FieldApp(state)}
            ui.onNodeWithText("Open The Last Light demo").assertDoesNotExist()
            ui.onNodeWithText("Read the demo script").assertDoesNotExist()
            ui.onNodeWithText("Read the 16-shot plan").assertDoesNotExist()
            ui.onNodeWithText("New blank report").performClick()
            ui.onNode(hasText("New production") and !hasSetTextAction()).assertExists()
            ui.onNodeWithText("Log",useUnmergedTree=false).performClick()
            val image=ui.onRoot().captureToImage();File("build/qa").mkdirs();File("build/qa/desktop-blank-report.png").writeBytes(Image.makeFromBitmap(image.asSkiaBitmap()).encodeToData(EncodedImageFormat.PNG)!!.bytes)
            ui.onNodeWithText("Scene for next take").performScrollTo().performTextInput("3A")
            ui.onNodeWithText("Next take",substring=false).performScrollTo().performClick()
            ui.onNodeWithText("Scene 3A · Take 1").performScrollTo().assertExists()
            ui.onNodeWithText("Review",useUnmergedTree=false).performClick()
            ui.onNodeWithText("1 takes · ${state.report.missing.size} outstanding requirements").assertExists()
            assertEquals("1",state.report.active.last().values["take"]);assertEquals("A",state.report.active.last().values["camera"])
            assertEquals(1,repo.load(state.slot).report.active.size)
            ui.onNodeWithText("Saves",useUnmergedTree=false).performClick()
            ui.onNodeWithText("Save As .camreport").assertExists()
            ui.onNodeWithText("Export CSV").assertExists()
            ui.onNodeWithText("Export HTML report").assertExists()
            ui.onNodeWithText("Naming preset",substring=true).assertDoesNotExist()
            ui.onNodeWithText("Template",substring=false).assertDoesNotExist()
            // Old saved/imported reports retain their data, but cannot restore removed reader controls.
            ui.runOnIdle {state.open(legacyReportFixture())}
            ui.onNodeWithText("Today",useUnmergedTree=false).performClick()
            ui.onNodeWithText("Read the demo script").assertDoesNotExist()
            ui.onNodeWithText("Read the 16-shot plan").assertDoesNotExist()
            ui.onNodeWithText("All Duties").assertDoesNotExist()
            ui.onNodeWithText("Settings").performClick()
            ui.onNodeWithText("Open-source notices").performScrollTo().performClick()
            ui.onNodeWithText("Shot Reporter — OPEN-SOURCE NOTICES",substring=true).assertIsDisplayed()
            ui.onNodeWithText("Done",substring=false).performClick()
        } finally {repo.close()}
    }
}
