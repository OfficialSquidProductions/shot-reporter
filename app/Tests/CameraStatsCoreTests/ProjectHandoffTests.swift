import XCTest
import Foundation
import PDFKit
@testable import CameraStatsCore
@testable import CameraStats

final class ProjectHandoffTests:XCTestCase {
    @MainActor func testCompleteProjectPhoneToMacAndBackPreservesEveryModelField() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("ShotReporterTest-handoff-"+UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let original=Report.fullHandoffFixture(),bytes=try Exchange.export(original,device:"Synthetic iPhone")
        let prefs=UserDefaults(suiteName:"ShotReporterTest-handoff-"+UUID().uuidString)!
        let mac=Store(root:root,preferences:prefs);mac.open(try Exchange.read(bytes).report)
        XCTAssertEqual(mac.report,original);XCTAssertEqual(mac.report.entries.count,6);XCTAssertEqual(mac.report.active.count,5)
        let file=ExportFile(data:try Exchange.export(mac.report,device:"Synthetic Mac"));XCTAssertEqual(try Exchange.read(XCTUnwrap(file.makeFileWrapper().regularFileContents)).report,original)
        let phoneEdit=Report.phoneHandoffEdit(try Exchange.read(bytes).report);let returned=try Exchange.export(phoneEdit,device:"Synthetic iPhone return")
        mac.open(try Exchange.read(returned).report);XCTAssertEqual(mac.documents.count,2);XCTAssertEqual(mac.report,phoneEdit)
        let reopened=Store(root:root,preferences:prefs);XCTAssertEqual(reopened.report,phoneEdit)
        let final=try Exchange.read(Exchange.export(reopened.report,device:"Synthetic Mac return")).report
        XCTAssertEqual(final,phoneEdit);XCTAssertEqual(final.namingSettings,original.namingSettings);XCTAssertEqual(final.entries[5],original.entries[5]);XCTAssertEqual(final.values["season"],"2");XCTAssertEqual(final.values["episode"],"7")
        let conflict=try Exchange.preview(local:original,incoming:Exchange.read(returned));XCTAssertFalse(conflict.conflicts.isEmpty)
        XCTAssertThrowsError(try Exchange.mergeAdditions(local:original,incoming:Exchange.read(returned),device:"Test"))
    }
    func testReadablePDFRetainsEveryVisibleFieldAndContinuation() throws {
        var r=Report.fullHandoffFixture();r.productionMode = .tv
        r.entries[0].values["remarks"]=String(repeating:"Continuity and exposure detail remain readable. ",count:100)+" END_OF_LONG_NOTE"
        let data=try Reports.pdf(r),pdf=try XCTUnwrap(PDFDocument(data:data)),text=try XCTUnwrap(pdf.string)
        XCTAssertTrue(text.contains("CAMERA / MEDIA / LENS"));XCTAssertTrue(text.contains("RECORDING SETTINGS"));XCTAssertTrue(text.contains("NOTES / POST REFERENCES"))
        XCTAssertTrue(text.replacingOccurrences(of:"\n",with:"").contains("END_OF_LONG_NOTE"))
        for f in Schema.settings {XCTAssertTrue(text.contains(f.title+":"),"Missing \(f.title)")}
        XCTAssertFalse(text.contains("Camera roll"));XCTAssertTrue(text.contains("Season:"));XCTAssertTrue(text.contains("Episode:"));XCTAssertGreaterThan(pdf.pageCount,6)
        for i in 0..<pdf.pageCount {let page=try XCTUnwrap(pdf.page(at:i));XCTAssertTrue(page.string?.contains("Revision 18") == true);XCTAssertEqual(page.bounds(for:.mediaBox).height,595)}
        if let output=ProcessInfo.processInfo.environment["SHOT_REPORTER_PDF_QA_OUTPUT"] {try data.write(to:URL(fileURLWithPath:output))}
    }
}
