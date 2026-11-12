import Foundation

func phoneTitleEdit(_ report:Report)->Report {
    var edited=Report.phoneHandoffEdit(report);edited.values["title"]="Harbor Lights – Renamed on iPhone 🎬";return edited
}
func verifyReportTitlePresentation()throws {
    var report=Report.fullHandoffFixture();let id=report.id,revision=report.revision
    for title:String? in [nil,"","  \t\n","  Café / カメラ 🎬  "] {
        report.values["title"]=title;let stored=try Exchange.encoder().encode(report)
        let expected=(title ?? "").trimmingCharacters(in:.whitespacesAndNewlines)
        guard report.displayTitle==(expected.isEmpty ? "Untitled production":expected),report.id==id,report.revision==revision,try Exchange.encoder().encode(report)==stored else {throw ReportError.invalid("Production title presentation changed report data or blank fallback failed")}
    }
}

func assertArchive(_ prepared:ProjectArchive.Prepared,edited:Bool)throws {
    try verifyReportTitlePresentation()
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
                guard saved.state==prepared.snapshot.state,try Exchange.read(saved.previous!).report == Report.fullHandoffFixture(),try repo.load(slot).report.displayTitle=="Harbor Lights – Renamed on iPhone 🎬",try repo.load(slot).report.id==loaded.report.id,try Repository(url:output.appendingPathComponent("reports.sqlite3")).load(slot).report.displayTitle=="Harbor Lights – Renamed on iPhone 🎬" else {throw ReportError.invalid("iOS persistence lost files, preferences or recovery")}
                try ProjectArchive.write(saved,resources:prepared.folder,device:"Native iPhone Simulator QA",to:output.appendingPathComponent("phone-return.camreport"))
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
            let prepared=try ProjectArchive.read(root.appendingPathComponent("phone-return.camreport"),to:root.appendingPathComponent("mac-files"));try assertArchive(prepared,edited:true)
            let repo=try Repository(url:root.appendingPathComponent("mac-return.sqlite3")),slot=UUID().uuidString;_=try repo.importProject(prepared.snapshot,slot:slot)
            try ProjectArchive.write(repo.projectSnapshot(slot),resources:prepared.folder,device:"Mac return QA",to:root.appendingPathComponent("mac-return.camreport"))
            let final=try ProjectArchive.read(root.appendingPathComponent("mac-return.camreport"),to:root.appendingPathComponent("final"));guard final.snapshot==prepared.snapshot else {throw ReportError.invalid("Mac re-export dropped archive information")};print("PASS native Mac round trip preserves full report, exact file bytes, preferences and recoveries")
        }
    }
}
#endif
