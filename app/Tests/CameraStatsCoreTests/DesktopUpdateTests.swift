#if os(macOS)
import XCTest
import CryptoKit
import Sparkle
import CameraStatsCore
@testable import CameraStats

final class DesktopUpdateTests:XCTestCase {
    private func directory() throws -> URL {let path=FileManager.default.temporaryDirectory.appendingPathComponent("ShotReporter-Update-Test-"+UUID().uuidString,isDirectory:true);try FileManager.default.createDirectory(at:path,withIntermediateDirectories:true);return path}
    private func policy(_ channel:DesktopUpdatePolicy.Channel = .alpha,_ distribution:DesktopUpdatePolicy.Distribution = .direct,key:Data?=Data(repeating:1,count:32),trusted:Bool=true)->DesktopUpdatePolicy {DesktopUpdatePolicy(distribution:distribution,channel:channel,build:2,feed:URL(string:"https://raw.githubusercontent.com/OfficialSquidProductions/shot-reporter/main/updates/macos/appcast.xml"),publicKey:key,hostTrusted:trusted)}
    private var archive:URL {URL(string:"https://github.com/OfficialSquidProductions/shot-reporter/releases/download/v0.2.0-alpha.1/Shot-Reporter-Mac.zip")!}
    func testDistributionAndTrustFailClosed() {
        XCTAssertNil(policy().unavailableReason)
        XCTAssertNotNil(policy(key:nil).unavailableReason)
        XCTAssertNotNil(policy(key:Data(repeating:0,count:31)).unavailableReason)
        XCTAssertNotNil(policy(trusted:false).unavailableReason)
        for distribution in [DesktopUpdatePolicy.Distribution.development,.appStore,.testFlight,.unconfigured] {XCTAssertNotNil(policy(.alpha,distribution).unavailableReason)}
        XCTAssertFalse(DesktopUpdatePolicy.trustedBundle(URL(fileURLWithPath:"/tmp/not-a-signed-app-"+UUID().uuidString)))
    }
    @MainActor func testMissingTrustSettingsAndInvalidChannelNeverStartUpdater() {
        let required:[String:Any] = ["SURequireSignedFeed":true,"SUVerifyUpdateBeforeExtraction":true,"SUAllowsAutomaticUpdates":false]
        var complete=required;complete["SUSignedFeedFailureExpirationInterval"]=0
        XCTAssertTrue(DesktopUpdatePolicy.completeSecuritySettings(complete))
        XCTAssertFalse(DesktopUpdatePolicy.completeSecuritySettings(required))
        for key in required.keys {
            var missing=complete;missing.removeValue(forKey:key)
            XCTAssertFalse(DesktopUpdatePolicy.completeSecuritySettings(missing))
            var changed=complete;changed[key] = !(required[key] as! Bool)
            XCTAssertFalse(DesktopUpdatePolicy.completeSecuritySettings(changed))
        }
        var noFallback=required;noFallback["SUSignedFeedFailureExpirationInterval"]=0
        XCTAssertTrue(DesktopUpdatePolicy.completeSecuritySettings(noFallback))
        for invalid:Any in ["0",false,true,1,-1,0.01,Double.infinity,Double.nan] {
            noFallback["SUSignedFeedFailureExpirationInterval"]=invalid
            XCTAssertFalse(DesktopUpdatePolicy.completeSecuritySettings(noFallback),"Rejected interval: \(invalid)")
        }
        for value in [policy(.unconfigured),policy(.alpha,.unconfigured),policy(.alpha,.development),policy(key:nil),policy(trusted:false)] {
            let updates=DesktopUpdates(policy:value);var shown=0
            updates.presentNotice={_,_ in shown += 1}
            updates.start();updates.start()
            XCTAssertTrue(updates.started);XCTAssertFalse(updates.isDirect)
            updates.automaticChecks=true;XCTAssertFalse(updates.automaticChecks)
            updates.check();XCTAssertEqual(shown,1)
        }
    }
    @MainActor func testSparkleDelegateRejectsSkippedOrFailedFeedSignature() throws {
        XCTAssertNoThrow(try DesktopUpdates.validateFeedSignature(.succeeded))
        XCTAssertThrowsError(try DesktopUpdates.validateFeedSignature(.skipped))
        XCTAssertThrowsError(try DesktopUpdates.validateFeedSignature(.failed))
        let updates=DesktopUpdates(policy:policy())
        let fixture=SPUStandardUpdaterController(startingUpdater:false,updaterDelegate:nil,userDriverDelegate:nil)
        XCTAssertThrowsError(try updates.updater(fixture.updater,shouldProceedWithUpdate:SUAppcastItem.empty(),updateCheck:.updates))
    }
    func testChannelAndMonotonicBuildPolicy() throws {
        try policy().validate(build:"3",channel:"alpha",archive:archive)
        try policy().validate(build:"3",channel:nil,archive:archive)
        try policy(.stable).validate(build:"4",channel:"stable",archive:archive)
        XCTAssertThrowsError(try policy(.stable).validate(build:"3",channel:"alpha",archive:archive))
        for value in ["2","1","0","2.1","v4","-5","18446744073709551616"] {XCTAssertThrowsError(try policy().validate(build:value,channel:nil,archive:archive))}
        XCTAssertThrowsError(try policy().validate(build:"3",channel:"nightly",archive:archive))
    }
    func testReleaseLocationRejectsUnrelatedCredentialsAndTraversal() {
        for path in ["http://github.com/OfficialSquidProductions/shot-reporter/releases/download/v1/App.zip","https://github.com.evil.test/OfficialSquidProductions/shot-reporter/releases/download/v1/App.zip","https://github.com/Other/shot-reporter/releases/download/v1/App.zip","https://user@github.com/OfficialSquidProductions/shot-reporter/releases/download/v1/App.zip","https://github.com/OfficialSquidProductions/shot-reporter/releases/download/v1/App.zip?x=1","https://github.com/OfficialSquidProductions/shot-reporter/releases/download/v1%2Fevil/App.zip"] {XCTAssertFalse(DesktopUpdatePolicy.allowedArchive(URL(string:path)!))}
        XCTAssertTrue(DesktopUpdatePolicy.allowedArchive(archive))
        XCTAssertFalse(DesktopUpdatePolicy.allowedFeed(archive))
    }
    @MainActor func testSaveFailureCancelRetryAndOneTimeInstall() throws {
        let root=try directory();defer {try? FileManager.default.removeItem(at:root)}
        let gate=DesktopUpdateSaveGate();defer {gate.updateAborted()};var saves=0,installs=0,fail=true
        gate.save={saves += 1;if fail {throw DesktopUpdateError("disk full fixture")}}
        gate.postpone {installs += 1}
        try gate.install(confirmed:false);XCTAssertEqual(saves,0);XCTAssertEqual(installs,0)
        XCTAssertThrowsError(try gate.install(confirmed:true));XCTAssertTrue(gate.pending);XCTAssertEqual(installs,0)
        fail=false;try gate.install(confirmed:true);try gate.install(confirmed:true)
        XCTAssertEqual(saves,2);XCTAssertEqual(installs,1);XCTAssertTrue(gate.installing)
        let cancelled=DesktopUpdateSaveGate();cancelled.postpone {installs += 10};cancelled.cancel();try cancelled.install(confirmed:true);XCTAssertEqual(installs,1)
    }
    @MainActor func testRealSparkleDelegateWaitsForConfirmationAndSaveThenRecoversOnAbort() async throws {
        let root=try directory();defer {try? FileManager.default.removeItem(at:root)}
        let updates=DesktopUpdates(policy:policy())
        let fixture=SPUStandardUpdaterController(startingUpdater:false,updaterDelegate:nil,userDriverDelegate:nil)
        var saves=0,installs=0,confirm=false,fail=false
        updates.confirmInstall={confirm};updates.presentNotice={_,_ in}
        updates.gate.save={saves += 1;if fail {throw DesktopUpdateError("save fixture failure")}}
        XCTAssertTrue(updates.updater(fixture.updater,shouldPostponeRelaunchForUpdate:SUAppcastItem.empty(),untilInvokingBlock:{installs += 1}))
        for _ in 0..<10 {await Task.yield()}
        XCTAssertEqual(installs,0);XCTAssertEqual(saves,0);XCTAssertTrue(updates.gate.pending)
        confirm=true;fail=true;updates.check();XCTAssertEqual(installs,0);XCTAssertEqual(saves,1)
        fail=false;updates.check();XCTAssertEqual(installs,1);XCTAssertEqual(saves,2);XCTAssertTrue(DesktopUpdateActivity.installing)
        updates.updater(fixture.updater,didAbortWithError:DesktopUpdateError("fixture installer failure"))
        XCTAssertFalse(DesktopUpdateActivity.installing);XCTAssertFalse(updates.gate.pending)
    }
    @MainActor func testSaveCheckpointPreservesCurrentAndPreviousRecoverySnapshots() throws {
        let root=try directory();defer {try? FileManager.default.removeItem(at:root)}
        let preferences=try XCTUnwrap(UserDefaults(suiteName:"ShotReporterUpdateTest-"+UUID().uuidString))
        let store=Store(root:root,preferences:preferences);store.open(.demo());store.change {$0.values["title"]="Update preservation fixture"}
        let repository=try Repository(url:root.appendingPathComponent("reports.sqlite3"))
        let current=try repository.load(store.slot).fingerprint,previous=try repository.load(store.slot,previous:true).fingerprint
        let updates=DesktopUpdates(policy:policy());updates.configure(store:store);try updates.gate.prepare()
        store.pendingImport=true;XCTAssertThrowsError(try updates.gate.prepare());store.pendingImport=false;try updates.gate.prepare()
        XCTAssertEqual(try repository.load(store.slot).fingerprint,current);XCTAssertEqual(try repository.load(store.slot,previous:true).fingerprint,previous)
        // A concurrent accepted write must block installing stale in-memory data.
        var newer=store.report;newer.values["title"]="Concurrent fixture";newer.record("fixture",device:"fixture")
        _=try repository.save(slot:store.slot,report:newer,device:"fixture",expectedFingerprint:current)
        XCTAssertThrowsError(try updates.gate.prepare())
    }
    func testEphemeralSignatureAndIsolatedReplacementRecoveryPreserveData() throws {
        // This is an offline trust/preservation fixture, *not* an end-to-end
        // Sparkle installer or production Developer ID/notarization acceptance.
        let root=try directory();defer {try? FileManager.default.removeItem(at:root)}
        let support=root.appendingPathComponent("Application Support",isDirectory:true),old=root.appendingPathComponent("Shot Reporter.app",isDirectory:true),backup=root.appendingPathComponent("old.app",isDirectory:true),stage=root.appendingPathComponent("staged.app",isDirectory:true)
        for dir in [support,old,stage] {try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)}
        let report=support.appendingPathComponent("reports.sqlite3"),journal=support.appendingPathComponent("media.sqlite3")
        try Data("report fixture".utf8).write(to:report);try Data("copy journal fixture".utf8).write(to:journal)
        let reportHash=SHA256.hash(data:try Data(contentsOf:report)),journalHash=SHA256.hash(data:try Data(contentsOf:journal))
        try Data("build 2".utf8).write(to:old.appendingPathComponent("version"));let newer=Data("build 3".utf8);try newer.write(to:stage.appendingPathComponent("version"))
        let key=Curve25519.Signing.PrivateKey(),signature=try key.signature(for:newer)
        XCTAssertTrue(key.publicKey.isValidSignature(signature,for:newer));XCTAssertFalse(key.publicKey.isValidSignature(signature,for:Data("tampered".utf8)));XCTAssertFalse(Curve25519.Signing.PrivateKey().publicKey.isValidSignature(signature,for:newer))
        try policy().validate(build:"3",channel:"alpha",archive:archive)
        try FileManager.default.moveItem(at:old,to:backup)
        // Simulated interrupted replacement: old app remains recoverable.
        XCTAssertEqual(try String(contentsOf:backup.appendingPathComponent("version")),"build 2")
        try FileManager.default.moveItem(at:backup,to:old)
        XCTAssertEqual(try String(contentsOf:old.appendingPathComponent("version")),"build 2")
        try FileManager.default.moveItem(at:old,to:backup);try FileManager.default.moveItem(at:stage,to:old)
        XCTAssertEqual(try String(contentsOf:old.appendingPathComponent("version")),"build 3")
        XCTAssertEqual(SHA256.hash(data:try Data(contentsOf:report)),reportHash);XCTAssertEqual(SHA256.hash(data:try Data(contentsOf:journal)),journalHash)
    }
}
#endif
