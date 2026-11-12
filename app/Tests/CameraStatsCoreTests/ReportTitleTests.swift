import XCTest
import Foundation
@testable import CameraStatsCore
@testable import CameraStats

final class ReportTitleTests:XCTestCase {
    func testNamesUseProductionTitleWithoutChangingStoredOrExportedData()throws {
        var report=Report.fullHandoffFixture();report.values["title"]="  Café / カメラ 🎬  "
        let before=try Exchange.encoder().encode(report),identity=report.id,revision=report.revision,template=report.namingTemplate
        XCTAssertEqual(report.displayTitle,"Café / カメラ 🎬")
        XCTAssertEqual(report.values["title"],"  Café / カメラ 🎬  ")
        XCTAssertEqual(try Exchange.encoder().encode(report),before);XCTAssertEqual(report.id,identity);XCTAssertEqual(report.revision,revision);XCTAssertEqual(report.namingTemplate,template)
        XCTAssertEqual(try Exchange.read(Exchange.export(report,device:"QA")).report,report)
    }
    func testMissingEmptyAndWhitespaceTitlesHaveSafePresentationFallback()throws {
        var report=Report()
        for title:String? in [nil,"","  \t\r\n","\u{00a0}\u{2003}"] {
            report.values["title"]=title;let before=try Exchange.encoder().encode(report)
            XCTAssertEqual(report.displayTitle,"Untitled production");XCTAssertEqual(Report.displayTitle(title),"Untitled production")
            XCTAssertEqual(try Exchange.encoder().encode(report),before)
        }
    }
    @MainActor func testRenameFollowsActiveSavedImportedAndRestoredReportWithoutChangingIdentity()async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("ShotReporterTest-title-"+UUID().uuidString),suite="ShotReporterTest-title-"+UUID().uuidString,prefs=UserDefaults(suiteName:suite)!
        defer{try? FileManager.default.removeItem(at:root);prefs.removePersistentDomain(forName:suite)}
        let store=Store(root:root,preferences:prefs),original=Report.fullHandoffFixture();store.open(original)
        let slot=store.slot,id=store.report.id,entries=store.report.entries,template=store.report.namingTemplate,oldRevision=store.report.revision
        store.change("Changed production title"){$0.values["title"]="Renamed production"}
        XCTAssertEqual(store.report.displayTitle,"Renamed production");XCTAssertEqual(store.documents.first{$0.0==slot}?.1,"Renamed production · r\(oldRevision+1)")
        XCTAssertEqual(store.slot,slot);XCTAssertEqual(store.report.id,id);XCTAssertEqual(store.report.entries,entries);XCTAssertEqual(store.report.namingTemplate,template)
        let reopened=Store(root:root,preferences:prefs);XCTAssertEqual(reopened.report.displayTitle,"Renamed production");XCTAssertEqual(reopened.slot,slot)
        let repo=try Repository(url:root.appendingPathComponent("reports.sqlite3"));XCTAssertEqual(try repo.load(slot,previous:true).report,original)
        reopened.change{$0.values["title"]="\n  "};XCTAssertEqual(reopened.report.displayTitle,"Untitled production");XCTAssertEqual(reopened.documents.first{$0.0==slot}?.1,"Untitled production · r\(oldRevision+2)")
        let request=try reopened.deletionRequest(for:slot);XCTAssertEqual(request.title,"Untitled production");reopened.deleteReport(request);XCTAssertEqual(reopened.deletedDocuments.first?.1,"Untitled production · r\(oldRevision+2)")
        reopened.restoreDeletedReport(slot);XCTAssertEqual(reopened.report.id,id);XCTAssertEqual(reopened.report.displayTitle,"Untitled production");XCTAssertEqual(reopened.report.values["title"],"\n  ")
        reopened.open(try Exchange.read(Exchange.export(original,device:"iPhone QA")).report);XCTAssertEqual(reopened.report.displayTitle,original.values["title"]);XCTAssertNotEqual(reopened.slot,slot);reopened.select(slot);XCTAssertEqual(reopened.report.displayTitle,"Untitled production")
    }
}
