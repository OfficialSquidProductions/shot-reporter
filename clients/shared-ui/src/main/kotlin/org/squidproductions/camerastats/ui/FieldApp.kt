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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import org.squidproductions.camerastats.core.*

interface PlatformGateway {
    val label:String
    val releaseLabel:String get()="FIELD ALPHA 0.1"
    val brand:ImageBitmap
    fun demo():Report
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
    var selected by mutableStateOf<String?>(null)
    var error by mutableStateOf<String?>(null)
    var status by mutableStateOf("Create a local report to begin");private set
    var blocked by mutableStateOf(repository==null);private set
    var pending by mutableStateOf<Exchange.Package?>(null)
    var lastExport by mutableStateOf<String?>(null);private set
    private var fingerprint:String?=null
    init {
        try {repository?.active()?.let { adopt(repository.select(it)) };refresh()}
        catch(e:Exception) {blocked=true;error="Existing reports could not be read. Their bytes were preserved. ${e.message}"}
    }
    private fun adopt(loaded:Loaded) {slot=loaded.slot;report=loaded.report;fingerprint=loaded.fingerprint;status="Saved on this device";blocked=false;selected=report.active.firstOrNull { "Circle" in it.flags }?.id ?: report.active.lastOrNull()?.id}
    private fun refresh() {documents=repository?.list().orEmpty()}
    private fun rememberDocument() {documents=(documents.filterNot {it.slot==slot}+Document(slot,report.values["title"] ?: "Untitled",report.revision)).sortedWith(compareBy({it.title},{it.slot}))}
    fun fail(e:Exception) {error=e.message ?: "This operation could not be completed; existing report preserved."}
    fun attempt(action:()->Unit) {try {action()} catch(e:Exception) {fail(e)}}
    fun change(summary:String,action:(Report)->Report) {
        if(blocked) {error="Local recovery is required before changes can be saved.";return}
        try {
            val proposed=action(report);val next=if(proposed.revision==report.revision) proposed.record(summary,platform.label) else proposed
            val hash=repository!!.save(slot,next,platform.label,fingerprint)
            report=next;fingerprint=hash;status="Saved on this device";rememberDocument()
        } catch(e:Exception) {error="Save failed; this change was not accepted. ${e.message.orEmpty()}"}
    }
    fun open(incoming:Report) = attempt {
        val newSlot=identity();val hash=repository!!.save(newSlot,incoming,platform.label,null)
        adopt(Loaded(newSlot,incoming,hash));rememberDocument()
    }
    fun demo()=attempt {open(platform.demo().separateDemo())}
    fun select(id:String)=attempt {adopt(repository!!.select(id))}
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
    var documentPicker by remember {mutableStateOf(false)};var script by remember {mutableStateOf<String?>(null)}
    var notices by remember {mutableStateOf<String?>(null)}
    MaterialTheme(colorScheme=palette) {
        Surface(Modifier.fillMaxSize(),color=palette.background) {
            Column(Modifier.fillMaxSize().safeDrawingPadding()) {
                Row(Modifier.fillMaxWidth().padding(16.dp),verticalAlignment=Alignment.CenterVertically) {
                    Image(host.brand,null,Modifier.size(38.dp,48.dp));Spacer(Modifier.width(12.dp))
                    Column {Text("Shot Reporter",fontSize=23.sp,fontWeight=FontWeight.Black);Text("A Squid Productions Software",style=MaterialTheme.typography.labelMedium)}
                }
                Row(Modifier.fillMaxWidth().padding(horizontal=16.dp),verticalAlignment=Alignment.CenterVertically) {Text(state.report.values["title"] ?: "New production",Modifier.weight(1f),fontWeight=FontWeight.Bold,maxLines=1);Text("r${state.report.revision}",style=MaterialTheme.typography.labelMedium)}
                Row(Modifier.fillMaxWidth().padding(8.dp),horizontalArrangement=Arrangement.SpaceEvenly) {
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
                                    Button(onClick={state.demo()},enabled=!state.blocked,modifier=Modifier.fillMaxWidth().heightIn(min=48.dp)) {Text("Open The Last Light demo")}
                                    TextButton(onClick={state.open(Report())},enabled=!state.blocked) {Text("New blank report")}
                                    Text("Demo data is fictional.",style=MaterialTheme.typography.bodySmall)
                                    state.report.values["demoScript"]?.let {v -> TextButton(onClick={script=v}) {Text("Read the demo script")} }
                                    state.report.values["demoShotPlan"]?.let {v -> TextButton(onClick={script=v}) {Text("Read the 16-shot plan")} }
                                }
                                Section("Workspace preferences") {
                                    Choice("Production profile",state.report.profile,Schema.profiles) {v -> state.change("Changed profile; all values retained") {it.copy(profile=v)}}
                                    Choice("Detail",detail,listOf("Quick","Standard","Full")) {v -> detail=v;host.preference("detail",v,true)}
                                    Choice("Appearance",theme,listOf("System","Light","Dark")) {v -> theme=v;host.preference("theme",v,true)}
                                    Schema.positions.forEach {position -> Check(position,position in state.report.positions) {on -> state.change("Changed responsibility view") {r ->r.copy(positions=if(on) (r.positions+position).distinct() else r.positions-position)}} }
                                    Text("Positions describe responsibilities. Every report group remains in Review.",style=MaterialTheme.typography.bodySmall)
                                    TextButton(onClick={state.attempt {notices=host.notices()}}) {Text("Open-source notices")}
                                }
                                Section("Project / crew · complete report") {Fields(Schema.project,state.report.values) {k,v ->state.change("Edited project field") {it.copy(values=it.values+(k to v))}} }
                                Section("Defaults for future takes") {Text("Earlier takes keep their recorded settings.",style=MaterialTheme.typography.bodySmall);Fields(Schema.settings,state.report.defaults) {k,v ->state.change("Changed defaults for future takes") {it.copy(defaults=it.defaults+(k to v))}} }
                            }
                            "Log" -> LogScreen(state,detail,{v ->detail=v;host.preference("detail",v,true)})
                            "Review" -> ReviewScreen(state)
                            "Saves" -> {
                                Section("Report handoff") {
                                    Text(state.status);state.lastExport?.let {Text(it,style=MaterialTheme.typography.bodySmall)}
                                    Button(onClick={state.export("camreport")}) {Text("Save As .camreport")}
                                    OutlinedButton(onClick={state.importReport()}) {Text("Import Save…")}
                                    Text("Schema 1 alpha: complete reports only. Import previews additions and competing edits; save is not proof of receipt.",style=MaterialTheme.typography.bodySmall)
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
                        Text("${host.releaseLabel} · ${host.label} · Saved on your device",style=MaterialTheme.typography.labelSmall,modifier=Modifier.padding(vertical=12.dp))
                    }
                }
            }
        }
        if(documentPicker) AlertDialog(onDismissRequest={documentPicker=false},title={Text("Open local report")},text={LazyColumn(Modifier.heightIn(max=400.dp)) {items(state.documents,key={it.slot}) {doc -> TextButton(onClick={state.select(doc.slot);documentPicker=false}) {Text("${doc.title} · r${doc.revision}")} }}},confirmButton={TextButton(onClick={documentPicker=false}) {Text("Done")}})
        script?.let {text -> AlertDialog(onDismissRequest={script=null},title={Text("The Last Light · Demo")},text={Text(text,Modifier.heightIn(max=550.dp).verticalScroll(rememberScrollState()))},confirmButton={TextButton(onClick={script=null}) {Text("Done")}}) }
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
    var scene by remember {mutableStateOf("")};var picking by remember {mutableStateOf(false)};var search by remember {mutableStateOf("")};var circles by remember {mutableStateOf(false)}
    Section("Camera ${state.report.defaults["camera"].orEmpty()} · ${state.report.defaults["roll"].orEmpty()}") {
        Editor("Scene for next take",scene) {scene=it}
        Button(onClick={state.next(scene)},enabled=scene.isNotBlank()&&!state.blocked,modifier=Modifier.fillMaxWidth()) {Text("Next take")}
        Row {TextButton(onClick={scene="";state.selected=null}) {Text("New setup")};TextButton(onClick={state.change("Reload: fresh load identity") {it.copy(defaults=it.defaults+("load" to identity()))}}) {Text("Reload")}}
        Text("Next take inherits current defaults. Reload creates a fresh load ID; enter the new roll and mag in Today before logging.",style=MaterialTheme.typography.bodySmall)
        OutlinedButton(onClick={picking=true}) {Text(state.report.entries.firstOrNull {it.id==state.selected && !it.deleted}?.let {"${it.values["scene"]} / ${it.values["take"]} · ${it.values["camera"]} ${it.values["roll"]}"} ?: "Choose take")}
    }
    val entry=state.report.entries.firstOrNull {it.id==state.selected && !it.deleted}
    if(entry!=null) Section("Scene ${entry.values["scene"]} · Take ${entry.values["take"]}") {
        Choice("Detail",detail,listOf("Quick","Standard","Full"),changeDetail)
        Schema.flags.chunked(2).forEach {pair ->Row {pair.forEach {flag ->FilterChip(selected=flag in entry.flags,onClick={state.entry(entry.id,"Changed take flag") {it.copy(flags=(if(flag in it.flags) it.flags-flag else it.flags+flag).sorted(),reviewed=false)}},label={Text(flag)},modifier=Modifier.padding(end=8.dp))}} }
        val takeFields=if(detail=="Quick") Schema.take.take(3) else Schema.take
        Fields(takeFields,entry.values) {k,v ->state.entry(entry.id,"Edited take field") {it.copy(values=it.values+(k to v),reviewed=false)}}
        Text("Recorded settings · edit this take only",style=MaterialTheme.typography.titleSmall)
        val settings=if(detail=="Full") Schema.settings else Schema.settings.filter {it.id in listOf("camera","roll","iso","temperature","lens","stop")}
        Fields(settings,entry.values) {k,v ->state.entry(entry.id,"Edited take settings") {it.copy(values=it.values+(k to v),reviewed=false)}}
        Check("Reviewed by me",entry.reviewed) {on ->state.entry(entry.id,"Changed self-review") {it.copy(reviewed=on)}}
        TextButton(onClick={state.entry(entry.id,"Removed take (recoverable)") {it.copy(deleted=true)};state.selected=null}) {Text("Remove take (recoverable)")}
        Text(state.status,style=MaterialTheme.typography.labelSmall)
    }
    if(picking) AlertDialog(onDismissRequest={picking=false},title={Text("Choose take")},text={Column {Editor("Search takes",search) {search=it};Check("Circled only",circles) {circles=it};LazyColumn(Modifier.heightIn(max=400.dp)) {items(state.report.active.asReversed().filter {(!circles||"Circle" in it.flags) && (search.isBlank()||it.values.values.any {v ->v.contains(search,true)})},key={it.id}) {e ->TextButton(onClick={state.selected=e.id;picking=false}) {Text("${e.values["scene"]} / ${e.values["take"]} · ${e.values["camera"]} ${e.values["roll"]}${if("Circle" in e.flags) " · Circle" else ""}")} }}}},confirmButton={TextButton(onClick={picking=false}) {Text("Done")}})
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
