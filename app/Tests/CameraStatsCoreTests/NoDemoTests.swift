import XCTest
import AppKit
import SwiftUI
import CameraStatsCore
@testable import CameraStats

final class NoDemoTests: XCTestCase {
    func testShippingSourcesHaveNoDemoEntrypointsOrFixturePayloads() throws {
        let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sources = app.appendingPathComponent("Sources")
        let ui = try String(contentsOf: sources.appendingPathComponent("CameraStats/CameraStatsApp.swift"))
        for removed in ["Open The Last Light demo", "Read the demo script", "Shared demo shots", "Read the 16-shot plan", "demoScript", "demoShotPlan", ".demo()"] {
            XCTAssertFalse(ui.contains(removed), "Demo entrypoint returned: \(removed)")
        }
        XCTAssertTrue(ui.contains("New blank report"))
        XCTAssertTrue(ui.contains("store.open(Report())"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sources.appendingPathComponent("CameraStatsCore/Demo.swift").path))
        let model = try String(contentsOf: sources.appendingPathComponent("CameraStatsCore/Model.swift"))
        XCTAssertFalse(model.contains("func fixture()"))
        XCTAssertFalse(model.contains("The Last Light"))
    }

    @MainActor func testBlankReportWorkflowPreservesExistingReportsAndLegacyDemoFields() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ShotReporter-NoDemo-" + UUID().uuidString)
        defer {try? FileManager.default.removeItem(at: root)}
        let suite = "ShotReporter-NoDemo-" + UUID().uuidString
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {preferences.removePersistentDomain(forName: suite)}
        let store = Store(root: root, preferences: preferences)
        XCTAssertTrue(store.report.active.isEmpty)
        XCTAssertNil(store.report.values["demoScript"])
        var existing = Report.demo()
        existing.values["title"] = "My existing production"
        existing.values["demoScript"] = "User-edited legacy script data must be preserved."
        existing.entries[0].values["remarks"] = "User's real production note"
        store.open(existing)
        let previousSlot = store.slot
        store.open(Report())
        let blankSlot = store.slot
        XCTAssertNotEqual(blankSlot, previousSlot)
        XCTAssertTrue(store.report.active.isEmpty)
        XCTAssertNil(store.report.values["demoScript"])
        XCTAssertNil(store.report.values["demoShotPlan"])
        store.change {report in
            report.values["title"] = "New production"
            _ = report.next(scene: "1A", device: "Test")
        }
        let newReport = store.report
        store.select(previousSlot)
        XCTAssertEqual(store.report, existing)
        XCTAssertEqual(try Exchange.read(Exchange.export(store.report, device: "Test")).report, existing)
        store.select(blankSlot)
        let reopened = Store(root: root, preferences: preferences)
        XCTAssertEqual(reopened.report, newReport)
        XCTAssertEqual(reopened.report.active.count, 1)
        XCTAssertEqual(reopened.documents.count, 2)
    }
    @MainActor func testTodayRendersBlankReportActionForSavedLegacyReport() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ShotReporter-NoDemoUI-" + UUID().uuidString)
        defer {try? FileManager.default.removeItem(at: root)}
        let suite = "ShotReporter-NoDemoUI-" + UUID().uuidString
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {preferences.removePersistentDomain(forName: suite)}
        let store = Store(root: root, preferences: preferences)
        store.open(.demo())
        let before = store.report
        _ = NSApplication.shared
        let host = NSHostingView(rootView: Workspace(store: store).content(.today))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 800), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: 1100, height: 800)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertGreaterThan(host.fittingSize.height, 0)

        window.close()
        XCTAssertEqual(store.report, before, "Viewing an existing report must not delete legacy data")
    }

}
