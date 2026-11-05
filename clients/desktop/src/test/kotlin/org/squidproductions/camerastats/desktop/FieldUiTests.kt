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
    @Test fun desktopDemoNextTakeAndDraftReview() {
        val root=Files.createTempDirectory("camera-ui-test");val host=DesktopGateway(root);val repo=Repository(JdbcDriver(root.resolve("reports.sqlite3")));val state=AppState(repo,host)
        try {
            ui.setContent {FieldApp(state)}
            ui.onNodeWithText("Open The Last Light demo").performClick()
            ui.onNode(hasText("The Last Light · DEMO") and !hasSetTextAction()).assertExists()
            ui.onNodeWithText("Log",useUnmergedTree=false).performClick()
            ui.onNodeWithText("Scene 3A · Take 2").assertExists()
            val image=ui.onRoot().captureToImage();File("build/qa").mkdirs();File("build/qa/desktop-demo.png").writeBytes(Image.makeFromBitmap(image.asSkiaBitmap()).encodeToData(EncodedImageFormat.PNG)!!.bytes)
            ui.onNodeWithText("Scene for next take").performTextInput("3A")
            ui.onNodeWithText("Next take",substring=false).performScrollTo().performClick()
            ui.onNodeWithText("Scene 3A · Take 4").assertExists()
            ui.onNodeWithText("Review",useUnmergedTree=false).performClick()
            ui.onNodeWithText("4 takes · 1 outstanding requirements").assertExists()
            assertEquals("4",state.report.active.last().values["take"]);assertEquals("24mm",state.report.active.last().values["lens"])
            assertEquals(4,repo.load(state.slot).report.active.size)
            ui.onNodeWithText("Saves",useUnmergedTree=false).performClick()
            ui.onNodeWithText("Save As .camreport").assertExists()
            ui.onNodeWithText("Export CSV").assertExists()
            ui.onNodeWithText("Export HTML report").assertExists()
            ui.onNodeWithText("Naming preset",substring=true).assertDoesNotExist()
            ui.onNodeWithText("Template",substring=false).assertDoesNotExist()
            ui.onNodeWithText("Today",useUnmergedTree=false).performClick()
            ui.onNodeWithText("Open-source notices").performScrollTo().performClick()
            ui.onNodeWithText("Shot Reporter — OPEN-SOURCE NOTICES",substring=true).assertIsDisplayed()
            ui.onNodeWithText("Done",substring=false).performClick()
        } finally {repo.close()}
    }
}
