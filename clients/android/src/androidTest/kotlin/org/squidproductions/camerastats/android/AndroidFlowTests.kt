package org.squidproductions.camerastats.android

import androidx.compose.ui.test.*
import androidx.compose.ui.graphics.asAndroidBitmap
import android.app.Activity
import android.app.Instrumentation
import android.content.Intent
import android.content.ContentValues
import android.content.pm.ActivityInfo
import android.provider.MediaStore
import android.graphics.Bitmap
import androidx.test.espresso.intent.Intents
import androidx.test.espresso.intent.Intents.intending
import androidx.test.espresso.intent.matcher.IntentMatchers.hasAction
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import org.junit.Rule
import org.junit.Test
import org.junit.Assert.*
import org.squidproductions.camerastats.core.*
import java.io.File

class AndroidFlowTests {
    @get:Rule val ui=createAndroidComposeRule<MainActivity>()
    @Test fun blankReportNextTakeAndDatabaseReopen() {
        ui.activityRule.scenario.onActivity {it.requestedOrientation=ActivityInfo.SCREEN_ORIENTATION_PORTRAIT}
        ui.waitUntil(10000) {val bounds=ui.onRoot().fetchSemanticsNode().boundsInRoot;bounds.height>bounds.width}
        ui.onNodeWithText("New blank report").performClick()
        ui.onNode(hasText("New production") and !hasSetTextAction()).assertExists()
        ui.onNodeWithText("Open The Last Light demo").assertDoesNotExist()
        ui.onNodeWithText("Read the demo script").assertDoesNotExist()
        ui.onNodeWithText("Read the 16-shot plan").assertDoesNotExist()
        assertFalse(ui.activity.assets.list("")!!.contains("demo-report.json"))
        capture("today-portrait")
        ui.onNodeWithText("Log").performClick()
        capture("take-portrait")
        ui.onNodeWithText("Scene for next take").performScrollTo().performTextInput("3A")
        ui.onNodeWithText("Next take",substring=false).performScrollTo().performClick()
        ui.onNodeWithText("Scene 3A · Take 1").assertExists()
        ui.activityRule.scenario.recreate()
        ui.onNode(hasText("New production") and !hasSetTextAction()).assertExists()
        ui.runOnIdle {assertEquals(1,ui.activity.model.report.active.size);assertEquals("1",ui.activity.model.report.active.last().values["take"]);assertEquals("A",ui.activity.model.report.active.last().values["camera"])}
        ui.activityRule.scenario.onActivity {it.requestedOrientation=ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE}
        ui.waitUntil(10000) {val bounds=ui.onRoot().fetchSemanticsNode().boundsInRoot;bounds.width>bounds.height}
        capture("today-landscape")
    }
    private fun capture(name:String) {
        ui.waitForIdle();val bitmap=ui.onRoot().captureToImage().asAndroidBitmap()
        writeQa("$name.png","image/png") {bitmap.compress(Bitmap.CompressFormat.PNG,100,it)}
    }
    // Test-only MediaStore outputs survive AGP uninstalling the tested app on the isolated CI VM.
    private fun writeQa(name:String,mime:String,write:(java.io.OutputStream)->Unit) {
        val resolver=ui.activity.contentResolver
        val values=ContentValues().apply {put(MediaStore.Downloads.DISPLAY_NAME,name);put(MediaStore.Downloads.MIME_TYPE,mime);put(MediaStore.Downloads.RELATIVE_PATH,"Download/CameraStatsQA");put(MediaStore.Downloads.IS_PENDING,1)}
        val uri=resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI,values)!!
        resolver.openOutputStream(uri)!!.use(write)
        resolver.update(uri,ContentValues().apply {put(MediaStore.Downloads.IS_PENDING,0)},null,null)
    }
    @Test fun storageAccessResultCallbacksExportAndImportActualBytes() {
        ui.activityRule.scenario.onActivity {it.requestedOrientation=ActivityInfo.SCREEN_ORIENTATION_PORTRAIT}
        val resolver=ui.activity.contentResolver
        val values=ContentValues().apply {put(MediaStore.Downloads.DISPLAY_NAME,"Camera-Stats-test-${identity()}.camreport");put(MediaStore.Downloads.MIME_TYPE,"application/octet-stream")}
        val uri=resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI,values)!!
        Intents.init()
        try {
            intending(hasAction(Intent.ACTION_CREATE_DOCUMENT)).respondWith(Instrumentation.ActivityResult(Activity.RESULT_OK,Intent().setData(uri)))
            intending(hasAction(Intent.ACTION_OPEN_DOCUMENT)).respondWith(Instrumentation.ActivityResult(Activity.RESULT_OK,Intent().setData(uri)))
            ui.onNodeWithText("New blank report").performClick();val source=ui.activity.model.report;val oldSlot=ui.activity.model.slot
            ui.onNodeWithText("Saves").performClick()
            ui.onNodeWithText("Naming preset",substring=true).assertDoesNotExist()
            ui.onNodeWithText("Template",substring=false).assertDoesNotExist()
            ui.onNodeWithText("Save As .camreport").performClick();ui.waitForIdle()
            val saved=resolver.openInputStream(uri)!!.use {it.readBytes()};assertEquals(source,Exchange.read(saved).report)
            ui.onNodeWithText("Import Save…").performClick();ui.onNodeWithText("Import preview").assertExists()
            ui.onNodeWithText("Open as separate editable report").performScrollTo().performClick();ui.waitForIdle()
            assertEquals(source,ui.activity.model.report);assertNotEquals(oldSlot,ui.activity.model.slot);assertTrue(ui.activity.model.documents.any {it.slot==oldSlot})
        } finally {Intents.release();resolver.delete(uri,null,null)}
    }
    @Test fun nativePdfAndPortableSaveRoundtrip() {
        val context=ui.activity;val report=(1..3).fold(Report()) { current, _ -> current.next("3A","Android test") };val pdf=context.pdf(report)
        assertTrue(pdf.copyOfRange(0,5).toString(Charsets.US_ASCII)=="%PDF-");assertTrue(pdf.size>1000)
        assertTrue(context.notices().contains("Independent JPEG Group"))
        val pdfFile=File(context.cacheDir,"android-report.pdf").apply {writeBytes(pdf)}
        writeQa("android-report.pdf","application/pdf") {it.write(pdf)}
        android.os.ParcelFileDescriptor.open(pdfFile,android.os.ParcelFileDescriptor.MODE_READ_ONLY).use {descriptor ->android.graphics.pdf.PdfRenderer(descriptor).use {renderer ->
            assertTrue(renderer.pageCount>1)
            for(index in 0 until renderer.pageCount) renderer.openPage(index).use {page ->
                assertEquals(842,page.width);assertEquals(595,page.height);val bitmap=Bitmap.createBitmap(page.width,page.height,Bitmap.Config.ARGB_8888);bitmap.eraseColor(android.graphics.Color.WHITE);page.render(bitmap,null,null,android.graphics.pdf.PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                writeQa("android-pdf-page-${index+1}.png","image/png") {bitmap.compress(Bitmap.CompressFormat.PNG,100,it)};bitmap.recycle()
            }
        }}
        val exported=Exchange.export(report,"Android instrumented test");assertEquals(report,Exchange.read(exported).report)
        val database=File(context.cacheDir,"isolated-${identity()}.sqlite3");val slot=identity()
        Repository(AndroidDriver(database)).use {r ->val hash=r.save(slot,report,"Android test",null);r.save(slot,report.next("3A","Android test"),"Android test",hash);assertEquals(report,r.load(slot,true).report)}
        Repository(AndroidDriver(database)).use {r ->assertEquals(4,r.load(slot).report.active.size)}
    }
}
