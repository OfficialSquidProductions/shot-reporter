import XCTest
import Foundation
@testable import CameraStatsCore
@testable import CameraStats

final class CompleteArchiveTests:XCTestCase {
    func root()throws->URL {let url=FileManager.default.temporaryDirectory.appendingPathComponent("ShotReporterTest-archive-"+UUID().uuidString,isDirectory:true);try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true);addTeardownBlock{try? FileManager.default.removeItem(at:url)};return url}
    func fixture(_ root:URL,large:Bool=false)throws->(ProjectArchive.Snapshot,URL,URL) {
        let files=root.appendingPathComponent("files"),original=root.appendingPathComponent("参考 – lighting.pdf")
        try Data("%PDF-1.7\nSynthetic binary attachment\0 café 🎥".utf8).write(to:original)
        var state=ProjectArchive.State();state.resources.append(try ProjectArchive.addFile(original,kind:"attachment",to:files))
        let media=root.appendingPathComponent("A001C001.mov");let data=Data((0..<256).map(UInt8.init));let h=FileManager.default.createFile(atPath:media.path,contents:nil);XCTAssertTrue(h)
        let out=try FileHandle(forWritingTo:media);for _ in 0..<(large ? 135_169:19) {try out.write(contentsOf:data)};try out.close()
        state.resources.append(try ProjectArchive.addFile(media,kind:"media",to:files))
        state.preferences=try PropertyListSerialization.data(fromPropertyList:["theme":"Dark","detail":"Full","SUFeedURL":"https://invalid.example/untrusted","future": ["bytes":Data([0,1,255]),"date":Date(timeIntervalSince1970:42)]],format:.binary,options:0)
        let current=try Exchange.export(Report.fullHandoffFixture(),device:"iPhone QA"),previous=try Exchange.export(Report(),device:"Previous QA")
        return (ProjectArchive.Snapshot(current:current,previous:previous,state:state),files,original)
    }
    func testStreamedMediaOverLegacyLimitAndEveryCategoryRoundTrips()throws {
        let root=try root(),(snapshot,files,original)=try fixture(root,large:true),archive=root.appendingPathComponent("whole.camreport"),before=try Data(contentsOf:original)
        try ProjectArchive.write(snapshot,resources:files,device:"Mac QA",to:archive)
        XCTAssertGreaterThan((try FileManager.default.attributesOfItem(atPath:archive.path)[.size] as! NSNumber).intValue,Exchange.limit)
        let incoming=try ProjectArchive.read(archive,to:root.appendingPathComponent("import"))
        XCTAssertEqual(incoming.snapshot.current,snapshot.current);XCTAssertEqual(incoming.snapshot.previous,snapshot.previous);XCTAssertEqual(incoming.report,.fullHandoffFixture());XCTAssertEqual(incoming.snapshot.state.preferences,snapshot.state.preferences)
        for resource in snapshot.state.resources {XCTAssertTrue(incoming.snapshot.state.resources.contains(resource));let copied=try ProjectZIP.fingerprint(ProjectArchive.blobURL(incoming.folder,resource.sha256));XCTAssertEqual(copied.sha256,resource.sha256);XCTAssertEqual(copied.size,resource.size)}
        XCTAssertEqual(incoming.snapshot.state.resources.filter{$0.kind=="recovery"}.count,2)
        let returned=root.appendingPathComponent("return.camreport");try ProjectArchive.write(incoming.snapshot,resources:incoming.folder,device:"Phone QA",to:returned)
        let final=try ProjectArchive.read(returned,to:root.appendingPathComponent("final"));XCTAssertEqual(final.snapshot,incoming.snapshot);XCTAssertEqual(try Data(contentsOf:original),before)
    }
    func testTamperAndTraversalFailBeforeAnyImport()throws {
        let root=try root(),(snapshot,files,_)=try fixture(root),archive=root.appendingPathComponent("original.camreport");try ProjectArchive.write(snapshot,resources:files,device:"QA",to:archive)
        let index=try ProjectZIP.index(archive),entry=try XCTUnwrap(index.values.first{$0.name.hasPrefix("payloads/")}),h=try FileHandle(forUpdating:archive)
        try h.seek(toOffset:entry.offset);try h.write(contentsOf:Data([77]));try h.close()
        let stage=root.appendingPathComponent("rejected");XCTAssertThrowsError(try ProjectArchive.read(archive,to:stage));XCTAssertFalse(FileManager.default.fileExists(atPath:stage.path))
        XCTAssertFalse(ProjectZIP.validName("payloads/../../escape"));XCTAssertFalse(ProjectZIP.validName("/manifest.json"));XCTAssertFalse(ProjectZIP.validName("payloads/"+String(repeating:"A",count:64)))
        let malicious=root.appendingPathComponent("link");try FileManager.default.createSymbolicLink(at:malicious,withDestinationURL:files);XCTAssertThrowsError(try ProjectArchive.addFile(malicious,kind:"media",to:root.appendingPathComponent("more")))
    }
    func testMissingOrMutatedFileNeverProducesPartialArchive()throws {
        let root=try root(),(snapshot,files,_)=try fixture(root),target=root.appendingPathComponent("bad.camreport"),resource=snapshot.state.resources[0]
        try Data("changed bytes".utf8).write(to:ProjectArchive.blobURL(files,resource.sha256));XCTAssertThrowsError(try ProjectArchive.write(snapshot,resources:files,device:"QA",to:target));XCTAssertFalse(FileManager.default.fileExists(atPath:target.path))
        try Data("existing export".utf8).write(to:target);XCTAssertThrowsError(try ProjectArchive.write(snapshot,resources:files,device:"QA",to:target));XCTAssertEqual(try Data(contentsOf:target),Data("existing export".utf8))
    }
    func testUnknownMetadataIsRejectedWithoutDroppingIt()throws {
        let root=try root(),(snapshot,files,_)=try fixture(root),archive=root.appendingPathComponent("good.camreport");try ProjectArchive.write(snapshot,resources:files,device:"QA",to:archive)
        let index=try ProjectZIP.index(archive);var inputs:[ProjectZIP.Input]=[]
        for entry in index.values {
            let file=root.appendingPathComponent(UUID().uuidString)
            if entry.name=="manifest.json" {
                var json=try JSONSerialization.jsonObject(with:ProjectZIP.data(entry,from:archive,limit:ProjectArchive.metadataLimit)) as! [String:Any];json["futureCategory"]=["mustSurvive":true];try JSONSerialization.data(withJSONObject:json).write(to:file)
            } else {try ProjectZIP.copy(entry,from:archive,to:file,expectedSHA256:String(entry.name.dropFirst(9)))}
            inputs.append(ProjectZIP.Input(name:entry.name,url:file,fingerprint:try ProjectZIP.fingerprint(file)))
        }
        let future=root.appendingPathComponent("future.camreport");try ProjectZIP.write(inputs.sorted{$0.name<$1.name},to:future)
        XCTAssertThrowsError(try ProjectArchive.read(future,to:root.appendingPathComponent("refused")))
    }
    func testProjectImportRollbackAndConflictAlwaysKeepBoth()throws {
        let root=try root(),(snapshot,_,_)=try fixture(root),repo=try Repository(url:root.appendingPathComponent("reports.sqlite3")),first=UUID().uuidString,second=UUID().uuidString
        _=try repo.importProject(snapshot,slot:first)
        XCTAssertThrowsError(try repo.importProject(snapshot,slot:first));XCTAssertThrowsError(try repo.importProject(snapshot,slot:second,failBeforeCommit:true));XCTAssertEqual(try repo.active(),first);XCTAssertEqual(try repo.list().count,1)
        _=try repo.importProject(snapshot,slot:second);XCTAssertEqual(try repo.list().count,2);XCTAssertEqual(try repo.projectSnapshot(first),snapshot);XCTAssertEqual(try repo.projectSnapshot(second),snapshot)
        var state=snapshot.state;state.resources.removeLast();let hash=try repo.load(first).fingerprint
        try repo.setProjectState(state,slot:first,expectedFingerprint:hash,expectedState:snapshot.state)
        XCTAssertThrowsError(try repo.setProjectState(snapshot.state,slot:first,expectedFingerprint:hash,expectedState:snapshot.state));XCTAssertEqual(try repo.projectState(first),state)
    }
    @MainActor func testNativeStoreImportsPreferencesSafelyPreservesOriginalAndRestoresFiles()async throws {
        let root=try root(),source=root.appendingPathComponent("source",isDirectory:true);try FileManager.default.createDirectory(at:source,withIntermediateDirectories:true)
        let (snapshot,files,original)=try fixture(source),archive=source.appendingPathComponent("complete.camreport");try ProjectArchive.write(snapshot,resources:files,device:"iPhone QA",to:archive)
        let suite="ShotReporterTest-prefs-"+UUID().uuidString,prefs=UserDefaults(suiteName:suite)!;defer{prefs.removePersistentDomain(forName:suite)}
        prefs.set("Light",forKey:"theme");prefs.set("https://trusted.example/",forKey:"SUFeedURL")
        let store=Store(root:root.appendingPathComponent("mac"),preferences:prefs,preferencesDomain:suite);store.open(Report());let originalSlot=store.slot
        let prepared=try await store.prepareProjectImport(archive);try store.acceptProject(prepared,applyPreferences:true)
        XCTAssertNil(store.error);XCTAssertEqual(store.documents.count,2);XCTAssertNotEqual(store.slot,originalSlot);XCTAssertEqual(store.report,.fullHandoffFixture());XCTAssertEqual(prefs.string(forKey:"theme"),"Dark");XCTAssertEqual(prefs.string(forKey:"detail"),"Full");XCTAssertEqual(prefs.string(forKey:"SUFeedURL"),"https://trusted.example/")
        XCTAssertEqual(store.projectState.resources.count,4);store.change{$0.values["title"]="Edited on Mac"};await store.restore();XCTAssertEqual(store.projectState.resources.count,4);XCTAssertEqual(store.report,.fullHandoffFixture())
        let exported=await store.prepareProjectExport();let reexport=try XCTUnwrap(exported),verified=try ProjectArchive.read(reexport,to:root.appendingPathComponent("verify"));XCTAssertEqual(verified.report,.fullHandoffFixture());XCTAssertTrue(FileManager.default.fileExists(atPath:original.path))
        store.select(originalSlot);XCTAssertTrue(store.projectState.resources.isEmpty)
    }
    @MainActor func testCancelImportAndTrashLeaveActiveFilesAndSourcesIntact()async throws {
        let root=try root(),source=root.appendingPathComponent("source",isDirectory:true);try FileManager.default.createDirectory(at:source,withIntermediateDirectories:true)
        let (snapshot,files,original)=try fixture(source),archive=source.appendingPathComponent("whole.camreport");try ProjectArchive.write(snapshot,resources:files,device:"QA",to:archive)
        let store=Store(root:root.appendingPathComponent("local"),preferences:UserDefaults(suiteName:UUID().uuidString)!);store.open(Report())
        let cancelled=try await store.prepareProjectImport(archive);store.discardProject(cancelled);XCTAssertEqual(store.documents.count,1);XCTAssertFalse(FileManager.default.fileExists(atPath:cancelled.folder.path))
        let prepared=try await store.prepareProjectImport(archive);try store.acceptProject(prepared,applyPreferences:false);let importedSlot=store.slot
        store.deleteReport(try store.deletionRequest(for:importedSlot));let request=try store.trashRequest();store.clearTrash(request)
        XCTAssertNil(store.error);XCTAssertEqual(store.documents.count,1);XCTAssertTrue(store.deletedDocuments.isEmpty);XCTAssertTrue(FileManager.default.fileExists(atPath:original.path));XCTAssertFalse(FileManager.default.fileExists(atPath:store.root.appendingPathComponent("ProjectFiles/"+importedSlot).path))
    }
    func testZIP64AcceptsOffsetsBeyondFourGiBWithoutAllocatingMediaInMemory()throws {
        let root=try root(),url=root.appendingPathComponent("sparse-zip64.camreport"),name=Data("manifest.json".utf8),length:UInt64=(1<<32)+123
        FileManager.default.createFile(atPath:url.path,contents:nil);let h=try FileHandle(forWritingTo:url)
        let local=ProjectZIP.packed([(0x04034b50,4),(45,2),(0,2),(0,2),(0,2),(0,2),(0,4),(0xffffffff,4),(0xffffffff,4),(UInt64(name.count),2),(20,2)])+name+ProjectZIP.packed([(1,2),(16,2),(length,8),(length,8)])
        try h.write(contentsOf:local);let centralOffset=UInt64(local.count)+length;try h.seek(toOffset:centralOffset)
        let central=ProjectZIP.packed([(0x02014b50,4),(0x032d,2),(45,2),(0,2),(0,2),(0,2),(0,2),(0,4),(0xffffffff,4),(0xffffffff,4),(UInt64(name.count),2),(28,2),(0,2),(0,2),(0,2),(UInt64(0o100600)<<16,4),(0xffffffff,4)])+name+ProjectZIP.packed([(1,2),(24,2),(length,8),(length,8),(0,8)])
        try h.write(contentsOf:central);let footer=try h.offset()
        try h.write(contentsOf:ProjectZIP.packed([(0x06064b50,4),(44,8),(45,2),(45,2),(0,4),(0,4),(1,8),(1,8),(UInt64(central.count),8),(centralOffset,8),(0x07064b50,4),(0,4),(footer,8),(1,4),(0x06054b50,4),(0,2),(0,2),(0xffff,2),(0xffff,2),(0xffffffff,4),(0xffffffff,4),(0,2)]));try h.close()
        let entry=try XCTUnwrap(ProjectZIP.index(url)["manifest.json"]);XCTAssertEqual(entry.fingerprint.size,length)
        XCTAssertThrowsError(try ProjectZIP.data(entry,from:url,limit:ProjectArchive.metadataLimit))
    }
    func testTruncationOverlapAndHeaderDisagreementAreRejected()throws {
        let root=try root(),(snapshot,files,_)=try fixture(root),url=root.appendingPathComponent("original.camreport");try ProjectArchive.write(snapshot,resources:files,device:"QA",to:url)
        let original=try Data(contentsOf:url)
        for mode in 0..<3 {
            var bytes=original
            if mode==0 {bytes.removeLast()}
            if mode==1 {bytes[8]=8} // compression contradicts central metadata
            if mode==2 {let footer=bytes.count-98;let directory=Int(try ProjectZIP.value(bytes,footer+48,8));bytes[directory+38]=255} // symlink/unsupported attributes
            let corrupt=root.appendingPathComponent("bad-\(mode).camreport");try bytes.write(to:corrupt)
            XCTAssertThrowsError(try ProjectArchive.read(corrupt,to:root.appendingPathComponent("no-import-\(mode)")))
        }
    }
    func testUnsafePreferenceAndOversizeBoundsRefused()throws {
        let root=try root();XCTAssertThrowsError(try ProjectArchive.blobURL(root,"../escape"));XCTAssertThrowsError(try ProjectZIP.add(UInt64.max,1));XCTAssertThrowsError(try ProjectArchive.checkSpace(at:root,bytes:UInt64.max))
        var state=ProjectArchive.State();state.preferences=Data("not plist".utf8);XCTAssertThrowsError(try ProjectArchive.validate(state))
        state=ProjectArchive.State();state.resources=[ProjectArchive.Resource(name:"file",kind:"run-script",sha256:String(repeating:"0",count:64),size:0)];XCTAssertThrowsError(try ProjectArchive.validate(state))
    }
}
