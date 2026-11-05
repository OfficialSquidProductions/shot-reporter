import Foundation
import CryptoKit

public enum Exchange {
    public static let limit = 32 * 1024 * 1024
    public static func encoder() -> JSONEncoder { let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]; return e }
    public static func digest(_ data: Data) -> String { SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined() }
    public struct Manifest: Codable {
        public var format = "org.squidproductions.camreport"
        public var schema = 1
        public var packageID = UUID().uuidString
        public var reportID: String
        public var revision: Int
        public var device: String
        public var scope = "full-report"
        public var sha256: String
    }
    public struct Package {
        public var manifest: Manifest
        public var report: Report
    }
    public static func export(_ report: Report, device: String) throws -> Data {
        let data = try encoder().encode(report)
        let manifest = Manifest(reportID:report.id,revision:report.revision,device:device,sha256:digest(data))
        return try StoredZIP.write([("manifest.json",try encoder().encode(manifest)),("report.json",data)])
    }
    public static func read(_ data: Data) throws -> Package {
        let files = try StoredZIP.read(data)
        guard files.count == 2, let m = files["manifest.json"], let r = files["report.json"] else { throw ReportError.invalid("Expected manifest.json and report.json; this alpha cannot import attachments.") }
        let manifest = try JSONDecoder().decode(Manifest.self,from:m)
        guard manifest.format == "org.squidproductions.camreport", manifest.schema == 1, manifest.scope == "full-report" else { throw ReportError.invalid("Unsupported format, schema, or partial scope. Existing report was preserved.") }
        guard digest(r) == manifest.sha256 else { throw ReportError.invalid("Report checksum mismatch. Existing report was preserved.") }
        // Reject unknown fields rather than silently dropping future data.
        let report = try JSONDecoder().decode(Report.self,from:r)
        let original = try JSONSerialization.jsonObject(with:r) as? NSDictionary
        let roundTrip = try JSONSerialization.jsonObject(with:encoder().encode(report)) as? NSDictionary
        guard original == roundTrip else { throw ReportError.invalid("This report contains unsupported fields. Open with a compatible version; no changes were made.") }
        guard report.id == manifest.reportID, report.revision == manifest.revision, report.entries.count <= 100000, Set(report.entries.map(\.id)).count == report.entries.count else { throw ReportError.invalid("Invalid report identity, revision, or duplicate records.") }
        return Package(manifest:manifest,report:report)
    }
    public struct Preview {
        public var additions: [Entry]
        public var conflicts: [String]
        public var duplicate: Bool
    }
    public static func preview(local: Report, incoming: Package) throws -> Preview {
        guard local.id == incoming.report.id else { throw ReportError.invalid("Different project. Use Open as separate report instead of merging.") }
        if local.importedPackages.contains(incoming.manifest.packageID) { return Preview(additions:[],conflicts:[],duplicate:true) }
        let known = Dictionary(uniqueKeysWithValues:local.entries.map{($0.id,$0)})
        let additions = incoming.report.entries.filter{known[$0.id] == nil}
        var conflicts = incoming.report.entries.compactMap { e -> String? in guard let old = known[e.id], old != e else { return nil }; return "Scene \(e.values["scene",default:"?"]) / take \(e.values["take",default:"?"]) (\(e.id.prefix(8)))" }
        if local.values != incoming.report.values { conflicts.append("Project / crew metadata") }
        if local.defaults != incoming.report.defaults { conflicts.append("Camera defaults") }
        if local.profile != incoming.report.profile || local.positions != incoming.report.positions || local.namingTemplate != incoming.report.namingTemplate || local.namingSettings != incoming.report.namingSettings { conflicts.append("Report settings / preserved legacy data") }
        return Preview(additions:additions,conflicts:conflicts,duplicate:false)
    }
    // This conservative alpha merges independent additions only. Competing edits are retained in the imported file, never silently resolved.
    public static func mergeAdditions(local: Report, incoming: Package, device: String) throws -> Report {
        let p = try preview(local:local,incoming:incoming)
        if p.duplicate { return local }
        guard p.conflicts.isEmpty else { throw ReportError.invalid("Competing changes need review. Open the incoming file separately; automatic conflict resolution is unavailable in this alpha.") }
        var result = local; result.entries += p.additions; result.importedPackages.append(incoming.manifest.packageID); result.record("Imported \(p.additions.count) additions from \(incoming.manifest.device)",device:device); return result
    }
}

// Dependency-free, uncompressed ZIP subset. Size, path, CRC and archive structure are validated before JSON decoding.
public enum StoredZIP {
    static func crc(_ data: Data) -> UInt32 { var c: UInt32 = 0xffffffff; for b in data { c ^= UInt32(b); for _ in 0..<8 { c = (c >> 1) ^ (c & 1 == 1 ? 0xedb88320 : 0) } }; return c ^ 0xffffffff }
    static func num(_ n: UInt32, _ width: Int) -> Data { Data((0..<width).map{UInt8(truncatingIfNeeded:n >> ($0*8))}) }
    static func val(_ data: Data, _ p: Int, _ n: Int) throws -> UInt32 { guard p >= 0, p+n <= data.count else { throw ReportError.invalid("Truncated archive") }; return (0..<n).reduce(UInt32(0)){$0 | UInt32(data[p+$1]) << ($1*8)} }
    public static func write(_ files: [(String,Data)]) throws -> Data {
        var out = Data(), directory = Data()
        for (name,bytes) in files {
            let nameData = Data(name.utf8), offset = UInt32(out.count), checksum = crc(bytes), size = UInt32(bytes.count)
            for (n,w) in [(UInt32(0x04034b50),4),(20,2),(0,2),(0,2),(0,2),(0,2),(checksum,4),(size,4),(size,4),(UInt32(nameData.count),2),(0,2)] { out += num(n,w) }
            out += nameData; out += bytes
            for (n,w) in [(UInt32(0x02014b50),4),(20,2),(20,2),(0,2),(0,2),(0,2),(0,2),(checksum,4),(size,4),(size,4),(UInt32(nameData.count),2),(0,2),(0,2),(0,2),(0,2),(0,4),(offset,4)] { directory += num(n,w) }; directory += nameData
        }
        let start = UInt32(out.count); out += directory
        for (n,w) in [(UInt32(0x06054b50),4),(0,2),(0,2),(UInt32(files.count),2),(UInt32(files.count),2),(UInt32(directory.count),4),(start,4),(0,2)] { out += num(n,w) }
        guard out.count <= Exchange.limit else { throw ReportError.invalid("Report exceeds the 32 MiB alpha limit") }; return out
    }
    public static func read(_ input: Data) throws -> [String:Data] {
        let data = Data(input)
        guard data.count >= 22, data.count <= Exchange.limit else { throw ReportError.invalid("Invalid archive size (32 MiB maximum)") }
        var p = 0, files: [String:Data] = [:], offsets:[String:Int] = [:]
        while try val(data,p,4) == 0x04034b50 {
            guard files.count < 8, try val(data,p+6,2) == 0, try val(data,p+8,2) == 0 else { throw ReportError.invalid("Only unencrypted stored ZIP packages are supported in schema 1") }
            let size = Int(try val(data,p+18,4)), expanded = Int(try val(data,p+22,4)), nameLen = Int(try val(data,p+26,2)), extra = Int(try val(data,p+28,2))
            let begin = p+30+nameLen+extra
            guard size == expanded, size <= Exchange.limit, begin <= data.count, begin+size <= data.count, let name = String(data:data.subdata(in:p+30..<p+30+nameLen),encoding:.utf8), ["manifest.json","report.json"].contains(name), files[name] == nil else { throw ReportError.invalid("Unsafe path, duplicate entry, or invalid archive bounds") }
            let bytes = data.subdata(in:begin..<begin+size)
            guard crc(bytes) == (try val(data,p+14,4)) else { throw ReportError.invalid("Archive CRC mismatch") }
            offsets[name] = p; files[name] = bytes; p = begin+size
        }
        let directoryStart = p; var seen = Set<String>()
        while try val(data,p,4) == 0x02014b50 {
            let n = Int(try val(data,p+28,2)), extra = Int(try val(data,p+30,2)), comment = Int(try val(data,p+32,2))
            guard p+46+n+extra+comment <= data.count, let name = String(data:data.subdata(in:p+46..<p+46+n),encoding:.utf8), !seen.contains(name), let bytes = files[name], offsets[name] == Int(try val(data,p+42,4)), crc(bytes) == (try val(data,p+16,4)), bytes.count == Int(try val(data,p+20,4)), bytes.count == Int(try val(data,p+24,4)), try val(data,p+10,2) == 0, try val(data,p+8,2) == 0, try val(data,p+34,2) == 0 else { throw ReportError.invalid("Invalid archive directory") }
            seen.insert(name); p += 46+n+extra+comment
        }
        guard try val(data,p,4) == 0x06054b50, p+22 == data.count, try val(data,p+4,4) == 0, Int(try val(data,p+8,2)) == files.count, Int(try val(data,p+10,2)) == files.count, Int(try val(data,p+12,4)) == p-directoryStart, Int(try val(data,p+16,4)) == directoryStart, try val(data,p+20,2) == 0, seen.count == files.count else { throw ReportError.invalid("Incomplete or unsupported ZIP directory") }
        return files
    }
}
