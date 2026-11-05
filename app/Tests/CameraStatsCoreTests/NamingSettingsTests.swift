import XCTest
@testable import CameraStatsCore
@testable import CameraStats

final class NamingSettingsTests: XCTestCase {
    func testMovieTVAndCustomSwitchingRetainsValuesAndChoices() throws {
        var report = Report.fixture()
        report.values["season"] = "2"; report.values["episode"] = "7"
        let metadata = report.values
        report.updateNaming {$0.preset = .television; $0.setEnabled("camera", false)}
        XCTAssertTrue(report.naming.reportTemplate.contains("{season}"))
        XCTAssertFalse(report.naming.reportTemplate.contains("{camera}"))
        report.updateNaming {$0.preset = .movie}
        XCTAssertFalse(report.naming.visibleComponents.contains("season"))
        XCTAssertFalse(report.naming.copyTemplate.contains("season"))
        XCTAssertFalse(try report.exportName(extension: "csv").contains("S2E7"))
        report.updateNaming {$0.preset = .television}
        XCTAssertFalse(report.naming.enabled("camera"))
        XCTAssertTrue(try report.exportName(extension: "csv").contains("S2E7"))
        XCTAssertEqual(report.values, metadata)
        report.updateNaming {$0.preset = .custom; var value = $0.selection; value.reportTemplate = "custom_{project}_S{season:02}E{episode:02}"; value.copyTemplate = "custom_{project}_{roll}_{original}"; $0.selection = value}
        let custom = report.naming.selection
        report.updateNaming {$0.preset = .movie}; report.updateNaming {$0.preset = .custom}
        XCTAssertEqual(report.naming.selection, custom)
        XCTAssertTrue(try report.exportName(extension: "html").contains("S02E07"))
    }
    func testDisabledEmptyFieldsAndNumericValidation() throws {
        var report = Report.fixture(); report.values["season"] = ""; report.values["episode"] = " "
        report.updateNaming {$0.preset = .movie}
        XCTAssertNoThrow(try Naming.preview(template: report.naming.reportTemplate, report: report, entry: report.entries[0]))
        report.updateNaming {$0.preset = .television}
        XCTAssertTrue(report.reportNameNeedsValues)
        XCTAssertEqual(try report.exportName(extension: "csv"), "Shot-Reporter-r\(report.revision).csv")
        XCTAssertThrowsError(try Naming.preview(template: report.naming.reportTemplate, report: report, entry: report.entries[0]))
        report.updateNaming {$0.setEnabled("season", false); $0.setEnabled("episode", false)}
        XCTAssertNoThrow(try report.exportName(extension: "csv"))
        XCTAssertFalse(report.reportNameNeedsValues)
        XCTAssertFalse(report.naming.copyTemplate.contains("_SE_"))
        report.updateNaming {$0.setEnabled("project", false)}
        XCTAssertEqual(try report.exportName(extension: "csv"), "Shot-Reporter-r\(report.revision).csv")
        XCTAssertThrowsError(try Naming.preview(template: "{take:99}", report: report, entry: report.entries[0]))
        XCTAssertThrowsError(try Naming.preview(template: "{take:}", report: report, entry: report.entries[0]))
    }
    func testHiddenTokensInEditedMovieTemplatesAreAlwaysOmitted() {
        var settings = NamingSettings()
        var selection = settings.selection
        selection.reportTemplate = "{project}_S{season}E{episode}_SC{scene}"
        selection.copyTemplate = "{project}_{season}_{episode}_{original}"
        settings.selection = selection
        XCTAssertEqual(settings.reportTemplate, "{project}_SC{scene}")
        XCTAssertEqual(settings.copyTemplate, "{project}_{original}")
        XCTAssertEqual(settings.selection, selection)
    }
    func testSavedPresetsKeepIndependentCustomizations() throws {
        var settings = NamingSettings()
        settings.preset = .custom
        var value = settings.selection; value.copyTemplate = "MY_{project}_{asset}"; settings.selection = value
        settings.loadSaved(id: "older:v4", name: "Saved studio", template: "STUDIO_{project}_{original}")
        settings.setEnabled("project", false)
        let saved = settings.selection, id = settings.selectionID
        settings.preset = .custom
        XCTAssertEqual(settings.copyTemplate, "MY_{project}_{asset}")
        settings.select(id)
        XCTAssertEqual(settings.selection, saved)
        settings.loadSaved(id: "older:v4", name: "Saved studio", template: "STUDIO_{project}_{original}")
        XCTAssertEqual(settings.selection, saved)
        XCTAssertEqual(try JSONDecoder().decode(NamingSettings.self, from: Exchange.encoder().encode(settings)), settings)
    }
    @MainActor func testPersistenceExchangeRecoveryAndLegacyMigration() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ShotReporterTest-Naming-" + UUID().uuidString)
        defer {try? FileManager.default.removeItem(at: root)}
        let preferences = UserDefaults(suiteName: "ShotReporterTest-Naming-" + UUID().uuidString)!
        let store = Store(root: root, preferences: preferences); store.open(.fixture())
        let original = store.report
        store.change {report in report.updateNaming {$0.preset = .television; $0.setEnabled("camera", false); $0.setEnabled("take", false)}}
        let expected = store.report
        let reopened = Store(root: root, preferences: preferences)
        XCTAssertEqual(reopened.report, expected)
        XCTAssertEqual(try Exchange.read(Exchange.export(expected, device: "test")).report, expected)
        let repo = try Repository(url: root.appendingPathComponent("reports.sqlite3"))
        XCTAssertEqual(try repo.load(store.slot, previous: true).report, original)
        for _ in 0..<10 {XCTAssertEqual(try Exchange.encoder().encode(expected), try Exchange.encoder().encode(reopened.report))}
        var legacy = Report.fixture(); legacy.namingTemplate = "handmade_{project}_{roll}"
        XCTAssertNil(legacy.namingSettings); XCTAssertEqual(legacy.naming.preset, .custom)
        XCTAssertEqual(legacy.naming.reportTemplate, legacy.namingTemplate)
        // Actual pre-feature archive has no namingSettings key.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Exchange.encoder().encode(legacy)) as? [String: Any]); json.removeValue(forKey: "namingSettings")
        let decoded = try JSONDecoder().decode(Report.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.naming.reportTemplate, legacy.namingTemplate)
        var incoming = expected
        incoming.updateNaming {var selection = $0.selection; selection.copyTemplate += "_{asset}"; $0.selection = selection}
        let package = try Exchange.read(Exchange.export(incoming, device: "other"))
        XCTAssertFalse(try Exchange.preview(local: expected, incoming: package).conflicts.isEmpty)
        XCTAssertThrowsError(try Exchange.mergeAdditions(local: expected, incoming: package, device: "test"))
    }
}
