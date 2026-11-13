import Foundation
import CoreGraphics
import CoreText

public enum Reports {
    public static func csv(_ report: Report) -> String {
        let keys = Schema.take.map(\.id) + (Schema.settings+Schema.legacySettings).map(\.id) + ["flags","reviewed","entryID"]
        func quote(_ s: String) -> String { "\"" + s.replacingOccurrences(of:"\"",with:"\"\"") + "\"" }
        var rows = [keys.map(quote).joined(separator:",")]
        rows += report.active.map { entry in keys.map { key in quote(key == "flags" ? entry.flags.sorted().joined(separator:"; ") : key == "reviewed" ? String(entry.reviewed) : key == "entryID" ? entry.id : report.displayedValue(key,in:entry)) }.joined(separator:",") }
        return rows.joined(separator:"\r\n") + "\r\n"
    }
    public static func html(_ report: Report) -> String {
        func esc(_ s: String) -> String { s.replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:"<",with:"&lt;").replacingOccurrences(of:">",with:"&gt;").replacingOccurrences(of:"\"",with:"&quot;") }
        let fields = Schema.take + Schema.settings
        let rows = report.active.map { e in "<tr>" + fields.map{"<td>\(esc(report.displayedValue($0.id,in:e)))</td>"}.joined() + "<td>\(esc(e.flags.sorted().joined(separator:", ")))</td></tr>" }.joined()
        return "<!doctype html><html lang=\"en\"><meta charset=\"utf-8\"><title>Shot Reporter report</title><style>body{font:14px system-ui;margin:32px;color:#241d21}table{border-collapse:collapse}td,th{border:1px solid #777;padding:8px;white-space:pre-wrap}thead{display:table-header-group}</style><h1>\(esc(report.displayTitle))</h1><p>A Squid Productions Software · Revision \(report.revision) · \(report.missing.isEmpty ? "Ready for Submission" : "DRAFT — \(report.missing.count) missing requirements")</p><p>\(esc(report.visibleProjectValues.sorted{$0.key < $1.key}.map{"\($0.key): \($0.value)"}.joined(separator:" · ")))</p><table><thead><tr>" + fields.map{"<th>\(esc($0.title))</th>"}.joined() + "<th>Flags</th></tr></thead><tbody>\(rows)</tbody></table></html>"
    }
    public static func pdf(_ report: Report) throws -> Data {
        let output=NSMutableData(),pageWidth:CGFloat=842,pageHeight:CGFloat=595
        var box=CGRect(x:0,y:0,width:pageWidth,height:pageHeight)
        guard let consumer=CGDataConsumer(data:output),let cg=CGContext(consumer:consumer,mediaBox:&box,[kCGPDFContextCreator as String:"Shot Reporter - Squid Productions",kCGPDFContextTitle as String:report.displayTitle] as CFDictionary) else {throw ReportError.invalid("Could not create PDF")}
        struct Line {let text:String;let bold:Bool}
        func draw(_ text:String,_ x:CGFloat,_ y:CGFloat,_ size:CGFloat=10,_ bold:Bool=false) {
            let font=CTFontCreateWithName((bold ? "Helvetica-Bold" : "Helvetica") as CFString,size,nil)
            let attr=NSAttributedString(string:text,attributes:[NSAttributedString.Key(kCTFontAttributeName as String):font,NSAttributedString.Key(kCTForegroundColorAttributeName as String):CGColor(gray:0.12,alpha:1)])
            cg.textPosition=CGPoint(x:x,y:pageHeight-y);CTLineDraw(CTLineCreateWithAttributedString(attr),cg)
        }
        func wrap(_ text:String,width:CGFloat,bold:Bool=false)->[Line] {
            let font=CTFontCreateWithName((bold ? "Helvetica-Bold" : "Helvetica") as CFString,bold ? 9:10,nil)
            return text.components(separatedBy:.newlines).flatMap {paragraph -> [Line] in
                if paragraph.isEmpty {return [Line(text:"",bold:bold)]}
                let attr=NSAttributedString(string:paragraph,attributes:[NSAttributedString.Key(kCTFontAttributeName as String):font])
                let ts=CTTypesetterCreateWithAttributedString(attr),ns=paragraph as NSString
                var index=0,result:[Line]=[]
                while index < ns.length {let count=max(1,CTTypesetterSuggestLineBreak(ts,index,Double(width)));result.append(Line(text:ns.substring(with:NSRange(location:index,length:count)),bold:bold));index += count}
                return result
            }
        }
        func field(_ title:String,_ value:String?,width:CGFloat)->[Line] {
            wrap(title+":",width:width,bold:true)+wrap(value?.isEmpty == false ? value!:"Not entered",width:width)+[Line(text:"",bold:false)]
        }
        var page=0
        func begin(_ section:String) {
            page += 1;cg.beginPDFPage(nil)
            let titleFont=CTFontCreateWithName("Helvetica-Bold" as CFString,16,nil)
            let titleAttributes=[NSAttributedString.Key(kCTFontAttributeName as String):titleFont]
            let title=CTLineCreateWithAttributedString(NSAttributedString(string:report.displayTitle,attributes:titleAttributes))
            let ellipsis=CTLineCreateWithAttributedString(NSAttributedString(string:"...",attributes:titleAttributes))
            cg.textPosition=CGPoint(x:28,y:pageHeight-30);CTLineDraw(CTLineCreateTruncatedLine(title,786,.end,ellipsis) ?? title,cg)
            draw("Shot Reporter - Camera Report | A Squid Productions Software",28,49,9)
            draw(section,28,72,11,true)
            cg.setStrokeColor(CGColor(gray:0.72,alpha:1));cg.move(to:CGPoint(x:28,y:pageHeight-82));cg.addLine(to:CGPoint(x:814,y:pageHeight-82));cg.strokePath()
            draw("Revision \(report.revision)  |  Report \(report.id.prefix(8))",28,577,8)
            draw("Page \(page)",755,577,8)
        }
        // A separate production overview keeps long crew/project information away from take details.
        let status=report.missing.isEmpty ? "READY FOR SUBMISSION - self-reviewed local report":"DRAFT - \(report.missing.count) outstanding requirements"
        var overview=wrap(status,width:786,bold:true)+[Line(text:"",bold:false)]
        overview += field("Production mode",report.productionMode.title,width:786)
        for f in report.projectFields {overview += field(f.title,report.values[f.id],width:786)}
        var offset=0
        repeat {
            begin(offset == 0 ? "Production / crew":"Production / crew - continued")
            let end=min(offset+35,overview.count)
            for n in offset..<end {let line=overview[n];draw(line.text,28,104+CGFloat(n-offset)*13,line.bold ? 9:10,line.bold)}
            cg.endPDFPage();offset=end
        } while offset < overview.count
        let active=report.active
        if active.isEmpty {begin("Takes");draw("No takes recorded.",28,110);cg.endPDFPage()}
        let widths:[CGFloat]=[210,240,300],xs:[CGFloat]=[28,256,514]
        for (index,e) in active.enumerated() {
            let v=e.values
            let camera=[Field("scene","Scene / setup",""),Field("take","Take label","")]+Schema.settings.filter{["camera","mag","load","lens","stop","height","distance"].contains($0.id)}
            let recording=Schema.settings.filter{!["camera","mag","load","lens","stop","height","distance","roll"].contains($0.id)}
            let notes=Schema.take.filter{!["scene","take"].contains($0.id) && !Schema.lighting.map(\.id).contains($0.id)}
            let meterRaw=v["lightMeter",default:""],meterUnit=v["lightMeterUnit",default:"f-stop"]
            let meterValue=meterUnit=="f-stop" ? (meterRaw.lowercased().hasPrefix("f/") ? meterRaw:"f/"+meterRaw):meterRaw+" "+meterUnit
            let lighting=meterRaw.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? []:wrap("LIGHT AT SUBJECT",width:widths[1],bold:true)+field("Meter reading",meterValue,width:widths[1])+field("Subject / meter context",v["lightMeterContext"],width:widths[1])
            let columns=[camera.flatMap{field($0.title,report.displayedValue($0.id,in:e),width:widths[0])},recording.flatMap{field($0.title,report.displayedValue($0.id,in:e),width:widths[1])}+lighting,field("Flags",e.flags.isEmpty ? "None":e.flags.sorted().joined(separator:", "),width:widths[2])+field("Review",e.reviewed ? "Reviewed":"Review pending",width:widths[2])+notes.flatMap{field($0.title,v[$0.id],width:widths[2])}]
            // Keep columns independent and preserve long multiline notes on labeled continuation pages.
            var row=0
            repeat {
                begin("Take \(index+1) of \(active.count) - \(row == 0 ? "recorded details":"continued")")
                for i in columns.indices {draw(["CAMERA / MEDIA / LENS","RECORDING SETTINGS","NOTES / POST REFERENCES"][i],xs[i],103,9,true)}
                let end=min(row+33,columns.map(\.count).max() ?? 0)
                for n in row..<end {for i in columns.indices where n < columns[i].count {let line=columns[i][n];draw(line.text,xs[i],124+CGFloat(n-row)*13,line.bold ? 9:10,line.bold)}}
                cg.endPDFPage();row=end
            } while row < (columns.map(\.count).max() ?? 0)
        }
        cg.closePDF();return output as Data
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
