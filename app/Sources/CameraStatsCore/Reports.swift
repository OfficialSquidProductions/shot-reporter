import Foundation
import CoreGraphics
import CoreText

public enum Reports {
    public static func csv(_ report: Report) -> String {
        let keys = Schema.take.map(\.id) + Schema.settings.map(\.id) + ["flags","reviewed","entryID"]
        func quote(_ s: String) -> String { "\"" + s.replacingOccurrences(of:"\"",with:"\"\"") + "\"" }
        var rows = [keys.map(quote).joined(separator:",")]
        rows += report.active.map { entry in keys.map { key in quote(key == "flags" ? entry.flags.sorted().joined(separator:"; ") : key == "reviewed" ? String(entry.reviewed) : key == "entryID" ? entry.id : entry.values[key,default:""]) }.joined(separator:",") }
        return rows.joined(separator:"\r\n") + "\r\n"
    }
    public static func html(_ report: Report) -> String {
        func esc(_ s: String) -> String { s.replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:"<",with:"&lt;").replacingOccurrences(of:">",with:"&gt;").replacingOccurrences(of:"\"",with:"&quot;") }
        let fields = Schema.take + Schema.settings
        let rows = report.active.map { e in "<tr>" + fields.map{"<td>\(esc(e.values[$0.id,default:""]))</td>"}.joined() + "<td>\(esc(e.flags.sorted().joined(separator:", ")))</td></tr>" }.joined()
        return "<!doctype html><html lang=\"en\"><meta charset=\"utf-8\"><title>Shot Reporter report</title><style>body{font:14px system-ui;margin:32px;color:#241d21}table{border-collapse:collapse}td,th{border:1px solid #777;padding:8px;white-space:pre-wrap}thead{display:table-header-group}</style><h1>\(esc(report.values["title",default:"Untitled"]))</h1><p>A Squid Productions Software · Revision \(report.revision) · \(report.missing.isEmpty ? "Ready for Submission" : "DRAFT — \(report.missing.count) missing requirements")</p><p>\(esc(report.visibleProjectValues.sorted{$0.key < $1.key}.map{"\($0.key): \($0.value)"}.joined(separator:" · ")))</p><table><thead><tr>" + fields.map{"<th>\(esc($0.title))</th>"}.joined() + "<th>Flags</th></tr></thead><tbody>\(rows)</tbody></table></html>"
    }
    public static func pdf(_ report: Report) throws -> Data {
        let output = NSMutableData()
        var box = CGRect(x:0,y:0,width:842,height:595)
        guard let consumer = CGDataConsumer(data:output), let cg = CGContext(consumer:consumer,mediaBox:&box,[kCGPDFContextCreator as String:"Shot Reporter · Squid Productions",kCGPDFContextTitle as String:report.values["title",default:"Shot Reporter report"]] as CFDictionary) else { throw ReportError.invalid("Could not create PDF") }
        let font = CTFontCreateWithName("Helvetica" as CFString,9,nil)
        func draw(_ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat = 9) {
            let attr = NSAttributedString(string:s,attributes:[NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString,size,nil)])
            cg.textPosition = CGPoint(x:x,y:595-y); CTLineDraw(CTLineCreateWithAttributedString(attr),cg)
        }
        func wrap(_ text: String, width: CGFloat) -> [String] {
            if text.isEmpty { return [""] }
            let attr = NSAttributedString(string:text,attributes:[NSAttributedString.Key(kCTFontAttributeName as String):font])
            let ts = CTTypesetterCreateWithAttributedString(attr), ns = text as NSString
            var index = 0, lines:[String] = []
            while index < ns.length { let count = max(1,CTTypesetterSuggestLineBreak(ts,index,Double(width))); lines.append(ns.substring(with:NSRange(location:index,length:count)).trimmingCharacters(in:.newlines)); index += count }
            return lines
        }
        var page = 0, y:CGFloat = 0
        let xs:[CGFloat] = [28,83,118,187,252,301,355,423,548]
        let widths:[CGFloat] = [51,31,65,61,45,50,64,121,265]
        func begin() {
            page += 1; cg.beginPDFPage(nil); draw("Shot Reporter · Cinematic Arts Camera Report",28,30,16); draw("A Squid Productions Software",28,47,9)
            draw("\(report.values["title",default:"Untitled"]) · \(report.values["date",default:""]) · Day \(report.values["day",default:""]) · Revision \(report.revision) · Page \(page)",28,65,10)
            draw(report.missing.isEmpty ? "READY FOR SUBMISSION · self-reviewed local report" : "DRAFT · \(report.missing.count) outstanding requirements — export is not proof of submission",28,82,9)
            let metadata = report.projectFields.filter{!["title","date","day"].contains($0.id)}.map{"\($0.title): \(report.values[$0.id,default:"—"])"}.joined(separator:" · ")
            for (i,line) in wrap(metadata,width:786).enumerated() { draw(line,28,100+CGFloat(i)*12) }
            let headers = ["Scene","Take","Camera","Lens","T-stop","Height","Distance","Recording settings","Remarks / flags / role notes"]
            y = 145
            for i in headers.indices { draw(headers[i],xs[i],y,8) }; y += 10
            cg.setStrokeColor(CGColor(gray:0.5,alpha:1)); cg.move(to:CGPoint(x:28,y:595-y)); cg.addLine(to:CGPoint(x:814,y:595-y)); cg.strokePath(); y += 14
        }
        begin()
        if report.active.isEmpty { draw("No takes recorded.",28,y) }
        for e in report.active {
            let v = e.values
            let technical = Schema.settings.filter{!["camera","roll","lens","stop","height","distance"].contains($0.id)}.map{"\($0.title): \(v[$0.id,default:"—"])"}.joined(separator:"; ")
            let notes = (["Flags: " + (e.flags.isEmpty ? "None" : e.flags.sorted().joined(separator:", ")), e.reviewed ? "Reviewed" : "Review pending"] + Schema.take.filter{!["scene","take"].contains($0.id)}.filter{!v[$0.id,default:""].isEmpty}.map{"\($0.title): \(v[$0.id,default:""])"}).joined(separator:"\n")
            let columns = [v["scene",default:"—"],v["take",default:"—"],v["camera",default:"—"],v["lens",default:"—"],v["stop",default:"—"],v["height",default:"—"],v["distance",default:"—"],technical,notes]
            let lines = columns.enumerated().map{wrap($0.element,width:widths[$0.offset])}
            for n in 0..<(lines.map(\.count).max() ?? 1) {
                if y > 555 { cg.endPDFPage(); begin(); draw("Continued take \(v["scene",default:""]) / \(v["take",default:""])",28,y,8); y += 14 }
                for i in lines.indices where n < lines[i].count { draw(lines[i][n],xs[i],y) }; y += 12
            }
            y += 3; cg.setStrokeColor(CGColor(gray:0.8,alpha:1)); cg.move(to:CGPoint(x:28,y:595-y)); cg.addLine(to:CGPoint(x:814,y:595-y)); cg.strokePath(); y += 14
        }
        cg.endPDFPage(); cg.closePDF(); return output as Data
    }
}
public enum Naming {
    public static let tv = "{project}_S{season}E{episode}_SC{scene}_TK{take}_CAM-{camera}"
    public static let movie = "{project}_SC{scene}_TK{take}_CAM-{camera}"
    public static func preview(template: String, report: Report, entry: Entry) throws -> String {
        guard (1...500).contains(template.count) else {throw ReportError.invalid("Naming template must contain 1–500 characters")}
        var values = report.values.merging(entry.values){_,new in new}; values["project"] = report.values["title"]
        var result = template
        while let open = result.firstIndex(of:"{"), let close = result[open...].firstIndex(of:"}") {
            let expression = String(result[result.index(after:open)..<close])
            let parts = expression.split(separator: ":", omittingEmptySubsequences: false)
            guard let first = parts.first, !first.isEmpty else {throw ReportError.invalid("Empty naming token")}
            let token = String(first)
            guard var value = values[token], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ReportError.invalid("Missing naming token: \(token)") }
            if parts.count > 1 {
                guard parts.count == 2, let width = Int(parts[1]), (1...32).contains(width), value.utf8.allSatisfy({(48...57).contains($0)}) else {throw ReportError.invalid("Invalid numeric naming token: \(expression)")}
                value = String(value.drop(while: {$0 == "0"})); if value.isEmpty {value = "0"}
                value = String(repeating: "0", count: max(0, width - value.count)) + value
            }
            guard !value.contains("{") && !value.contains("}") else { throw ReportError.invalid("Invalid token value") }
            result.replaceSubrange(open...close,with:value)
        }
        let stem = result.precomposedStringWithCanonicalMapping
        let reserved = Set(["CON","PRN","AUX","NUL"] + (1...9).flatMap{["COM\($0)","LPT\($0)"]})
        guard !stem.isEmpty, stem.utf8.count <= 180, !stem.contains(where:{"<>:\"/\\|?*{}".contains($0) || $0.asciiValue.map{$0 < 32} == true}), !stem.hasSuffix("."), !stem.hasSuffix(" "), !reserved.contains(stem.components(separatedBy:".")[0].uppercased()) else { throw ReportError.invalid("Name fails portable filename rules") }
        return stem
    }
}
