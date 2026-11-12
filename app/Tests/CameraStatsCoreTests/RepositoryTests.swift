import XCTest
import Foundation
import PDFKit
@testable import CameraStatsCore
@testable import CameraStats

final class RepositoryTests:XCTestCase {
    func temporary() throws ->URL {let root=FileManager.default.temporaryDirectory.appendingPathComponent("CameraStatsTests-"+UUID().uuidString); try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true); addTeardownBlock{try? FileManager.default.removeItem(at:root)}; return root}
    @MainActor func testRebrandReadsOriginalCameraStatsDatabaseWithoutRewritingReports() throws {
        let url=try XCTUnwrap(Bundle.module.url(forResource:"LegacyRebrand",withExtension:"json",subdirectory:"Fixtures"))
        let fixture=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:String])
        XCTAssertEqual(fixture["sourceCommit"],"fe51b582742d036bb1c4bae09d2df3497777675c")
        let root=try temporary(), db=root.appendingPathComponent("reports.sqlite3")
        try XCTUnwrap(Data(base64Encoded:try XCTUnwrap(fixture["sqlite"]))).write(to:db)
        let expected=try Exchange.read(XCTUnwrap(Data(base64Encoded:try XCTUnwrap(fixture["expectedPackage"])))).report
        let prefs=try XCTUnwrap(UserDefaults(suiteName:"ShotReporterRebrandTest-"+UUID().uuidString));prefs.set("Dark",forKey:"theme")
        let store=Store(root:root,preferences:prefs)
        XCTAssertFalse(store.blocked);XCTAssertNil(store.error);XCTAssertEqual(store.report,expected)
        XCTAssertEqual(store.documents.count,1);XCTAssertEqual(store.slot,"10000000-0000-4000-8000-000000000001")
        XCTAssertEqual(prefs.string(forKey:"theme"),"Dark")
        let repo=try Repository(url:db);XCTAssertEqual(try repo.load(store.slot,previous:true).report.active.count,3)
        XCTAssertEqual(try Exchange.read(Exchange.export(store.report,device:"Shot Reporter fixture")).report,expected)
        let pdf=try Reports.pdf(store.report);XCTAssertTrue(PDFKit.PDFDocument(data:pdf)?.string?.contains("Shot Reporter") == true)
    }
    func testCommitReopenPreviousAndIndependentSlots() throws {
        let url=try temporary().appendingPathComponent("reports.sqlite3"), slot=UUID().uuidString, other=UUID().uuidString
        var r=Report.demo(); var hash:String
        do {let repo=try Repository(url:url); hash=try repo.save(slot:slot,report:r,device:"Test",expectedFingerprint:nil); r.values["title"]="Accepted revision"; r.record("Changed title",device:"Test"); hash=try repo.save(slot:slot,report:r,device:"Test",expectedFingerprint:hash); XCTAssertEqual(try repo.active(),slot); XCTAssertEqual(try repo.load(slot,previous:true).report.values["title"],"The Last Light · DEMO")}
        let reopened=try Repository(url:url); XCTAssertEqual(try reopened.load(slot).report,r); XCTAssertEqual(try reopened.load(slot).fingerprint,hash)
        _=try reopened.save(slot:other,report:.demo(),device:"Other",expectedFingerprint:nil); XCTAssertEqual(try reopened.list().count,2); XCTAssertEqual(try reopened.load(slot).report,r)
    }
    func testInterruptedTransactionRollsBackDataAndActiveSelection() throws {
        let repo=try Repository(url:temporary().appendingPathComponent("reports.sqlite3")), slot=UUID().uuidString
        let original=Report.demo(), hash=try repo.save(slot:slot,report:original,device:"Test",expectedFingerprint:nil)
        var changed=original; changed.values["title"]="Must not commit"; changed.record("Change",device:"Test")
        XCTAssertThrowsError(try repo.save(slot:slot,report:changed,device:"Test",expectedFingerprint:hash,failBeforeCommit:true))
        XCTAssertEqual(try repo.load(slot).report,original); XCTAssertEqual(try repo.load(slot).fingerprint,hash)
        let failedSlot=UUID().uuidString
        XCTAssertThrowsError(try repo.save(slot:failedSlot,report:changed,device:"Test",expectedFingerprint:nil,failBeforeCommit:true))
        XCTAssertEqual(try repo.active(),slot); XCTAssertEqual(try repo.list().count,1)
    }
    func testTwoConnectionsRejectStaleOverwrite() throws {
        let url=try temporary().appendingPathComponent("reports.sqlite3"), slot=UUID().uuidString
        let a=try Repository(url:url), b=try Repository(url:url); let original=Report.demo(), hash=try a.save(slot:slot,report:original,device:"A",expectedFingerprint:nil)
        var changed=original; changed.values["title"]="Accepted A"; changed.record("Change",device:"A"); _=try a.save(slot:slot,report:changed,device:"A",expectedFingerprint:hash)
        XCTAssertThrowsError(try b.save(slot:slot,report:original,device:"B",expectedFingerprint:hash)); XCTAssertEqual(try b.load(slot).report,changed)
    }
    func testDatabaseFullRollsBackAcceptedSnapshot() throws {
        let repo=try Repository(url:temporary().appendingPathComponent("reports.sqlite3")), slot=UUID().uuidString
        let original=Report.demo(), hash=try repo.save(slot:slot,report:original,device:"Test",expectedFingerprint:nil)
        try repo.capDatabasePagesForTesting(1)
        var changed=original; changed.entries[0].values["remarks"]=String(repeating:"low-storage-fixture ",count:50000); changed.record("Must fail",device:"Test")
        XCTAssertThrowsError(try repo.save(slot:slot,report:changed,device:"Test",expectedFingerprint:hash))
        XCTAssertEqual(try repo.load(slot).report,original); XCTAssertEqual(try repo.active(),slot)
    }
    func testInvalidSlotsAndCorruptDatabasePreserveBytes() throws {
        let root=try temporary(), url=root.appendingPathComponent("reports.sqlite3"), bytes=Data("not a database — do not replace".utf8)
        try bytes.write(to:url); XCTAssertThrowsError(try Repository(url:url)); XCTAssertEqual(try Data(contentsOf:url),bytes)
        let repo=try Repository(url:root.appendingPathComponent("good.sqlite3")); XCTAssertThrowsError(try repo.save(slot:"../escape",report:.demo(),device:"Test",expectedFingerprint:nil))
    }
    @MainActor func testNativeStoreMigrationAndRestart() async throws {
        let root=try temporary(), slot=UUID().uuidString, prefs=UserDefaults(suiteName:"CameraStatsTests-"+UUID().uuidString)!, original=Report.demo()
        let legacy=root.appendingPathComponent(slot+".camreport"), data=try Exchange.export(original,device:"Legacy")
        try data.write(to:legacy); prefs.set(slot,forKey:"activeReport")
        let store=Store(root:root,preferences:prefs); XCTAssertFalse(store.blocked); XCTAssertEqual(store.report,original)
        store.change("Native saved edit"){$0.values["title"]="Native persisted title"}
        XCTAssertNil(store.error); let accepted=store.report
        let reopened=Store(root:root,preferences:prefs); XCTAssertEqual(reopened.report,accepted); XCTAssertEqual(try Data(contentsOf:legacy),data)
        await reopened.restore(); XCTAssertEqual(reopened.report.values["title"],original.values["title"]); XCTAssertNotEqual(reopened.slot,slot)
    }
    @MainActor func testNativeStoreFailedSaveDoesNotAcceptEdit() async throws {
        let root=try temporary(), prefs=UserDefaults(suiteName:"CameraStatsTests-"+UUID().uuidString)!, a=Store(root:root,preferences:prefs)
        a.open(.demo()); let before=a.report, b=Store(root:root,preferences:prefs)
        b.change{$0.values["title"]="Other accepted title"}; XCTAssertNil(b.error)
        a.change{$0.values["title"]="Rejected stale title"}; XCTAssertNotNil(a.error); XCTAssertEqual(a.report,before)
        let restarted=Store(root:root,preferences:prefs); XCTAssertEqual(restarted.report.values["title"],"Other accepted title")
    }
    func testNativeFileDocumentExportsAreExactAndOpenable() throws {
        let report=Report.demo(), archive=try Exchange.export(report,device:"Native export test"), document=ExportFile(data:archive)
        let wrapper=document.makeFileWrapper()
        XCTAssertEqual(wrapper.regularFileContents,archive)
        let root=try temporary(), output=root.appendingPathComponent("The-Last-Light.camreport")
        try wrapper.write(to:output,options:.atomic,originalContentsURL:nil)
        XCTAssertEqual(try Exchange.read(Data(contentsOf:output)).report,report)
        let pdf=ExportFile(data:try Reports.pdf(report)); let pdfWrapper=pdf.makeFileWrapper(); XCTAssertTrue(pdfWrapper.regularFileContents?.starts(with:Data("%PDF-".utf8)) == true)
    }
}
