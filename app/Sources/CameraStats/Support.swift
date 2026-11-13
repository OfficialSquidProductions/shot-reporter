import SwiftUI
import Observation
import UniformTypeIdentifiers
import CameraStatsCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Explicit local QA launch only; never moves or rewrites the normal library.
enum AppProfile {
    static let root:URL? = {
        // A preview bundle pins its profile so Finder/direct launches are isolated too.
        guard let path=(Bundle.main.object(forInfoDictionaryKey:"ShotReporterPreviewProfileRoot") as? String) ?? ProcessInfo.processInfo.environment["SHOT_REPORTER_TEST_PROFILE"] else {return nil}
        let url=URL(fileURLWithPath:path,isDirectory:true).standardizedFileURL
        guard path.hasPrefix("/"),url.lastPathComponent.hasPrefix("ShotReporterTest-") else {fatalError("Invalid isolated Shot Reporter preview profile; normal library will not be opened.")}
        return url
    }()
    static let preferencesDomain:String = root.map {"org.squidproductions.shotreporter.test."+Exchange.digest(Data($0.path.utf8))} ?? (Bundle.main.bundleIdentifier ?? "org.squidproductions.camerastats")
    static let preferences:UserDefaults = root == nil ? .standard : UserDefaults(suiteName:preferencesDomain)!
}

@MainActor @Observable final class DiagnosticsCenter {
    static let shared=DiagnosticsCenter()
    private var journal:DiagnosticsJournal?
    private(set) var incidents:[DiagnosticIncident]=[]
    private(set) var storageNotice:String?
    private var nativeInstalled=false
    private var retentionTimer:Timer?
    var hasPreviousTermination:Bool {incidents.contains {$0.kind == .crash || $0.kind == .interrupted}}
    init(root:URL?=nil,installNative:Bool=true) {
        do {
            let base=root ?? AppProfile.root ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("org.squidproductions.camerastats",isDirectory:true)
            let journal=try DiagnosticsJournal(root:base.appendingPathComponent("Diagnostics",isDirectory:true));self.journal=journal
            #if os(macOS)
            try journal.begin(trackInterrupted:true)
            #else
            // iOS routinely kills background apps without willTerminate. Only
            // an actual fatal marker is a crash; no guessed crash from a kill.
            try journal.begin(trackInterrupted:false)
            #endif
            incidents=journal.pending()
            if installNative {
                nativeInstalled=NativeCrashCapture.install(at:journal.signalURL)
                if nativeInstalled {NSSetUncaughtExceptionHandler { _ in NativeCrashCapture.recordException() }}
                else {storageNotice="Native crash capture is unavailable. Bug reporting and local failure categories remain available."}
                retentionTimer=Timer.scheduledTimer(withTimeInterval:3_600,repeats:true) {[weak self] _ in Task {@MainActor in self?.refresh()}}
            }
        } catch {journal=nil;storageNotice="Local diagnostics could not be saved. You can still describe, copy or export a bug report."}
    }
    func capture(_ area:DiagnosticArea,error:NSError?=nil) {
        do {try journal?.failure(area,error:error);incidents=journal?.pending() ?? []}
        catch {storageNotice="Local diagnostics could not be saved. Existing reports are unchanged."}
    }
    func refresh() {incidents=journal?.pending() ?? []}
    func dismiss() {
        do {try journal?.dismiss(Set(incidents.map(\.id)));incidents=journal?.pending() ?? []}
        catch {storageNotice="Diagnostics could not be dismissed. Please retry."}
    }
    func cleanShutdown() {journal?.cleanShutdown();if nativeInstalled {NativeCrashCapture.uninstall();nativeInstalled=false}}
}

struct BugReportView:View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var diagnostics:DiagnosticsCenter
    @State private var description=""
    @State private var steps=""
    @State private var includeDiagnostics=true
    @State private var exporting=false
    @State private var message=""
    @State private var exportData=Data()
    private var version:String {let info=Bundle.main.infoDictionary ?? [:];return "\(info["CFBundleShortVersionString"] as? String ?? "development") (\(info["CFBundleVersion"] as? String ?? "local"))"}
    private var report:String {SupportReport.body(description:description,steps:steps,version:version,os:ProcessInfo.processInfo.operatingSystemVersionString,incidents:diagnostics.incidents,includeDiagnostics:includeDiagnostics)}
    var body:some View {
        NavigationStack {
            Form {
                Section("Report a Bug") {
                    Text("To: \(SupportReport.recipient)").textSelection(.enabled)
                    Text("Nothing is sent automatically. Review the preview before opening an email draft. Opening a draft does not confirm delivery.").font(.callout)
                    Text("No project, script, media contents, personal paths, environment or raw crash dumps are collected automatically. Common paths and secrets in your text are redacted; review any other identifying details you enter.").font(.caption)
                }
                Section("What happened?") {
                    TextField("Description",text:$description,axis:.vertical).lineLimit(3...7).accessibilityLabel("Bug description")
                    TextField("Steps to reproduce",text:$steps,axis:.vertical).lineLimit(3...7).accessibilityLabel("Steps to reproduce")
                    Text("Each field is limited to 4,000 characters.").font(.caption)
                    Toggle("Include sanitized diagnostic categories",isOn:$includeDiagnostics)
                    if let notice=diagnostics.storageNotice {Text(notice).font(.caption)}
                }
                Section("Review exactly what will be shared") {
                    Text(report).font(.system(.caption,design:.monospaced)).textSelection(.enabled).accessibilityLabel("Report preview").accessibilityValue(report)
                }
                Section("Share after review") {
                    Button("Open email draft") {openDraft()}
                    Button("Copy report") {copyReport()}
                    Button("Export report as text…") {exportData=Data(report.utf8);exporting=true}
                    if !message.isEmpty {Text(message).accessibilityLabel("Report action status")}
                    Text("If your mail client cannot open the draft, copy or export the full report and address it to \(SupportReport.recipient).").font(.caption)
                }
                if !diagnostics.incidents.isEmpty {
                    Section("Local diagnostics") {Button("Dismiss stored diagnostics",role:.destructive) {diagnostics.dismiss();message="Stored diagnostics dismissed. Nothing was sent."}}
                }
            }.formStyle(.grouped).navigationTitle("Report a Bug")
                .toolbar {ToolbarItem(placement:.cancellationAction) {Button("Close") {dismiss()}}}
                .onChange(of:description) {_,value in if value.count > 4_000 {description=String(value.prefix(4_000))}}
                .onChange(of:steps) {_,value in if value.count > 4_000 {steps=String(value.prefix(4_000))}}
                .fileExporter(isPresented:$exporting,document:ExportFile(data:exportData),contentType:.plainText,defaultFilename:"Shot-Reporter-support.txt") {result in
                    switch result {case .success:message="Report exported locally. Nothing was sent.";case .failure:message="Export was cancelled or unavailable. Copy report is still available."}
                }
        }
        #if os(macOS)
        .frame(minWidth:560,idealWidth:700,minHeight:600,idealHeight:760)
        #endif
    }
    private func copyReport() {
        #if os(macOS)
        NSPasteboard.general.clearContents();let copied=NSPasteboard.general.setString(report,forType:.string)
        message=copied ? "Report copied. Nothing was sent." : "Clipboard unavailable. Export the report instead."
        #else
        UIPasteboard.general.string=report;message="Report copied. Nothing was sent."
        #endif
    }
    private func openDraft() {
        guard let url=SupportReport.mailURL(body:report) else {message="This report is too long for a reliable mail link. Copy or export the full report instead.";return}
        #if os(macOS)
        guard NSWorkspace.shared.urlForApplication(toOpen:url) != nil else {message="No supported mail client was found. Copy or export the report instead.";return}
        message=NSWorkspace.shared.open(url) ? "Draft requested in your mail client. Delivery is not confirmed." : "The mail client could not open a draft. Copy or export the report instead."
        #else
        guard UIApplication.shared.canOpenURL(url) else {message="No supported mail client was found. Copy or export the report instead.";return}
        UIApplication.shared.open(url,options:[:]) {opened in message=opened ? "Draft requested in your mail client. Delivery is not confirmed." : "The mail client could not open a draft. Copy or export the report instead."}
        #endif
    }
}

#if !os(macOS)
final class DiagnosticsAppDelegate:NSObject,UIApplicationDelegate {
    func applicationWillTerminate(_ application:UIApplication) {DiagnosticsCenter.shared.cleanShutdown()}
}
#else
extension Notification.Name {static let reportBugRequested=Notification.Name("ShotReporterReportBugRequested")}
struct SupportCommands:Commands {
    var body:some Commands {CommandGroup(replacing:.help) {Button("Report a Bug…") {NotificationCenter.default.post(name:.reportBugRequested,object:nil)}}}
}
#endif

struct ArchiveExportItem:Identifiable {let id=UUID();var url:URL;var slot:String?;var revision:Int?}
enum ArchiveFileCopy {
    static func copy(_ source:URL,to destination:URL)throws {
        // File coordination preserves existing destination bytes until the complete copy is ready.
        let coordinator=NSFileCoordinator(),fm=FileManager.default;var coordinationError:NSError?,copyError:Error?
        coordinator.coordinate(writingItemAt:destination,options:.forReplacing,error:&coordinationError) {target in
            do {
                let replacement=try fm.url(for:.itemReplacementDirectory,in:.userDomainMask,appropriateFor:target,create:true)
                defer{try? fm.removeItem(at:replacement)}
                let temp=replacement.appendingPathComponent(source.lastPathComponent);try fm.copyItem(at:source,to:temp)
                if fm.fileExists(atPath:target.path) {_=try fm.replaceItemAt(target,withItemAt:temp)} else {try fm.moveItem(at:temp,to:target)}
            } catch {copyError=error}
        }
        if let coordinationError {throw coordinationError};if let copyError {throw copyError}
    }
}
#if !os(macOS)
struct ArchiveExportPicker:UIViewControllerRepresentable {
    var url:URL;var completion:(Bool)->Void
    func makeCoordinator()->Coordinator {Coordinator(completion)}
    func makeUIViewController(context:Context)->UIDocumentPickerViewController {
        let picker=UIDocumentPickerViewController(forExporting:[url],asCopy:true);picker.delegate=context.coordinator;return picker
    }
    func updateUIViewController(_ controller:UIDocumentPickerViewController,context:Context) {}
    final class Coordinator:NSObject,UIDocumentPickerDelegate {
        let completion:(Bool)->Void;init(_ completion:@escaping(Bool)->Void) {self.completion=completion}
        func documentPicker(_ controller:UIDocumentPickerViewController,didPickDocumentsAt urls:[URL]) {completion(!urls.isEmpty)}
        func documentPickerWasCancelled(_ controller:UIDocumentPickerViewController) {completion(false)}
    }
}
#endif

/// A strong selected fill, explicit checkmark and accessible state work in both color schemes.
struct SelectionButton:View {
    var title:String;var selected:Bool;var action:()->Void
    var body:some View {
        Button(action:action) {
            HStack(spacing:6) {Image(systemName:selected ? "checkmark.circle.fill":"circle");Text(title).multilineTextAlignment(.center)}
                .frame(maxWidth:.infinity,minHeight:44).padding(.horizontal,10)
                .foregroundStyle(selected ? Color.white:Color.primary)
                .background(selected ? Color("SelectionGreen"):Color("Paper"),in:RoundedRectangle(cornerRadius:8))
                .overlay(RoundedRectangle(cornerRadius:8).stroke(selected ? Color("SelectionGreen"):Color.primary.opacity(0.35),lineWidth:selected ? 2:1))
        }.buttonStyle(.plain).accessibilityLabel(title).accessibilityValue(selected ? "Selected":"Not selected").accessibilityAddTraits(selected ? .isSelected:[])
    }
}
struct MeasurementField:View {
    var title:String;@Binding var raw:String;var unit:MeasurementUnit
    @FocusState private var focused:Bool
    @State private var draft:String
    init(title:String,raw:Binding<String>,unit:MeasurementUnit) {
        self.title=title;self._raw=raw;self.unit=unit
        self._draft=State(initialValue:LengthMeasurement.display(raw.wrappedValue,unit:unit))
    }
    var body:some View {
        VStack(alignment:.leading,spacing:4) {
            Text("\(title) (\(unit.symbol))").font(.caption).foregroundStyle(.secondary)
            TextField(unit.example,text:Binding(get:{draft},set:{text in
                // Focus and programmatic display refreshes are not edits. Keep the
                // initialized draft stable, and commit only actual changed input.
                guard text != draft else {return};draft=text;raw=LengthMeasurement.edited(text,unit:unit)
            }))
                .textFieldStyle(.roundedBorder).focused($focused).autocorrectionDisabled().accessibilityLabel("\(title) (\(unit.symbol))")
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .onChange(of:focused) {_,value in if !value {draft=LengthMeasurement.display(raw,unit:unit)}}
                .onChange(of:raw) {_,value in if !focused {draft=LengthMeasurement.display(value,unit:unit)}}
                .onChange(of:unit) {_,value in draft=LengthMeasurement.display(raw,unit:value)}
            if !raw.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,LengthMeasurement.meters(raw)==nil {
                Text("Kept as entered. Add explicit units to convert this value when changing measurement units.").font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(.vertical,2)
    }
}
