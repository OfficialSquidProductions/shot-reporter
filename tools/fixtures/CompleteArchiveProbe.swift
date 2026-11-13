import Foundation
#if os(macOS)
import AppKit
import PDFKit
#endif

func phoneTitleEdit(_ report:Report)->Report {
    var edited=Report.phoneHandoffEdit(report);edited.values["title"]="Harbor Lights – Renamed on iPhone 🎬";return edited
}
func verifyReportTitlePresentation()throws {
    var report=Report.fullHandoffFixture();let id=report.id,revision=report.revision
    for title:String? in [nil,"","  \t\n","  Café / カメラ 🎬  "] {
        report.values["title"]=title;let stored=try Exchange.encoder().encode(report)
        let expected=(title ?? "").trimmingCharacters(in:.whitespacesAndNewlines)
        guard report.displayTitle==Report.displayTitle(expected,day:report.values["day"]),report.id==id,report.revision==revision,try Exchange.encoder().encode(report)==stored else {throw ReportError.invalid("Production title presentation changed report data or blank fallback failed")}
    }
}

func assertArchive(_ prepared:ProjectArchive.Prepared,edited:Bool)throws {
    try verifyReportTitlePresentation()
    guard prepared.report.measurementUnit == .feetInches,prepared.report.defaults["height"]=="1.45 m",LengthMeasurement.display("1.6764 m",unit:.feetInches)=="5 ft 6 in",prepared.report.entries[0].values["lightMeter"]=="2.8 + 1/3",prepared.report.entries[0].values["sensorRate"] != nil else {throw ReportError.invalid("Units, meter or hidden legacy values did not survive")}

    guard prepared.report == (edited ? phoneTitleEdit(.fullHandoffFixture()):.fullHandoffFixture()),prepared.snapshot.previous != nil else {throw ReportError.invalid("Full report or previous snapshot mismatch")}
    guard let prefs=prepared.snapshot.state.preferences,let dictionary=try PropertyListSerialization.propertyList(from:prefs,format:nil) as? [String:Any],dictionary["theme"] as? String=="Dark",dictionary["opaque"] as? Data==Data([0,255,3]) else {throw ReportError.invalid("Preference snapshot mismatch")}
    guard prepared.snapshot.state.resources.contains(where:{$0.kind=="media" && $0.size>UInt64(Exchange.limit)}),prepared.snapshot.state.resources.contains(where:{$0.kind=="attachment" && $0.name=="照明 – reference.pdf"}),prepared.snapshot.state.resources.contains(where:{$0.kind=="recovery"}) else {throw ReportError.invalid("Missing media, attachment or recovery category")}
    for resource in prepared.snapshot.state.resources {let hash=try ProjectZIP.fingerprint(ProjectArchive.blobURL(prepared.folder,resource.sha256));guard hash.sha256==resource.sha256,hash.size==resource.size else {throw ReportError.invalid("File bytes changed across platforms")}}
}
#if os(iOS)
import UIKit
@main final class CompleteArchiveProbe:UIResponder,UIApplicationDelegate {
    func application(_ app:UIApplication,didFinishLaunchingWithOptions options:[UIApplication.LaunchOptionsKey:Any]?)->Bool {
        let output=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
        DispatchQueue.global(qos:.userInitiated).async {
            do {
                let prepared=try ProjectArchive.read(Bundle.main.url(forResource:"complete-project",withExtension:"camreport")!,to:output.appendingPathComponent("files"));try assertArchive(prepared,edited:false)
                let repo=try Repository(url:output.appendingPathComponent("reports.sqlite3")),slot=UUID().uuidString
                _=try repo.importProject(prepared.snapshot,slot:slot)
                let loaded=try repo.load(slot),edited=phoneTitleEdit(loaded.report)
                _=try repo.save(slot:slot,report:edited,device:"Native iOS Simulator QA",expectedFingerprint:loaded.fingerprint)
                let saved=try repo.projectSnapshot(slot)
                guard saved.state==prepared.snapshot.state,try Exchange.read(saved.previous!).report == Report.fullHandoffFixture(),try repo.load(slot).report.displayTitle=="Harbor Lights – Renamed on iPhone 🎬 Day 12",try repo.load(slot).report.id==loaded.report.id,try Repository(url:output.appendingPathComponent("reports.sqlite3")).load(slot).report.displayTitle=="Harbor Lights – Renamed on iPhone 🎬 Day 12" else {throw ReportError.invalid("iOS persistence lost files, preferences or recovery")}
                try ProjectArchive.write(saved,resources:prepared.folder,device:"Native iPhone Simulator QA",to:output.appendingPathComponent("phone-return.camreport"))
                var next=try edited.nextShootingDay();next.record("Started next shooting day",device:"Native iOS QA")
                var nextState=saved.state;nextState.resources=nextState.resources.filter{$0.kind=="attachment"}
                let nextSlot=UUID().uuidString,nextSnapshot=ProjectArchive.Snapshot(current:try Exchange.export(next,device:"Native iOS QA"),state:nextState)
                _=try repo.importProject(nextSnapshot,slot:nextSlot,expectedSource:Repository.ProjectSourceVersion(slot:slot,fingerprint:try repo.load(slot).fingerprint,state:saved.state))
                guard next.values["day"]=="13",next.values["date"]=="2026-11-13",next.entries.isEmpty,next.id != edited.id,try repo.projectSnapshot(slot)==saved else {throw ReportError.invalid("New day lost source data or copied prior-day takes")}
                try ProjectArchive.write(repo.projectSnapshot(nextSlot),resources:prepared.folder,device:"Native iOS next day QA",to:output.appendingPathComponent("phone-next-day.camreport"))
                try Data("PASS native iOS: full model, >32 MiB media, unicode attachment, preferences, recoveries, persistence, edit and export".utf8).write(to:output.appendingPathComponent("PASS.txt"))
            } catch {try? Data(error.localizedDescription.utf8).write(to:output.appendingPathComponent("FAIL.txt"))}
        };return true
    }
}
#else
@main struct CompleteArchiveProbe {
    static func main()throws {
        let args=CommandLine.arguments,root=URL(fileURLWithPath:args[2]);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        if args[1]=="generate" {
            let pdf=try Reports.pdf(.fullHandoffFixture());try pdf.write(to:root.appendingPathComponent("production-report.pdf"))
            let document=PDFDocument(data:pdf)!
            for i in 0..<document.pageCount {
                let thumbnail=document.page(at:i)!.thumbnail(of:NSSize(width:1684,height:1190),for:.mediaBox)
                let png=NSBitmapImageRep(data:thumbnail.tiffRepresentation!)!.representation(using:.png,properties:[:])!
                try png.write(to:root.appendingPathComponent("report-page-\(i+1).png"))
            }
            let media=root.appendingPathComponent("A001C001.mov")
            FileManager.default.createFile(atPath:media.path,contents:nil);let h=try FileHandle(forWritingTo:media)
            let block=Data((0..<1024*1024).map{UInt8(truncatingIfNeeded:$0)})
            for _ in 0..<35 {try h.write(contentsOf:block)};try h.close()
            let attachment=root.appendingPathComponent("照明 – reference.pdf");try Data("%PDF-1.7\nSynthetic binary\0 attachment 🎥".utf8).write(to:attachment)
            let legacy=root.appendingPathComponent("Legacy recovery.camreport");try Exchange.export(Report(),device:"Legacy QA").write(to:legacy)
            let files=root.appendingPathComponent("sources"),resources=try [(media,"media"),(attachment,"attachment"),(legacy,"recovery")].map{try ProjectArchive.addFile($0.0,kind:$0.1,to:files)}
            var state=ProjectArchive.State();state.resources=resources;state.preferences=try PropertyListSerialization.data(fromPropertyList:["theme":"Dark","detail":"Full","opaque":Data([0,255,3]),"sourceDate":Date(timeIntervalSince1970:55)],format:.binary,options:0)
            let snapshot=ProjectArchive.Snapshot(current:try Exchange.export(.fullHandoffFixture(),device:"Mac QA"),previous:try Exchange.export(Report(),device:"Previous QA"),state:state)
            try ProjectArchive.write(snapshot,resources:files,device:"Native Mac QA",to:root.appendingPathComponent("complete-project.camreport"));print("PASS generated complete archive fixture")
        } else {
            let next=try ProjectArchive.read(root.appendingPathComponent("phone-next-day.camreport"),to:root.appendingPathComponent("next-day-files"))
            guard next.report.values["day"]=="13",next.report.entries.isEmpty,next.report.values["director"]==Report.fullHandoffFixture().values["director"],!next.snapshot.state.resources.contains(where:{$0.kind=="media"}),next.snapshot.state.resources.contains(where:{$0.kind=="attachment"}) else {throw ReportError.invalid("Mac new-day import lost crew/reference data or included prior-day media")}
            let prepared=try ProjectArchive.read(root.appendingPathComponent("phone-return.camreport"),to:root.appendingPathComponent("mac-files"));try assertArchive(prepared,edited:true)
            let repo=try Repository(url:root.appendingPathComponent("mac-return.sqlite3")),slot=UUID().uuidString;_=try repo.importProject(prepared.snapshot,slot:slot)
            try ProjectArchive.write(repo.projectSnapshot(slot),resources:prepared.folder,device:"Mac return QA",to:root.appendingPathComponent("mac-return.camreport"))
            let final=try ProjectArchive.read(root.appendingPathComponent("mac-return.camreport"),to:root.appendingPathComponent("final"));guard final.snapshot==prepared.snapshot else {throw ReportError.invalid("Mac re-export dropped archive information")};print("PASS native Mac round trip preserves full report, exact file bytes, preferences and recoveries")
        }
    }
}
#endif
