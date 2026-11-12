package org.squidproductions.camerastats.ui

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import org.squidproductions.camerastats.core.*

interface PlatformGateway {
    val label:String
    val releaseLabel:String get()="FIELD ALPHA 0.1"
    val brand:ImageBitmap
    fun notices():String
    fun importFile(complete:(ByteArray?)->Unit)
    fun exportFile(name:String,mime:String,bytes:ByteArray,complete:()->Unit)
    fun pdf(report:Report):ByteArray
    fun preference(key:String,fallback:String):String
    fun preference(key:String,value:String,write:Boolean)
}

class AppState(private val repository:Repository?,val platform:PlatformGateway) {
    var report by mutableStateOf(Report());private set
    var slot by mutableStateOf(identity());private set
    var documents by mutableStateOf(emptyList<Document>());private set
    var deletedDocuments by mutableStateOf(emptyList<Document>());private set
    data class DeletionRequest(val slot:String,val title:String,val fingerprint:String)
    var selected by mutableStateOf<String?>(null)
    var error by mutableStateOf<String?>(null)
    var status by mutableStateOf("Create a local report to begin");private set
    var blocked by mutableStateOf(repository==null);private set
    var pending by mutableStateOf<Exchange.Package?>(null)
    var lastExport by mutableStateOf<String?>(null);private set
    private var fingerprint:String?=null
    init {
        try {repository?.active()?.let { adopt(repository.select(it)) };refresh();cleanupExpiredTrash()}
        catch(e:Exception) {blocked=true;error="Existing reports could not be read. Their bytes were preserved. ${e.message}"}
    }
    private fun adopt(loaded:Loaded) {slot=loaded.slot;report=loaded.report;fingerprint=loaded.fingerprint;status="Saved on this device";blocked=false;selected=report.active.firstOrNull { "Circle" in it.flags }?.id ?: report.active.lastOrNull()?.id}
    private fun refresh() {documents=repository?.list().orEmpty();deletedDocuments=repository?.list(true).orEmpty()}
    private fun rememberDocument() {documents=(documents.filterNot {it.slot==slot}+Document(slot,report.values["title"] ?: "Untitled",report.revision)).sortedWith(compareBy({it.title},{it.slot}))}
    fun fail(e:Exception) {error=e.message ?: "This operation could not be completed; existing report preserved."}
    fun attempt(action:()->Unit) {try {action()} catch(e:Exception) {fail(e)}}
    fun change(summary:String,action:(Report)->Report) {
        if(blocked) {error="Local recovery is required before changes can be saved.";return}
        try {
            val proposed=action(report);if(proposed==report) return;val next=if(proposed.revision==report.revision) proposed.record(summary,platform.label) else proposed
            val hash=repository!!.save(slot,next,platform.label,fingerprint)
            report=next;fingerprint=hash;status="Saved on this device";rememberDocument()
        } catch(e:Exception) {error="Save failed; this change was not accepted. ${e.message.orEmpty()}"}
    }
    fun open(incoming:Report) = attempt {
        val newSlot=identity();val hash=repository!!.save(newSlot,incoming,platform.label,null)
        adopt(Loaded(newSlot,incoming,hash));rememberDocument()
    }
    fun select(id:String)=attempt {adopt(repository!!.select(id))}
    fun deletionRequest(id:String):DeletionRequest {
        require(!blocked && pending==null) {"Resolve recovery or import before deleting a report."}
        val loaded=repository!!.load(id);return DeletionRequest(id,loaded.report.values["title"] ?: "Untitled",loaded.fingerprint)
    }
    fun deleteReport(request:DeletionRequest)=attempt {
        require(!blocked && pending==null) {"Resolve recovery or import before deleting a report."}
        val next=repository!!.delete(request.slot,request.fingerprint)
        if(next!=null) adopt(next) else {report=Report();slot=identity();fingerprint=null;selected=null;status="Create a local report to begin"}
        refresh()
    }
    fun restoreDeletedReport(id:String)=attempt {
        require(!blocked && pending==null) {"Resolve recovery or import before restoring a report."}
        adopt(repository!!.restoreDeleted(id));refresh()
    }
    fun trashRequest():List<TrashItem> {require(!blocked && pending==null) {"Resolve recovery or import before clearing trash."};return repository!!.trash()}
    fun clearTrash(request:List<TrashItem>)=attempt {require(!blocked && pending==null);repository!!.clearTrash(request);refresh()}
    fun cleanupExpiredTrash() {if(!blocked && pending==null) attempt {repository!!.cleanupExpiredTrash();refresh()}}
    fun previous()=attempt {open(repository!!.load(slot,true).report)}
    fun next(scene:String) {change("Added take") {it.next(scene,platform.label)};selected=report.active.lastOrNull()?.id}
    fun entry(id:String,summary:String,action:(Entry)->Entry)=change(summary) {r -> r.copy(entries=r.entries.map {if(it.id==id) action(it) else it})}
    fun importReport()=attempt {platform.importFile {bytes -> if(bytes!=null) attempt {pending=Exchange.read(bytes)}}}
    fun export(kind:String)=attempt {
        val snapshot=report
        val (type,bytes)=when(kind) {"pdf" -> "application/pdf" to platform.pdf(snapshot);"csv" -> "text/csv" to Reports.csv(snapshot).toByteArray(Charsets.UTF_8);"html" -> "text/html" to Reports.html(snapshot).toByteArray(Charsets.UTF_8);else -> "application/octet-stream" to Exchange.export(snapshot,platform.label)}
        platform.exportFile("Shot-Reporter-r${snapshot.revision}.$kind",type,bytes) {lastExport="Saved $kind snapshot · r${snapshot.revision}"}
    }
}

private val Green=Color(0xff237b20)
@Composable fun FieldApp(state:AppState) {
    val host=state.platform
    var theme by remember {mutableStateOf(host.preference("theme","System"))}
    val dark=theme=="Dark" || theme=="System" && isSystemInDarkTheme()
    val palette=if(dark) darkColorScheme(primary=Color(0xff95df8d),secondary=Color(0xff95df8d),secondaryContainer=Color(0xff34452f),onSecondaryContainer=Color(0xffc3efbc),outline=Color(0xff8d7784),outlineVariant=Color(0xff49333f),background=Color(0xff191419),surface=Color(0xff251d23),onSurface=Color(0xfff3eaf0)) else lightColorScheme(primary=Green,secondary=Green,secondaryContainer=Color(0xffdaeed6),onSecondaryContainer=Color(0xff1c4618),background=Color(0xfffaf8f9),surface=Color.White)
    var page by remember {mutableStateOf("Today")};var detail by remember {mutableStateOf(host.preference("detail","Standard"))}
    var documentPicker by remember {mutableStateOf(false)}
    var trashToClear by remember {mutableStateOf<List<TrashItem>?>(null)}
    LaunchedEffect(state) {while(true) {state.cleanupExpiredTrash();kotlinx.coroutines.delay(3_600_000)}}
    var reportToDelete by remember {mutableStateOf<AppState.DeletionRequest?>(null)}
    var notices by remember {mutableStateOf<String?>(null)}
    MaterialTheme(colorScheme=palette) {
        Surface(Modifier.fillMaxSize(),color=palette.background) {
            BoxWithConstraints(Modifier.fillMaxSize().safeDrawingPadding()) {
                val wide=maxWidth>=800.dp
                Row(Modifier.fillMaxSize()) {
                    if(wide) Column(Modifier.width(248.dp).fillMaxHeight().background(palette.surface).padding(16.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {
                        WorkspaceBrand(host)
                        Text(if(state.blocked) "Recovery required" else state.status,style=MaterialTheme.typography.labelSmall,color=palette.onSurfaceVariant)
                        HorizontalDivider(Modifier.padding(vertical=12.dp))
                        listOf("Today","Log","Review","Saves").forEach {destination ->
                            if(page==destination) FilledTonalButton(onClick={page=destination},modifier=Modifier.fillMaxWidth(),shape=RoundedCornerShape(6.dp)) {WorkspaceLabel(destination)}
                            else TextButton(onClick={page=destination},modifier=Modifier.fillMaxWidth(),shape=RoundedCornerShape(6.dp)) {WorkspaceLabel(destination)}
                        }
                        Spacer(Modifier.weight(1f))
                        HorizontalDivider()
                        TextButton(onClick={page="Settings"},modifier=Modifier.fillMaxWidth()) {WorkspaceLabel("Settings")}
                    }
                    Column(Modifier.weight(1f).fillMaxHeight()) {
                        if(!wide) WorkspaceBrand(host)
                        Row(Modifier.fillMaxWidth().padding(horizontal=16.dp),verticalAlignment=Alignment.CenterVertically) {Text(state.report.values["title"] ?: "New production",Modifier.weight(1f),fontWeight=FontWeight.Bold,maxLines=1);Text("r${state.report.revision}",style=MaterialTheme.typography.labelMedium)}
                        if(!wide) Row(Modifier.fillMaxWidth().padding(8.dp),horizontalArrangement=Arrangement.SpaceEvenly) {
                            listOf("Today","Log","Review","Saves").forEach { destination ->
                                if(page==destination) FilledTonalButton(onClick={page=destination},modifier=Modifier.weight(1f).padding(horizontal=2.dp),contentPadding=PaddingValues(horizontal=4.dp,vertical=8.dp)) {Text(destination)} else TextButton(onClick={page=destination},modifier=Modifier.weight(1f).padding(horizontal=2.dp),contentPadding=PaddingValues(horizontal=4.dp,vertical=8.dp)) {Text(destination)}
                            }
                        }
                        HorizontalDivider()
                        Box(Modifier.weight(1f).fillMaxWidth(),contentAlignment=Alignment.TopCenter) {
                            Column(Modifier.widthIn(max=1000.dp).fillMaxWidth().verticalScroll(rememberScrollState()).padding(16.dp),verticalArrangement=Arrangement.spacedBy(12.dp)) {
                                when(page) {
                                    "Today" -> {
                                        Section("Local production") {
                                            Text(if(state.blocked) "Recovery required" else state.status,style=MaterialTheme.typography.labelMedium)
                                            OutlinedButton(onClick={documentPicker=true},enabled=state.documents.isNotEmpty()) {Text("Open report")}
                                            Button(onClick={state.open(Report())},enabled=!state.blocked,modifier=Modifier.fillMaxWidth().heightIn(min=48.dp)) {Text("New blank report")}
                                        }
                                        Section("Production profile") {
                                            Choice("Production profile",state.report.profile,Schema.profiles) {v -> state.change("Changed profile; all values retained") {it.copy(profile=v)}}
                                        }
                                        Section("Project / crew · complete report") {Fields(state.report.projectFields,state.report.values) {k,v ->state.change("Edited project field") {it.copy(values=it.values+(k to v))}} }
                                    }
                                    "Settings" -> {
                                        Section("Production mode") {
                                            Choice("Production mode",state.report.productionMode.label,listOf("Movie","TV")) {v ->state.change("Changed production mode; all values retained") {it.withProductionMode(if(v=="TV") ProductionMode.TV else ProductionMode.MOVIE)}}
                                            Text("Movie hides Season and Episode. TV shows them in Today and reports. Hidden values are kept for this report.")
                                        }
                                        Section("Trash") {
                                            Text("Deleted reports are permanently removed after 14 days, when the app next opens or while it is running. Restoring cancels cleanup. Existing trash gets a fresh 14 days after this update.")
                                            OutlinedButton(onClick={state.attempt {trashToClear=state.trashRequest()}},enabled=state.deletedDocuments.isNotEmpty() && !state.blocked && state.pending==null) {Text("Clear Trash…")}
                                            Text("Exports and external backups are kept.")
                                        }
                                        Section("Appearance") {
                                            Choice("Appearance",theme,listOf("System","Light","Dark")) {v -> theme=v;host.preference("theme",v,true)}
                                        }
                                        Section("Support & about") {
                                            TextButton(onClick={state.attempt {notices=host.notices()}}) {Text("Open-source notices")}
                                            Text("All camera, DP, data, and script / continuity responsibilities are always available.")
                                            Text("${host.releaseLabel} · ${host.label}",style=MaterialTheme.typography.labelSmall)
                                        }
                                    }
                                    "Log" -> LogScreen(state,detail,{v ->detail=v;host.preference("detail",v,true)})
                                    "Review" -> ReviewScreen(state)
                                    "Saves" -> {
                                        Section("Saved reports") {
                                            if(state.documents.isEmpty()) Text("No saved reports. Create a blank report in Today.")
                                            state.documents.forEach {doc ->Row(verticalAlignment=Alignment.CenterVertically) {
                                                TextButton(onClick={state.select(doc.slot)},modifier=Modifier.weight(1f)) {Text("${doc.title} · r${doc.revision}")}
                                                TextButton(onClick={state.attempt {reportToDelete=state.deletionRequest(doc.slot)}},enabled=!state.blocked && state.pending==null) {Text("Delete Report")}
                                            }}
                                        }
                                        if(state.deletedDocuments.isNotEmpty()) Section("Recently Deleted") {
                                            Text("Deleted reports can be restored for 14 days, then are permanently removed. Clear Trash in Settings removes them sooner.")
                                            state.deletedDocuments.forEach {doc ->Row(verticalAlignment=Alignment.CenterVertically) {
                                                Text("${doc.title} · r${doc.revision}",Modifier.weight(1f))
                                                TextButton(onClick={state.restoreDeletedReport(doc.slot)},enabled=!state.blocked && state.pending==null) {Text("Restore Report")}
                                            }}
                                        }
                                        Section("Report handoff") {
                                            Text(state.status);state.lastExport?.let {Text(it,style=MaterialTheme.typography.bodySmall)}
                                            Button(onClick={state.export("camreport")}) {Text("Save As .camreport")}
                                            OutlinedButton(onClick={state.importReport()}) {Text("Import Save…")}
                                            Text("A .camreport includes all project fields, camera defaults, takes, notes, flags, review state and history, including hidden Movie/TV values. Open separately for a complete handoff. Media, attachments, device preferences, other reports and recovery snapshots are excluded. A save is not proof of receipt.",style=MaterialTheme.typography.bodySmall)
                                            TextButton(onClick={state.previous()},enabled=!state.blocked) {Text("Restore previous snapshot separately")}
                                        }
                                        Section("Preview and export") {
                                            Button(onClick={state.export("pdf")}) {Text("Save landscape Camera Report PDF")}
                                            OutlinedButton(onClick={state.export("csv")}) {Text("Export CSV")}
                                            OutlinedButton(onClick={state.export("html")}) {Text("Export HTML report")}
                                            Text("PDF is a frozen draft/ready report. CSV and HTML are generic report exports.",style=MaterialTheme.typography.bodySmall)
                                        }
                                    }
                                }
                            }
                        }
                        if(!wide) {
                            HorizontalDivider()
                            TextButton(onClick={page="Settings"},modifier=Modifier.fillMaxWidth().padding(8.dp)) {WorkspaceLabel("Settings")}
                        }
                    }
                }
            }
        }
        trashToClear?.let {request ->AlertDialog(onDismissRequest={trashToClear=null},title={Text("Permanently clear trash?")},text={Text("Remove ${request.size} deleted report(s) and their previous local snapshots from this device? This cannot be undone in the app. Saved reports, exports and external backups are kept.")},confirmButton={TextButton(onClick={state.clearTrash(request);trashToClear=null}) {Text("Permanently Remove ${request.size} Deleted Report(s)")}},dismissButton={TextButton(onClick={trashToClear=null}) {Text("Cancel")}})}
        reportToDelete?.let {request ->AlertDialog(onDismissRequest={reportToDelete=null},title={Text("Delete report?")},text={Text("Move ${request.title} to Recently Deleted? You can restore it from Saves for 14 days. Exported files are kept.")},confirmButton={TextButton(onClick={state.deleteReport(request);reportToDelete=null}) {Text("Delete Report")}},dismissButton={TextButton(onClick={reportToDelete=null}) {Text("Cancel")}})}
        if(documentPicker) AlertDialog(onDismissRequest={documentPicker=false},title={Text("Open local report")},text={LazyColumn(Modifier.heightIn(max=400.dp)) {items(state.documents,key={it.slot}) {doc -> TextButton(onClick={state.select(doc.slot);documentPicker=false}) {Text("${doc.title} · r${doc.revision}")} }}},confirmButton={TextButton(onClick={documentPicker=false}) {Text("Done")}})
        state.pending?.let {incoming ->
            val preview=runCatching {Exchange.preview(state.report,incoming)}
            AlertDialog(onDismissRequest={state.pending=null},title={Text("Import preview")},text={Column(Modifier.heightIn(max=500.dp).verticalScroll(rememberScrollState()),verticalArrangement=Arrangement.spacedBy(8.dp)) {
                Text(incoming.report.values["title"] ?: "Untitled",fontWeight=FontWeight.Bold);Text("Revision ${incoming.report.revision} · ${incoming.report.active.size} takes · ${incoming.manifest.device}")
                Text("Verified schema, CRCs, SHA-256 and report identity.")
                preview.onSuccess {p ->Text("${p.additions.size} additions · ${p.conflicts.size} conflicts${if(p.duplicate) " · Already imported" else ""}");p.conflicts.forEach {Text(it)}}.onFailure {Text(it.message.orEmpty())}
                TextButton(onClick={state.change("Merged independent additions") {Exchange.merge(it,incoming,host.label)};state.pending=null},enabled=preview.isSuccess && preview.getOrNull()?.conflicts?.isEmpty()==true && preview.getOrNull()?.duplicate==false) {Text("Merge independent additions")}
                Button(onClick={state.open(incoming.report);state.pending=null}) {Text("Open as separate editable report")}
                Text("Opening separately preserves the current local document. Omissions never mean deletion.",style=MaterialTheme.typography.bodySmall)
            }},confirmButton={TextButton(onClick={state.pending=null}) {Text("Cancel")}})
        }
        notices?.let {text ->AlertDialog(onDismissRequest={notices=null},title={Text("Open-source notices")},text={LazyColumn(Modifier.heightIn(max=550.dp)) {items(text.split("\n\n")) {paragraph ->Text(paragraph+"\n",style=MaterialTheme.typography.bodySmall)}}},confirmButton={TextButton(onClick={notices=null}) {Text("Done")}})}
        state.error?.let {message ->AlertDialog(onDismissRequest={state.error=null},title={Text("Shot Reporter")},text={Text(message)},confirmButton={TextButton(onClick={state.error=null}) {Text("OK")}}) }
    }
}

@Composable private fun WorkspaceBrand(host:PlatformGateway) {
    Row(Modifier.fillMaxWidth().padding(vertical=16.dp,horizontal=8.dp),verticalAlignment=Alignment.CenterVertically) {
        Image(host.brand,null,Modifier.size(44.dp,66.dp));Spacer(Modifier.width(12.dp))
        Column {
            Text("SHOT\nREPORTER",fontSize=18.sp,fontWeight=FontWeight.Bold,letterSpacing=0.6.sp)
            Text("A Squid Productions™ Software",fontSize=9.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
@Composable private fun WorkspaceLabel(destination:String) {
    val color=LocalContentColor.current
    Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(12.dp)) {
        Canvas(Modifier.size(18.dp)) {
            val data=when(destination) {
                "Today" -> "M3 3H10V10H3ZM14 3H21V10H14ZM3 14H10V21H3ZM14 14H21V21H14Z"
                "Log" -> "M3 3H21V21H3ZM8 8H17M8 12H17M8 16H17"
                "Review" -> "M9 5H21M9 12H21M9 19H21M2 4L4 6L7 2M2 11L4 13L7 9M2 18L4 20L7 16"
                "Saves" -> "M3 14L6 4H18L21 14V20H3ZM3 14H21M16 17H18"
                else -> "M9 2H15L16 6L20 7L22 12L20 17L16 18L15 22H9L8 18L4 17L2 12L4 7L8 6ZM9 12A3 3 0 1 0 15 12A3 3 0 1 0 9 12"
            }
            scale(size.width/24f,size.height/24f,pivot=androidx.compose.ui.geometry.Offset.Zero) {
                drawPath(PathParser().parsePathString(data).toPath(),color,style=Stroke(width=1.6f))
            }
        }
        Text(destination)
    }
}

@Composable private fun Section(title:String,content:@Composable ColumnScope.()->Unit) {
    Card(Modifier.fillMaxWidth(),shape=RoundedCornerShape(12.dp),colors=CardDefaults.cardColors(containerColor=MaterialTheme.colorScheme.surface)) {Column(Modifier.padding(16.dp),verticalArrangement=Arrangement.spacedBy(10.dp)) {Text(title,style=MaterialTheme.typography.titleMedium,fontWeight=FontWeight.Bold);content()}}
}
@Composable private fun Editor(label:String,value:String,change:(String)->Unit) {
    val notes=label.contains("notes",true)||label.contains("remarks",true)||label.contains("intent",true)
    OutlinedTextField(value,change,label={Text(label)},modifier=Modifier.fillMaxWidth(),singleLine=!notes,minLines=if(notes) 2 else 1,maxLines=if(notes) 8 else 1)
}
@Composable private fun Fields(fields:List<Field>,values:Map<String,String>,change:(String,String)->Unit) {fields.forEach {f ->Editor(f.title,values[f.id].orEmpty()) {change(f.id,it)}}}
@Composable private fun Check(label:String,value:Boolean,change:(Boolean)->Unit) {Row(verticalAlignment=Alignment.CenterVertically) {Checkbox(value,change);Text(label,Modifier.clickable {change(!value)}.padding(4.dp))}}
@Composable private fun Choice(label:String,value:String,options:List<String>,change:(String)->Unit) {
    var expanded by remember {mutableStateOf(false)}
    Column {Text(label,style=MaterialTheme.typography.labelMedium);Box {OutlinedButton(onClick={expanded=true}) {Text(value)};DropdownMenu(expanded,{expanded=false}) {options.forEach {option ->DropdownMenuItem(text={Text(option)},onClick={change(option);expanded=false})}}}}
}
@Composable private fun LogScreen(state:AppState,detail:String,changeDetail:(String)->Unit) {
    var showSettings by remember(state.slot) {mutableStateOf(true)}
    var scene by remember(state.slot) {mutableStateOf("")};var picking by remember {mutableStateOf(false)};var search by remember {mutableStateOf("")};var circles by remember {mutableStateOf(false)}
    Section("Camera ${state.report.defaults["camera"].orEmpty()}") {
        Editor("Scene for next take",scene) {scene=it}
        Button(onClick={state.next(scene);if(state.selected!=null) showSettings=false},enabled=scene.isNotBlank()&&!state.blocked,modifier=Modifier.fillMaxWidth()) {Text("Next take")}
        Row {TextButton(onClick={scene="";state.selected=null;showSettings=true}) {Text("New setup")};TextButton(onClick={state.change("Reload: fresh load identity") {it.copy(defaults=it.defaults+mapOf("load" to identity(),"mag" to ""))}}) {Text("Reload")}}
        Text("Next take uses the camera and recording settings in this log. Reload creates a fresh load ID; enter the new SSD / mag here before logging.",style=MaterialTheme.typography.bodySmall)
        OutlinedButton(onClick={picking=true}) {Text(state.report.entries.firstOrNull {it.id==state.selected && !it.deleted}?.let {"${it.values["scene"]} / ${it.values["take"]} · ${it.values["camera"]}"} ?: "Choose take")}
    }
    Section("Camera & recording · next take") {
        Text("Settings carry forward until you edit them or return to app defaults. Earlier takes keep their recorded values.",style=MaterialTheme.typography.bodySmall)
        TextButton(onClick={state.change("Returned next-take settings to app defaults") {it.returnToDefaults()}},enabled=!state.blocked) {Text("Return to defaults")}
        TextButton(onClick={showSettings=!showSettings}) {Text(if(showSettings) "Hide recording details" else "Edit recording details")}
        if(showSettings) Fields(Schema.settings,state.report.defaults) {k,v ->state.change("Changed settings for next takes") {it.setRecordingSetting(k,v)}}
    }
    val entry=state.report.entries.firstOrNull {it.id==state.selected && !it.deleted}
    if(entry!=null) Section("Scene ${entry.values["scene"]} · Take ${entry.values["take"]}") {
        Choice("Detail",detail,listOf("Quick","Standard","Full"),changeDetail)
        Schema.flags.chunked(2).forEach {pair ->Row {pair.forEach {flag ->FilterChip(selected=flag in entry.flags,onClick={state.entry(entry.id,"Changed take flag") {it.copy(flags=(if(flag in it.flags) it.flags-flag else it.flags+flag).sorted(),reviewed=false)}},label={Text(flag)},modifier=Modifier.padding(end=8.dp))}} }
        val takeFields=if(detail=="Quick") Schema.take.take(3) else Schema.take
        Fields(takeFields,entry.values) {k,v ->state.entry(entry.id,"Edited take field") {it.copy(values=it.values+(k to v),reviewed=false)}}
        Text("Recorded settings · changes also carry forward",style=MaterialTheme.typography.titleSmall)
        val settings=if(detail=="Full") Schema.settings else Schema.settings.filter {it.id in listOf("camera","roll","iso","temperature","lens","stop")}
        Fields(settings,entry.values) {k,v ->state.change("Edited take settings and carried forward") {it.setRecordingSetting(k,v,entry.id)}}
        Check("Reviewed by me",entry.reviewed) {on ->state.entry(entry.id,"Changed self-review") {it.copy(reviewed=on)}}
        TextButton(onClick={state.entry(entry.id,"Removed take (recoverable)") {it.copy(deleted=true)};state.selected=null}) {Text("Remove take (recoverable)")}
        Text(state.status,style=MaterialTheme.typography.labelSmall)
    }
    if(picking) AlertDialog(onDismissRequest={picking=false},title={Text("Choose take")},text={Column {Editor("Search takes",search) {search=it};Check("Circled only",circles) {circles=it};LazyColumn(Modifier.heightIn(max=400.dp)) {items(state.report.active.asReversed().filter {(!circles||"Circle" in it.flags) && (search.isBlank()||it.values.values.any {v ->v.contains(search,true)})},key={it.id}) {e ->TextButton(onClick={state.selected=e.id;picking=false}) {Text("${e.values["scene"]} / ${e.values["take"]} · ${e.values["camera"]}${if("Circle" in e.flags) " · Circle" else ""}")} }}}},confirmButton={TextButton(onClick={picking=false}) {Text("Done")}})
}
@Composable private fun ReviewScreen(state:AppState) {
    Section("Complete report review") {
        Text("${state.report.active.size} takes · ${state.report.missing.size} outstanding requirements",fontWeight=FontWeight.Bold)
        if(state.report.missing.isEmpty()) Text("Ready for Submission · self-reviewed local report")
        else state.report.missing.forEach {Text("• $it")}
        Text("Self-review is not an instructor signature or evidence of delivery.",style=MaterialTheme.typography.bodySmall)
    }
    val deleted=state.report.entries.filter {it.deleted}
    if(deleted.isNotEmpty()) Section("Recoverable removed takes") {deleted.forEach {e ->TextButton(onClick={state.entry(e.id,"Restored removed take") {it.copy(deleted=false)}}) {Text("Restore ${e.values["scene"]} / ${e.values["take"]}")}}}
    Section("Recent history · last 20 changes") {state.report.history.takeLast(20).asReversed().forEach {Text("${it.summary} · ${it.device}",style=MaterialTheme.typography.bodySmall)}}
}
