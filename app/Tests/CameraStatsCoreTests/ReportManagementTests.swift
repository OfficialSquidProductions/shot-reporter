import XCTest
import Foundation
import PDFKit
@testable import CameraStatsCore
@testable import CameraStats

final class ReportManagementTests:XCTestCase {
    func root() throws ->URL {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("ShotReporterTest-management-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        addTeardownBlock {try? FileManager.default.removeItem(at:root)};return root
    }
    func testMovieDefaultAndTVRoundTripRetainHiddenLegacyFields() throws {
        var report=Report.demo()
        XCTAssertEqual(report.productionMode,.movie)
        let originalValues=report.values,originalTakes=report.entries,originalDefaults=report.defaults
        XCTAssertFalse(report.projectFields.contains {$0.id == "season" || $0.id == "episode"})
        XCTAssertFalse(Schema.settings.contains {$0.id == "roll"})
        XCTAssertNil(Report().defaults["roll"])
        let moviePDF=try XCTUnwrap(PDFDocument(data:Reports.pdf(report))?.string)
        XCTAssertFalse(moviePDF.contains("Season:"));XCTAssertFalse(moviePDF.contains("Episode:"));XCTAssertFalse(moviePDF.contains("Camera / roll"))
        XCTAssertFalse(Reports.html(report).contains("season:"));XCTAssertFalse(Reports.csv(report).components(separatedBy:"\r\n")[0].contains("\"roll\""))
        report.productionMode = .tv
        let tvPDF=try XCTUnwrap(PDFDocument(data:Reports.pdf(report))?.string)
        XCTAssertTrue(tvPDF.contains("Season:"));XCTAssertTrue(tvPDF.contains("Episode:"))
        XCTAssertTrue(Reports.html(report).contains("season:"))
        report.productionMode = .movie
        let reopened=try Exchange.read(Exchange.export(report,device:"Test")).report
        XCTAssertEqual(reopened.productionMode,.movie)
        XCTAssertEqual(reopened.values["season"],originalValues["season"]);XCTAssertEqual(reopened.values["episode"],originalValues["episode"])
        XCTAssertEqual(reopened.entries,originalTakes);XCTAssertEqual(reopened.defaults,originalDefaults)
    }
    func testDeleteRestoresExactCurrentPreviousAndSelectionAfterRestart() throws {
        let path=try root().appendingPathComponent("reports.sqlite3"),first=UUID().uuidString,second=UUID().uuidString
        var report=Report.demo();let original=report
        do {
            let repo=try Repository(url:path)
            let hash=try repo.save(slot:first,report:report,device:"Test",expectedFingerprint:nil)
            report.values["title"]="Updated report";report.record("Edit",device:"Test")
            let next=try repo.save(slot:first,report:report,device:"Test",expectedFingerprint:hash)
            _=try repo.save(slot:second,report:Report(),device:"Test",expectedFingerprint:nil);_=try repo.select(first)
            XCTAssertEqual(try repo.delete(first,expectedFingerprint:next)?.slot,second)
            XCTAssertEqual(try repo.list().map(\.slot),[second]);XCTAssertEqual(try repo.list(deleted:true).map(\.slot),[first])
            XCTAssertThrowsError(try repo.load(first));XCTAssertThrowsError(try repo.save(slot:first,report:report,device:"Stale app",expectedFingerprint:next))
        }
        let reopened=try Repository(url:path)
        let restored=try reopened.restoreDeleted(first)
        XCTAssertEqual(restored.report,report);XCTAssertEqual(try reopened.load(first,previous:true).report,original)
        XCTAssertEqual(try reopened.active(),first);XCTAssertTrue(try reopened.list(deleted:true).isEmpty)
    }
    func testDeletingInactiveReportLeavesCurrentSelectionAndSnapshotsAlone() throws {
        let repo=try Repository(url:root().appendingPathComponent("reports.sqlite3")),first=UUID().uuidString,second=UUID().uuidString
        let report=Report.demo(),hash=try repo.save(slot:first,report:report,device:"Test",expectedFingerprint:nil)
        let selected=Report();let selectedHash=try repo.save(slot:second,report:selected,device:"Test",expectedFingerprint:nil)
        XCTAssertEqual(try repo.delete(first,expectedFingerprint:hash)?.slot,second)
        XCTAssertEqual(try repo.active(),second);XCTAssertEqual(try repo.load(second).fingerprint,selectedHash)
        XCTAssertEqual(try repo.restoreDeleted(first).report,report);XCTAssertEqual(try repo.load(second).fingerprint,selectedHash)
    }
    func testDeleteRejectsStaleConfirmationAndRollsBackFailure() throws {
        let path=try root().appendingPathComponent("reports.sqlite3"),slot=UUID().uuidString
        let repo=try Repository(url:path),other=try Repository(url:path);var report=Report.demo()
        let old=try repo.save(slot:slot,report:report,device:"Test",expectedFingerprint:nil)
        report.values["title"]="Newer edit";let next=try other.save(slot:slot,report:report,device:"Other",expectedFingerprint:old)
        XCTAssertThrowsError(try repo.delete(slot,expectedFingerprint:old))
        XCTAssertThrowsError(try repo.delete(slot,expectedFingerprint:next,failBeforeCommit:true))
        XCTAssertEqual(try repo.load(slot).report,report);XCTAssertEqual(try repo.active(),slot);XCTAssertTrue(try repo.list(deleted:true).isEmpty)
    }
    @MainActor func testDeleteLastLegacyReportDoesNotReimportOrResurrectIt() throws {
        let root=try root(),slot=UUID().uuidString,legacy=root.appendingPathComponent(slot+".camreport")
        let data=try Exchange.export(Report.demo(),device:"Legacy");try data.write(to:legacy)
        let prefs=try XCTUnwrap(UserDefaults(suiteName:"ShotReporterTest-management-"+UUID().uuidString))
        let store=Store(root:root,preferences:prefs);let request=try store.deletionRequest(for:slot)
        store.pendingImport=true;store.deleteReport(request);XCTAssertEqual(store.documents.count,1)
        store.pendingImport=false;store.error=nil;store.deleteReport(request)
        XCTAssertTrue(store.documents.isEmpty);XCTAssertEqual(store.deletedDocuments.count,1);XCTAssertNil(store.saved)
        let restarted=Store(root:root,preferences:prefs)
        XCTAssertTrue(restarted.documents.isEmpty);XCTAssertEqual(restarted.deletedDocuments.count,1);XCTAssertEqual(try Data(contentsOf:legacy),data)
        restarted.restoreDeletedReport(slot);XCTAssertEqual(restarted.report,try Exchange.read(data).report)
        let before=try Repository(url:root.appendingPathComponent("reports.sqlite3")).load(slot).fingerprint
        restarted.change {$0.values["title"]=$0.values["title"]}
        XCTAssertEqual(try Repository(url:root.appendingPathComponent("reports.sqlite3")).load(slot).fingerprint,before)
    }
}
