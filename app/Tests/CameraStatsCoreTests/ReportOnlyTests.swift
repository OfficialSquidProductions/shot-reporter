import XCTest
import SwiftUI
import AppKit
import CameraStatsCore
@testable import CameraStats

final class ReportOnlyTests: XCTestCase {
    func testDestinationsContainOnlyReportingWorkflows() {
        XCTAssertEqual(Destination.allCases.map(\.rawValue), ["Today", "Log", "Review", "Saves"])
    }

    func testAppSourcesHaveNoRemovedWorkflowEntrypoints() throws {
        let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sources = app.appendingPathComponent("Sources/CameraStats")
        for filename in ["DesktopMediaView.swift", "DesktopMediaModel.swift", "DesktopMediaTypes.swift"] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: sources.appendingPathComponent(filename).path))
        }
        let workspace = try String(contentsOf: sources.appendingPathComponent("CameraStatsApp.swift"))
        for removed in ["Footage", "DesktopMedia", "NamingSettingsView", "Naming.preview", "copyTemplate", "Saved footage presets"] {
            XCTAssertFalse(workspace.contains(removed), "Removed workflow returned: \(removed)")
        }
        XCTAssertTrue(workspace.contains("ForEach(Schema.project)"), "Project metadata must not depend on a retired naming preset")
        let updates = try String(contentsOf: sources.appendingPathComponent("DesktopUpdates.swift"))
        XCTAssertFalse(updates.contains("desktop-media"))
        XCTAssertFalse(updates.contains("DesktopUpdateMediaLease"))
    }

    @MainActor func testReportingScreensRenderWithoutMediaServices() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ShotReporter-ReportScreens-" + UUID().uuidString)
        defer {try? FileManager.default.removeItem(at: root)}
        let suite = "ShotReporter-ReportScreens-" + UUID().uuidString
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {preferences.removePersistentDomain(forName: suite)}
        let store = Store(root: root, preferences: preferences)
        store.open(.demo())
        _ = NSApplication.shared
        for destination in Destination.allCases {
            let host = NSHostingView(rootView: Workspace(store: store).content(destination))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 800), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host
            host.frame = NSRect(x: 0, y: 0, width: 1100, height: 800)
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertGreaterThan(host.fittingSize.height, 0)
            XCTAssertEqual(host.bounds.height, 800)
            window.close()
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("desktop-media").path))
    }

    @MainActor func testLegacyArchivesAndLocalDataRemainIntact() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ShotReporter-ReportOnly-" + UUID().uuidString)
        defer {try? FileManager.default.removeItem(at: root)}
        let oldDirectory = root.appendingPathComponent("desktop-media/legacy-report", isDirectory: true)
        try FileManager.default.createDirectory(at: oldDirectory, withIntermediateDirectories: true)
        let untouched = oldDirectory.appendingPathComponent("media.sqlite3")
        let originalBytes = Data("legacy data must not be migrated or deleted".utf8)
        try originalBytes.write(to: untouched)
        var legacy = Report.fixture()
        legacy.updateNaming {settings in
            settings.loadSaved(id: "legacy:v1", name: "Legacy preset", template: "KEEP_{original}_{asset}")
            var selection = settings.selection
            selection.disabled = ["camera", "asset"]
            settings.selection = selection
        }
        legacy.values["season"] = "2"; legacy.values["episode"] = "7"
        let archive = try Exchange.export(legacy, device: "legacy")
        XCTAssertEqual(try Exchange.read(archive).report, legacy)
        let suite = "ShotReporter-ReportOnly-" + UUID().uuidString
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {preferences.removePersistentDomain(forName: suite)}
        preferences.set("preserve", forKey: "legacy-worker-preference")
        let store = Store(root: root, preferences: preferences)
        store.open(try Exchange.read(archive).report)
        store.change {$0.values["title"] = "Reporting only"}
        let reopened = Store(root: root, preferences: preferences)
        XCTAssertEqual(reopened.report, store.report)
        XCTAssertEqual(reopened.report.namingSettings, legacy.namingSettings)
        XCTAssertEqual(reopened.report.values["season"], "2")
        XCTAssertEqual(reopened.report.values["episode"], "7")
        XCTAssertEqual(try Exchange.read(Exchange.export(reopened.report, device: "current")).report, reopened.report)
        XCTAssertEqual(try Data(contentsOf: untouched), originalBytes)
        XCTAssertEqual(preferences.string(forKey: "legacy-worker-preference"), "preserve")
        let repo = try Repository(url: root.appendingPathComponent("reports.sqlite3"))
        XCTAssertEqual(try repo.load(store.slot, previous: true).report, legacy)
    }
}
