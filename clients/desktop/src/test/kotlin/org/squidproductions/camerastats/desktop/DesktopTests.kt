package org.squidproductions.camerastats.desktop

import org.junit.jupiter.api.Test
import kotlin.test.*
import java.nio.file.Files
import org.apache.pdfbox.Loader
import org.apache.pdfbox.rendering.PDFRenderer
import org.squidproductions.camerastats.core.*
import org.squidproductions.camerastats.storage.JdbcDriver
import org.squidproductions.camerastats.ui.AppState

// Compatibility/PDF data is read from the test directory, never shipped with the application.
internal fun legacyReportFixture()=Exchange.decode(java.io.File(System.getProperty("fixtures"),"owner-demo.json").readBytes())

class DesktopTests {
    @Test fun runtimeDoesNotBundleDemo() {
        assertNull(DesktopGateway::class.java.getResource("/demo-report.json"))
    }

    @Test fun testOnlyFixtureAndPdfRenderWithoutFontRedistribution() {
        val host=DesktopGateway(Files.createTempDirectory("camera-pdf-test"));val demo=legacyReportFixture()
        assertEquals(3,demo.active.size);val pdf=host.pdf(demo)
        val output=java.io.File("build/qa").apply {mkdirs()};java.io.File(output,"desktop-report.pdf").writeBytes(pdf)
        Loader.loadPDF(pdf).use {doc ->assertTrue(doc.numberOfPages>1);val renderer=PDFRenderer(doc)
            for(page in 0 until doc.numberOfPages) {val image=renderer.renderImage(page);assertEquals(842,image.width);assertEquals(595,image.height);assertTrue((0 until image.width step 4).any {x ->(0 until image.height step 4).any {y ->(image.getRGB(x,y) and 0xffffff)!=0xffffff}});javax.imageio.ImageIO.write(image,"png",java.io.File(output,"desktop-pdf-page-${page+1}.png"))}
        }
    }
    @Test fun reportExportCannotReplaceCameraOriginalByAccidentalExtension() {
        val root=Files.createTempDirectory("camera-extension-test");val original=root.resolve("A001_C001.R3D");Files.write(original,byteArrayOf(1,2,3))
        val target=exportDestination(original,"camreport");assertEquals("A001_C001.R3D.camreport",target.fileName.toString());durableExport(target,byteArrayOf(4,5,6));assertContentEquals(byteArrayOf(1,2,3),Files.readAllBytes(original))
    }
    @Test fun failedClientSaveLeavesAcceptedUiReportAndDocumentSelection() {
        val root=Files.createTempDirectory("camera-client-save-test");val driver=JdbcDriver(root.resolve("reports.sqlite3"));var fail=false
        val interrupted=object:SqlDriver by driver {override fun execute(sql:String,args:List<Any?>) {if(fail && sql=="COMMIT") throw ReportException("Interrupted commit");driver.execute(sql,args)}}
        Repository(interrupted).use {repo ->val state=AppState(repo,DesktopGateway(root));state.open(Report());val accepted=state.report;val slot=state.slot;fail=true
            state.change("Rejected edit") {it.copy(values=it.values+("title" to "Rejected title"))};fail=false
            assertEquals(accepted,state.report);assertEquals(slot,state.slot);assertTrue(state.error!!.contains("not accepted"));assertEquals(accepted,repo.load(slot).report)
        }
    }
    @Test fun durableExportRoundtripAndNoTemporaryDebris() {
        val root=Files.createTempDirectory("camera-export-test");val demo=legacyReportFixture();val path=root.resolve("saved.camreport")
        durableExport(path,Exchange.export(demo,"Desktop test"));assertEquals(demo,Exchange.read(Files.readAllBytes(path)).report)
        val changed=demo.next("3A","Desktop test");durableExport(path,Exchange.export(changed,"Desktop test"));assertEquals(changed,Exchange.read(Files.readAllBytes(path)).report)
        Files.list(root).use {files ->assertFalse(files.anyMatch {it.fileName.toString().startsWith(".camera-stats-export-")})}
    }
}
