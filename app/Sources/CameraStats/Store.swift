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
    var archiveBusy=false
    var archiveStatus:String?
    var projectState=ProjectArchive.State()
    private let preferencesDomain:String?
    var lastExportedRevision: Int? { preferences.object(forKey:"exported-"+slot) as? Int }
    let root: URL
    let device: String
    private let preferences:UserDefaults
    private var repository:Repository?
    private var fingerprint:String?
    init(root:URL? = nil,preferences:UserDefaults = .standard,preferencesDomain:String?=nil,now:@escaping ()->Date = Date.init) {
        self.preferences = preferences;self.preferencesDomain=preferencesDomain; device = ProcessInfo.processInfo.hostName
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
            refresh();reloadProject();cleanupExpiredTrash()
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
        guard !blocked,!archiveBusy else { error = "Recovery is required before edits can be accepted."; return }
        var next = report; action(&next); guard next != report else {return}; if next.revision == report.revision { next.record(summary,device:device) }
        do { try persist(next) } catch { self.error = "Save failed; this change was not accepted. \(error.localizedDescription)" }
    }
    func open(_ r: Report) {
        guard !archiveBusy else {return}
        let prior = slot, priorFingerprint=fingerprint; slot = UUID().uuidString; fingerprint=nil
        do { try persist(r); blocked = false;reloadProject() } catch { slot = prior; fingerprint=priorFingerprint; self.error = error.localizedDescription }
    }
    func select(_ id: String) {
        guard !archiveBusy else {return}
        do { guard let repository else {throw ReportError.invalid("Local database unavailable")}; let loaded=try repository.select(id); slot=id; report=loaded.report; fingerprint=loaded.fingerprint; blocked=false; saved=Date();reloadProject() } catch { self.error = error.localizedDescription }
    }
    func deletionRequest(for id:String) throws ->DeletionRequest {
        guard !blocked,!pendingImport,!archiveBusy else {throw ReportError.invalid("Resolve recovery or import before deleting a report.")}
        guard let repository else {throw ReportError.invalid("Local database unavailable")}
        let loaded = try repository.load(id)
        return DeletionRequest(id:id,title:loaded.report.values["title",default:"Untitled"],fingerprint:loaded.fingerprint)
    }
    private func adopt(_ loaded:Repository.Loaded) {
        slot=loaded.slot;report=loaded.report;fingerprint=loaded.fingerprint;saved=Date();blocked=false;error=nil;reloadProject()
    }
    func deleteReport(_ request:DeletionRequest) {
        do {
            guard !blocked,!pendingImport,!archiveBusy,let repository else {throw ReportError.invalid("Resolve recovery or import before deleting a report.")}
            if let next = try repository.delete(request.id,expectedFingerprint:request.fingerprint) {adopt(next)}
            else {report=Report();slot=UUID().uuidString;fingerprint=nil;saved=nil;error=nil;projectState=ProjectArchive.State()}
            refresh()
        } catch {self.error=error.localizedDescription}
    }
    func restoreDeletedReport(_ id:String) {
        do {
            guard !blocked,!pendingImport,!archiveBusy,let repository else {throw ReportError.invalid("Resolve recovery or import before restoring a report.")}
            adopt(try repository.restoreDeleted(id));refresh()
        } catch {self.error=error.localizedDescription}
    }
    func trashRequest() throws ->TrashRequest {
        guard !blocked,!pendingImport,!archiveBusy,let repository else {throw ReportError.invalid("Resolve recovery or import before clearing trash.")}
        return TrashRequest(items:try repository.trash())
    }
    func clearTrash(_ request:TrashRequest) {
        do {
            guard !blocked,!pendingImport,!archiveBusy,let repository else {throw ReportError.invalid("Resolve recovery or import before clearing trash.")}
            let count=try repository.clearTrash(expected:request.items);refresh();removePurgedResources();trashNotice="Permanently removed \(count) deleted report(s) from this device."
        } catch {self.error=error.localizedDescription}
    }
    func cleanupExpiredTrash() {
        guard !blocked,!pendingImport,!archiveBusy,let repository else {return}
        do {let count=try repository.cleanupExpiredTrash();if count > 0 {refresh();removePurgedResources();trashNotice="Automatically removed \(count) report(s) deleted at least 14 days ago."}}
        catch {self.error="Trash cleanup stopped; saved reports are preserved. \(error.localizedDescription)"}
    }
    func restore() async {
        do {
            guard !archiveBusy,!pendingImport,let repository else {throw ReportError.invalid("Local database is unavailable or busy.")}
            archiveBusy=true;archiveStatus="Restoring report and verifying its files…";defer{archiveBusy=false;archiveStatus=nil}
            var snapshot=try repository.projectSnapshot(slot)
            let recovery:Data
            if let previous=snapshot.previous {recovery=previous}
            else {recovery=try Data(contentsOf:root.appendingPathComponent(slot+".previous.camreport"));_=try Exchange.read(recovery)}
            snapshot.previous=snapshot.current;snapshot.current=recovery
            try await openProjectSnapshot(snapshot)
        } catch {self.error="No readable previous snapshot: \(error.localizedDescription)"}
    }
    private func openProjectSnapshot(_ snapshot:ProjectArchive.Snapshot)async throws {
        guard let repository else {throw ReportError.invalid("Local database unavailable.")}
        let next=UUID().uuidString,folder=resourcesRoot(next);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        do {
            let sourceFolder=resourcesRoot(slot)
            try await Task.detached(priority:.userInitiated) {
                for file in snapshot.state.resources {
                    let source=try ProjectArchive.blobURL(sourceFolder,file.sha256),target=try ProjectArchive.blobURL(folder,file.sha256)
                    if !FileManager.default.fileExists(atPath:target.path) {
                        let copied=try ProjectArchive.addFile(source,kind:file.kind,to:folder)
                        guard copied.sha256==file.sha256,copied.size==file.size else {throw ReportError.invalid("A project file failed verification; recovery stopped without omissions.")}
                    }
                }
            }.value
            adopt(try repository.importProject(snapshot,slot:next));refresh()
        } catch {try? FileManager.default.removeItem(at:folder);throw error}
    }
    private func resourcesRoot(_ id:String)->URL {root.appendingPathComponent("ProjectFiles",isDirectory:true).appendingPathComponent(id,isDirectory:true)}
    private func reloadProject() {guard fingerprint != nil else {projectState=ProjectArchive.State();return};do {projectState=(try repository?.projectState(slot)) ?? ProjectArchive.State()} catch {projectState=ProjectArchive.State();self.error="Project files could not be read; no files were removed. \(error.localizedDescription)"}}
    private func removePurgedResources() {
        do {guard let repository else {return};for id in try repository.purgedSlots() where UUID(uuidString:id) != nil {let url=resourcesRoot(id);if FileManager.default.fileExists(atPath:url.path) {try FileManager.default.removeItem(at:url)}}}
        catch {self.error="A deleted report's managed file copies could not be removed. Original files and saved reports are preserved. \(error.localizedDescription)"}
    }
    func addProjectFiles(_ urls:[URL],kind:String) async {
        guard !archiveBusy,!blocked,!pendingImport,let repository,let fingerprint else {error="Save a report before adding files.";return}
        archiveBusy=true;archiveStatus="Copying and verifying files…";defer{archiveBusy=false;archiveStatus=nil}
        let folder=resourcesRoot(slot)
        do {
            let additions=try await Task.detached(priority:.userInitiated) {
                try urls.map {url in let access=url.startAccessingSecurityScopedResource();defer{if access {url.stopAccessingSecurityScopedResource()}};return try ProjectArchive.addFile(url,kind:kind,to:folder)}
            }.value
            var state=projectState;state.resources+=additions;try repository.setProjectState(state,slot:slot,expectedFingerprint:fingerprint,expectedState:projectState);projectState=state
        } catch {self.error="Files were not added to the report. Source files are unchanged. \(error.localizedDescription)"}
    }
    /// Snapshot only the application's own domain, never global/system preferences.
    private func capturedPreferences()throws->Data {
        var dictionary:[String:Any]=[:]
        if let stored=projectState.preferences {dictionary=(try PropertyListSerialization.propertyList(from:stored,format:nil) as? [String:Any]) ?? [:]}
        if let preferencesDomain {dictionary.merge(preferences.persistentDomain(forName:preferencesDomain) ?? [:]) {_,new in new}}
        else {for key in ["theme","detail"] {if let value=preferences.object(forKey:key) {dictionary[key]=value}}}
        return try PropertyListSerialization.data(fromPropertyList:dictionary,format:.binary,options:0)
    }
    func prepareProjectExport() async ->URL? {
        guard !archiveBusy,!blocked,!pendingImport,let repository else {error="Resolve recovery or import before exporting.";return nil}
        archiveBusy=true;archiveStatus="Verifying complete report and file copies…";defer{archiveBusy=false;archiveStatus=nil}
        do {
            if fingerprint==nil {try persist(report)}
            var snapshot=try repository.projectSnapshot(slot)
            let captured=try capturedPreferences()
            if let original=snapshot.state.preferences,original != captured,!snapshot.state.preferenceSnapshots.contains(original) {snapshot.state.preferenceSnapshots.append(original)}
            snapshot.state.preferences=captured
            let folder=resourcesRoot(slot),sourceSlot=slot,base=root.appendingPathComponent("ArchiveStaging",isDirectory:true),device=device
            try FileManager.default.createDirectory(at:base,withIntermediateDirectories:true)
            let work=base.appendingPathComponent(UUID().uuidString,isDirectory:true);try FileManager.default.createDirectory(at:work,withIntermediateDirectories:false)
            let output=work.appendingPathComponent(try report.exportName(extension:"camreport"))
            do {
                // Retain all known legacy recovery bytes, including unreadable copies, as opaque files.
                for suffix in [".camreport",".previous.camreport"] {
                    let url=root.appendingPathComponent(sourceSlot+suffix)
                    if FileManager.default.fileExists(atPath:url.path) {
                        let resource=try await Task.detached {try ProjectArchive.addFile(url,kind:"recovery",to:folder)}.value
                        if !snapshot.state.resources.contains(where:{$0.kind=="recovery" && $0.sha256==resource.sha256}) {snapshot.state.resources.append(resource)}
                    }
                }
                let frozen=snapshot
                try await Task.detached(priority:.userInitiated) {try ProjectArchive.write(frozen,resources:folder,device:device,to:output)}.value
                archiveStatus="Complete report archive is ready to save.";return output
            } catch {try? FileManager.default.removeItem(at:work);throw error}
        } catch {self.error="Complete export stopped; nothing was omitted. \(error.localizedDescription)";return nil}
    }
    func prepareProjectImport(_ url:URL) async throws ->ProjectArchive.Prepared {
        guard !archiveBusy,!pendingImport else {throw ReportError.invalid("Finish the current import or file operation first.")}
        archiveBusy=true;pendingImport=true;archiveStatus="Verifying archive and every file…"
        defer{archiveBusy=false;archiveStatus=nil}
        let base=root.appendingPathComponent("ArchiveStaging",isDirectory:true)
        do {try FileManager.default.createDirectory(at:base,withIntermediateDirectories:true);return try await Task.detached(priority:.userInitiated) {
            let access=url.startAccessingSecurityScopedResource();defer{if access {url.stopAccessingSecurityScopedResource()}}
            return try ProjectArchive.read(url,to:base.appendingPathComponent(UUID().uuidString,isDirectory:true))
        }.value} catch {pendingImport=false;throw error}
    }
    func acceptProject(_ prepared:ProjectArchive.Prepared,applyPreferences:Bool) throws {
        guard !archiveBusy,let repository else {throw ReportError.invalid("Local database is unavailable or busy.")}
        let newSlot=UUID().uuidString,folder=resourcesRoot(newSlot),fm=FileManager.default
        try fm.createDirectory(at:folder.deletingLastPathComponent(),withIntermediateDirectories:true)
        // The verified directory is on the same volume, so the move is atomic and needs no second media copy.
        try fm.moveItem(at:prepared.folder,to:folder)
        do {adopt(try repository.importProject(prepared.snapshot,slot:newSlot));refresh()}
        catch {try? fm.moveItem(at:folder,to:prepared.folder);throw error}
        if applyPreferences,let data=prepared.snapshot.state.preferences,let prefs=try? PropertyListSerialization.propertyList(from:data,format:nil) as? [String:Any] {
            if let theme=prefs["theme"] as? String,["System","Light","Dark"].contains(theme) {preferences.set(theme,forKey:"theme")}
            if let detail=prefs["detail"] as? String,["Quick","Standard","Full"].contains(detail) {preferences.set(detail,forKey:"detail")}
        }
        pendingImport=false
    }
    func discardProject(_ prepared:ProjectArchive.Prepared) {try? FileManager.default.removeItem(at:prepared.folder);pendingImport=false}
    func restoreProjectRecovery(_ resource:ProjectArchive.Resource) async {
        do {
            guard !archiveBusy,resource.kind=="recovery",resource.size<=UInt64(Exchange.limit) else {throw ReportError.invalid("Export this recovery file to open it with a compatible app.")}
            archiveBusy=true;archiveStatus="Restoring report and verifying its files…";defer{archiveBusy=false;archiveStatus=nil}
            let bytes=try Data(contentsOf:ProjectArchive.blobURL(resourcesRoot(slot),resource.sha256));guard Exchange.digest(bytes)==resource.sha256 else {throw ReportError.invalid("Recovery checksum mismatch.")}
            let previous=try Exchange.read(bytes).report
            var snapshot=try repository!.projectSnapshot(slot);snapshot.current=try Exchange.export(previous,device:device)
            // Opening a recovery retains the complete project's files, preferences and original snapshots.
            try await openProjectSnapshot(snapshot)
        } catch {self.error="Recovery was preserved. \(error.localizedDescription)"}
    }

    func prepareResourceExport(_ resource:ProjectArchive.Resource) async ->URL? {
        guard !archiveBusy,!blocked,!pendingImport else {return nil}
        archiveBusy=true;defer{archiveBusy=false}
        do {
            let base=root.appendingPathComponent("ArchiveStaging",isDirectory:true);try FileManager.default.createDirectory(at:base,withIntermediateDirectories:true)
            let work=base.appendingPathComponent(UUID().uuidString,isDirectory:true);try FileManager.default.createDirectory(at:work,withIntermediateDirectories:false)
            // Display names never become extraction paths. Export uses only the final component.
            let name=URL(fileURLWithPath:resource.name).lastPathComponent
            let safeName=([".","..",""] .contains(name) || name==resource.sha256) ? "project-file":name
            let output=work.appendingPathComponent(safeName),source=try ProjectArchive.blobURL(resourcesRoot(slot),resource.sha256)
            do {try await Task.detached {try ProjectArchive.checkSpace(at:work,bytes:resource.size);let copied=try ProjectArchive.addFile(source,kind:resource.kind,to:work);guard copied.sha256==resource.sha256,copied.size==resource.size else {throw ReportError.invalid("File checksum mismatch.")};try FileManager.default.moveItem(at:ProjectArchive.blobURL(work,copied.sha256),to:output)}.value;return output}
            catch {try? FileManager.default.removeItem(at:work);throw error}
        } catch {self.error=error.localizedDescription;return nil}
    }

}
