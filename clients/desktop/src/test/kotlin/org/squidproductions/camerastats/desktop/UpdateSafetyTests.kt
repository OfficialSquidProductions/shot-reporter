package org.squidproductions.camerastats.desktop

import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import org.squidproductions.camerastats.core.*
import org.squidproductions.camerastats.storage.JdbcDriver
import java.nio.file.*
import java.nio.channels.FileChannel
import java.sql.DriverManager
import kotlin.test.*

class UpdateSafetyTests {
    @TempDir lateinit var root:Path
    @org.junit.jupiter.api.BeforeEach fun canonicalTemp() {root=root.toRealPath()}
    private fun report()=Exchange.decode(Files.readAllBytes(Path.of(System.getProperty("fixtures"),"owner-demo.json")))
    @Test fun snapshotsReopenReportsAndLeaveLegacyDataUntouched() {
        val report=report();val slot=identity();Repository(JdbcDriver(root.resolve("reports.sqlite3"))).use {it.save(slot,report,"Update synthetic fixture",null)}
        val media=root.resolve("desktop-media/example");Files.createDirectories(media)
        JdbcDriver(media.resolve("media.sqlite3")).use {it.execute("CREATE TABLE journal(id TEXT,state TEXT)");it.execute("INSERT INTO journal VALUES('fixture','interrupted-copy')")}
        UpdateSaveGuard.acquire(root,slot,report,false,false,null).use {guard->
            val files=Files.list(guard.backup).use {it.toList()}
            val reportBackup=files.single {it.fileName.toString().endsWith("reports.sqlite3")}
            Repository(JdbcDriver(reportBackup)).use {assertEquals(report,it.load(slot).report)}
            assertFalse(files.any {it.fileName.toString().endsWith("media.sqlite3")})
            JdbcDriver(media.resolve("media.sqlite3")).use {assertEquals("interrupted-copy",it.query("SELECT state FROM journal").single().single())}
            assertFalse(Files.exists(media.resolve("worker.lock")))
        }
    }
    @Test fun legacyLocksDoNotGateUpdatesButUnacceptedEditsDo() {
        val media=root.resolve("desktop-media/example");Files.createDirectories(media)
        FileChannel.open(media.resolve("worker.lock"),StandardOpenOption.CREATE,StandardOpenOption.WRITE).use {channel->channel.lock().use {
            UpdateSaveGuard.acquire(root,null,null,false,false,null).close()
        }}
        assertFails {UpdateSaveGuard.acquire(root,null,null,true,false,null)}
        assertFails {UpdateSaveGuard.acquire(root,null,null,false,true,null)}
        assertFails {UpdateSaveGuard.acquire(root,null,null,false,false,"Save failed")}
    }
    @Test fun staleReportNeverCreatesAnInstallableCheckpoint() {
        val report=report();val slot=identity();Repository(JdbcDriver(root.resolve("reports.sqlite3"))).use {it.save(slot,report,"Update synthetic fixture",null)}
        assertFails {UpdateSaveGuard.acquire(root,slot,report.copy(revision=report.revision+1),false,false,null)}
        Repository(JdbcDriver(root.resolve("reports.sqlite3"))).use {assertEquals(report,it.load(slot).report)}
    }
    @Test fun missingAcceptedRevisionZeroReportIsNeverTreatedAsAnUnsavedNewDocument() {
        val zero=report().copy(revision=0);val slot=identity()
        Repository(JdbcDriver(root.resolve("reports.sqlite3"))).use {it.save(slot,zero,"Imported revision-zero report",null)}
        JdbcDriver(root.resolve("reports.sqlite3")).use {it.execute("DELETE FROM documents")}
        assertFails {UpdateSaveGuard.acquire(root,slot,zero,false,false,null,expectSaved=true)}
        UpdateSaveGuard.acquire(root,identity(),Report(),false,false,null,expectSaved=false).close()
    }
    @Test fun changedSaveAfterUICaptureBlocksUpdateWithoutFollowingLegacySymlinks() {
        val gateway=DesktopGateway(root)
        Repository(JdbcDriver(root.resolve("reports.sqlite3"))).use {repo->
            val state=org.squidproductions.camerastats.ui.AppState(repo,gateway);state.open(Report())
            val captured=captureUpdateSaveState(state)
            state.change("Changed after update intent") {it.copy(values=it.values+("title" to "Changed report"))}
            assertFails {updateSaveGuard(root,captured)}
        }
        val actual=root.resolve("elsewhere");Files.createDirectory(actual)
        Files.createSymbolicLink(root.resolve("desktop-media"),actual)
        UpdateSaveGuard.acquire(root,null,null,false,false,null).close()
        assertTrue(Files.isSymbolicLink(root.resolve("desktop-media")))
        assertEquals(0L,Files.list(actual).use {it.count()})
    }

}
