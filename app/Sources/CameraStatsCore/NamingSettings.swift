import Foundation

/// Stored in the report so settings travel with backups, imports and local snapshots.
/// Source templates remain intact when a component is hidden.
public struct NamingSettings: Codable, Equatable {
    public enum Preset: String, Codable, CaseIterable, Identifiable {
        case movie = "Movie", television = "TV / Episodic", custom = "Custom"
        public var id: String { rawValue }
    }
    public struct Selection: Codable, Equatable {
        public var name: String
        public var reportTemplate: String
        // Legacy archive field, retained verbatim for non-destructive round trips.
        public var copyTemplate: String
        public var disabled: Set<String> = []
        public init(name: String, reportTemplate: String, copyTemplate: String) {
            self.name = name; self.reportTemplate = reportTemplate; self.copyTemplate = copyTemplate
        }
        enum CodingKeys: String, CodingKey {case name, reportTemplate, copyTemplate, disabled}
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(reportTemplate, forKey: .reportTemplate)
            try container.encode(copyTemplate, forKey: .copyTemplate)
            try container.encode(disabled.sorted(), forKey: .disabled)
        }
    }
    public static let components = ["project", "season", "episode", "scene", "take", "camera", "roll"]
    public static let copyMovie = "{project}_SC{scene}_TK{take:03}_CAM-{camera}_{original}"
    public static let copyTV = "{project}_S{season:02}E{episode:02}_SC{scene}_TK{take:03}_CAM-{camera}_{original}"
    public var preset: Preset { didSet {savedPresetID = nil} }
    public var savedPresetID: String?
    public var selections: [String: Selection]
    public init(legacyTemplate: String = Naming.movie) {
        preset = legacyTemplate == Naming.movie ? .movie : legacyTemplate == Naming.tv ? .television : .custom
        selections = [
            Preset.movie.rawValue: Selection(name: "Movie", reportTemplate: Naming.movie, copyTemplate: Self.copyMovie),
            Preset.television.rawValue: Selection(name: "TV", reportTemplate: Naming.tv, copyTemplate: Self.copyTV),
            Preset.custom.rawValue: Selection(name: "Custom", reportTemplate: legacyTemplate, copyTemplate: Self.copyMovie)
        ]
    }
    public var selection: Selection {
        get { selections[selectionID] ?? NamingSettings().selections[preset.rawValue]! }
        set { selections[selectionID] = newValue }
    }
    public var selectionID: String {savedPresetID ?? preset.rawValue}
    public var savedSelectionIDs: [String] {selections.keys.filter {$0.hasPrefix("saved:")}.sorted()}
    public mutating func select(_ id: String) {
        if let preset = Preset(rawValue: id) {self.preset = preset}
        else if selections[id] != nil {preset = .custom; savedPresetID = id}
    }
    public mutating func loadSaved(id: String, name: String, template: String) {
        let key = "saved:" + id
        if selections[key] == nil {selections[key] = Selection(name: name, reportTemplate: selection.reportTemplate, copyTemplate: template)}
        preset = .custom; savedPresetID = key
    }
    public var visibleComponents: [String] { Self.components.filter { preset != .movie || !["season", "episode"].contains($0) } }
    public func enabled(_ component: String) -> Bool { !selection.disabled.contains(component) && (preset != .movie || !["season", "episode"].contains(component)) }
    public mutating func setEnabled(_ component: String, _ enabled: Bool) {
        var value = selection
        if enabled { value.disabled.remove(component) } else { value.disabled.insert(component) }
        // Add newly selected tokens without replacing the user's template or formatting.
        if enabled {
            let segment = Self.segment(component, padded: false)
            if !Self.tokens(value.reportTemplate).contains(component), !["original", "asset"].contains(component) { value.reportTemplate += "_" + segment }
        }
        selection = value
    }
    public var reportTemplate: String { filtered(selection.reportTemplate) }
    public var copyTemplate: String { filtered(selection.copyTemplate) }
    public func includes(_ component: String) -> Bool { Self.tokens(reportTemplate).contains(component) }
    public func filtered(_ template: String) -> String {
        let disabled = selection.disabled.union(preset == .movie ? ["season", "episode"] : [])
        return template.components(separatedBy: "_").compactMap { segment -> String? in
            let tokens = Self.tokens(segment)
            if !tokens.isEmpty && tokens.isSubset(of: disabled) { return nil }
            var result = segment
            for token in disabled {
                let prefix = ["season": "S", "episode": "E", "scene": "SC", "take": "TK", "camera": "CAM-" ][token] ?? ""
                result = result.replacingOccurrences(of: NSRegularExpression.escapedPattern(for: prefix) + "\\{" + NSRegularExpression.escapedPattern(for: token) + "(?::[0-9]+)?\\}", with: "", options: .regularExpression)
                result = result.replacingOccurrences(of: "\\{" + NSRegularExpression.escapedPattern(for: token) + "(?::[0-9]+)?\\}", with: "", options: .regularExpression)
            }
            return result.isEmpty ? nil : result
        }.joined(separator: "_")
    }
    private static func tokens(_ template: String) -> Set<String> {
        let regex = try! NSRegularExpression(pattern: "\\{([^{}:]+)(?::[0-9]+)?\\}")
        let text = template as NSString
        return Set(regex.matches(in: template, range: NSRange(location: 0, length: text.length)).map { text.substring(with: $0.range(at: 1)) })
    }
    private static func segment(_ token: String, padded: Bool) -> String {
        let prefix = ["season": "S", "episode": "E", "scene": "SC", "take": "TK", "camera": "CAM-"][token] ?? ""
        let width = padded ? (["season": ":02", "episode": ":02", "take": ":03"][token] ?? "") : ""
        return prefix + "{" + token + width + "}"
    }
}

public extension Report {
    var naming: NamingSettings { namingSettings ?? NamingSettings(legacyTemplate: namingTemplate) }
    mutating func updateNaming(_ change: (inout NamingSettings) -> Void) {
        var settings = naming; change(&settings); namingSettings = settings; namingTemplate = settings.reportTemplate
    }
    /// Report-level names use only project tokens from the selected template.
    private var reportNameStem: String? {
        let template = naming.reportTemplate.components(separatedBy: "_").filter { segment in
            !["scene", "take", "camera", "roll", "original", "asset"].contains { segment.contains("{" + $0 + "}") || segment.contains("{" + $0 + ":") }
        }.joined(separator: "_")
        return try? Naming.preview(template: template.isEmpty ? "Shot-Reporter" : template, report: self, entry: Entry(values: [:]))
    }
    var reportNameNeedsValues: Bool {reportNameStem == nil}
    func exportName(extension ext: String) throws -> String {
        // A naming error must never prevent a draft or recovery backup.
        "\(reportNameStem ?? "Shot-Reporter")-r\(revision).\(ext)"
    }
}
