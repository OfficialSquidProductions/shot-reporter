import XCTest
import Foundation
import CSQLite
@testable import CameraStatsCore
@testable import CameraStats

final class TrashCleanupTests:XCTestCase {
    final class Clock {var date=Date(timeIntervalSince1970:1_800_000_000)}
    func root() throws ->URL {let p=FileManager.default.temporaryDirectory.appendingPathComponent("ShotReporterTest-trash-"+UUID().uuidString);try FileManager.default.createDirectory(at:p,withIntermediateDirectories:true);addTeardownBlock{try? FileManager.default.removeItem(at:p)};return p}
    func sql(_ path:URL,_ statement:String) throws {var db:OpaquePointer?;XCTAssertEqual(sqlite3_open(path.path,&db),SQLITE_OK);defer{sqlite3_close(db)};XCTAssertEqual(sqlite3_exec(db,statement,nil,nil,nil),SQLITE_OK)}
    @discardableResult func add(_ repo:Repository,_ slot:String=UUID().uuidString) throws ->(String,String) {let hash=try repo.save(slot:slot,report:.demo(),device:"Synthetic",expectedFingerprint:nil);return (slot,hash)}
    func testExactAgeBoundaryAndActiveSnapshotsStayUnchanged() throws {
        let clock=Clock(),repo=try Repository(url:root().appendingPathComponent("reports.sqlite3"),now:{clock.date})
        let (deleted,hash)=try add(repo);_=try repo.delete(deleted,expectedFingerprint:hash)
        let (active,activeHash)=try add(repo);let current=try repo.load(active)
        clock.date.addTimeInterval(Repository.trashRetention-1);XCTAssertEqual(try repo.cleanupExpiredTrash(),0)
        clock.date.addTimeInterval(1);XCTAssertEqual(try repo.cleanupExpiredTrash(),1)
        XCTAssertEqual(try repo.load(active).fingerprint,activeHash);XCTAssertEqual(try repo.load(active).report,current.report);XCTAssertEqual(try repo.active(),active)
        XCTAssertTrue(try repo.trash().isEmpty);XCTAssertThrowsError(try repo.restoreDeleted(deleted));XCTAssertTrue(try repo.knownSlots().contains(deleted))
        XCTAssertThrowsError(try repo.save(slot:deleted,report:.demo(),device:"Stale",expectedFingerprint:nil))
    }
    func testClockRollbackAndRestoredReportsNeverExpire() throws {
        let clock=Clock(),repo=try Repository(url:root().appendingPathComponent("reports.sqlite3"),now:{clock.date})
        let (id,hash)=try add(repo);_=try repo.delete(id,expectedFingerprint:hash)
        clock.date.addTimeInterval(-100_000);XCTAssertEqual(try repo.cleanupExpiredTrash(),0)
        _=try repo.restoreDeleted(id);clock.date.addTimeInterval(Repository.trashRetention*10)
        XCTAssertEqual(try repo.cleanupExpiredTrash(),0);XCTAssertEqual(try repo.load(id).fingerprint,hash)
    }
    func testManualClearRequiresExactSnapshotAndRejectsRestoreRedeleteAtSameClock() throws {
        let clock=Clock(),repo=try Repository(url:root().appendingPathComponent("reports.sqlite3"),now:{clock.date})
        let (id,hash)=try add(repo);_=try repo.delete(id,expectedFingerprint:hash);let request=try repo.trash()
        _=try repo.restoreDeleted(id);_=try repo.delete(id,expectedFingerprint:hash)
        XCTAssertThrowsError(try repo.clearTrash(expected:request));XCTAssertEqual(try repo.trash().count,1)
        let (other,otherHash)=try add(repo);let currentRequest=try repo.trash();_=try repo.delete(other,expectedFingerprint:otherHash)
        XCTAssertThrowsError(try repo.clearTrash(expected:currentRequest));XCTAssertEqual(try repo.trash().count,2)
        XCTAssertEqual(try repo.clearTrash(expected:repo.trash()),2)
    }
    func testInterruptedPurgeRollsBackAllAndActiveCorruptionFailsClosed() throws {
        let path=try root().appendingPathComponent("reports.sqlite3"),clock=Clock(),repo=try Repository(url:path,now:{clock.date})
        let (id,hash)=try add(repo);_=try repo.delete(id,expectedFingerprint:hash);let request=try repo.trash()
        XCTAssertThrowsError(try repo.purge(expected:request,expiredOnly:false,failBeforeCommit:true));XCTAssertEqual(try repo.trash(),request)
        try sql(path,"INSERT OR REPLACE INTO metadata VALUES('active','\(id)')")
        clock.date.addTimeInterval(Repository.trashRetention+1)
        XCTAssertThrowsError(try repo.cleanupExpiredTrash());XCTAssertEqual(try repo.trash(),request)
    }
    func testSchemaTwoMigrationGrantsExistingTrashFullGracePeriod() throws {
        let path=try root().appendingPathComponent("reports.sqlite3"),id=UUID().uuidString,clock=Clock()
        let expected=Report.demo();let payload=try Exchange.export(expected,device:"Legacy synthetic").map{String(format:"%02x",$0)}.joined()
        try sql(path,"CREATE TABLE documents(slot TEXT PRIMARY KEY,title TEXT NOT NULL,revision INTEGER NOT NULL,current BLOB NOT NULL,previous BLOB,deleted INTEGER NOT NULL DEFAULT 0); CREATE TABLE metadata(key TEXT PRIMARY KEY,value TEXT NOT NULL); INSERT INTO documents VALUES('\(id)','Legacy trash',0,X'\(payload)',X'\(payload)',1); PRAGMA user_version=2;")
        let repo=try Repository(url:path,now:{clock.date});XCTAssertEqual(try repo.trash().first?.deletedAt,clock.date)
        XCTAssertEqual(try repo.cleanupExpiredTrash(),0);clock.date.addTimeInterval(Repository.trashRetention-1);XCTAssertEqual(try repo.cleanupExpiredTrash(),0)
        _=try repo.restoreDeleted(id);XCTAssertEqual(try repo.load(id,previous:true).report,expected)
    }
    @MainActor func testStoreCleanupIsGuardedAndPurgedLegacyNeverReimports() throws {
        let root=try root(),clock=Clock(),id=UUID().uuidString,prefs=try XCTUnwrap(UserDefaults(suiteName:"ShotReporterTest-trash-"+UUID().uuidString))
        let bytes=try Exchange.export(.demo(),device:"Synthetic legacy backup");try bytes.write(to:root.appendingPathComponent(id+".camreport"))
        let store=Store(root:root,preferences:prefs,now:{clock.date});store.deleteReport(try store.deletionRequest(for:id));let request=try store.trashRequest()
        store.pendingImport=true;clock.date.addTimeInterval(Repository.trashRetention);store.cleanupExpiredTrash();store.clearTrash(request)
        XCTAssertEqual(store.deletedDocuments.count,1);store.pendingImport=false;store.error=nil;store.cleanupExpiredTrash();XCTAssertTrue(store.deletedDocuments.isEmpty)
        let restarted=Store(root:root,preferences:prefs,now:{clock.date});XCTAssertTrue(restarted.documents.isEmpty);XCTAssertTrue(restarted.deletedDocuments.isEmpty)
        XCTAssertEqual(try Data(contentsOf:root.appendingPathComponent(id+".camreport")),bytes) // independent recovery file intentionally preserved
        restarted.open(try Exchange.read(bytes).report);XCTAssertEqual(restarted.report,try Exchange.read(bytes).report);XCTAssertNotEqual(restarted.slot,id)
    }
}
