#if os(macOS)
import AppKit
import SwiftUI
import Observation
import Security
#if canImport(Sparkle) && !SHOT_REPORTER_STORE_DISTRIBUTION
import Sparkle
#endif
import CameraStatsCore

/// A distribution policy, not a second downloader. Sparkle authenticates the
/// Ed25519 archive before extraction, then validates and replaces the app bundle.
struct DesktopUpdatePolicy {
    static let identifier = "org.squidproductions.camerastats"
    static let team = "FZ298DXLS3"
    enum Distribution: Equatable { case direct, testFlight, appStore, development, unconfigured }
    enum Channel: String { case alpha, stable, unconfigured }
    let distribution: Distribution
    let channel: Channel
    let build: UInt64
    let feed: URL?
    let publicKey: Data?
    let hostTrusted: Bool
    var unavailableReason: String? {
        switch distribution {
        case .testFlight: return "This copy receives updates through TestFlight. Open TestFlight to read release notes and install updates."
        case .appStore: return "This copy receives updates through the Mac App Store."
        case .development: return "This development build has no published update feed. Install a verified direct-distribution release to receive automatic updates."
        case .unconfigured: return "Update security settings are incomplete. Use a verified Shot Reporter build; automatic installation is disabled."
        case .direct: break
        }
        guard channel != .unconfigured else { return "The update release channel is not configured. Automatic installation is disabled." }
        guard hostTrusted else { return "The installed app's signing identity could not be verified. Use the verified Shot Reporter download to repair this copy." }
        guard build > 0, let feed, Self.allowedFeed(feed), publicKey?.count == 32 else { return "Automatic updates are not configured for this build. A dedicated Shot Reporter update key and published feed are required." }
        return nil
    }
    static func allowedFeed(_ url: URL) -> Bool {
        url.absoluteString == "https://raw.githubusercontent.com/OfficialSquidProductions/shot-reporter/main/updates/macos/appcast.xml"
    }
    static func allowedArchive(_ url: URL) -> Bool {
        guard let parts = URLComponents(url:url,resolvingAgainstBaseURL:false),parts.scheme == "https",parts.host == "github.com",parts.user == nil,parts.password == nil,parts.port == nil,parts.query == nil,parts.fragment == nil else { return false }
        let pieces = parts.path.split(separator:"/")
        return pieces.count == 6 && pieces[0] == "OfficialSquidProductions" && pieces[1] == "shot-reporter" && pieces[2] == "releases" && pieces[3] == "download" && !pieces[4].isEmpty && pieces[5].hasSuffix(".zip") && !parts.percentEncodedPath.lowercased().contains("%2f") && !pieces.contains("..")
    }
    func validate(build incoming: String, channel incomingChannel: String?, archive: URL?) throws {
        guard let value = UInt64(incoming),value > build else { throw DesktopUpdateError("The update build must be newer than this installation.") }
        guard incomingChannel == nil || incomingChannel == "stable" || (channel == .alpha && incomingChannel == "alpha") else { throw DesktopUpdateError("This update belongs to a different release channel.") }
        guard let archive,Self.allowedArchive(archive) else { throw DesktopUpdateError("This update does not use the Shot Reporter release archive location.") }
    }
    static func installed(bundle: Bundle = .main) -> Self {
        let info = bundle.infoDictionary ?? [:]
        let receipt = bundle.appStoreReceiptURL
        let receiptExists = receipt.map { FileManager.default.fileExists(atPath:$0.path) } ?? false
        let declared = info["ShotReporterDistribution"] as? String
        var distribution: Distribution
        if declared == "testflight" || (receiptExists && receipt?.lastPathComponent == "sandboxReceipt") { distribution = .testFlight }
        else if declared == "appstore" || receiptExists { distribution = .appStore }
        else if declared == "direct" { distribution = .direct }
        else { distribution = .development }
        if distribution == .direct && !Self.completeSecuritySettings(info) { distribution = .unconfigured }
        return Self(distribution:distribution,channel:Channel(rawValue:info["ShotReporterUpdateChannel"] as? String ?? "") ?? .unconfigured,build:UInt64(info["CFBundleVersion"] as? String ?? "") ?? 0,feed:(info["SUFeedURL"] as? String).flatMap(URL.init(string:)),publicKey:(info["SUPublicEDKey"] as? String).flatMap {Data(base64Encoded:$0)},hostTrusted:trustedBundle(bundle.bundleURL))
    }
    static func completeSecuritySettings(_ info:[String:Any]) -> Bool {
        guard let expiration=info["SUSignedFeedFailureExpirationInterval"] as? NSNumber,
              CFGetTypeID(expiration) != CFBooleanGetTypeID(), expiration.doubleValue == 0 else {return false}
        return info["SURequireSignedFeed"] as? Bool == true &&
        info["SUVerifyUpdateBeforeExtraction"] as? Bool == true &&
        info["SUAllowsAutomaticUpdates"] as? Bool == false
    }
    static func trustedBundle(_ url:URL) -> Bool {
        var code:SecStaticCode?, requirement:SecRequirement?
        let text = "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\""
        guard SecStaticCodeCreateWithPath(url as CFURL,[],&code) == errSecSuccess,let code,SecRequirementCreateWithString(text as CFString,[],&requirement) == errSecSuccess,let requirement else {return false}
        return SecStaticCodeCheckValidity(code,SecCSFlags(rawValue:kSecCSCheckAllArchitectures | kSecCSStrictValidate),requirement) == errSecSuccess
    }
}
struct DesktopUpdateError:LocalizedError { let message:String; init(_ message:String){self.message=message};var errorDescription:String? {message} }

/// Installation proceeds only after confirmation and verification of the saved report.
@MainActor enum DesktopUpdateActivity {static var installing=false}

@MainActor final class DesktopUpdateSaveGate {
    var save: (() throws -> Void)?
    private(set) var installing=false
    private var continuation:(() -> Void)?
    func postpone(_ action:@escaping ()->Void) {guard !installing,continuation == nil else {return};continuation=action}
    var pending:Bool {continuation != nil}
    func cancel() {guard !installing else {return};continuation=nil}
    func prepare() throws {
        guard !installing else {return}
        guard let save else {throw DesktopUpdateError("The report workspace is not ready. Keep working and retry the update.")}
        try save()
    }
    func install(confirmed:Bool) throws {
        guard confirmed,!installing,let action=continuation else {return}
        try prepare();installing=true;DesktopUpdateActivity.installing=true;continuation=nil;action()
    }
    func updateAborted() {installing=false;DesktopUpdateActivity.installing=false;continuation=nil}
}

#if canImport(Sparkle) && !SHOT_REPORTER_STORE_DISTRIBUTION
@MainActor @Observable final class DesktopUpdates:NSObject,SPUUpdaterDelegate {
    private(set) var status="Updates have not been checked."
    private(set) var availableVersion:String?
    private(set) var started=false
    private let policy:DesktopUpdatePolicy
    private var controller:SPUStandardUpdaterController?
    let gate=DesktopUpdateSaveGate()
    var confirmInstall:(()->Bool)?
    var presentNotice:((String,String)->Void)?
    init(policy:DesktopUpdatePolicy = .installed()) {self.policy=policy;super.init()}
    private var automaticCheckState=false
    var automaticChecks:Bool {get {automaticCheckState} set {controller?.updater.automaticallyChecksForUpdates=newValue;automaticCheckState=controller?.updater.automaticallyChecksForUpdates ?? false}}
    var isDirect:Bool {policy.distribution == .direct && policy.unavailableReason == nil}
    var channelName:String {policy.channel.rawValue.capitalized}
    func configure(store:Store) {
        gate.save={
            guard !store.blocked,!store.pendingImport,store.error == nil else {throw DesktopUpdateError("Resolve the report's recovery, import or save message before installing an update.")}
            if store.saved == nil {try store.persist(store.report)}
            // Every accepted edit already commits with synchronous=FULL. Verify
            // that accepted snapshot instead of saving it twice (which would
            // overwrite the user's previous recovery snapshot with a duplicate).
            let repository=try Repository(url:store.root.appendingPathComponent("reports.sqlite3"))
            let durable=try repository.load(store.slot).report
            guard try Exchange.encoder().encode(durable) == Exchange.encoder().encode(store.report) else {throw DesktopUpdateError("The local report changed in another window or app instance. Reopen it before updating.")}
        }
    }
    func start() {
        guard !started else {return};started=true
        if let reason=policy.unavailableReason {status=reason;return}
        let controller=SPUStandardUpdaterController(startingUpdater:false,updaterDelegate:self,userDriverDelegate:nil)
        self.controller=controller;controller.startUpdater();automaticCheckState=controller.updater.automaticallyChecksForUpdates
        // Sparkle's scheduled checks continue daily. A launch check is silent
        // when current/offline, and honours the user's automatic-check setting.
        if controller.updater.automaticallyChecksForUpdates {
            controller.updater.checkForUpdatesInBackground()
            status="Checking the \(channelName.lowercased()) channel; installations require confirmation."
        } else {status="Automatic update checks are off. Choose Check for Updates for a manual check."}
    }
    func check() {
        if policy.distribution == .testFlight {NSWorkspace.shared.open(URL(fileURLWithPath:"/Applications/TestFlight.app"));return}
        if policy.distribution == .appStore {NSWorkspace.shared.open(URL(string:"macappstore://showUpdatesPage")!);return}
        if let reason=policy.unavailableReason {show("Updates unavailable",reason);return}
        if gate.pending {continueInstall()} else {controller?.checkForUpdates(nil)}
    }
    private func show(_ title:String,_ detail:String) {if let presentNotice {presentNotice(title,detail);return};let alert=NSAlert();alert.messageText=title;alert.informativeText=detail;alert.addButton(withTitle:"Keep Working");alert.runModal()}
    private func continueInstall() {
        guard gate.pending,!gate.installing else {return}
        let confirmed:Bool
        if let confirmInstall {confirmed=confirmInstall()} else {
        let alert=NSAlert();alert.messageText="Save and install Shot Reporter?"
        alert.informativeText="Your report will be saved before Shot Reporter closes and relaunches. Reports and recovery snapshots stay in their existing locations."
        alert.addButton(withTitle:"Save, Install and Relaunch");alert.addButton(withTitle:"Keep Working")
        confirmed=alert.runModal() == .alertFirstButtonReturn
        }
        guard confirmed else {status="Update postponed. Choose Check for Updates to continue.";return}
        do {try gate.install(confirmed:true)} catch {status=error.localizedDescription;show("Update postponed",status)}
    }
    func prepareToTerminate()->Bool {
        guard gate.pending || gate.installing else {return true}
        if gate.pending && !gate.installing {continueInstall();return gate.installing}
        do {try gate.prepare();return true} catch {status=error.localizedDescription;show("Keep Shot Reporter open",status);return false}
    }
    func allowedChannels(for updater:SPUUpdater)->Set<String> {policy.channel == .alpha ? ["alpha","stable"]:["stable"]}
    static func validateFeedSignature(_ status:SPUAppcastSigningValidationStatus)throws {
        guard status == .succeeded else {throw DesktopUpdateError("The update feed signature could not be verified. Installation is disabled.")}
    }
    func updater(_ updater:SPUUpdater,shouldProceedWithUpdate item:SUAppcastItem,updateCheck:SPUUpdateCheck)throws {
        try Self.validateFeedSignature(item.signingValidationStatus)
        try policy.validate(build:item.versionString,channel:item.channel,archive:item.fileURL)
    }
    func updater(_ updater:SPUUpdater,didFindValidUpdate item:SUAppcastItem) {availableVersion=item.displayVersionString;status="Shot Reporter \(item.displayVersionString) is available. Review release notes before installing."}
    func updaterDidNotFindUpdate(_ updater:SPUUpdater) {availableVersion=nil;status="You have the newest available \(channelName.lowercased()) build."}
    func updater(_ updater:SPUUpdater,didAbortWithError error:Error) {DiagnosticsCenter.shared.capture(.updates,error:error as NSError);status="Update check or install stopped: \(error.localizedDescription). Local reports and recovery snapshots remain in their existing locations.";gate.updateAborted()}
    func updater(_ updater:SPUUpdater,shouldPostponeRelaunchForUpdate item:SUAppcastItem,untilInvokingBlock installHandler:@escaping ()->Void)->Bool {
        gate.postpone(installHandler);DispatchQueue.main.async {[weak self] in self?.continueInstall()};return true
    }
}

#else
// App Store/TestFlight archives contain no Sparkle framework or install helper.
@MainActor @Observable final class DesktopUpdates:NSObject {
    private let policy:DesktopUpdatePolicy
    private(set) var status="Updates are managed by the store."
    var availableVersion:String? {nil}
    var automaticChecks:Bool {get {false} set {}}
    var isDirect:Bool {false}
    var channelName:String {policy.channel.rawValue.capitalized}
    init(policy:DesktopUpdatePolicy = .installed()) {self.policy=policy;super.init()}
    func configure(store:Store) {}
    func start() {status=policy.unavailableReason ?? "Updates are managed by the store."}
    func check() {
        if policy.distribution == .testFlight {
            let testFlight=URL(fileURLWithPath:"/Applications/TestFlight.app")
            if FileManager.default.fileExists(atPath:testFlight.path) {NSWorkspace.shared.open(testFlight);return}
        }
        NSWorkspace.shared.open(URL(string:"macappstore://showUpdatesPage")!)
    }
    func prepareToTerminate()->Bool {true}
}
#endif

@MainActor final class DesktopUpdateAppDelegate:NSObject,NSApplicationDelegate {
    func applicationWillTerminate(_ notification:Notification) {DiagnosticsCenter.shared.cleanShutdown()}
    weak var updates:DesktopUpdates?
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {guard let updates else {return .terminateNow};return updates.prepareToTerminate() ? .terminateNow:.terminateCancel}
}
struct DesktopUpdateCommands:Commands {
    @Bindable var updates:DesktopUpdates
    var body:some Commands {
        CommandGroup(after:.appInfo) {
            Button(updates.availableVersion.map {"Update to \($0)…"} ?? "Check for Updates…") {updates.check()}
            Toggle("Automatically Check for Updates",isOn:Binding(get:{updates.automaticChecks},set:{updates.automaticChecks=$0})).disabled(!updates.isDirect)
        }
    }
}
#endif
