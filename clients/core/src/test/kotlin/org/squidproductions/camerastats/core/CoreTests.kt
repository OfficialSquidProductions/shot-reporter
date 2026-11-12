package org.squidproductions.camerastats.core

import kotlin.test.*
import org.junit.jupiter.api.Test
import java.io.File
import kotlinx.serialization.json.*

class CoreTests {
    private fun fixture(name:String="swift-demo")=File(System.getProperty("fixtures"),"$name.camreport").readBytes()
    @Test fun movieModeHidesTVMetadataWithoutErasingDigitalReportData() {
        val report=Report(values=mapOf("season" to "2","episode" to "7"),defaults=Report().defaults+("roll" to "A009"))
        assertEquals(ProductionMode.MOVIE,report.productionMode);assertFalse(report.projectFields.any {it.id=="season" || it.id=="episode"});assertFalse(Schema.settings.any {it.id=="roll"});assertNull(Report().defaults["roll"])
        assertFalse(Reports.html(report).contains("season:"));assertFalse(Reports.printable(report).any {it.startsWith("Season:")})
        val tv=report.withProductionMode(ProductionMode.TV);assertTrue(Reports.printable(tv).any {it=="Season: 2"})
        val restored=Exchange.read(Exchange.export(tv.withProductionMode(ProductionMode.MOVIE),"Test")).report
        assertEquals("2",restored.values["season"]);assertEquals("7",restored.values["episode"]);assertEquals("A009",restored.defaults["roll"])
    }
    @Test fun swiftGoldenRoundtripAndKotlinExport() {
        val original=Exchange.read(fixture()).report
        assertEquals(3,original.active.size);assertEquals(listOf("MOS","Tail slate"),original.entries.first().flags)
        assertTrue(original.values.getValue("unicodeTest").contains("カメラ"))
        val bytes=Exchange.export(original,"JVM conformance fixture");assertEquals(original,Exchange.read(bytes).report)
        val folder=File("build/conformance").apply { mkdirs() };File(folder,"kotlin-roundtrip.camreport").writeBytes(bytes)
        val changed=original.next("8B","JVM conformance fixture");File(folder,"kotlin-edited.camreport").writeBytes(Exchange.export(changed,"JVM conformance fixture"))
    }
    @Test fun longTakeLabelsMatchSwiftIntegerRangeWithoutOverflow() {
        val report=Exchange.read(fixture()).report;val entry=report.entries.first().copy(values=report.entries.first().values+("take" to "9223372036854775806"));val base=report.copy(entries=listOf(entry))
        val next=base.next("3A","Test");assertEquals("9223372036854775807",next.entries.last().values["take"]);assertFails {next.next("3A","Test")}
        assertFails {base.copy(revision=Long.MAX_VALUE).record("Test","Test")}
    }
    @Test fun legacyDemoMetadataRemainsOpaqueAndRoundtrips() {
        val legacy=Exchange.decode(File(System.getProperty("fixtures"),"owner-demo.json").readBytes())
        val edited=legacy.next("3A","Compatibility test")
        val restored=Exchange.read(Exchange.export(edited,"Compatibility test")).report
        assertEquals(edited,restored)
        assertEquals(legacy.values.getValue("demoScript"),restored.values["demoScript"])
        assertEquals(legacy.values.getValue("demoShotPlan"),restored.values["demoShotPlan"])
    }
    @Test fun nextTakeUsesCameraAndKeepsEarlierSnapshots() {
        val old=Exchange.read(fixture()).report;val updated=old.copy(defaults=old.defaults+("iso" to "1600")).next("3A","Test")
        assertEquals("4",updated.active.last().values["take"]);assertEquals("1600",updated.active.last().values["iso"]);assertEquals(old.entries,updated.entries.dropLast(1))
        assertEquals("1",updated.copy(defaults=updated.defaults+("camera" to "B")).next("3A","Test").active.last().values["take"])
    }
    @Test fun recordingSettingsCarryForwardResetAndRoundtrip() {
        var report=Report().next("12B","Test")
        val first=report.entries.first().id
        report=report.setRecordingSetting("iso","800",first).next("12B","Test")
        report=report.setRecordingSetting("iso","1600",report.entries.last().id)
        assertEquals("800",report.entries.first().values["iso"])
        report=Exchange.read(Exchange.export(report,"Test")).report.next("13","Test")
        assertEquals("1600",report.entries.last().values["iso"])
        val recorded=report.entries
        report=report.returnToDefaults()
        assertEquals("A",report.defaults["camera"])
        assertNull(report.defaults["iso"])
        assertEquals(recorded,report.entries)
        assertNull(report.next("13","Test").entries.last().values["iso"])
        assertEquals(report,report.setRecordingSetting("iso","3200","missing"))
    }
    @Test fun conservativeMergeAndIdempotenceMatchSwift() {
        val base=Exchange.read(fixture()).report;val incoming=Exchange.read(fixture("swift-additions"));val preview=Exchange.preview(base,incoming)
        assertEquals(1,preview.additions.size);assertTrue(preview.conflicts.isEmpty())
        val merged=Exchange.merge(base,incoming,"Test");assertEquals(4,merged.active.size);assertEquals(merged,Exchange.merge(merged,incoming,"Test"))
        val conflict=Exchange.read(fixture("swift-conflict"));assertTrue(Exchange.preview(base,conflict).conflicts.isNotEmpty());assertFails { Exchange.merge(base,conflict,"Test") }
        val tombstone=Exchange.read(fixture("swift-tombstone"));assertTrue(Exchange.preview(base,tombstone).conflicts.isNotEmpty())
        assertFails { Exchange.preview(base.copy(id=identity()),incoming) }
    }
    @Test fun corruptUnsafeAndUnsupportedPackagesAreRejected() {
        val archive=fixture();val files=StoredZIP.read(archive)
        val crc=archive.copyOf();crc[100]=(crc[100].toInt() xor 1).toByte();assertFails { Exchange.read(crc) }
        val compression=archive.copyOf();compression[8]=8;assertFails { Exchange.read(compression) }
        val encrypted=archive.copyOf();encrypted[6]=1;assertFails { Exchange.read(encrypted) }
        assertFails { Exchange.read(archive.copyOf(archive.size-1)) };assertFails { Exchange.read(archive+byteArrayOf(0)) }
        assertFails { Exchange.read(StoredZIP.write(mapOf("../report.json" to files.getValue("report.json")))) }
        val manifest=Exchange.json.parseToJsonElement(files.getValue("manifest.json").toString(Charsets.UTF_8)).jsonObject
        val schema=JsonObject(manifest+("schema" to JsonPrimitive(99))).toString().toByteArray()
        assertFails { Exchange.read(StoredZIP.write(files+("manifest.json" to schema))) }
        val body=Exchange.json.parseToJsonElement(files.getValue("report.json").toString(Charsets.UTF_8)).jsonObject
        val future=JsonObject(body+("futureField" to JsonPrimitive("must not be lost"))).toString().toByteArray()
        val correctedManifest=JsonObject(manifest+("sha256" to JsonPrimitive(Exchange.digest(future)))).toString().toByteArray()
        assertFails { Exchange.read(StoredZIP.write(files+mapOf("manifest.json" to correctedManifest,"report.json" to future))) }
    }
    @Test fun boundsAndDuplicateRecordsAreRejected() {
        val archive=fixture();val huge=archive.copyOf();for(i in 18..21) huge[i]=0xff.toByte();assertFails { Exchange.read(huge) }
        for(size in listOf(0,1,21,32,100,archive.size-5)) assertFails { Exchange.read(archive.copyOf(size)) }
        val r=Exchange.read(archive).report;assertFails { Exchange.read(Exchange.export(r.copy(entries=r.entries+ r.entries.first()),"Test")) }
    }
    @Test fun unicodeEscapingAndLongNotes() {
        val report=Exchange.read(fixture()).report;val e=report.entries.first().copy(values=report.entries.first().values+("remarks" to "a,\"b\"\n<script>alert(1)</script> カメラ"));val r=report.copy(entries=listOf(e))
        assertTrue(Reports.csv(r).contains("\"a,\"\"b\"\""));assertTrue(Reports.html(r).contains("&lt;script&gt;"));assertFalse(Reports.html(r).contains("<script>"))
        assertTrue(Reports.printable(r).joinToString("\n").contains("カメラ"))
        val long=r.copy(entries=listOf(e.copy(values=e.values+("remarks" to "Long note ".repeat(10000)+"FINAL-MARKER"))))
        assertTrue(Reports.printable(long).last { it.startsWith("Camera remarks:") }.endsWith("FINAL-MARKER"))
    }
    @Test fun legacyCompatibilityDataSurvivesReportEditsAndExports() {
        val legacy=Exchange.read(fixture()).report.copy(namingTemplate="legacy {opaque} value")
        val restored=Exchange.read(Exchange.export(legacy,"Compatibility test")).report
        val edited=restored.next("3A","Compatibility test")
        assertEquals(legacy.namingTemplate,Exchange.read(Exchange.export(edited,"Compatibility test")).report.namingTemplate)
        val competing=Exchange.read(Exchange.export(legacy.copy(namingTemplate="other legacy value"),"Compatibility test"))
        assertTrue(Exchange.preview(legacy,competing).conflicts.isNotEmpty())
        assertFails {Exchange.merge(legacy,competing,"Compatibility test")}
    }
    @Test fun thousandTakeAppleFixtureRetainsFields() {
        val r=Exchange.read(fixture("swift-1000-takes")).report;assertEquals(1000,r.active.size);assertEquals(r,Exchange.read(Exchange.export(r,"Scale fixture")).report)
    }
}
