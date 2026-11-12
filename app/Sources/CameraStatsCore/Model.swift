import Foundation

public struct Field: Identifiable {
    public let id: String
    public let title: String
    public let group: String
    public init(_ id: String, _ title: String, _ group: String) { self.id = id; self.title = title; self.group = group }
}
public enum Schema {
    public static let project: [Field] = [Field("title", "Production title", "Project / crew"), Field("date", "Shooting date", "Project / crew"), Field("day", "Shooting day", "Project / crew"), Field("director", "Director", "Project / crew"), Field("dp", "Director of photography", "Project / crew"), Field("dit", "DIT / data — use N/A if unassigned", "Project / crew"), Field("cycle", "Cycle Group #", "Student"), Field("professor", "Cohort Professor", "Student"), Field("season", "Season", "Project / crew"), Field("episode", "Episode", "Project / crew")]
    public static let settings: [Field] = [Field("camera", "Camera", "Camera / media"), Field("roll", "Camera roll / reel", "Camera / media"), Field("mag", "SSD / physical mag", "Camera / media"), Field("load", "Load ID", "Camera / media"), Field("resolution", "Resolution", "Recording settings"), Field("compression", "Compression", "Recording settings"), Field("aspect", "Aspect ratio", "Recording settings"), Field("playbackRate", "Project time base (e.g. 24000/1001)", "Recording settings"), Field("sensorRate", "Varispeed / sensor FPS", "Recording settings"), Field("shutter", "Shutter angle / speed", "Recording settings"), Field("iso", "ISO", "Recording settings"), Field("temperature", "Color temperature / tint", "Recording settings"), Field("filters", "Filters / internal & external ND", "Recording settings"), Field("look", "Log / gamut / look reference", "Recording settings"), Field("lens", "Lens / focal length", "Lens / measurements"), Field("stop", "T-stop", "Lens / measurements"), Field("height", "Camera height (include units)", "Lens / measurements"), Field("distance", "Focus / subject distance (include units)", "Lens / measurements")]
    public static let take: [Field] = [Field("scene", "Scene / setup", "Slate"), Field("take", "Take label", "Slate"), Field("remarks", "Camera remarks", "Notes"), Field("dpNotes", "DP intent / selects", "Notes"), Field("continuity", "Script / continuity notes", "Notes"), Field("editorNotes", "Editorial notes", "Notes"), Field("sound", "Sound roll / file", "Post references"), Field("originalFilename", "Original clip filename", "Post references"), Field("timecode", "Source timecode (manual)", "Post references")]
    public static let profiles = ["Student / Cinematic Arts Full Report", "Small Crew / Combined Duties", "Feature / Television Department", "Custom Production"]
    public static let positions = ["All Duties", "2nd AC", "1st AC", "DP / operator", "DIT / data", "Script / continuity"]
}
public struct Entry: Codable, Identifiable, Equatable {
    public var id = UUID().uuidString
    public var values: [String:String]
    public var flags: Set<String> = []
    public var reviewed = false
    public var deleted = false
    public var created = Date()
    public init(values: [String:String]) { self.values = values }
    enum CodingKeys:String,CodingKey { case id,values,flags,reviewed,deleted,created }
    public func encode(to encoder:Encoder) throws {
        var c = encoder.container(keyedBy:CodingKeys.self)
        try c.encode(id,forKey:.id); try c.encode(values,forKey:.values); try c.encode(flags.sorted(),forKey:.flags); try c.encode(reviewed,forKey:.reviewed); try c.encode(deleted,forKey:.deleted); try c.encode(created,forKey:.created)
    }
}
public struct Change: Codable, Equatable {
    public var date = Date()
    public var device: String
    public var summary: String
    public init(device: String, summary: String) { self.device = device; self.summary = summary }
}
public struct Report: Codable, Equatable {
    public var id = UUID().uuidString
    public var revision = 0
    public var values: [String:String] = [:]
    public var defaults: [String:String] = ["camera":"A", "roll":"A001", "load":UUID().uuidString, "playbackRate":"24000/1001", "sensorRate":"24000/1001"]
    public var profile = Schema.profiles[0]
    public var positions = ["All Duties"]
    public var entries: [Entry] = []
    public var history: [Change] = []
    public var importedPackages: [String] = []
    public var namingSettings: NamingSettings?
    public var namingTemplate = "{project}_SC{scene}_TK{take}_CAM-{camera}"
    public init() { values["date"] = ISO8601DateFormatter().string(from: Date()).prefix(10).description }
    public var active: [Entry] { entries.filter { !$0.deleted } }
    public mutating func record(_ summary: String, device: String) { revision += 1; history.append(Change(device:device, summary:summary)) }
    public mutating func next(scene: String, device: String) -> String {
        let camera = defaults["camera",default:""]
        let n = active.filter { $0.values["scene"] == scene && $0.values["camera"] == camera }.compactMap { Int($0.values["take",default:""]) }.max() ?? 0
        var snapshot = defaults; snapshot["scene"] = scene; snapshot["take"] = String(n+1)
        let entry = Entry(values:snapshot); entries.append(entry); record("Added scene \(scene), take \(n+1), camera \(camera)", device:device); return entry.id
    }
    // Current logging settings are persisted in the existing defaults map for schema-1 compatibility.
    public mutating func setRecordingSetting(_ key: String, value: String, takeID: String? = nil) {
        guard Schema.settings.contains(where: { $0.id == key }) else { return }
        if let takeID {
            guard let index = entries.firstIndex(where: { $0.id == takeID && !$0.deleted }) else { return }
            entries[index].values[key] = value
            entries[index].reviewed = false
        }
        defaults[key] = value
    }
    public mutating func returnToDefaults() { defaults = Report().defaults }
    public var missing: [String] {
        var result: [String] = []
        let required = ["title","date","director","dp","dit"] + (profile == Schema.profiles[0] ? ["cycle","professor"] : [])
        for key in required where values[key,default:""].trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { result.append(Schema.project.first{$0.id == key}!.title) }
        if active.isEmpty { result.append("At least one take") }
        for (i, entry) in active.enumerated() {
            for field in Schema.settings + Array(Schema.take.prefix(2)) where entry.values[field.id,default:""].trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
                result.append("Row \(i+1): \(field.title)")
            }
            if !entry.reviewed { result.append("Row \(i+1): review") }
        }
        return result
    }
}
public enum ReportError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { switch self { case .invalid(let s): return s } }
}
