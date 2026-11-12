package org.squidproductions.camerastats.core

import java.io.Closeable

interface SqlDriver:Closeable {
    fun execute(sql:String,args:List<Any?> = emptyList())
    fun query(sql:String,args:List<Any?> = emptyList()):List<List<Any?>>
}
data class Document(val slot:String,val title:String,val revision:Long)
data class Loaded(val slot:String,val report:Report,val fingerprint:String)

/** One database per app, never a shared drive. A failed or stale save leaves the prior snapshot intact. */
data class TrashItem(val slot:String,val title:String,val deletedAt:Double,val fingerprint:String)
class Repository(private val db:SqlDriver,private val now:()->Double={System.currentTimeMillis()/1000.0}):Closeable {
    companion object {const val TRASH_RETENTION=14*24*60*60.0}
    init {
        try {
            db.query("PRAGMA journal_mode=WAL"); db.execute("PRAGMA synchronous=FULL");db.execute("PRAGMA foreign_keys=ON");db.query("PRAGMA busy_timeout=3000")
            val version=(db.query("PRAGMA user_version").single().single() as Number).toInt()
            require(version<=3) { "Newer database schema; existing bytes preserved." }
            if(version==0) transaction {
                db.execute("CREATE TABLE documents(slot TEXT PRIMARY KEY, title TEXT NOT NULL, revision INTEGER NOT NULL, current BLOB NOT NULL, previous BLOB)")
                db.execute("CREATE TABLE metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL)")
                db.execute("PRAGMA user_version=1")
            }
            if(version<2) transaction {
                db.execute("ALTER TABLE documents ADD COLUMN deleted INTEGER NOT NULL DEFAULT 0")
                db.execute("PRAGMA user_version=2")
            }
            if(version<3) transaction {
                db.execute("ALTER TABLE documents ADD COLUMN deleted_at REAL")
                db.execute("ALTER TABLE documents ADD COLUMN deletion_token TEXT")
                db.execute("CREATE TABLE purged_slots(slot TEXT PRIMARY KEY)")
                list(true).forEach {stampDeletion(it.slot)}
                db.execute("PRAGMA user_version=3")
            }
            require(db.query("PRAGMA quick_check").single().single()=="ok") { "Local database integrity check failed; existing bytes preserved." }
        } catch(e:Exception) {db.close();throw e}
    }
    private fun <T> transaction(block:()->T):T {
        db.execute("BEGIN IMMEDIATE")
        try {val result=block();db.execute("COMMIT");return result} catch(e:Exception) {try {db.execute("ROLLBACK")} catch(_:Exception) {};throw e}
    }
    private fun validate(slot:String) { require(Regex("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}").matches(slot)) { "Invalid document slot." } }
    private fun bytes(slot:String,previous:Boolean=false,includeDeleted:Boolean=false):ByteArray? {
        validate(slot);val row=db.query("SELECT ${if(previous) "previous" else "current"} FROM documents WHERE slot=? ${if(includeDeleted) "" else "AND deleted=0"}",listOf(slot)).firstOrNull() ?: return null
        val bytes=row[0] as? ByteArray ?: return null;require(bytes.size<=Exchange.LIMIT) { "Invalid snapshot size." };return bytes
    }
    @Synchronized fun active():String? = db.query("SELECT value FROM metadata WHERE key='active'").firstOrNull()?.first() as? String
    @Synchronized fun list(deleted:Boolean=false):List<Document> = db.query("SELECT slot,title,revision FROM documents WHERE deleted=${if(deleted) 1 else 0} ORDER BY title,slot").map { Document(it[0] as String,it[1] as String,(it[2] as Number).toLong()) }
    @Synchronized fun delete(slot:String,expectedFingerprint:String):Loaded? = transaction {
        val current=load(slot)
        require(current.fingerprint==expectedFingerprint) {"This report changed. Reopen it before deleting; nothing was deleted."}
        db.execute("UPDATE documents SET deleted=1 WHERE slot=?",listOf(slot))
        stampDeletion(slot)
        if(active()==slot) {
            val next=list().firstOrNull()?.slot
            if(next==null) db.execute("DELETE FROM metadata WHERE key='active'") else setActive(next)
        }
        active()?.let {load(it)}
    }
    @Synchronized fun restoreDeleted(slot:String):Loaded = transaction {
        validate(slot);require(list(true).any {it.slot==slot}) {"This report is no longer in Recently Deleted."}
        db.execute("UPDATE documents SET deleted=0,deleted_at=NULL,deletion_token=NULL WHERE slot=?",listOf(slot));setActive(slot);load(slot)
    }
    private fun stampDeletion(slot:String) {db.execute("UPDATE documents SET deleted_at=?,deletion_token=? WHERE slot=? AND deleted=1",listOf(now(),identity(),slot))}
    @Synchronized fun trash():List<TrashItem> = db.query("SELECT slot,title,deleted_at,deletion_token,current,previous FROM documents WHERE deleted=1 ORDER BY slot").map {row ->
        val time=(row[2] as? Number)?.toDouble() ?: error("Incomplete trash date; nothing was removed.")
        require(time.isFinite()) {"Invalid trash date; nothing was removed."}
        val token=row[3] as? String ?: error("Incomplete trash metadata; nothing was removed.")
        TrashItem(row[0] as String,row[1] as String,time,Exchange.digest((token+time).toByteArray()+((row[4] as? ByteArray) ?: byteArrayOf())+((row[5] as? ByteArray) ?: byteArrayOf())))
    }
    @Synchronized fun clearTrash(expected:List<TrashItem>):Int=purge(expected,false)
    @Synchronized fun cleanupExpiredTrash():Int=purge(emptyList(),true)
    private fun purge(expected:List<TrashItem>,expiredOnly:Boolean):Int=transaction {
        val current=trash();require(expiredOnly || current==expected) {"Recently Deleted changed. Review Clear Trash again; nothing was removed."}
        val instant=now();val targets=if(expiredOnly) current.filter {instant-it.deletedAt>=TRASH_RETENTION} else current
        require(targets.none {it.slot==active()}) {"An active report cannot be purged; nothing was removed."}
        targets.forEach {item ->validate(item.slot);db.execute("INSERT OR IGNORE INTO purged_slots(slot) VALUES(?)",listOf(item.slot));db.execute("DELETE FROM documents WHERE slot=? AND deleted=1",listOf(item.slot))}
        targets.size
    }
    @Synchronized fun load(slot:String,previous:Boolean=false):Loaded {
        val bytes=bytes(slot,previous) ?: throw ReportException("Local snapshot not found.")
        return Loaded(slot,Exchange.read(bytes).report,Exchange.digest(bytes))
    }
    @Synchronized fun select(slot:String):Loaded = transaction {
        val loaded=load(slot);setActive(slot);loaded
    }
    private fun setActive(slot:String) {db.execute("INSERT OR REPLACE INTO metadata(key,value) VALUES('active',?)",listOf(slot))}
    @Synchronized fun save(slot:String,report:Report,device:String,expectedFingerprint:String?):String {
        validate(slot);val payload=Exchange.export(report,device);Exchange.read(payload)
        return transaction {
            val current=bytes(slot)
            require(db.query("SELECT slot FROM purged_slots WHERE slot=?",listOf(slot)).isEmpty()) {"This report was permanently removed. Import a backup as a new report."}
            require(current!=null || bytes(slot,includeDeleted=true)==null) {"This report is in Recently Deleted. Restore it before editing; no changes were accepted."}
            if(current!=null) {
                Exchange.read(current)
                require(expectedFingerprint==Exchange.digest(current)) { "This report changed in another app instance. Reopen it before saving; no change was accepted." }
            } else require(expectedFingerprint==null) { "Local document disappeared; no change was accepted." }
            if(current==null) db.execute("INSERT INTO documents(slot,title,revision,current,previous) VALUES(?,?,?,?,NULL)",listOf(slot,report.values["title"] ?: "Untitled",report.revision,payload))
            else db.execute("UPDATE documents SET title=?,revision=?,previous=current,current=? WHERE slot=?",listOf(report.values["title"] ?: "Untitled",report.revision,payload,slot))
            setActive(slot);Exchange.digest(payload)
        }
    }
    override fun close()=db.close()
}
