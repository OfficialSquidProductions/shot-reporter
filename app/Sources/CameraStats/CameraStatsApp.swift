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
    @State private var store = Store(root:AppProfile.root,preferences:AppProfile.preferences)
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
        HStack(spacing:12) {
            Image("SPMark").resizable().scaledToFit().frame(width:36,height:48).accessibilityHidden(true)
            VStack(alignment:.leading,spacing:3) { Text("Shot Reporter").font(.system(.title2,design:.rounded,weight:.heavy)); Text("A Squid Productions Software").font(.caption).foregroundStyle(.secondary) }
        }.padding(.vertical,8).accessibilityElement(children:.combine)
    }
}
enum Destination: String, CaseIterable, Identifiable {
    case today = "Today", log = "Log", review = "Review", saves = "Saves"
    var id:String { rawValue }
    var icon:String {
        switch self {
        case .today:return "sun.max"
        case .log:return "list.bullet.rectangle"
        case .review:return "checklist"
        case .saves:return "externaldrive"
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
    @State private var exportFile: ExportFile?
    @State private var exporting = false
    @State private var exportType: UTType = .camreport
    @State private var exportName = "Shot-Reporter.camreport"
    @State private var selected: String?
    @State private var search = ""
    @State private var circleOnly = false
    @AppStorage("detail") private var detail = "Standard"
    @State private var scene = ""
    @State private var pdfPreview: PDFReview?
    @State private var showingSupport=false
    private var diagnostics:DiagnosticsCenter {DiagnosticsCenter.shared}
    var scheme:ColorScheme? { theme == "Dark" ? .dark : theme == "Light" ? .light : nil }
    var body: some View {
        Group {
            #if os(macOS)
            NavigationSplitView {
                Brand().padding(.horizontal)
                List(Destination.allCases,selection:$destination) { d in Label(d.rawValue,systemImage:d.icon).tag(d) }
                VStack(alignment:.leading) { Text("LOCAL DESKTOP ALPHA 0.2").font(.caption.bold()); Text("\(store.report.values["title",default:"Untitled"]) · r\(store.report.revision)").font(.caption); status }.padding()
            } detail: { content(destination ?? .today) }
            #else
            TabView(selection:$tab) {
                ForEach(Destination.allCases) { d in NavigationStack { content(d) }.tabItem { Label(d.rawValue,systemImage:d.icon) }.tag(d) }
            }
            #endif
        }.tint(Color("AccentColor")).preferredColorScheme(scheme).background(Color("Canvas"))
        .onOpenURL { readImport($0) }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for:.reportBugRequested)) {_ in showingSupport=true}
        #endif
        .fileImporter(isPresented:$importing,allowedContentTypes:[.camreport],allowsMultipleSelection:false) { result in
            do { if let url = try result.get().first { readImport(url) } } catch { store.error = error.localizedDescription }
        }
        .fileExporter(isPresented:$exporting,document:exportFile,contentType:exportType,defaultFilename:exportName) { result in switch result { case .failure(let e): store.error = e.localizedDescription; case .success: AppProfile.preferences.set(store.report.revision,forKey:"exported-"+store.slot) } }
        .sheet(isPresented:$showingSupport) {BugReportView(diagnostics:diagnostics)}
        .sheet(item:$pending) { item in importSheet(item) }
        .onChange(of:pending != nil) {_,value in store.pendingImport=value}
        .sheet(item:$pdfPreview) { item in PDFReviewScreen(item:item) }
        .alert("Shot Reporter",isPresented:Binding(get:{store.error != nil},set:{if !$0 { store.error = nil }})) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
    }
    func readImport(_ url:URL) {
        do {
            let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
            let attrs = try FileManager.default.attributesOfItem(atPath:url.path)
            guard ((attrs[.size] as? NSNumber)?.intValue ?? Int.max) <= Exchange.limit else { throw ReportError.invalid("File exceeds 32 MiB maximum") }
            pending = ImportReview(package:try Exchange.read(Data(contentsOf:url)))
        } catch { store.error = error.localizedDescription }
    }
    @ViewBuilder func content(_ d: Destination) -> some View {
        VStack(spacing:0) {
            #if !os(macOS)
            Brand().padding(.horizontal).frame(maxWidth:.infinity,alignment:.leading)
            #endif
            HStack { Text(store.report.values["title",default:"New production"]).font(.headline).lineLimit(1); Spacer(); Text("r\(store.report.revision)").monospacedDigit().foregroundStyle(.secondary); Button {showingSupport=true} label:{Label("Report a Bug",systemImage:"ladybug")} }.padding(.horizontal).padding(.vertical,8)
            Divider()
            switch d {
            case .today: today
            case .log: log
            case .review: review
            case .saves: saves
            }
        }.navigationTitle(d.rawValue).background(Color("Canvas"))
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
    var status: some View { Label(store.blocked ? "Recovery required" : store.saved == nil ? "Create a local report to begin" : "Saved on this device",systemImage:store.blocked ? "exclamationmark.triangle" : "checkmark.circle").font(.caption).foregroundStyle(.secondary) }
    func projectBinding(_ key:String) -> Binding<String> { Binding(get:{store.report.values[key,default:""]},set:{v in store.change { $0.values[key] = v }}) }
    func defaultBinding(_ key:String) -> Binding<String> { Binding(get:{store.report.defaults[key,default:""]},set:{v in store.change("Changed defaults for future takes") { $0.defaults[key] = v }}) }
    func entryBinding(_ id:String,_ key:String) -> Binding<String> { Binding(get:{store.report.entries.first{$0.id == id}?.values[key] ?? ""},set:{v in store.change { r in if let i = r.entries.firstIndex(where:{$0.id == id}) { r.entries[i].values[key] = v; r.entries[i].reviewed = false } }}) }
    func field(_ f:Field,_ binding:Binding<String>) -> some View { VStack(alignment:.leading,spacing:4) { Text(f.title).font(.caption).foregroundStyle(.secondary); TextField(f.title,text:binding,axis:f.id.lowercased().contains("notes") || f.id == "remarks" ? .vertical : .horizontal).textFieldStyle(.roundedBorder).accessibilityLabel(f.title) }.padding(.vertical,2) }
    var today: some View {
        Form {
            Section("Support") {
                Button("Report a Bug") {showingSupport=true}
                if diagnostics.hasPreviousTermination {Text(diagnostics.incidents.contains {$0.kind == .crash} ? "A crash from a previous launch was captured locally." : "The previous session ended unexpectedly; a crash is not confirmed."); Button("Review previous launch diagnostics") {showingSupport=true};Button("Dismiss previous diagnostics") {diagnostics.dismiss()}}
            }
            Section("Local production") {
                status
                Picker("Open report",selection:Binding(get:{store.slot},set:{store.select($0)})) { Text("Current report").tag(store.slot); ForEach(store.documents.filter{$0.0 != store.slot},id:\.0) { doc in Text(doc.1).tag(doc.0) } }
                Button { store.open(Report()); selected = nil } label: { Label("New blank report",systemImage:"plus").frame(maxWidth:.infinity,minHeight:32) }.buttonStyle(.borderedProminent)
            }
            Section("Workspace preferences") {
                Picker("Production profile",selection:Binding(get:{store.report.profile},set:{v in store.change("Changed profile; all values retained"){$0.profile = v}})) { ForEach(Schema.profiles,id:\.self) { Text($0) } }
                Picker("Detail",selection:$detail) { ForEach(["Quick","Standard","Full"],id:\.self) { Text($0) } }
                ForEach(Schema.positions,id:\.self) { p in Toggle(p,isOn:Binding(get:{store.report.positions.contains(p)},set:{on in store.change("Changed local position view") { r in if on { if !r.positions.contains(p) {r.positions.append(p)} } else {r.positions.removeAll{$0 == p}} }})) }
                Text("Positions describe responsibilities. This alpha shows all report groups; every requirement remains in Review.").font(.caption)
                Picker("Appearance",selection:$theme) { ForEach(["System","Light","Dark"],id:\.self) { Text($0) } }
            }
            Section("Project / crew · complete report") { ForEach(Schema.project) { f in field(f,projectBinding(f.id)) } }
            Section("Defaults · snapshot when a new take is created") { ForEach(Schema.settings) { f in field(f,defaultBinding(f.id)) }; Text("Editing defaults affects future takes. Existing takes keep their recorded settings.").font(.caption) }
        }.formStyle(.grouped).scrollContentBackground(.hidden).background(Color("Canvas"))
    }
    var log: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                HStack { Label("Camera \(store.report.defaults["camera",default:"A"])",systemImage:"camera").font(.title2.bold()); Spacer(); Text(store.report.defaults["roll",default:""]).monospaced() }
                TextField("Scene / setup (e.g. 12B)",text:$scene).textFieldStyle(.roundedBorder).font(.title2).accessibilityLabel("Scene for next take")
                HStack {
                    Button { store.change("Next take") { r in selected = r.next(scene:scene,device:store.device) } } label: { Label("Next take",systemImage:"plus").frame(maxWidth:.infinity,minHeight:36) }.buttonStyle(.borderedProminent).disabled(scene.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || store.blocked)
                    Button("New setup") { scene = ""; selected = nil }
                    Button("Reload") { store.change("New media load") { $0.defaults["load"] = UUID().uuidString; $0.defaults["mag"] = ""; $0.defaults["roll"] = "" } }
                }
                Text("Next take inherits visible camera defaults. Reload creates a fresh load ID; enter the new roll and mag in Today before logging.").font(.caption).foregroundStyle(.secondary)
                Picker("Take",selection:$selected) { Text("Choose take").tag(String?.none); ForEach(store.report.active.reversed()) { e in Text("\(e.values["scene",default:"?"]) / \(e.values["take",default:"?"]) · \(e.values["camera",default:""]) \(e.values["roll",default:""])").tag(Optional(e.id)) } }
                if let id = selected, let e = store.report.entries.first(where:{$0.id == id && !$0.deleted}) { takeEditor(e) } else { ContentUnavailableView("Ready for the next slate",systemImage:"camera",description:Text("Enter the scene, then add a take. All logging works offline.")) }
            }.padding(20).frame(maxWidth:900,alignment:.leading).frame(maxWidth:.infinity)
        }
    }
    func takeEditor(_ e:Entry) -> some View {
        VStack(alignment:.leading,spacing:16) {
            HStack { Text("Scene \(e.values["scene",default:""]) · Take \(e.values["take",default:""])").font(.largeTitle.bold()); Spacer() }
            LazyVGrid(columns:[GridItem(.adaptive(minimum:130))],alignment:.leading) {
                ForEach(["Circle","MOS","Pickup","Tail slate","False roll","Technical issue"],id:\.self) { flag in Toggle(flag,isOn:Binding(get:{store.report.entries.first{$0.id == e.id}?.flags.contains(flag) == true},set:{on in store.change { r in if let i = r.entries.firstIndex(where:{$0.id == e.id}) { if on { r.entries[i].flags.insert(flag) } else { r.entries[i].flags.remove(flag) }; r.entries[i].reviewed = false } }})).toggleStyle(.button).buttonStyle(.bordered) }
            }
            Picker("Detail",selection:$detail) { ForEach(["Quick","Standard","Full"],id:\.self) { Text($0) } }.pickerStyle(.segmented)
            ForEach(Schema.take.filter{detail != "Quick" || ["scene","take","remarks"].contains($0.id)}) { f in field(f,entryBinding(e.id,f.id)) }
            if detail != "Quick" { Divider(); Text("Recorded settings · edit this take only").font(.headline); ForEach(Schema.settings.filter{detail == "Full" || ["lens","stop","iso","temperature","camera","roll"].contains($0.id)}) { f in field(f,entryBinding(e.id,f.id)) } }
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
                Text("Missing fields can be completed in Today (defaults / project) or Log → Full (recorded take). Enter N/A with a reason where the report permits it. Changing defaults does not fill existing takes.").font(.caption)
                ForEach(Array(store.report.missing.enumerated()),id:\.offset) { _,m in Text(m).font(.caption) }
            }
            Section("Find takes") {
                TextField("Search scene, roll, notes, camera",text:$search).textFieldStyle(.roundedBorder)
                Toggle("Circled takes only",isOn:$circleOnly)
                ForEach(store.report.active.filter{e in (!circleOnly || e.flags.contains("Circle")) && (search.isEmpty || (e.values.values.joined(separator:" ")+e.flags.joined(separator:" ")).localizedCaseInsensitiveContains(search))}) { e in
                    Button { selected = e.id; destination = .log; tab = .log } label: { VStack(alignment:.leading) { Text("\(e.values["scene",default:"?"]) / \(e.values["take",default:"?"]) · Camera \(e.values["camera",default:""]) · \(e.values["roll",default:""])").font(.headline); Text(e.flags.sorted().joined(separator:" · ") + (e.reviewed ? " · Reviewed" : " · Review pending")).font(.caption); Text(e.values["remarks",default:""]).font(.caption).foregroundStyle(.secondary) } }
                }
            }
            Section("Recovery") { ForEach(store.report.entries.filter(\.deleted)) { e in Button("Restore \(e.values["scene",default:""]) / \(e.values["take",default:""])") { store.change("Restored deleted take") { r in if let i = r.entries.firstIndex(where:{$0.id == e.id}) {r.entries[i].deleted = false} } } } }
        }
    }
    var saves: some View {
        Form {
            Section("Report handoff") {
                status; Text("Device: \(store.device) · report revision \(store.report.revision) · last file export \(store.lastExportedRevision.map{ "r\($0)" } ?? "none")").font(.caption)
                Button("Save As .camreport") { export(.camreport,"camreport") {try Exchange.export(store.report,device:store.device)} }
                Button("Import Save…") { importing = true }
                Text("Schema 1 alpha: complete report only, no attachments or scoped packages. Import previews independent additions; competing edits must be opened separately. A saved file is not proof of receipt.").font(.caption)
                Button("Restore previous local snapshot as separate report") { store.restore() }
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
        }.formStyle(.grouped).scrollContentBackground(.hidden).background(Color("Canvas"))
    }
    func export(_ type:UTType,_ ext:String,_ data:() throws ->Data) { do { exportType = type; exportName = try store.report.exportName(extension:ext); exportFile = ExportFile(data:try data()); exporting = true } catch {store.error = error.localizedDescription} }
    struct ImportReview: Identifiable { let id = UUID(); let package:Exchange.Package }
    func importSheet(_ item:ImportReview) -> some View {
        let p = item.package; let preview = try? Exchange.preview(local:store.report,incoming:p)
        return NavigationStack {
            List {
                Section("Incoming report") { Text(p.report.values["title",default:"Untitled"]); Text("Revision \(p.manifest.revision) · \(p.report.active.count) takes · \(p.manifest.device)"); Text("Verified schema, CRCs, SHA-256 and report identity.").font(.caption) }
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
