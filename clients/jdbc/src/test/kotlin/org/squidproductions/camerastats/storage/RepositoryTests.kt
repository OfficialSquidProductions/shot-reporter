package org.squidproductions.camerastats.storage

import org.squidproductions.camerastats.core.*
import org.junit.jupiter.api.Test
import kotlin.test.*
import java.io.File
import java.nio.file.Files
import java.net.URLClassLoader

class RepositoryTests {
    private fun root()=Files.createTempDirectory("camerastats-jdbc-")
    private fun demo()=Exchange.read(File(System.getProperty("fixtures"),"swift-demo.camreport").readBytes()).report
    @Test fun transactionalSnapshotsSelectionAndReopen() {
        val path=root().resolve("reports.sqlite3");val slot=identity();val first=demo();val next=first.next("3A","Test")
        Repository(JdbcDriver(path)).use { repo -> val hash=repo.save(slot,first,"Test",null);repo.save(slot,next,"Test",hash);assertEquals(first,repo.load(slot,true).report);assertEquals(slot,repo.active()) }
        Repository(JdbcDriver(path)).use { repo -> assertEquals(next,repo.load(slot).report);val other=identity();repo.save(other,demo(),"Test",null);assertEquals(2,repo.list().size);repo.select(slot);assertEquals(slot,repo.active()) }
    }
    @Test fun staleWriterCannotOverwriteAcceptedSnapshot() {
        val path=root().resolve("reports.sqlite3");Repository(JdbcDriver(path)).use { a -> Repository(JdbcDriver(path)).use { b -> val slot=identity();val initial=demo();val hash=a.save(slot,initial,"A",null);val next=initial.next("3A","A");a.save(slot,next,"A",hash);assertFails { b.save(slot,initial.copy(values=initial.values+("title" to "stale")),"B",hash) };assertEquals(next,b.load(slot).report) } }
    }
    @Test fun failedCommitRollsBackSnapshotAndActiveSelection() {
        val path=root().resolve("reports.sqlite3");val underlying=JdbcDriver(path);var fail=false
        val driver=object:SqlDriver by underlying {override fun execute(sql:String,args:List<Any?>) {if(fail && sql=="COMMIT") throw ReportException("Injected interrupted commit");underlying.execute(sql,args)}}
        Repository(driver).use { r -> val slot=identity();val initial=demo();val hash=r.save(slot,initial,"Test",null);fail=true;assertFails {r.save(identity(),initial.next("3A","Test"),"Test",null)};fail=false;assertEquals(slot,r.active());assertEquals(1,r.list().size);assertEquals(initial,r.load(slot).report);assertEquals(hash,r.load(slot).fingerprint) }
    }
    @Test fun storageFullPreservesReport() {
        val path=root().resolve("reports.sqlite3");val driver=JdbcDriver(path);Repository(driver).use { r -> val slot=identity();val initial=demo();val hash=r.save(slot,initial,"Test",null);val pages=(driver.query("PRAGMA page_count").single().single() as Number).toInt();driver.query("PRAGMA max_page_count=$pages");val large=initial.copy(values=initial.values+("large" to "offline day ".repeat(500000)));assertFails {r.save(slot,large,"Test",hash)};assertEquals(initial,r.load(slot).report) }
    }
    @Test fun deletedReportsRestoreExactSnapshotsAndRejectStaleWriters() {
        val path=root().resolve("reports.sqlite3");val slot=identity();val report=demo();val changed=report.next("8B","Test")
        Repository(JdbcDriver(path)).use {repo ->
            val old=repo.save(slot,report,"Test",null);val latest=repo.save(slot,changed,"Test",old)
            assertFails {repo.delete(slot,old)};assertEquals(changed,repo.load(slot).report)
            assertNull(repo.delete(slot,latest));assertNull(repo.active());assertTrue(repo.list().isEmpty());assertEquals(slot,repo.list(true).single().slot)
            assertFails {repo.save(slot,changed,"Stale",latest)}
        }
        Repository(JdbcDriver(path)).use {repo ->assertEquals(changed,repo.restoreDeleted(slot).report);assertEquals(report,repo.load(slot,true).report);assertEquals(slot,repo.active());assertTrue(repo.list(true).isEmpty())}
    }
    @Test fun failedDeleteCommitRetainsReportAndActiveSelection() {
        val path=root().resolve("reports.sqlite3");val driver=JdbcDriver(path);var fail=false
        val interrupted=object:SqlDriver by driver {override fun execute(sql:String,args:List<Any?>) {if(fail && sql=="COMMIT") throw ReportException("Interrupted delete");driver.execute(sql,args)}}
        Repository(interrupted).use {repo ->val slot=identity();val report=demo();val hash=repo.save(slot,report,"Test",null);fail=true;assertFails {repo.delete(slot,hash)};fail=false;assertEquals(report,repo.load(slot).report);assertEquals(slot,repo.active());assertTrue(repo.list(true).isEmpty())}
    }
    @Test fun invalidSlotAndFutureSchemaPreserveExistingDatabase() {
        val path=root().resolve("reports.sqlite3");Repository(JdbcDriver(path)).use {r -> assertFails {r.save("../escape",demo(),"Test",null)} }
        JdbcDriver(path).use {it.execute("PRAGMA user_version=99")};assertFails {Repository(JdbcDriver(path))};JdbcDriver(path).use { assertEquals(99,(it.query("PRAGMA user_version").single().single() as Number).toInt()) }
    }
    @Test fun committedReportSurvivesAbruptProcessExit() {
        val path=root().resolve("crash.sqlite3");val urls=mutableListOf<String>();var loader:ClassLoader?=javaClass.classLoader
        while(loader!=null) {if(loader is URLClassLoader) urls+=loader.urLs.map { File(it.toURI()).path };loader=loader.parent}
        val classpath=(urls+System.getProperty("java.class.path").split(File.pathSeparator)).distinct().joinToString(File.pathSeparator)
        val javaPath=File(System.getProperty("java.home"),"bin/java").path
        val process=ProcessBuilder(javaPath,"-cp",classpath,CrashChild::class.java.name,path.toString(),System.getProperty("fixtures")).redirectErrorStream(true).start()
        assertTrue(process.waitFor(30,java.util.concurrent.TimeUnit.SECONDS));val output=process.inputStream.bufferedReader().readText();assertEquals(137,process.exitValue(),output)
        Repository(JdbcDriver(path)).use { r -> assertEquals(1,r.list().size);assertEquals(3,r.load(r.active()!!).report.active.size) }
    }
}
object CrashChild {
    @JvmStatic fun main(args:Array<String>) {val report=Exchange.read(File(args[1],"swift-demo.camreport").readBytes()).report;val repository=Repository(JdbcDriver(java.nio.file.Path.of(args[0])));repository.save(identity(),report,"Crash fixture",null);Runtime.getRuntime().halt(137)}
}
