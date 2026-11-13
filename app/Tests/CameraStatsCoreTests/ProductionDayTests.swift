import XCTest
import PDFKit
@testable import CameraStatsCore
@testable import CameraStats

final class ProductionDayTests:XCTestCase {
    func root()throws->URL {let root=FileManager.default.temporaryDirectory.appendingPathComponent("ShotReporterTest-production-"+UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);addTeardownBlock{try? FileManager.default.removeItem(at:root)};return root}
    func testDayLabelsDoNotRewriteProductionTitleOrReportIdentity()throws {
        var r=Report();r.values["title"]="Angels on High";r.values["day"]="1";let before=try Exchange.encoder().encode(r),id=r.id
        XCTAssertEqual(r.displayTitle,"Angels on High Day 1");r.values["day"]=" Day 02 ";XCTAssertEqual(r.displayTitle,"Angels on High Day 02");r.values["day"]="1"
        XCTAssertEqual(try Exchange.encoder().encode(r),before);XCTAssertEqual(r.id,id)
        r.values.removeValue(forKey:"day");XCTAssertEqual(r.displayTitle,"Angels on High");r.values["title"]=" ";XCTAssertEqual(r.displayTitle,"Untitled production")
    }
    func testNextDayKeepsProductionCrewAndGeneralSettingsButClearsDailyRecords()throws {
        var original=Report.fullHandoffFixture();original.values["day"]="1";original.values["date"]="2028-02-28"
        let bytes=try Exchange.encoder().encode(original),next=try original.nextShootingDay()
        XCTAssertNotEqual(next.id,original.id);XCTAssertEqual(next.displayTitle,"Harbor Lights - Night Unit Day 2");XCTAssertEqual(next.values["date"],"2028-02-29")
        for (key,value) in original.values where !["day","date"].contains(key) {XCTAssertEqual(next.values[key],value)}
        XCTAssertEqual(next.profile,original.profile);XCTAssertEqual(next.positions,original.positions);XCTAssertEqual(next.namingSettings,original.namingSettings);XCTAssertEqual(next.namingTemplate,original.namingTemplate)
        XCTAssertEqual(next.defaults["iso"],original.defaults["iso"]);XCTAssertEqual(next.defaults["sensorRate"],original.defaults["sensorRate"])
        XCTAssertNotEqual(next.defaults["load"],original.defaults["load"]);XCTAssertEqual(next.defaults["mag"],"");XCTAssertNil(next.defaults["height"]);XCTAssertNil(next.defaults["distance"])
        XCTAssertTrue(next.entries.isEmpty);XCTAssertTrue(next.importedPackages.isEmpty);XCTAssertTrue(next.history.isEmpty);XCTAssertEqual(try Exchange.encoder().encode(original),bytes)
        XCTAssertEqual(try next.nextShootingDay().values["date"],"2028-03-01")
        original.values["date"]="2027-03-14";XCTAssertEqual(try original.nextShootingDay().values["date"],"2027-03-15")
    }
    func testInvalidDayDoesNotGuessOrOverwriteAndBlankLegacyDayStartsAtOne()throws {
        var r=Report();r.values["day"]="1A";let before=r;XCTAssertThrowsError(try r.nextShootingDay());XCTAssertEqual(r,before)
        r.values["day"]=String(Int.max);XCTAssertThrowsError(try r.nextShootingDay());r.values["day"]="-1";XCTAssertThrowsError(try r.nextShootingDay())
        r.values.removeValue(forKey:"day");XCTAssertEqual(try r.nextShootingDay().values["day"],"1")
    }
    func testExactLengthConversionsAndFractionalInches()throws {
        for (raw,expected) in [("5 ft 6 in",1.6764),("5'6\"",1.6764),("5′ 6″",1.6764),("5’6”",1.6764),("5 feet 6 1/2 inches",1.6891),("66 in",1.6764),("5.5 ft",1.6764),("167.64 cm",1.6764),("1.6764 m",1.6764),("1/2 in",0.0127)] {
            XCTAssertEqual(try XCTUnwrap(LengthMeasurement.meters(raw)),expected,accuracy:0.000000001,raw)
            XCTAssertEqual(LengthMeasurement.display(raw,unit:.feetInches).contains("ft"),true)
        }
        XCTAssertEqual(LengthMeasurement.display("5 ft 6 in",unit:.meters),"1.6764 m");XCTAssertEqual(LengthMeasurement.display("1.6764 m",unit:.feetInches),"5 ft 6 in");XCTAssertEqual(LengthMeasurement.display("1.6764 m",unit:.centimeters),"167.64 cm")
        XCTAssertEqual(LengthMeasurement.edited("5.5",unit:.feetInches),"5.5 ft");XCTAssertEqual(LengthMeasurement.edited("170",unit:.centimeters),"170 cm")
    }
    func testLegacyUnknownAndAmbiguousMeasurementsArePreserved() {
        for raw in ["5","1,000 cm","N/A","~5 ft","infinity","5 ft at top of stairs","-2 m","1/0 in","NaN m","1e99 m"] {XCTAssertNil(LengthMeasurement.meters(raw),raw);for unit in MeasurementUnit.allCases {XCTAssertEqual(LengthMeasurement.display(raw,unit:unit),raw)}}
        var report=Report.fullHandoffFixture();let original=report;XCTAssertEqual(report.measurementUnit,.feetInches)
        for _ in 0..<50 {for unit in MeasurementUnit.allCases {report.measurementUnit=unit;for entry in report.entries {_=report.displayedValue("height",in:entry);_=report.displayedValue("distance",in:entry)}}}
        XCTAssertEqual(report.entries,original.entries);XCTAssertEqual(report.defaults,original.defaults)
    }
    func testOptionalLightMeterBelongsToEachTakeAndRemovedBoxesKeepLegacyValues()throws {
        var r=Report.fullHandoffFixture();let raw=r.defaults["playbackRate"];XCTAssertFalse(Schema.settings.contains{$0.id=="playbackRate" || $0.id=="sensorRate"})
        r.entries[0].values["lightMeter"]="2.8 + 1/3";r.entries[0].values["lightMeterUnit"]="f-stop";r.entries[0].values["lightMeterContext"]="Face / incident / ISO 800 / 1/48 s"
        r.defaults["lightMeter"]="stale legacy default";let next=r.next(scene:"12C",device:"QA")
        XCTAssertNil(r.entries.first{$0.id==next}?.values["lightMeter"]);XCTAssertEqual(r.defaults["playbackRate"],raw)
        XCTAssertEqual(try Exchange.read(Exchange.export(r,device:"QA")).report,r)
        XCTAssertTrue(Reports.csv(r).contains("playbackRate"));XCTAssertTrue(Reports.csv(r).contains("lightMeterContext"))
    }
    func testPDFDayUnitsMeterAndLegacyRoundTrip()throws {
        var r=Report.fullHandoffFixture();r.values["day"]="1";r.entries[0].values["height"]="1.6764 m";r.entries[0].values["distance"]="304.8 cm";r.entries[0].values["lightMeter"]="2.8 + 1/3";r.entries[0].values["lightMeterUnit"]="f-stop";r.entries[0].values["lightMeterContext"]="Subject face / incident / ISO 800 / 1/48 s"
        let legacy=r;let pdf=try Reports.pdf(r),document=try XCTUnwrap(PDFDocument(data:pdf)),text=try XCTUnwrap(document.string)
        XCTAssertTrue(text.contains("Night Unit Day 1"));XCTAssertTrue(text.contains("5 ft 6 in"));XCTAssertTrue(text.contains("10 ft 0 in"));XCTAssertTrue(text.contains("LIGHT AT SUBJECT"));XCTAssertTrue(text.contains("f/2.8 + 1/3"));XCTAssertTrue(text.contains("Subject face"));XCTAssertFalse(text.contains("Varispeed"));XCTAssertFalse(text.contains("Project time base"))
        r.measurementUnit = .centimeters;let metric=try XCTUnwrap(PDFDocument(data:Reports.pdf(r))?.string);XCTAssertTrue(metric.contains("167.64 cm"));XCTAssertEqual(r.entries,legacy.entries)
        if let output=ProcessInfo.processInfo.environment["SHOT_REPORTER_PDF_QA_OUTPUT"] {try pdf.write(to:URL(fileURLWithPath:output))}
        let imported=try Exchange.read(Exchange.export(r,device:"QA")).report;XCTAssertEqual(imported,r);XCTAssertEqual(imported.entries[0].values["height"],"1.6764 m");XCTAssertEqual(imported.defaults["sensorRate"],legacy.defaults["sensorRate"])
        XCTAssertTrue(try r.exportName(extension:"camreport").contains("Day1"))
    }
    @MainActor func testNewDayNativeStoreCopiesReferencesWithoutOldMediaAndKeepsPriorReport()async throws {
        let root=try root(),suite="ShotReporterTest-newday-"+UUID().uuidString,prefs=UserDefaults(suiteName:suite)!;defer{prefs.removePersistentDomain(forName:suite)}
        let store=Store(root:root,preferences:prefs);var r=Report.fullHandoffFixture();r.values["day"]="1";store.open(r);store.change{$0.values["director"]="Updated crew"};let original=store.report,oldSlot=store.slot
        let file=root.appendingPathComponent("Script.pdf");try Data("synthetic reference".utf8).write(to:file);await store.addProjectFiles([file],kind:"attachment")
        let media=root.appendingPathComponent("Take.mov");try Data([0,1,2,255]).write(to:media);await store.addProjectFiles([media],kind:"media")
        let repo=try Repository(url:root.appendingPathComponent("reports.sqlite3")),before=try repo.projectSnapshot(oldSlot),request=try store.newDayRequest();await store.startNewDay(request)
        XCTAssertNil(store.error);XCTAssertNotEqual(store.slot,oldSlot);XCTAssertNotEqual(store.report.id,original.id);XCTAssertEqual(store.report.values["day"],"2");XCTAssertEqual(store.report.values["director"],"Updated crew");XCTAssertTrue(store.report.entries.isEmpty)
        XCTAssertEqual(store.projectState.resources.count,1);XCTAssertEqual(store.projectState.resources.first?.kind,"attachment");XCTAssertEqual(try repo.projectSnapshot(oldSlot),before)
        XCTAssertEqual(store.documents.count,2);XCTAssertTrue(store.documents.contains{$0.1.contains("Day 1")});XCTAssertTrue(store.documents.contains{$0.1.contains("Day 2")})
        let returned=await store.prepareProjectExport();let prepared=try ProjectArchive.read(try XCTUnwrap(returned),to:root.appendingPathComponent("verify"));XCTAssertEqual(prepared.report,store.report);XCTAssertTrue(prepared.snapshot.state.resources.contains{$0.kind=="attachment"});XCTAssertFalse(prepared.snapshot.state.resources.contains{$0.kind=="media"})
        store.select(oldSlot);XCTAssertEqual(store.report,original);XCTAssertEqual(store.projectState.resources.count,2)
    }
    @MainActor func testStaleNewDayRequestAndRollbackNeverAlterSource()async throws {
        let root=try root(),prefs=UserDefaults(suiteName:UUID().uuidString)!,store=Store(root:root,preferences:prefs);store.open(.fullHandoffFixture());let slot=store.slot,request=try store.newDayRequest()
        let other=Store(root:root,preferences:prefs);other.change{$0.values["director"]="Concurrent crew change"};await store.startNewDay(request)
        XCTAssertNotNil(store.error);let repo=try Repository(url:root.appendingPathComponent("reports.sqlite3"));XCTAssertEqual(try repo.list().count,1);XCTAssertEqual(try repo.load(slot).report,other.report)
        let current=try repo.projectSnapshot(slot),destination=UUID().uuidString;XCTAssertThrowsError(try repo.importProject(current,slot:destination,failBeforeCommit:true));XCTAssertEqual(try repo.list().count,1);XCTAssertEqual(try repo.projectSnapshot(slot),current)
    }
    func testSelectionGreenHasReadableWhiteTextContrast() {
        func channel(_ c:Double)->Double {let c=c/255;return c<=0.04045 ? c/12.92:pow((c+0.055)/1.055,2.4)}
        let luminance=0.2126*channel(20)+0.7152*channel(85)+0.0722*channel(51)
        XCTAssertGreaterThan((1.0+0.05)/(luminance+0.05),7.0)
    }
}
