import XCTest
import PDFKit
@testable import CameraStatsCore

final class CoreTests: XCTestCase {
    func testOwnerDemoUsesProductionDeskScriptAndIndependentIdentity() {
        let a = Report.demo(), b = Report.demo()
        XCTAssertTrue(a.values["title",default:""].contains("The Last Light")); XCTAssertNotEqual(a.id,b.id)
        XCTAssertEqual(a.active.count,3); XCTAssertEqual(Set(a.active.compactMap{$0.values["scene"]}),["3A"])
        XCTAssertEqual(a.active.filter{$0.flags.contains("Circle")}.map{$0.values["take"]},["2"])
        XCTAssertEqual(a.values["demoScriptSHA256"],"84b4bea90b72a1d3d09be8925b07cdf696e9bc579386ed21c3255bb305336f87")
        XCTAssertTrue(a.values["demoShotPlan",default:""].contains("8B · B camera · 24mm"))
        XCTAssertTrue(a.active.contains{$0.values["continuity",default:""].contains("brass key")})
    }
    func testDemoPDFExportAndRender() throws {
        let data=try Reports.pdf(.demo()), pdf=try XCTUnwrap(PDFDocument(data:data))
        XCTAssertGreaterThan(pdf.pageCount,1); XCTAssertTrue(pdf.string?.contains("The Last Light") == true)
        try data.write(to:URL(fileURLWithPath:"/tmp/camerastats-demo.pdf"))
        let image=try XCTUnwrap(pdf.page(at:0)).thumbnail(of:CGSize(width:1684,height:1190),for:.mediaBox)
        #if os(macOS)
        let rep=try XCTUnwrap(NSBitmapImageRep(data:try XCTUnwrap(image.tiffRepresentation)))
        try XCTUnwrap(rep.representation(using:.png,properties:[:])).write(to:URL(fileURLWithPath:"/tmp/camerastats-demo-page1.png"))
        #endif
    }
    func testSnapshotAndCameraTakeProgression() {
        var r = Report.fixture(); let old = r.entries[0].values
        r.defaults["iso"] = "1600"; _ = r.next(scene:"12B",device:"Test")
        XCTAssertEqual(r.entries[0].values,old); XCTAssertEqual(r.entries.last?.values["iso"],"1600"); XCTAssertEqual(r.entries.last?.values["take"],"4")
        r.defaults["camera"] = "B"; _ = r.next(scene:"12B",device:"Test"); XCTAssertEqual(r.entries.last?.values["take"],"1")
    }
    func testRecordingSettingsCarryForwardResetAndRoundtrip() throws {
        var report = Report()
        let first = report.next(scene:"12B",device:"Test")
        report.setRecordingSetting("iso",value:"800",takeID:first)
        report.entries[0].reviewed = true
        let second = report.next(scene:"12B",device:"Test")
        report.setRecordingSetting("iso",value:"1600",takeID:second)
        XCTAssertEqual(report.entries[0].values["iso"],"800")
        XCTAssertTrue(report.entries[0].reviewed)
        XCTAssertFalse(report.entries[1].reviewed)
        report = try Exchange.read(Exchange.export(report,device:"Test")).report
        _ = report.next(scene:"13",device:"Test")
        XCTAssertEqual(report.entries.last?.values["iso"],"1600")
        let recorded = report.entries
        report.returnToDefaults()
        XCTAssertEqual(report.defaults["camera"],"A")
        XCTAssertEqual(report.defaults["playbackRate"],"24000/1001")
        XCTAssertNil(report.defaults["iso"])
        XCTAssertEqual(report.entries,recorded)
        _ = report.next(scene:"13",device:"Test")
        XCTAssertNil(report.entries.last?.values["iso"])
        let unchanged = report
        report.setRecordingSetting("iso",value:"3200",takeID:"missing")
        XCTAssertEqual(report,unchanged)
    }
    func testPortableArchiveAndIntegrity() throws {
        var r = Report.fixture(); r.entries[0].flags = ["MOS","Circle","Tail slate"]
        let data = try Exchange.export(r,device:"Test")
        XCTAssertEqual(try Exchange.read(data).report,r)
        var broken = data; broken[100] ^= 1; XCTAssertThrowsError(try Exchange.read(broken))
        XCTAssertThrowsError(try Exchange.read(data.dropLast()))
        XCTAssertThrowsError(try Exchange.read(Data(repeating:0,count:Exchange.limit+1)))
        XCTAssertThrowsError(try StoredZIP.read(StoredZIP.write([("../report.json",Data())])))
    }
    func testUnknownSchemaAndFieldsPreservedByRejection() throws {
        let data = try Exchange.export(.fixture(),device:"Test"); let files = try StoredZIP.read(data)
        var manifest = try JSONSerialization.jsonObject(with:files["manifest.json"]!) as! [String:Any]
        manifest["schema"] = 99
        XCTAssertThrowsError(try Exchange.read(StoredZIP.write([("manifest.json",try JSONSerialization.data(withJSONObject:manifest)),("report.json",files["report.json"]!)])))
        manifest["schema"] = 1
        var report = try JSONSerialization.jsonObject(with:files["report.json"]!) as! [String:Any]; report["futureFeature"] = "preserve me"
        let newer = try JSONSerialization.data(withJSONObject:report); manifest["sha256"] = Exchange.digest(newer)
        XCTAssertThrowsError(try Exchange.read(StoredZIP.write([("manifest.json",try JSONSerialization.data(withJSONObject:manifest)),("report.json",newer)])))
    }
    func testMergeAddsWithoutOmissionDeletionAndRepeatIsIdempotent() throws {
        let base = Report.fixture(); var incoming = base; _ = incoming.next(scene:"13",device:"B")
        let p = try Exchange.read(Exchange.export(incoming,device:"B"))
        let merged = try Exchange.mergeAdditions(local:base,incoming:p,device:"A")
        XCTAssertEqual(merged.entries.count,4); XCTAssertEqual(try Exchange.mergeAdditions(local:merged,incoming:p,device:"A"),merged)
        var partial = base; partial.entries.removeLast(); let p2 = try Exchange.read(Exchange.export(partial,device:"B")); XCTAssertEqual(try Exchange.mergeAdditions(local:base,incoming:p2,device:"A").entries.count,3)
    }
    func testConflictingEditDoesNotMutateLocal() throws {
        let base = Report.fixture(); var incoming = base; incoming.entries[0].values["scene"] = "99"
        let p = try Exchange.read(Exchange.export(incoming,device:"B")); XCTAssertEqual(try Exchange.preview(local:base,incoming:p).conflicts.count,1)
        XCTAssertThrowsError(try Exchange.mergeAdditions(local:base,incoming:p,device:"A")); XCTAssertEqual(base.entries[0].values["scene"],"12B")
    }
    func testAllFieldsAndHiddenRequirements() {
        var r = Report.fixture(); let original = r.entries
        r.positions = ["2nd AC"]; XCTAssertEqual(r.entries,original)
        r.entries[0].values["height"] = ""; XCTAssertTrue(r.missing.contains("Row 1: Camera height"))
        XCTAssertTrue(Schema.settings.map(\.id).contains("distance")); XCTAssertTrue(Schema.settings.map(\.id).contains("filters"))
    }
    func testCSVAndHTMLInjectionEscaped() {
        var r = Report.fixture(); r.entries[0].values["remarks"] = "a,\"b\"\n<script>alert(1)</script>"
        XCTAssertTrue(Reports.csv(r).contains("\"a,\"\"b\"\"")); XCTAssertFalse(Reports.html(r).contains("<script>"))
    }
    func testPDFLongNotesContinueWithFlagsAndHeaders() throws {
        var r = Report.fixture(); r.entries[0].values["remarks"] = String(repeating:"Long technical note for continuity. ",count:500) + "FINAL-NOTE-MARKER"; r.entries[0].flags.insert("MOS")
        let data = try Reports.pdf(r); let pdf = try XCTUnwrap(PDFDocument(data:data))
        XCTAssertGreaterThan(pdf.pageCount,2); XCTAssertTrue(pdf.string?.replacingOccurrences(of:"\n",with:"").contains("FINAL-NOTE-MARKER") == true); XCTAssertTrue(pdf.string?.contains("MOS") == true)
        for n in 0..<pdf.pageCount { let page = try XCTUnwrap(pdf.page(at:n)); XCTAssertTrue(page.string?.contains("Revision") == true); XCTAssertEqual(page.bounds(for:.mediaBox).width,842) }
        try data.write(to:URL(fileURLWithPath:"/tmp/camerastats-long-notes.pdf"))
    }
    func testNamingMissingInvalidAndSuffixes() throws {
        let r = Report.fixture(); XCTAssertTrue(try Naming.preview(template:Naming.movie,report:r,entry:r.entries[0]).contains("SC12B"))
        XCTAssertThrowsError(try Naming.preview(template:"{unknown}",report:r,entry:r.entries[0])); XCTAssertThrowsError(try Naming.preview(template:"CON",report:r,entry:r.entries[0])); XCTAssertThrowsError(try Naming.preview(template:"bad/name",report:r,entry:r.entries[0]))
    }
    func testThousandEntryDay() throws {
        var r = Report.fixture(); for _ in 0..<997 { _ = r.next(scene:"1",device:"Scale fixture") }
        let data = try Exchange.export(r,device:"Scale fixture"); XCTAssertEqual(try Exchange.read(data).report.entries.count,1000)
        try data.write(to:URL(fileURLWithPath:"/tmp/camerastats-1000.camreport"))
    }
}
