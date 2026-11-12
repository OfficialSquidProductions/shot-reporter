import Foundation
import Observation
import CameraStatsCore

@MainActor @Observable final class Store {
    private(set) var report = Report()
    private(set) var saved: Date?
    var error: String? {didSet {if error != nil {DiagnosticsCenter.shared.capture(.reports)}}}
    var slot = UUID().uuidString
    var documents: [(String,String)] = []
    var deletedDocuments: [(String,String)] = []
    struct TrashRequest:Identifiable {let id=UUID();let items:[Repository.TrashItem]}
    var trashNotice:String?
    struct DeletionRequest: Identifiable { let id:String; let title:String; let fingerprint:String }
    var blocked = false
    var pendingImport = false
    var lastExportedRevision: Int? { preferences.object(forKey:"exported-"+slot) as? Int }
    let root: URL
    let device: String
    private let preferences:UserDefaults
    private var repository:Repository?
    private var fingerprint:String?
    init(root:URL? = nil,preferences:UserDefaults = .standard,now:@escaping ()->Date = Date.init) {
        self.preferences = preferences; device = ProcessInfo.processInfo.hostName
        self.root = root ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("org.squidproductions.camerastats",isDirectory:true)
        do {
            let repo = try Repository(url:self.root.appendingPathComponent("reports.sqlite3"),now:now); repository = repo
            // One-time, idempotent migration. Legacy snapshots stay untouched as recovery files.
            let known = try repo.knownSlots()
            for url in try FileManager.default.contentsOfDirectory(at:self.root,includingPropertiesForKeys:nil) where url.pathExtension == "camreport" && !url.lastPathComponent.contains("previous") {
                let id=url.deletingPathExtension().lastPathComponent
                if !known.contains(id) {let legacy=try Exchange.read(Data(contentsOf:url)); _=try repo.save(slot:id,report:legacy.report,device:device,expectedFingerprint:nil)}
            }
            if let legacyActive = preferences.string(forKey:"activeReport"), (try repo.list()).contains(where:{$0.slot == legacyActive}) { _=try repo.select(legacyActive); preferences.removeObject(forKey:"activeReport") }
            if let selected = try repo.active() { let loaded=try repo.load(selected); slot=selected; report=loaded.report; fingerprint=loaded.fingerprint; saved=Date() }
            refresh();cleanupExpiredTrash()
        } catch { self.error = "Local report could not be read. Its bytes were preserved. Export/recover it before creating a new report. \(error.localizedDescription)"; blocked = true }
    }
    func refresh() {
        deletedDocuments = ((try? repository?.list(deleted:true)) ?? []).map{($0.slot,$0.title + " · r\($0.revision)")}
        documents = ((try? repository?.list()) ?? []).map{($0.slot,$0.title + " · r\($0.revision)")}
    }
    func persist(_ next: Report) throws {
        guard let repository else {throw ReportError.invalid("Local database is unavailable; existing files are preserved")}
        let accepted=try repository.save(slot:slot,report:next,device:device,expectedFingerprint:fingerprint)
        report = next; fingerprint=accepted; saved = Date()
        documents.removeAll{$0.0 == slot}; documents.append((slot,next.values["title",default:"Untitled"] + " · r\(next.revision)")); documents.sort{$0.1 < $1.1}
    }
    func change(_ summary: String = "Edited report", _ action: (inout Report)->Void) {
        guard !blocked else { error = "Recovery is required before edits can be accepted."; return }
        var next = report; action(&next); guard next != report else {return}; if next.revision == report.revision { next.record(summary,device:device) }
        do { try persist(next) } catch { self.error = "Save failed; this change was not accepted. \(error.localizedDescription)" }
    }
    func open(_ r: Report) {
        let prior = slot, priorFingerprint=fingerprint; slot = UUID().uuidString; fingerprint=nil
        do { try persist(r); blocked = false } catch { slot = prior; fingerprint=priorFingerprint; self.error = error.localizedDescription }
    }
    func select(_ id: String) {
        do { guard let repository else {throw ReportError.invalid("Local database unavailable")}; let loaded=try repository.select(id); slot=id; report=loaded.report; fingerprint=loaded.fingerprint; blocked=false; saved=Date() } catch { self.error = error.localizedDescription }
    }
    func deletionRequest(for id:String) throws ->DeletionRequest {
        guard !blocked,!pendingImport else {throw ReportError.invalid("Resolve recovery or import before deleting a report.")}
        guard let repository else {throw ReportError.invalid("Local database unavailable")}
        let loaded = try repository.load(id)
        return DeletionRequest(id:id,title:loaded.report.values["title",default:"Untitled"],fingerprint:loaded.fingerprint)
    }
    private func adopt(_ loaded:Repository.Loaded) {
        slot=loaded.slot;report=loaded.report;fingerprint=loaded.fingerprint;saved=Date();blocked=false;error=nil
    }
    func deleteReport(_ request:DeletionRequest) {
        do {
            guard !blocked,!pendingImport,let repository else {throw ReportError.invalid("Resolve recovery or import before deleting a report.")}
            if let next = try repository.delete(request.id,expectedFingerprint:request.fingerprint) {adopt(next)}
            else {report=Report();slot=UUID().uuidString;fingerprint=nil;saved=nil;error=nil}
            refresh()
        } catch {self.error=error.localizedDescription}
    }
    func restoreDeletedReport(_ id:String) {
        do {
            guard !blocked,!pendingImport,let repository else {throw ReportError.invalid("Resolve recovery or import before restoring a report.")}
            adopt(try repository.restoreDeleted(id));refresh()
        } catch {self.error=error.localizedDescription}
    }
    func trashRequest() throws ->TrashRequest {
        guard !blocked,!pendingImport,let repository else {throw ReportError.invalid("Resolve recovery or import before clearing trash.")}
        return TrashRequest(items:try repository.trash())
    }
    func clearTrash(_ request:TrashRequest) {
        do {
            guard !blocked,!pendingImport,let repository else {throw ReportError.invalid("Resolve recovery or import before clearing trash.")}
            let count=try repository.clearTrash(expected:request.items);refresh();trashNotice="Permanently removed \(count) deleted report(s) from this device."
        } catch {self.error=error.localizedDescription}
    }
    func cleanupExpiredTrash() {
        guard !blocked,!pendingImport,let repository else {return}
        do {let count=try repository.cleanupExpiredTrash();if count > 0 {refresh();trashNotice="Automatically removed \(count) report(s) deleted at least 14 days ago."}}
        catch {self.error="Trash cleanup stopped; saved reports are preserved. \(error.localizedDescription)"}
    }
    func restore() {
        do {
            guard let repository else {throw ReportError.invalid("Local database unavailable")}
            if let previous = try? repository.load(slot,previous:true) {open(previous.report)}
            else {let legacy=try Exchange.read(Data(contentsOf:root.appendingPathComponent(slot+".previous.camreport"))); open(legacy.report)}
        } catch { self.error = "No readable previous snapshot: \(error.localizedDescription)" }
    }
}
