import SwiftUI
import UniformTypeIdentifiers
import CameraStatsCore
import PDFKit

extension UTType { static let camreport = UTType(exportedAs:"org.squidproductions.camreport",conformingTo:.data) }
struct ExportFile: FileDocument {
    static var readableContentTypes:[UTType] { [.data,.camreport,.pdf,.commaSeparatedText,.html] }
    var data: Data
    init(data:Data) { self.data = data }
    init(configuration:ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func makeFileWrapper() -> FileWrapper { FileWrapper(regularFileWithContents:data) }
    func fileWrapper(configuration:WriteConfiguration) throws -> FileWrapper { makeFileWrapper() }
}
@main struct CameraStatsApp: App {
    @State private var diagnostics = DiagnosticsCenter.shared
    @State private var store = Store(root:AppProfile.root,preferences:AppProfile.preferences,preferencesDomain:AppProfile.preferencesDomain)
    #if !os(macOS)
    @UIApplicationDelegateAdaptor(DiagnosticsAppDelegate.self) private var diagnosticsDelegate
    #endif
    #if os(macOS)
    @State private var updates = DesktopUpdates()
    @NSApplicationDelegateAdaptor(DesktopUpdateAppDelegate.self) private var appDelegate
    #endif
    var body: some Scene {
        WindowGroup {
            Workspace(store:store).defaultAppStorage(AppProfile.preferences).frame(minWidth:320,minHeight:480)
            #if os(macOS)
                .task {updates.configure(store:store);appDelegate.updates=updates;updates.start()}
            #endif
        }
        #if os(macOS)
        .commands {DesktopUpdateCommands(updates:updates);SupportCommands()}
        #endif
    }
}
struct Brand: View {
    var body: some View {
        HStack(alignment:.center,spacing:12) {
            Image("SPMark").resizable().scaledToFit().frame(width:44,height:66).accessibilityHidden(true)
            VStack(alignment:.leading,spacing:5) {
                Text("SHOT\nREPORTER").font(.custom("Futura-Medium",size:18)).tracking(0.6).fixedSize(horizontal:false,vertical:true)
                Text("A Squid Productions™ Software").font(.system(size:9)).foregroundStyle(.secondary)
            }
        }.padding(.vertical,16).accessibilityElement(children:.combine)
    }
}
enum Destination: String, CaseIterable, Identifiable {
    case today = "Today", log = "Log", review = "Review", saves = "Saves", settings = "Settings"
    var id:String { rawValue }
    var icon:String {
        switch self {
        case .today:return "square.grid.2x2"
        case .log:return "list.bullet.rectangle"
        case .review:return "checklist"
        case .saves:return "externaldrive"
        case .settings:return "gearshape"
        }
    }
}
struct Workspace: View {
    @Bindable var store: Store
    @State private var destination: Destination? = .today
    @State private var tab: Destination = .today
    @AppStorage("theme") var theme = "System"
    @State private var importing = false
    @State private var pending: ImportReview?
    @State private var completeImport:ProjectArchive.Prepared?
    @State private var applyImportedPreferences=true
    @State private var addingFiles=false
    @State private var fileCategory="attachment"
    @State private var archiveExport:ArchiveExportItem?
    @State private var exportFile: ExportFile?
    @State private var exporting = false
    @State private var exportType: UTType = .camreport
    @State private var exportName = "Shot-Reporter.camreport"
    @State private var selected: String?
    @State private var search = ""
    @State private var circleOnly = false
    @AppStorage("detail") private var detail = "Standard"
    @State private var scene = ""
    @State private var showRecordingSettings = true
    @State private var pdfPreview: PDFReview?
    @State private var showingSupport=false
    @State private var reportToDelete: Store.DeletionRequest?
    @State private var trashToClear:Store.TrashRequest?
    @State private var nextDay:Store.NewDayRequest?
    @Environment(\.scenePhase) private var scenePhase
    private var diagnostics:DiagnosticsCenter {DiagnosticsCenter.shared}
    var scheme:ColorScheme? { theme == "Dark" ? .dark : theme == "Light" ? .light : nil }
    var body: some View {
        Group {
            #if os(macOS)
            NavigationSplitView {
                VStack(spacing:0) {
                    Brand().padding(.horizontal,18).frame(maxWidth:.infinity,alignment:.leading)
                    status.padding(.horizontal,18).padding(.bottom,18).frame(maxWidth:.infinity,alignment:.leading)
                    Divider()
                    ScrollView {
                        VStack(spacing:4) {
                            ForEach(Destination.allCases.filter { $0 != .settings }) { d in
                                Button { destination = d } label: {
                                    Label(d.rawValue,systemImage:d.icon).frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,12).padding(.vertical,10).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                    .foregroundStyle(destination == d ? Color.white : Color.primary)
                                    .background(destination == d ? Color("SelectionGreen") : Color.clear,in:RoundedRectangle(cornerRadius:6))
                                    .accessibilityAddTraits(destination == d ? .isSelected : [])
                            }
                        }.padding(10)
                    }
                    Divider()
                    Button { destination = .settings } label: {
                        Label("Settings",systemImage:"gearshape").frame(maxWidth:.infinity,alignment:.leading).padding(16).contentShape(Rectangle())
                    }.buttonStyle(.plain).foregroundStyle(destination == .settings ? Color.white : Color.primary).background(destination == .settings ? Color("SelectionGreen"):Color.clear,in:RoundedRectangle(cornerRadius:6))
                }.background(Color("Paper"))
                .navigationSplitViewColumnWidth(min:230,ideal:260,max:320)
            } detail: { content(destination ?? .today) }
            #else
            TabView(selection:$tab) {
                ForEach(Destination.allCases) { d in NavigationStack { content(d) }.tabItem { Label(d.rawValue,systemImage:d.icon) }.tag(d) }
            }
            #endif
        }.tint(Color("AccentColor")).preferredColorScheme(scheme).background(Color("Canvas"))
        .onOpenURL { readImport($0) }
        .onChange(of:scenePhase) {_,phase in if phase == .active {store.cleanupExpiredTrash()}}
        .onReceive(Timer.publish(every:3600,on:.main,in:.common).autoconnect()) {_ in store.cleanupExpiredTrash()}
        .onChange(of:selected) { _,value in showRecordingSettings = value == nil }
        .onChange(of:store.slot) { _,_ in selected = nil; scene = ""; showRecordingSettings = true }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for:.reportBugRequested)) {_ in showingSupport=true}
        #endif
        .fileImporter(isPresented:$importing,allowedContentTypes:[.camreport],allowsMultipleSelection:false) { result in
            do { if let url = try result.get().first { readImport(url) } } catch { store.error = error.localizedDescription }
        }
        .fileExporter(isPresented:$exporting,document:exportFile,contentType:exportType,defaultFilename:exportName) { result in switch result { case .failure(let e): store.error = e.localizedDescription; case .success: AppProfile.preferences.set(store.report.revision,forKey:"exported-"+store.slot) } }
        .sheet(isPresented:$showingSupport) {BugReportView(diagnostics:diagnostics)}
        .sheet(item:$pending) { item in importSheet(item) }
        .onChange(of:pending != nil || completeImport != nil) {_,value in store.pendingImport=value}
        .sheet(item:$completeImport,onDismiss:{store.pendingImport=false}) {item in completeImportSheet(item)}
        #if !os(macOS)
        .sheet(item:$archiveExport) {item in ArchiveExportPicker(url:item.url) {success in finishArchiveExport(item,success:success);archiveExport=nil}}
        #endif
        .fileImporter(isPresented:$addingFiles,allowedContentTypes:[.item],allowsMultipleSelection:true) {result in
            do {let urls=try result.get();let kind=fileCategory;Task {await store.addProjectFiles(urls,kind:kind)}} catch {store.error=error.localizedDescription}
        }
        .overlay {if store.archiveBusy {VStack(spacing:12) {ProgressView();Text(store.archiveStatus ?? "Verifying files…").font(.callout);Text("Keep Shot Reporter open until this finishes.").font(.caption)}.padding(24).background(.regularMaterial,in:RoundedRectangle(cornerRadius:12)).accessibilityElement(children:.combine)}}
        .confirmationDialog("Delete report?",isPresented:Binding(get:{reportToDelete != nil},set:{if !$0 {reportToDelete=nil}}),titleVisibility:.visible,presenting:reportToDelete) { request in
            Button("Delete Report",role:.destructive) {store.deleteReport(request);reportToDelete=nil}
            Button("Cancel",role:.cancel) {reportToDelete=nil}
        } message: { request in Text("Move \(request.title) to Recently Deleted? You can restore it from Saves. Deleted reports are automatically removed after 14 days. Exported files are kept.") }
        .confirmationDialog("Permanently clear trash?",isPresented:Binding(get:{trashToClear != nil},set:{if !$0 {trashToClear=nil}}),titleVisibility:.visible,presenting:trashToClear) {request in
            Button("Permanently Remove \(request.items.count) Deleted Report(s)",role:.destructive) {store.clearTrash(request);trashToClear=nil}
            Button("Cancel",role:.cancel) {trashToClear=nil}
        } message: {request in Text("Remove \(request.items.count) deleted report(s) and their previous local snapshots from this device? This cannot be undone in the app. Saved reports are kept. Previously exported files, legacy recovery files and external backups are not erased.")}
        .confirmationDialog("Start New Day?",isPresented:Binding(get:{nextDay != nil},set:{if !$0 {nextDay=nil}}),titleVisibility:.visible,presenting:nextDay) {request in
            Button("Create \(request.next.displayTitle)") {Task {await store.startNewDay(request)};nextDay=nil}
            Button("Cancel",role:.cancel) {nextDay=nil}
        } message:{request in Text("Create \(request.next.displayTitle) for \(request.next.values["date",default:""])? Production, crew, general camera settings and reference attachments are copied. Takes, prior-day media and recoveries stay with \(request.sourceName), which is kept unchanged.")}
        .sheet(item:$pdfPreview) { item in PDFReviewScreen(item:item) }
        .alert("Shot Reporter",isPresented:Binding(get:{store.error != nil},set:{if !$0 { store.error = nil }})) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
    }
    func readImport(_ url:URL) {
        guard !store.archiveBusy,!store.pendingImport else {store.error="Finish the current import or file operation first.";return}
        Task {
            do {
                let access=url.startAccessingSecurityScopedResource();defer{if access {url.stopAccessingSecurityScopedResource()}}
                let h=try FileHandle(forReadingFrom:url);let prefix=try h.read(upToCount:6) ?? Data();try h.close()
                if prefix.count==6,prefix[4]==45,prefix[5]==0 {completeImport=try await store.prepareProjectImport(url);applyImportedPreferences=true}
                else {
                    let attrs=try FileManager.default.attributesOfItem(atPath:url.path)
                    guard ((attrs[.size] as? NSNumber)?.intValue ?? Int.max)<=Exchange.limit else {throw ReportError.invalid("Legacy report exceeds 32 MiB. Complete archives require the new archive format.")}
                    pending=ImportReview(package:try Exchange.read(Data(contentsOf:url)))
                }
            } catch {store.pendingImport=false;store.error=error.localizedDescription}
        }
    }
    @ViewBuilder func content(_ d: Destination) -> some View {
        VStack(spacing:0) {
            #if !os(macOS)
            Brand().padding(.horizontal).frame(maxWidth:.infinity,alignment:.leading)
            #endif
            HStack { Text(store.report.displayTitle).font(.headline).lineLimit(1); Spacer(); Text("r\(store.report.revision)").monospacedDigit().foregroundStyle(.secondary) }.padding(.horizontal).padding(.vertical,8)
            Divider()
            switch d {
            case .today: today
            case .log: log
            case .review: review
            case .saves: saves
            case .settings: settings
            }
        }.disabled(store.archiveBusy).navigationTitle(d.rawValue).background(Color("Canvas"))
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
    var status: some View { Label(store.blocked ? "Recovery required" : store.saved == nil ? "Create a local report to begin" : "Saved on this device",systemImage:store.blocked ? "exclamationmark.triangle" : "checkmark.circle").font(.caption).foregroundStyle(.secondary) }
    func projectBinding(_ key:String) -> Binding<String> { Binding(get:{store.report.values[key,default:""]},set:{v in store.change { $0.values[key] = v }}) }
    func defaultBinding(_ key:String) -> Binding<String> { Binding(get:{store.report.defaults[key,default:""]},set:{v in store.change("Changed settings for next takes") { $0.setRecordingSetting(key,value:v) }}) }
    func entryBinding(_ id:String,_ key:String) -> Binding<String> { Binding(get:{store.report.entries.first{$0.id == id}?.values[key] ?? ""},set:{v in store.change { r in if let i = r.entries.firstIndex(where:{$0.id == id}) { if Schema.settings.contains(where: { $0.id == key }) { r.setRecordingSetting(key,value:v,takeID:id) } else { r.entries[i].values[key] = v; r.entries[i].reviewed = false } } }}) }
    @ViewBuilder func field(_ f:Field,_ binding:Binding<String>) -> some View {
        if ["height","distance"].contains(f.id) {MeasurementField(title:f.title,raw:binding,unit:store.report.measurementUnit)} else { VStack(alignment:.leading,spacing:4) { Text(f.title).font(.caption).foregroundStyle(.secondary); TextField(f.title,text:binding,axis:f.id.lowercased().contains("notes") || f.id == "remarks" ? .vertical : .horizontal).textFieldStyle(.roundedBorder).accessibilityLabel(f.title) }.padding(.vertical,2) } }
    var today: some View {
        Form {
            Section("Local production") {
                status
                Picker("Open report",selection:Binding(get:{store.slot},set:{store.select($0)})) { Text(store.report.displayTitle).tag(store.slot); ForEach(store.documents.filter{$0.0 != store.slot},id:\.0) { doc in Text(doc.1).tag(doc.0) } }
                Text("Report name combines Production title and Shooting day below.").font(.caption).foregroundStyle(.secondary)
                Button { store.open(Report()); selected = nil } label: { Label("New blank report",systemImage:"plus").frame(maxWidth:.infinity,minHeight:32) }.buttonStyle(.borderedProminent)
            }
            Section("Production profile") {
                Picker("Production profile",selection:Binding(get:{store.report.profile},set:{v in store.change("Changed profile; all values retained"){$0.profile = v}})) { ForEach(Schema.profiles,id:\.self) { Text($0) } }
            }
            Section("Project / crew · complete report") { ForEach(store.report.projectFields) { f in field(f,projectBinding(f.id)) } }
            Section {
                Button("Start New Day…") {do {nextDay=try store.newDayRequest()} catch {store.error=error.localizedDescription}}
                    .buttonStyle(.borderedProminent).disabled(store.blocked || store.pendingImport || store.report.values["title",default:""].trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                Text("Keeps this day's report and starts a separate next-day report with the production and crew information. Review the new date and shooting day in Today.").font(.caption)
            }
        }.formStyle(.grouped).scrollContentBackground(.hidden).background(Color("Canvas"))
    }
    var settings: some View {
        Form {
            Section("Production mode") {
                HStack {ForEach(ProductionMode.allCases) {mode in SelectionButton(title:mode.title,selected:store.report.productionMode==mode) {store.change("Changed production mode; all values retained") {$0.productionMode=mode}}}}
                Text("Movie hides Season and Episode. TV shows them in Today and reports. Hidden values are kept for this report.").font(.caption)
            }
            Section("Measurements") {
                HStack {ForEach(MeasurementUnit.allCases) {unit in SelectionButton(title:unit.title,selected:store.report.measurementUnit==unit) {store.change("Changed measurement display units; original values retained") {$0.measurementUnit=unit}}}}
                Text("This report uses feet/inches by default. Recognized values are converted for display and PDF; stored measurements stay unchanged until edited. Older values without units are kept as entered.").font(.caption)
            }
            Section("Trash") {
                Text("Deleted reports are permanently removed after 14 days, when the app next opens or becomes active, and hourly while open. Restoring a report cancels its cleanup. Reports already in trash when this version first opens get a fresh 14 days.").font(.caption)
                Button("Clear Trash…",role:.destructive) {do {trashToClear=try store.trashRequest()} catch {store.error=error.localizedDescription}}
                    .disabled(store.deletedDocuments.isEmpty || store.blocked || store.pendingImport)
                Text("Clear Trash affects deleted reports on this device only. Exports, legacy recovery files and external backups are kept.").font(.caption)
                if let notice=store.trashNotice {Text(notice).font(.caption)}
            }
            Section("Appearance") {
                Picker("Appearance",selection:$theme) { ForEach(["System","Light","Dark"],id:\.self) { Text($0) } }
            }
            Section("Support") {
                Button("Report a Bug") {showingSupport=true}
                if diagnostics.hasPreviousTermination {Text(diagnostics.incidents.contains {$0.kind == .crash} ? "A crash from a previous launch was captured locally." : "The previous session ended unexpectedly; a crash is not confirmed."); Button("Review previous launch diagnostics") {showingSupport=true};Button("Dismiss previous diagnostics") {diagnostics.dismiss()}}
            }
            Section("About") {
                Text("Shot Reporter").font(.headline)
                Text("A Squid Productions™ Software").foregroundStyle(.secondary)
                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2")").font(.caption)
                Text("All camera, DP, data, and script / continuity responsibilities are always available.").font(.caption)
            }
        }.formStyle(.grouped).scrollContentBackground(.hidden).background(Color("Canvas"))
    }
    var recordingSettings: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Label("Camera & recording",systemImage:"camera").font(.headline)
                Spacer()
                Button("Return to defaults") { store.change("Returned next-take settings to app defaults") { $0.returnToDefaults() } }
                    .disabled(store.blocked)
            }
            Text("These settings carry forward to each new take until you edit them or return to app defaults. Earlier takes keep their recorded values.").font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("Camera, media, recording & lens details",isExpanded:$showRecordingSettings) {
                LazyVGrid(columns:[GridItem(.adaptive(minimum:240),alignment:.topLeading)],alignment:.leading,spacing:12) {
                    ForEach(Schema.settings) { f in field(f,defaultBinding(f.id)) }
                }.padding(.top,8)
            }
        }.padding(16).background(Color("Paper"),in:RoundedRectangle(cornerRadius:12))
    }
    var log: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                HStack { Label("Camera \(store.report.defaults["camera",default:"A"])",systemImage:"camera").font(.title2.bold()); Spacer() }
                TextField("Scene / setup (e.g. 12B)",text:$scene).textFieldStyle(.roundedBorder).font(.title2).accessibilityLabel("Scene for next take")
                HStack {
                    Button { store.change("Next take") { r in selected = r.next(scene:scene,device:store.device) } } label: { Label("Next take",systemImage:"plus").frame(maxWidth:.infinity,minHeight:36) }.buttonStyle(.borderedProminent).disabled(scene.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || store.blocked)
                    Button("New setup") { scene = ""; selected = nil }
                    Button("Reload") { store.change("New media load") { $0.defaults["load"] = UUID().uuidString; $0.defaults["mag"] = "" } }
                }
                Text("Next take uses the camera and recording settings in this log. Reload creates a fresh load ID; enter the new SSD / mag here before logging.").font(.caption).foregroundStyle(.secondary)
                recordingSettings
                Picker("Take",selection:$selected) { Text("Choose take").tag(String?.none); ForEach(store.report.active.reversed()) { e in Text("\(e.values["scene",default:"?"]) / \(e.values["take",default:"?"]) · \(e.values["camera",default:""])").tag(Optional(e.id)) } }
                if let id = selected, let e = store.report.entries.first(where:{$0.id == id && !$0.deleted}) { takeEditor(e) } else { ContentUnavailableView("Ready for the next slate",systemImage:"camera",description:Text("Enter the scene, then add a take. All logging works offline.")) }
            }.padding(20).frame(maxWidth:900,alignment:.leading).frame(maxWidth:.infinity)
        }
    }
    func takeEditor(_ e:Entry) -> some View {
        VStack(alignment:.leading,spacing:16) {
            HStack { Text("Scene \(e.values["scene",default:""]) · Take \(e.values["take",default:""])").font(.largeTitle.bold()); Spacer() }
            LazyVGrid(columns:[GridItem(.adaptive(minimum:130))],alignment:.leading) {
                ForEach(["Circle","MOS","Pickup","Tail slate","False roll","Technical issue"],id:\.self) { flag in
                    SelectionButton(title:flag,selected:store.report.entries.first{$0.id==e.id}?.flags.contains(flag)==true) {
                        store.change {r in if let i=r.entries.firstIndex(where:{$0.id==e.id}) {if r.entries[i].flags.contains(flag) {r.entries[i].flags.remove(flag)} else {r.entries[i].flags.insert(flag)};r.entries[i].reviewed=false}}
                    }
                }
            }
            HStack {ForEach(["Quick","Standard","Full"],id:\.self) {level in SelectionButton(title:level,selected:detail==level) {detail=level}}}
            ForEach(Schema.take.filter{!Schema.lighting.map(\.id).contains($0.id) && (detail != "Quick" || ["scene","take","remarks"].contains($0.id))}) { f in field(f,entryBinding(e.id,f.id)) }
            if detail != "Quick" { Divider(); Text("Recorded settings · changes also carry forward").font(.headline); ForEach(Schema.settings.filter{detail == "Full" || ["lens","stop","iso","temperature","camera","roll"].contains($0.id)}) { f in field(f,entryBinding(e.id,f.id)) } }
            VStack(alignment:.leading,spacing:8) {
                Text("Light meter at subject · optional").font(.headline)
                HStack {
                    TextField("Reading (e.g. 2.8 + 1/3)",text:Binding(get:{store.report.entries.first{$0.id==e.id}?.values["lightMeter"] ?? ""},set:{v in store.change {r in if let i=r.entries.firstIndex(where:{$0.id==e.id}) {r.entries[i].values["lightMeter"]=v;if r.entries[i].values["lightMeterUnit"]==nil {r.entries[i].values["lightMeterUnit"]="f-stop"};r.entries[i].reviewed=false}}})).textFieldStyle(.roundedBorder).accessibilityLabel("Light meter reading")
                    Picker("Meter unit (as read)",selection:Binding(get:{store.report.entries.first{$0.id==e.id}?.values["lightMeterUnit"] ?? "f-stop"},set:{entryBinding(e.id,"lightMeterUnit").wrappedValue=$0})) {ForEach(LightMeterUnit.allCases) {unit in Text(unit.title).tag(unit.rawValue)}}
                }
                TextField("Subject / context (e.g. face · incident · ISO 800 · 1/48 s)",text:entryBinding(e.id,"lightMeterContext")).textFieldStyle(.roundedBorder).accessibilityLabel("Light meter subject and context")
                Text("Enter the value and unit shown by your meter; unit selection labels the reading without converting it. For f-stop/EV, note ISO and shutter in context. Lens T-stop is separate. A new take starts with no meter reading.").font(.caption).foregroundStyle(.secondary)
            }.padding(12).background(Color("Paper"),in:RoundedRectangle(cornerRadius:8))
            if store.report.active.filter({$0.id != e.id && $0.values["scene"] == e.values["scene"] && $0.values["take"] == e.values["take"] && $0.values["camera"] == e.values["camera"]}).count > 0 { Label("Duplicate scene / take / camera label. Review before export.",systemImage:"exclamationmark.triangle") }
            Toggle("Reviewed by me",isOn:Binding(get:{store.report.entries.first{$0.id == e.id}?.reviewed == true},set:{v in store.change("Changed take review") { r in if let i = r.entries.firstIndex(where:{$0.id == e.id}) { r.entries[i].reviewed = v } }}))
            Button("Remove take (recoverable)",role:.destructive) { store.change("Marked take deleted") { r in if let i = r.entries.firstIndex(where:{$0.id == e.id}) {r.entries[i].deleted = true} }; selected = nil }
            status
        }
    }
    var review: some View {
        List {
            Section("Submission checklist · all views") {
                Text(store.report.missing.isEmpty ? "Ready for Submission" : "DRAFT · \(store.report.missing.count) requirements outstanding").font(.headline)
                Text("Complete project and crew fields in Today and recorded take fields in Log → Full. Enter N/A with a reason where the report permits it. Next-take settings do not fill earlier takes.").font(.caption)
                ForEach(Array(store.report.missing.enumerated()),id:\.offset) { _,m in Text(m).font(.caption) }
            }
            Section("Find takes") {
                TextField("Search scene, notes, camera",text:$search).textFieldStyle(.roundedBorder)
                Toggle("Circled takes only",isOn:$circleOnly)
                ForEach(store.report.active.filter{e in (!circleOnly || e.flags.contains("Circle")) && (search.isEmpty || (e.values.values.joined(separator:" ")+e.flags.joined(separator:" ")).localizedCaseInsensitiveContains(search))}) { e in
                    Button { selected = e.id; destination = .log; tab = .log } label: { VStack(alignment:.leading) { Text("\(e.values["scene",default:"?"]) / \(e.values["take",default:"?"]) · Camera \(e.values["camera",default:""])").font(.headline); Text(e.flags.sorted().joined(separator:" · ") + (e.reviewed ? " · Reviewed" : " · Review pending")).font(.caption); Text(e.values["remarks",default:""]).font(.caption).foregroundStyle(.secondary) } }
                }
            }
            Section("Recovery") { ForEach(store.report.entries.filter(\.deleted)) { e in Button("Restore \(e.values["scene",default:""]) / \(e.values["take",default:""])") { store.change("Restored deleted take") { r in if let i = r.entries.firstIndex(where:{$0.id == e.id}) {r.entries[i].deleted = false} } } } }
        }
    }
    var saves: some View {
        Form {
            Section("Saved reports") {
                if store.documents.isEmpty { Text("No saved reports. Create a blank report in Today.").foregroundStyle(.secondary) }
                ForEach(store.documents,id:\.0) { doc in
                    HStack {
                        Button {store.select(doc.0)} label:{Label(doc.1,systemImage:doc.0 == store.slot ? "checkmark.circle.fill" : "doc.text").frame(maxWidth:.infinity,alignment:.leading).padding(8).foregroundStyle(doc.0 == store.slot ? Color.white:Color.primary).background(doc.0 == store.slot ? Color("SelectionGreen"):Color.clear,in:RoundedRectangle(cornerRadius:6))}
                        Button(role:.destructive) {do {reportToDelete=try store.deletionRequest(for:doc.0)} catch {store.error=error.localizedDescription}} label:{Label("Delete Report",systemImage:"trash")}
                            .disabled(store.blocked || store.pendingImport)
                    }.buttonStyle(.borderless)
                }
            }
            if !store.deletedDocuments.isEmpty {
                Section("Recently Deleted") {
                    Text("Deleted reports can be restored for 14 days, then are permanently removed. Clear Trash in Settings removes them sooner.").font(.caption)
                    ForEach(store.deletedDocuments,id:\.0) {doc in
                        HStack {Text(doc.1);Spacer();Button("Restore Report") {store.restoreDeletedReport(doc.0)}.disabled(store.blocked || store.pendingImport)}.buttonStyle(.borderless)
                    }
                }
            }
            Section("Report handoff") {
                status; Text("Device: \(store.device) · report revision \(store.report.revision) · last file export \(store.lastExportedRevision.map{ "r\($0)" } ?? "none")").font(.caption)
                Button("Save As .camreport") {Task {if let url=await store.prepareProjectExport() {saveArchive(url)}}}
                Button("Export report data only (legacy compatibility)…") {export(.camreport,"camreport") {try Exchange.export(store.report,device:store.device)}}
                Button("Import Save…") { importing = true }
                Text("Save As .camreport bundles this complete open report, all files added below, app preferences, the previous local snapshot and known legacy recovery copies. Other saved reports are separate. Media filenames typed in takes do not grant access to files: add those files below before exporting. Both devices need this version or later. Legacy export contains report data only and is limited to 32 MiB. A saved file is not proof of receipt.").font(.caption)
                Button("Restore previous local snapshot as separate report") { Task {await store.restore()} }
            }
            Section("Files in this report") {
                Text("Files are copied into the report; original files stay where they are. Add every media file or reference document you need to take with you. Folders, aliases and symbolic links are not followed. Large media needs space for a local copy and the archive.").font(.caption)
                HStack {Button("Add Media…") {fileCategory="media";addingFiles=true};Button("Add Attachments…") {fileCategory="attachment";addingFiles=true}}
                Button("Add Recovery File…") {fileCategory="recovery";addingFiles=true}
                ForEach(store.projectState.resources) {resource in
                    VStack(alignment:.leading) {
                        Text(resource.name);Text("\(resource.kind.capitalized) · \(ByteCountFormatter.string(fromByteCount:Int64(resource.size),countStyle:.file))").font(.caption).foregroundStyle(.secondary)
                        if resource.kind=="recovery" {Button("Open recovery as separate report") {Task {await store.restoreProjectRecovery(resource)}}}
                        Button("Save file copy…") {Task {if let url=await store.prepareResourceExport(resource) {saveArchive(url,complete:false)}}}
                    }
                }
                if store.projectState.resources.isEmpty {Text("No media, attachments or added recovery files yet.").font(.caption)}
            }
            Section("Preview and export") {
                Button("Preview landscape Camera Report PDF") { do { pdfPreview = PDFReview(data:try Reports.pdf(store.report),revision:store.report.revision,filename:try store.report.exportName(extension:"pdf")) } catch { store.error = error.localizedDescription } }
                Button("Export CSV") { export(.commaSeparatedText,"csv") {Data(Reports.csv(store.report).utf8)} }
                Button("Export HTML report") { export(.html,"html") {Data(Reports.html(store.report).utf8)} }
                Text("PDF is a frozen report with continuation pages and a draft/ready label. CSV and HTML are generic exports; no NLE adapter has been certified.").font(.caption)
            }
            Section("History") { ForEach(Array(store.report.history.suffix(30).reversed().enumerated()),id:\.offset) { _,h in VStack(alignment:.leading) { Text(h.summary).font(.caption); Text("\(h.device) · \(h.date.formatted())").font(.caption2).foregroundStyle(.secondary) } } }
            Section("About") {
                Brand()
                #if os(macOS)
                Text("0.2 desktop alpha · macOS 14 or later. Local files only. No accounts, telemetry, or cloud services. Export a backup to a second local destination regularly.").font(.caption)
                #else
                Text("0.1 owner-test alpha · iOS 17 or later. Local files only. No accounts, telemetry, or cloud services. Export a backup to a second local destination regularly.").font(.caption)
                #endif
            }
            Section("Next shooting day") {
                Button("Start New Day…") {do {nextDay=try store.newDayRequest()} catch {store.error=error.localizedDescription}}
                    .buttonStyle(.borderedProminent).disabled(store.blocked || store.pendingImport || store.report.values["title",default:""].trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                Text("Creates a separate next-day report. The previous day is kept.").font(.caption)
            }
        }.formStyle(.grouped).scrollContentBackground(.hidden).background(Color("Canvas"))
    }
    func saveArchive(_ url:URL,complete:Bool=true) {
        let item=ArchiveExportItem(url:url,slot:complete ? store.slot:nil,revision:complete ? store.report.revision:nil)
        #if os(macOS)
        let panel=NSSavePanel();panel.nameFieldStringValue=url.lastPathComponent;panel.canCreateDirectories=true
        panel.begin {response in
            guard response == .OK,let destination=panel.url else {finishArchiveExport(item,success:false);return}
            let access=destination.startAccessingSecurityScopedResource()
            Task {
                do {try await Task.detached {try ArchiveFileCopy.copy(url,to:destination)}.value;finishArchiveExport(item,success:true)}
                catch {store.error="The file could not be saved. \(error.localizedDescription)";finishArchiveExport(item,success:false)}
                if access {destination.stopAccessingSecurityScopedResource()}
            }
        }
        #else
        archiveExport=item
        #endif
    }
    func finishArchiveExport(_ item:ArchiveExportItem,success:Bool) {
        if success,let slot=item.slot,let revision=item.revision {AppProfile.preferences.set(revision,forKey:"exported-"+slot)}
        try? FileManager.default.removeItem(at:item.url.deletingLastPathComponent())
    }
    func completeImportSheet(_ item:ProjectArchive.Prepared)->some View {
        NavigationStack {
            List {
                Section("Complete open report") {
                    Text(item.report.displayTitle)
                    Text("Revision \(item.report.revision) · \(item.report.entries.count) takes · \(item.manifest.device)")
                    Text("\(item.snapshot.state.resources.filter{$0.kind=="media"}.count) media · \(item.snapshot.state.resources.filter{$0.kind=="attachment"}.count) attachments · \(item.snapshot.state.resources.filter{$0.kind=="recovery"}.count + (item.snapshot.previous == nil ? 0:1)) recovery copies")
                    Text(ByteCountFormatter.string(fromByteCount:Int64(item.totalBytes),countStyle:.file))
                    Text("Every payload passed CRC and SHA-256 checks. This file contains one open report. Reports with the same identity or title stay as separate local copies; no existing report is replaced or merged.").font(.caption)
                }
                Section("Preferences") {
                    Toggle("Apply appearance and detail preferences",isOn:$applyImportedPreferences)
                    Text("The complete preference snapshot travels with the report for re-export. Appearance and detail are portable; updater, account, security and other device settings are retained as archive data and are never activated by an import.").font(.caption)
                }
                Section("Included files") {ForEach(item.snapshot.state.resources) {r in Text("\(r.kind.capitalized): \(r.name)")}}
                Button("Open as separate editable report") {
                    do {try store.acceptProject(item,applyPreferences:applyImportedPreferences);selected=nil;completeImport=nil}
                    catch {store.error=error.localizedDescription}
                }.buttonStyle(.borderedProminent)
            }.navigationTitle("Verified import").toolbar {Button("Cancel") {store.discardProject(item);completeImport=nil}}
        }.interactiveDismissDisabled().frame(minWidth:320,minHeight:450)
    }
    func export(_ type:UTType,_ ext:String,_ data:() throws ->Data) { do { exportType = type; exportName = try store.report.exportName(extension:ext); exportFile = ExportFile(data:try data()); exporting = true } catch {store.error = error.localizedDescription} }
    struct ImportReview: Identifiable { let id = UUID(); let package:Exchange.Package }
    func importSheet(_ item:ImportReview) -> some View {
        let p = item.package; let preview = try? Exchange.preview(local:store.report,incoming:p)
        return NavigationStack {
            List {
                Section("Incoming report") { Text(p.report.displayTitle); Text("Revision \(p.manifest.revision) · \(p.report.active.count) takes · \(p.manifest.device)"); Text("Verified schema, CRCs, SHA-256 and report identity.").font(.caption) }
                if let preview { Section("Merge preview") { Text(preview.duplicate ? "Already imported — no changes" : "\(preview.additions.count) additions · \(preview.conflicts.count) conflicts"); ForEach(preview.conflicts,id:\.self) { Text($0) }; Button("Merge independent additions") { do { let merged = try Exchange.mergeAdditions(local:store.report,incoming:p,device:store.device); try store.persist(merged); pending = nil } catch { store.error = error.localizedDescription } }.disabled(!preview.conflicts.isEmpty || preview.duplicate) } }
                else { Text("Different report identity. Merge is unavailable.") }
                Button("Open as separate editable report") { store.open(p.report); selected = nil; pending = nil }
                Text("Opening separately keeps the existing report in Today → Open report. No omissions are treated as deletions.").font(.caption)
            }.navigationTitle("Import preview").toolbar { Button("Cancel") { pending = nil } }
        }.frame(minWidth:320,minHeight:450)
    }
}
struct PDFReview: Identifiable { let id = UUID(); let data:Data; let revision:Int; let filename:String }
struct PDFReviewScreen: View {
    let item:PDFReview
    @Environment(\.dismiss) var dismiss
    @State private var exporting = false
    @State private var error:String?
    var body:some View {
        NavigationStack {
            NativePDF(data:item.data).navigationTitle("Frozen report · r\(item.revision)").toolbar {
                Button("Done") { dismiss() }
                Button("Save PDF…") { exporting = true }
            }
            .fileExporter(isPresented:$exporting,document:ExportFile(data:item.data),contentType:.pdf,defaultFilename:item.filename) { result in if case .failure(let e) = result { error = e.localizedDescription } }
            .alert("PDF export",isPresented:Binding(get:{error != nil},set:{if !$0 {error = nil}})) { Button("OK") {error = nil} } message:{Text(error ?? "")}
        }.frame(minWidth:320,minHeight:450)
    }
}
#if os(macOS)
struct NativePDF:NSViewRepresentable {
    let data:Data
    func makeNSView(context:Context)->PDFView { let v = PDFView(); v.autoScales = true; v.document = PDFDocument(data:data); return v }
    func updateNSView(_ v:PDFView,context:Context) {}
}
#else
struct NativePDF:UIViewRepresentable {
    let data:Data
    func makeUIView(context:Context)->PDFView { let v = PDFView(); v.autoScales = true; v.document = PDFDocument(data:data); return v }
    func updateUIView(_ v:PDFView,context:Context) {}
}
#endif
