package org.squidproductions.camerastats.desktop

import org.squidproductions.camerastats.core.*
import org.squidproductions.camerastats.storage.JdbcDriver
import org.squidproductions.camerastats.ui.AppState
import org.squidproductions.camerastats.updates.*
import java.nio.channels.FileChannel
import java.nio.file.*
import java.sql.DriverManager
import java.time.Instant
import java.util.UUID

/** Report-only checkpoint. Legacy application data is left untouched. */
class UpdateSaveGuard private constructor(val backup:Path):AutoCloseable {
    override fun close() = Unit
    companion object {
        fun acquire(root:Path,slot:String?,report:Report?,blocked:Boolean,pending:Boolean,error:String?,expectSaved:Boolean=report!=null):UpdateSaveGuard {
            check(!blocked && !pending && error==null) {"Resolve the report save or import message before installing an update."}
            val home=safeDirectory(root)
            val databases=mutableListOf<Path>()
            val reports=home.resolve("reports.sqlite3")
            if(Files.exists(reports,LinkOption.NOFOLLOW_LINKS)) {
                check(!Files.isSymbolicLink(reports))
                Repository(JdbcDriver(reports)).use {repo->if(expectSaved) {check(slot!=null && report!=null);check(repo.load(slot).report==report) {"The report in memory differs from its durable save. Reopen it before updating."}}}
                databases.add(0,reports)
            } else check(!expectSaved && (report==null || report.revision==0L)) {"A saved report database is missing."}
            val backup=safeDirectory(home.resolve("updates/backups")).resolve(UUID.randomUUID().toString());Files.createDirectory(backup)
            val manifest=java.util.Properties()
            databases.forEachIndexed {index,path->
                manifest.setProperty("$index.file",home.relativize(path).toString())
                check(Files.isRegularFile(path,LinkOption.NOFOLLOW_LINKS) && !Files.isSymbolicLink(path))
                val destination=backup.resolve("$index-${path.fileName}")
                DriverManager.getConnection("jdbc:sqlite:${path.toAbsolutePath()}").use {db->
                    db.createStatement().use {stmt->stmt.execute("PRAGMA busy_timeout=3000");stmt.execute("VACUUM INTO '${destination.toString().replace("'","''")}'")}
                }
                FileChannel.open(destination,StandardOpenOption.WRITE).use {it.force(true)}
                DriverManager.getConnection("jdbc:sqlite:${destination.toAbsolutePath()}").use {db->db.createStatement().use {stmt->stmt.executeQuery("PRAGMA quick_check").use {result->check(result.next() && result.getString(1)=="ok") {"Update backup verification failed."}}}}
            }
            val mapping=java.io.ByteArrayOutputStream().also {manifest.store(it,"Pre-update backup filename index -> original relative path")}.toByteArray()
            durableNew(backup.resolve("manifest.properties"),mapping)
            durableNew(backup.resolve("README.txt"),("Shot Reporter pre-update snapshots, ${Instant.now()}.\nReports stay at their existing locations. These SQLite snapshots are retained for manual recovery. Other application data is not opened, migrated or removed.\n").toByteArray())
            return UpdateSaveGuard(backup)
        }
    }
}
/** Capture on the UI thread before dispatch; never mix fields from different selected reports. */
data class UpdateSaveState(val slot:String,val report:Report,val blocked:Boolean,val pending:Boolean,val error:String?,val expectSaved:Boolean)
fun captureUpdateSaveState(state:AppState)=UpdateSaveState(state.slot,state.report,state.blocked,state.pending!=null,state.error,state.documents.any {it.slot==state.slot})
fun updateSaveGuard(root:Path,state:UpdateSaveState)=UpdateSaveGuard.acquire(root,state.slot,state.report,state.blocked,state.pending,state.error,state.expectSaved)
fun updateSaveGuard(root:Path,state:AppState)=updateSaveGuard(root,captureUpdateSaveState(state))
