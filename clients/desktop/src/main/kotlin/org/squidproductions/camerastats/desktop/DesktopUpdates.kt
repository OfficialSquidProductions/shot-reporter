package org.squidproductions.camerastats.desktop

import androidx.compose.runtime.*
import androidx.compose.material3.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import org.squidproductions.camerastats.updates.*
import org.squidproductions.camerastats.ui.AppState
import kotlinx.coroutines.delay
import java.nio.file.*
import java.util.concurrent.*
import javax.swing.SwingUtilities

class DesktopUpdates(private val root:Path,private val gateway:DesktopGateway):AutoCloseable {
    var visible by mutableStateOf(false)
    var busy by mutableStateOf(false);private set
    var installing by mutableStateOf(false);private set
    var status by mutableStateOf("Update service is not configured for this development build.");private set
    var release by mutableStateOf<UpdateRelease?>(null);private set
    var installer by mutableStateOf<Path?>(null);private set
    var channel by mutableStateOf(gateway.preference("updates.channel","alpha"));private set
    var automatic by mutableStateOf(gateway.preference("updates.automatic","true")=="true");private set
    private val pool=Executors.newSingleThreadExecutor {r->Thread(r,"Shot Reporter updates").apply {isDaemon=true}}
    private var future:Future<*>?=null
    @Volatile private var generation=0L
    private var guard:PreparedInstall?=null
    private val lifecycle=Any()
    @Volatile private var closed=false
    private val policy=runCatching {javaClass.getResourceAsStream("/windows-update-policy.json")?.use {updateJSON.decodeFromString<UpdatePolicy>(it.readBytes().toString(Charsets.UTF_8)).also(UpdatePolicy::validate)}}.getOrNull()
    init {
        if(channel !in setOf("alpha","stable")) channel="alpha"
        // A failed installation result remains visible until a later successful update replaces it.
        val storage=root.resolve("updates/downloads")
        runCatching {if(Files.isDirectory(storage)) Files.walk(storage,3).use {paths->paths.filter {it.fileName.toString()=="install-result.json" && Files.isRegularFile(it,LinkOption.NOFOLLOW_LINKS) && !Files.isSymbolicLink(it)}.sorted(compareByDescending<Path> {Files.getLastModifiedTime(it).toMillis()}).limit(1).forEach {result->
            val text=readBounded(Files.newInputStream(result,LinkOption.NOFOLLOW_LINKS),1024*1024).toString(Charsets.UTF_8).removePrefix("\uFEFF");status=installResultMessage(updateJSON.decodeFromString<UpdateInstallResult>(text));visible=true
        }}}
    }
    fun changeAutomatic(value:Boolean) {automatic=value;gateway.preference("updates.automatic",value.toString(),true)}
    fun changeChannel(value:String) {if(busy || value !in setOf("alpha","stable")) return;channel=value;release=null;installer=null;gateway.preference("updates.channel",value,true);status="Channel changed. Check for updates to refresh availability."}
    private fun run(action:(Long)->Unit) {if(busy || closed) return;busy=true;val operation=++generation;future=pool.submit {try {action(operation)} catch(e:Throwable) {SwingUtilities.invokeLater {if(!closed && operation==generation) {status=e.message ?: "Update failed; app data was preserved.";visible=true}}} finally {SwingUtilities.invokeLater {if(!closed && operation==generation) busy=false}}}}
    private fun publish(operation:Long,action:()->Unit)=SwingUtilities.invokeLater {if(!closed && operation==generation) action()}
    private fun unavailable():Boolean {
        if(!System.getProperty("os.name").startsWith("Windows")) {status="Use the native macOS Shot Reporter update menu on this platform.";return true}
        if(policy==null) {status="Automatic installation is not configured. This build has no trusted Shot Reporter update feed, signing key or Windows publisher certificate. Existing unsigned releases require manual installation. Reports remain in their existing folder.";return true};return false
    }
    fun check(manual:Boolean=true) {
        if(manual) visible=true
        if(unavailable()) return
        val selected=channel
        run {operation->
            val watermark=UpdateRollbackStore(root.resolve("updates"),policy!!.currentBuild)
            val next=UpdateDownloader(policy,root.resolve("updates/downloads")).check(selected,watermark.load())
            next?.let {watermark.remember(it.build)}
            publish(operation) {if(channel==selected) {release=next;installer=null;status=if(next==null) "No newer verified update is available on the $selected channel." else "Shot Reporter ${next.version} is available.";if(next!=null || manual) visible=true}}
        }
    }
    fun download() {val next=release ?: return;if(unavailable()) return
        run {operation->val path=UpdateDownloader(policy!!,root.resolve("updates/downloads")).download(next) {got,total->publish(operation) {status="Downloading update · ${100*got/total}%"}}
            publish(operation) {installer=path;status="Download length and SHA-256 verified. Windows publisher and MSI identity will be checked before installation."}}
    }
    fun openRecoveryFolder() {
        try {java.awt.Desktop.getDesktop().open(safeDirectory(root.resolve("updates")).toFile())}
        catch(e:Exception) {status="Could not open the update recovery folder. ${e.message.orEmpty()}"}
    }
    fun cancel() {if(installing) return;generation++;future?.cancel(true);busy=false;status="Update operation cancelled. Partial downloads and logs are retained; they cannot be installed."}
    fun install(state:AppState,exit:()->Unit) {
        val next=release ?: return;val file=installer ?: return;if(unavailable() || busy) return
        val savedState=captureUpdateSaveState(state)
        installing=true;status="Verifying saved reports and recovery snapshots…"
        run {operation->
            try {
                val executable=System.getProperty("jpackage.app-path")?.let(Path::of) ?: error("Run the installed Windows application before updating.")
                val prepared=WindowsUpdateInstaller(policy!!).prepare(next,file,executable) {updateSaveGuard(root,savedState)}
                synchronized(lifecycle) {
                    if(closed || operation!=generation) {prepared.close();return@run}
                    guard=prepared
                }
                publish(operation) {
                    try {
                        prepared.commit()
                        exit()
                    } catch(e:Throwable) {
                        prepared.close();synchronized(lifecycle) {if(guard===prepared) guard=null}
                        installing=false;status=e.message ?: "Update handoff failed; app data was preserved."
                    }
                }
            } catch(e:Throwable) {publish(operation) {installing=false};throw e}
        }
    }
    override fun close() {
        synchronized(lifecycle) {if(closed) return;closed=true;generation++;guard?.close();guard=null}
        future?.cancel(true);pool.shutdownNow()
    }
}
@Composable fun DesktopUpdateButton(updates:DesktopUpdates,state:AppState,exit:()->Unit) {
    LaunchedEffect(Unit) {delay(15000);while(true) {if(updates.automatic) updates.check(false);delay(86400000)}}
    TextButton(enabled=!updates.installing,onClick={updates.visible=true}) {Text(if(updates.release!=null) "Update available" else "Updates…")}
    if(updates.visible) AlertDialog(onDismissRequest={if(!updates.installing) updates.visible=false},title={Text(updates.release?.let {"Shot Reporter ${it.version}"} ?: "Shot Reporter updates")},text={Column(Modifier.widthIn(min=420.dp,max=680.dp).heightIn(max=520.dp).verticalScroll(rememberScrollState()),verticalArrangement=Arrangement.spacedBy(12.dp)) {
        Text(updates.status)
        TextButton(enabled=!updates.busy,onClick={updates.openRecoveryFolder()}) {Text("Logs and backups")}
        updates.release?.let {Text("What’s new",style=MaterialTheme.typography.titleMedium);Text(it.releaseNotes.ifBlank {"Release notes unavailable."});Text("The app saves and verifies reports before installation. Windows Installer may request permission, then Shot Reporter relaunches. Cancel to keep working.")}
        Row {Checkbox(updates.automatic,{updates.changeAutomatic(it)},enabled=!updates.busy);Text("Check automatically at launch and daily")}
        Row {listOf("stable","alpha").forEach {value->FilterChip(updates.channel==value,{updates.changeChannel(value)},label={Text(value.replaceFirstChar(Char::uppercase))},enabled=!updates.busy)}}
        if(updates.busy) LinearProgressIndicator(Modifier.fillMaxWidth())
    }},confirmButton={Row {
        if(!updates.busy) TextButton(onClick={updates.check()}) {Text("Check for updates")}
        if(updates.release!=null && !updates.busy) {
            if(updates.installer==null) Button(onClick={updates.download()}) {Text("Download update")}
            else Button(onClick={updates.install(state,exit)}) {Text("Save, install and restart")}
        }
    }},dismissButton={TextButton(enabled=!updates.installing,onClick={if(updates.busy) updates.cancel() else updates.visible=false}) {Text(if(updates.busy) "Cancel" else "Keep working")}})
}
