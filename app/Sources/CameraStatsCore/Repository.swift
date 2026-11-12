import Foundation
import CSQLite

// One connection per local app process; serialized by the app's MainActor. Never put this live DB on a shared drive.
public final class Repository {
    private var db:OpaquePointer?
    private let transient = unsafeBitCast(-1,to:sqlite3_destructor_type.self)
    public struct Document { public var slot:String; public var title:String; public var revision:Int }
    public struct Loaded { public var slot:String; public var report:Report; public var fingerprint:String }
    public init(url:URL) throws {
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        guard sqlite3_open_v2(url.path,&db,SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,nil) == SQLITE_OK else { let message = db.map{String(cString:sqlite3_errmsg($0))} ?? "Cannot open SQLite database"; if db != nil {sqlite3_close(db)}; db = nil; throw ReportError.invalid(message) }
        do {
            sqlite3_busy_timeout(db,3000)
            try execute("PRAGMA journal_mode=WAL"); try execute("PRAGMA synchronous=FULL"); try execute("PRAGMA foreign_keys=ON")
            let version = try scalarInt("PRAGMA user_version")
            guard version <= 2 else {throw ReportError.invalid("Newer local database schema; existing data preserved")}
            if version == 0 {
                try execute("BEGIN IMMEDIATE")
                do {
                    try execute("CREATE TABLE documents(slot TEXT PRIMARY KEY, title TEXT NOT NULL, revision INTEGER NOT NULL, current BLOB NOT NULL, previous BLOB)")
                    try execute("CREATE TABLE metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL)")
                    try execute("PRAGMA user_version=1"); try execute("COMMIT")
                } catch {try? execute("ROLLBACK"); throw error}
            }
            if version < 2 {
                try execute("BEGIN IMMEDIATE")
                do { try execute("ALTER TABLE documents ADD COLUMN deleted INTEGER NOT NULL DEFAULT 0"); try execute("PRAGMA user_version=2"); try execute("COMMIT") }
                catch { try? execute("ROLLBACK"); throw error }
            }
            guard try scalarText("PRAGMA quick_check") == "ok" else {throw ReportError.invalid("Local database integrity check failed; existing data preserved")}
        } catch {sqlite3_close(db); db = nil; throw error}
    }
    deinit { if db != nil {sqlite3_close(db)} }
    private func message()->ReportError { .invalid(db.map{String(cString:sqlite3_errmsg($0))} ?? "Local database unavailable") }
    private func execute(_ sql:String) throws { guard sqlite3_exec(db,sql,nil,nil,nil) == SQLITE_OK else {throw message()} }
    private func statement(_ sql:String) throws ->OpaquePointer {var s:OpaquePointer?; guard sqlite3_prepare_v2(db,sql,-1,&s,nil) == SQLITE_OK, let s else {throw message()}; return s}
    private func bind(_ s:OpaquePointer,_ i:Int32,_ text:String) throws {guard sqlite3_bind_text(s,i,text,-1,transient) == SQLITE_OK else {throw message()}}
    private func bind(_ s:OpaquePointer,_ i:Int32,_ data:Data) throws { let code = data.withUnsafeBytes {sqlite3_bind_blob(s,i,$0.baseAddress,Int32(data.count),transient)}; guard code == SQLITE_OK else {throw message()} }
    private func scalarInt(_ sql:String) throws ->Int { let s=try statement(sql); defer{sqlite3_finalize(s)}; guard sqlite3_step(s) == SQLITE_ROW else {throw message()}; return Int(sqlite3_column_int(s,0)) }
    private func scalarText(_ sql:String) throws ->String { let s=try statement(sql); defer{sqlite3_finalize(s)}; guard sqlite3_step(s) == SQLITE_ROW, let value=sqlite3_column_text(s,0) else {throw message()}; return String(cString:value) }
    private func validate(_ slot:String) throws {guard UUID(uuidString:slot) != nil else {throw ReportError.invalid("Invalid local document slot")}}
    private func bytes(_ slot:String,previous:Bool=false,includeDeleted:Bool=false) throws ->Data? {
        try validate(slot)
        let s=try statement("SELECT \(previous ? "previous" : "current") FROM documents WHERE slot=? \(includeDeleted ? "" : "AND deleted=0")"); defer{sqlite3_finalize(s)}; try bind(s,1,slot)
        let status=sqlite3_step(s); if status == SQLITE_DONE {return nil}; guard status == SQLITE_ROW else {throw message()}
        if sqlite3_column_type(s,0) == SQLITE_NULL {return nil}
        let size=Int(sqlite3_column_bytes(s,0)); guard size <= Exchange.limit, let b=sqlite3_column_blob(s,0) else {throw ReportError.invalid("Invalid local snapshot size")}; return Data(bytes:b,count:size)
    }
    public func active() throws ->String? {
        let s=try statement("SELECT value FROM metadata WHERE key='active'"); defer{sqlite3_finalize(s)}
        let status=sqlite3_step(s); if status == SQLITE_DONE {return nil}; guard status == SQLITE_ROW, let text=sqlite3_column_text(s,0) else {throw message()}; return String(cString:text)
    }
    public func list(deleted:Bool=false) throws ->[Document] {
        let s=try statement("SELECT slot,title,revision FROM documents WHERE deleted=\(deleted ? 1 : 0) ORDER BY title,slot"); defer{sqlite3_finalize(s)}; var result:[Document]=[]
        while true {let status=sqlite3_step(s); if status == SQLITE_DONE {break}; guard status == SQLITE_ROW, let slot=sqlite3_column_text(s,0), let title=sqlite3_column_text(s,1) else {throw message()}; result.append(Document(slot:String(cString:slot),title:String(cString:title),revision:Int(sqlite3_column_int64(s,2))))}; return result
    }
    public func knownSlots() throws ->Set<String> { Set(try list().map(\.slot) + list(deleted:true).map(\.slot)) }
    public func delete(_ slot:String,expectedFingerprint:String) throws ->Loaded? {
        try delete(slot,expectedFingerprint:expectedFingerprint,failBeforeCommit:false)
    }
    func delete(_ slot:String,expectedFingerprint:String,failBeforeCommit:Bool) throws ->Loaded? {
        try execute("BEGIN IMMEDIATE")
        do {
            let current = try load(slot)
            guard current.fingerprint == expectedFingerprint else { throw ReportError.invalid("This report changed. Reopen it and review it before deleting; nothing was deleted.") }
            let s = try statement("UPDATE documents SET deleted=1 WHERE slot=?"); defer {sqlite3_finalize(s)}
            try bind(s,1,slot); guard sqlite3_step(s) == SQLITE_DONE else {throw message()}
            if try active() == slot {
                if let next = try list().first { _ = try select(next.slot) }
                else { try execute("DELETE FROM metadata WHERE key='active'") }
            }
            let next = try active().map {try load($0)}
            if failBeforeCommit { throw ReportError.invalid("Injected interrupted delete") }
            try execute("COMMIT"); return next
        } catch {try? execute("ROLLBACK"); throw error}
    }
    public func restoreDeleted(_ slot:String) throws ->Loaded {
        try validate(slot); try execute("BEGIN IMMEDIATE")
        do {
            guard try list(deleted:true).contains(where:{$0.slot == slot}) else {throw ReportError.invalid("This report is no longer in Recently Deleted.")}
            let s = try statement("UPDATE documents SET deleted=0 WHERE slot=?"); defer {sqlite3_finalize(s)}
            try bind(s,1,slot); guard sqlite3_step(s) == SQLITE_DONE else {throw message()}
            let loaded = try select(slot); try execute("COMMIT"); return loaded
        } catch {try? execute("ROLLBACK"); throw error}
    }
    public func load(_ slot:String,previous:Bool=false) throws ->Loaded {
        guard let data=try bytes(slot,previous:previous) else {throw ReportError.invalid("Local snapshot not found")}
        return Loaded(slot:slot,report:try Exchange.read(data).report,fingerprint:Exchange.digest(data))
    }
    public func select(_ slot:String) throws ->Loaded {
        let loaded=try load(slot); let s=try statement("INSERT INTO metadata(key,value) VALUES('active',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value"); defer{sqlite3_finalize(s)}; try bind(s,1,slot); guard sqlite3_step(s) == SQLITE_DONE else {throw message()}; return loaded
    }
    public func save(slot:String,report:Report,device:String,expectedFingerprint:String?) throws ->String {
        try save(slot:slot,report:report,device:device,expectedFingerprint:expectedFingerprint,failBeforeCommit:false)
    }
    func capDatabasePagesForTesting(_ pages:Int) throws {try execute("PRAGMA max_page_count=\(max(1,pages))")}
    // Failure injection is internal and used only to prove rollback before the commit boundary.
    func save(slot:String,report:Report,device:String,expectedFingerprint:String?,failBeforeCommit:Bool) throws ->String {
        try validate(slot)
        let payload=try Exchange.export(report,device:device); _=try Exchange.read(payload)
        try execute("BEGIN IMMEDIATE")
        do {
            let current=try bytes(slot)
            if current == nil, try bytes(slot,includeDeleted:true) != nil {throw ReportError.invalid("This report is in Recently Deleted. Restore it before editing; no changes were accepted.")}
            if let current { _=try Exchange.read(current); guard expectedFingerprint == Exchange.digest(current) else {throw ReportError.invalid("This local report changed in another app instance. Reopen it before saving; no changes were accepted.")} }
            else if expectedFingerprint != nil {throw ReportError.invalid("Local document disappeared; no changes were accepted")}
            let s=try statement("INSERT INTO documents(slot,title,revision,current,previous) VALUES(?,?,?,?,NULL) ON CONFLICT(slot) DO UPDATE SET title=excluded.title,revision=excluded.revision,previous=documents.current,current=excluded.current")
            defer{sqlite3_finalize(s)}; try bind(s,1,slot); try bind(s,2,report.values["title",default:"Untitled"])
            guard sqlite3_bind_int64(s,3,sqlite3_int64(report.revision)) == SQLITE_OK else {throw message()}; try bind(s,4,payload); guard sqlite3_step(s) == SQLITE_DONE else {throw message()}
            let active=try statement("INSERT INTO metadata(key,value) VALUES('active',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value"); defer{sqlite3_finalize(active)}; try bind(active,1,slot); guard sqlite3_step(active) == SQLITE_DONE else {throw message()}
            if failBeforeCommit {throw ReportError.invalid("Injected interrupted transaction")}
            try execute("COMMIT"); return Exchange.digest(payload)
        } catch {try? execute("ROLLBACK"); throw error}
    }
}
