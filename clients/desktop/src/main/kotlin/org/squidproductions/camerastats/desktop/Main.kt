package org.squidproductions.camerastats.desktop

import androidx.compose.runtime.*
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.toComposeImageBitmap
import androidx.compose.ui.graphics.painter.BitmapPainter
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.*
import org.jetbrains.skia.Image
import org.squidproductions.camerastats.core.*
import org.squidproductions.camerastats.storage.JdbcDriver
import org.squidproductions.camerastats.ui.*
import java.nio.file.*
import java.nio.channels.FileChannel
import java.nio.ByteBuffer
import java.util.Properties
import javax.swing.*
import javax.swing.filechooser.FileNameExtensionFilter

fun main(args:Array<String>) {
    if(args.firstOrNull()=="--self-test") {
        require(args.size==2) { "--self-test requires an isolated output directory" }
        packagedSelfTest(Path.of(args[1]));return
    }
    if(args.firstOrNull()=="--verify-report-upgrade") {
        require(args.size==3);verifyReportUpgrade(Path.of(args[1]),Path.of(args[2]));return
    }
    if(args.firstOrNull()=="--desktop-release-smoke") {require(args.size==2);windowsDesktopReleaseSmoke(Path.of(args[1]));return}
    application {
    val root=remember {reportDataRoot()}
    val gateway=remember {DesktopGateway(root)}
    val repositoryResult=remember {runCatching {Repository(JdbcDriver(root.resolve("reports.sqlite3")))}}
    val state=remember {AppState(repositoryResult.getOrNull(),gateway).also {model ->repositoryResult.exceptionOrNull()?.let {model.error="Local reports could not be opened. Existing bytes were preserved. ${it.message}"};gateway.failure={model.fail(it)}}}
    DisposableEffect(Unit) {onDispose {repositoryResult.getOrNull()?.close()}}
    val updates=remember {DesktopUpdates(root,gateway)}
    DisposableEffect(updates) {onDispose {updates.close()}}
    Window(onCloseRequest=::exitApplication,title="Shot Reporter",icon=BitmapPainter(gateway.icon),state=rememberWindowState(width=1280.dp,height=900.dp)) {
        androidx.compose.foundation.layout.Column {
            androidx.compose.foundation.layout.Row {
                DesktopUpdateButton(updates,state,::exitApplication)
            }
            FieldApp(state)
        }
    }
}
}
class DesktopGateway(private val root:Path):PlatformGateway {
    override val releaseLabel="DESKTOP ALPHA 0.2"
    override val label="Windows / desktop"
    private fun resource(name:String)=javaClass.getResourceAsStream("/$name")!!.use {it.readBytes()}
    override val brand:ImageBitmap=Image.makeFromEncoded(resource("brand.png")).toComposeImageBitmap()
    val icon:ImageBitmap=Image.makeFromEncoded(resource("icon.png")).toComposeImageBitmap()
    var failure:(Exception)->Unit={}
    private val prefs=Properties().apply {runCatching {Files.newInputStream(root.resolve("preferences.properties")).use {load(it)}}}
    override fun demo():Report=Exchange.decode(resource("demo-report.json"))
    override fun notices():String=resource("open-source-notices.txt").toString(Charsets.UTF_8)
    override fun preference(key:String,fallback:String):String=prefs.getProperty(key,fallback)
    override fun preference(key:String,value:String,write:Boolean) {prefs.setProperty(key,value);runCatching {Files.createDirectories(root);Files.newOutputStream(root.resolve("preferences.properties")).use {prefs.store(it,"Shot Reporter local display preferences")}}}
    override fun importFile(complete:(ByteArray?)->Unit) {SwingUtilities.invokeLater {
        try {
            val chooser=JFileChooser().apply {dialogTitle="Import Shot Reporter report";fileFilter=FileNameExtensionFilter("Shot Reporter reports (*.camreport)","camreport");isAcceptAllFileFilterUsed=false}
            if(chooser.showOpenDialog(null)!=JFileChooser.APPROVE_OPTION) {complete(null);return@invokeLater}
            val bytes=Files.newInputStream(chooser.selectedFile.toPath()).use {it.readNBytes(Exchange.LIMIT+1)};require(bytes.size<=Exchange.LIMIT) {"Report exceeds the 32 MiB alpha limit."};complete(bytes)
        } catch(e:Exception) {failure(e)}
    }}
    override fun exportFile(name:String,mime:String,bytes:ByteArray,complete:()->Unit) {SwingUtilities.invokeLater {
        try {
            val chooser=JFileChooser().apply {dialogTitle="Save Shot Reporter report";selectedFile=java.io.File(name)}
            if(chooser.showSaveDialog(null)!=JFileChooser.APPROVE_OPTION) return@invokeLater
            val path=exportDestination(chooser.selectedFile.toPath().toAbsolutePath(),name.substringAfterLast('.'))
            if(Files.exists(path) && JOptionPane.showConfirmDialog(null,"Replace ${path.fileName}?","Replace existing file",JOptionPane.YES_NO_OPTION)!=JOptionPane.YES_OPTION) return@invokeLater
            durableExport(path,bytes);complete()
        } catch(e:Exception) {failure(e)}
    }}
    override fun pdf(report:Report):ByteArray=DesktopPDF.render(report)
}
fun durableExport(path:Path,bytes:ByteArray) {
    val temp=Files.createTempFile(path.parent,".camera-stats-export-",".tmp")
    try {
        FileChannel.open(temp,StandardOpenOption.WRITE).use {channel ->val buffer=ByteBuffer.wrap(bytes);while(buffer.hasRemaining()) channel.write(buffer);channel.force(true)}
        try {Files.move(temp,path,StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING)} catch(_:AtomicMoveNotSupportedException) {Files.move(temp,path,StandardCopyOption.REPLACE_EXISTING)}
    } finally {Files.deleteIfExists(temp)}
}

/** Report export never replaces a differently typed file such as a camera original. */
fun exportDestination(selected:Path,extension:String):Path {
    require(extension in setOf("camreport","pdf","csv","html"))
    return if(selected.fileName.toString().endsWith(".$extension",ignoreCase=true)) selected else selected.resolveSibling(selected.fileName.toString()+".$extension")
}

/** Exercises the bundled runtime in CI, with only synthetic data under the supplied QA directory. */
fun packagedSelfTest(root:Path) {
    Files.createDirectories(root);val gateway=DesktopGateway(root);val demo=gateway.demo().separateDemo();val slot=identity()
    Repository(JdbcDriver(root.resolve("qa.sqlite3"))).use {repo ->val hash=repo.save(slot,demo,"Packaged runtime test",null);repo.save(slot,demo.next("3A","Packaged runtime test"),"Packaged runtime test",hash)}
    val restored=Repository(JdbcDriver(root.resolve("qa.sqlite3"))).use {it.load(slot).report}
    check(restored.active.size==4 && restored.active.last().values["take"]=="4")
    durableExport(root.resolve("package-test.camreport"),Exchange.export(restored,"Packaged runtime test"))
    check(Exchange.read(Files.readAllBytes(root.resolve("package-test.camreport"))).report==restored)
    val pdf=gateway.pdf(restored);check(pdf.take(5).toByteArray().toString(Charsets.US_ASCII)=="%PDF-");Files.write(root.resolve("package-test.pdf"),pdf)
    check(gateway.brand.width>0 && gateway.icon.width==256)
    check(gateway.notices().contains("Independent JPEG Group"))
    check(java.security.Signature.getInstance("Ed25519").algorithm=="Ed25519") {"Bundled update signature provider is missing"}
    check(Files.isDirectory(Path.of(System.getProperty("java.home"),"legal"))) {"Bundled runtime license files are missing"}
    Files.writeString(root.resolve("PASS.txt"),"PASS: bundled JVM, native SQLite durable reopen, camreport roundtrip, PDF rendering and suite image resources.\n")
}

/** The legacy directory is part of the upgrade contract; branding never changes report ownership. */
fun reportDataRoot():Path=Path.of(System.getenv("LOCALAPPDATA") ?: Path.of(System.getProperty("user.home"),".local","share").toString(),"Squid Productions","Camera Stats")

/** Read an old installed runtime's synthetic report from the normal data location in isolated CI. */
fun verifyReportUpgrade(expectedFile:Path,output:Path) {
    val root=reportDataRoot();val expected=Exchange.read(Files.readAllBytes(expectedFile)).report
    val restored=Repository(JdbcDriver(root.resolve("reports.sqlite3"))).use {repo ->
        val slot=checkNotNull(repo.active());val current=repo.load(slot).report
        check(current==expected);check(repo.load(slot,true).report.active.size==3);check(repo.list().size==1);current
    }
    val host=DesktopGateway(root);check(host.preference("theme","System")=="Dark")
    Files.createDirectories(output);val bytes=Exchange.export(restored,"Shot Reporter upgrade verification")
    check(Exchange.read(bytes).report==expected);durableExport(output.resolve("Shot-Reporter-upgraded.camreport"),bytes)
    durableExport(output.resolve("Shot-Reporter-upgraded.pdf"),host.pdf(restored))
    Files.writeString(output.resolve("PASS.txt"),"PASS: previous installed runtime -> Shot Reporter MSI upgrade; normal legacy data directory, active report, every field/history/identity/revision, previous snapshot, preferences and camreport roundtrip preserved.\n")
}
