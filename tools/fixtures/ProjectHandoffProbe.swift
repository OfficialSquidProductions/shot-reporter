import Foundation
#if os(iOS)
import UIKit
@main final class HandoffProbe:UIResponder,UIApplicationDelegate {
    func application(_ application:UIApplication,didFinishLaunchingWithOptions options:[UIApplication.LaunchOptionsKey:Any]?)->Bool {
        let output=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
        do {
            let bytes=try Data(contentsOf:Bundle.main.url(forResource:"full-project",withExtension:"camreport")!)
            let report=try Exchange.read(bytes).report
            guard report == Report.fullHandoffFixture() else {throw ReportError.invalid("iOS full model mismatch")}
            let repo=try Repository(url:output.appendingPathComponent("reports.sqlite3")),slot=UUID().uuidString
            _=try repo.save(slot:slot,report:report,device:"iPhone Simulator QA",expectedFingerprint:nil)
            guard try repo.load(slot).report == report else {throw ReportError.invalid("iOS persisted report mismatch")}
            let edited=Report.phoneHandoffEdit(try repo.load(slot).report)
            try Exchange.export(edited,device:"iPhone Simulator QA").write(to:output.appendingPathComponent("phone-return.camreport"))
            try Data("PASS: iOS native core read, persisted, edited and exported every project/model field".utf8).write(to:output.appendingPathComponent("PASS.txt"))
        } catch {try? Data(error.localizedDescription.utf8).write(to:output.appendingPathComponent("FAIL.txt"))}
        return true
    }
}
#else
import PDFKit
import AppKit
@main struct HandoffProbe {
    static func main() throws {
        let args=CommandLine.arguments,root=URL(fileURLWithPath:args[2]);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        if args[1]=="generate" {
            let report=Report.fullHandoffFixture();try Exchange.export(report,device:"Mac QA").write(to:root.appendingPathComponent("full-project.camreport"));try Reports.pdf(report).write(to:root.appendingPathComponent("readable-camera-report.pdf"))
        } else if args[1]=="render" {
            let pdf=PDFDocument(url:root.appendingPathComponent("readable-camera-report.pdf"))!
            for i in 0..<pdf.pageCount {
                let image=pdf.page(at:i)!.thumbnail(of:NSSize(width:1684,height:1190),for:.mediaBox)
                let data=NSBitmapImageRep(data:image.tiffRepresentation!)!.representation(using:.png,properties:[:])!
                try data.write(to:root.appendingPathComponent("report-page-\(i+1).png"))
            };print("Rendered \(pdf.pageCount) PDF pages")
        } else {
            let report=try Exchange.read(Data(contentsOf:root.appendingPathComponent("phone-return.camreport"))).report
            guard report == Report.phoneHandoffEdit(Report.fullHandoffFixture()) else {throw ReportError.invalid("Mac full return model mismatch")}
            let repo=try Repository(url:root.appendingPathComponent("mac-return.sqlite3")),slot=UUID().uuidString
            _=try repo.save(slot:slot,report:report,device:"Mac QA",expectedFingerprint:nil)
            let exported=try Exchange.export(repo.load(slot).report,device:"Mac QA return")
            guard try Exchange.read(exported).report == report else {throw ReportError.invalid("Mac persisted re-export mismatch")}
            try exported.write(to:root.appendingPathComponent("mac-return.camreport"));print("PASS: native iOS Simulator -> Mac full model, persistence and re-export")
        }
    }
}
#endif
