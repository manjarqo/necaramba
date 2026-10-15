import Foundation
import NecarambaCore

/// Application use cases compose native domain ports. Flutter transport stays outside this type.
@MainActor public final class ApplicationServices {
    public let rules: any ApplicationRuleStore
    public let preferences: any ApplicationPreferences
    public let sound: any ApplicationSound
    public let header: any ApplicationHeader
    public let statistics: any ApplicationStatistics
    public let login: any ApplicationLogin
    public let permissions: PermissionReading
    private let version: String
    public var onRefreshCapabilities: (() -> Void)?
    public var onRulesChanged: (() -> Void)?
    public var externalCommand: ((String, [String:Any]) async throws -> [String:Any])?
    public var runtimeRunning = false
    public var runtimeIsRunning: (() -> Bool)?
    public var automaticReady = false
    public var modelVersion: String = "0"
    public var modelState = "idle"
    public var modelLastChecked: String?
    public var licenseState = "unavailable"
    public var licenseExpiresAt: String?
    public var onChanged: (() -> Void)?
    private var dropHandles: [String:(Date,Data)] = [:]
    private var wordRows: [WordRule] = []
    private var legacyRows: [WordRule] = []
    private var appRows: [AppRule] = []
    private var hasHeaderImage = false
    private let files: any ApplicationFiles
    private let appSelection: any ApplicationSelection
    private let thumbnailer: any ApplicationThumbnailer

    public init(rules: any ApplicationRuleStore, preferences: any ApplicationPreferences,
                sound: any ApplicationSound, header: any ApplicationHeader,
                statistics: any ApplicationStatistics, login: any ApplicationLogin,
                permissions: PermissionReading, files: any ApplicationFiles,
                appSelection: any ApplicationSelection, thumbnailer: any ApplicationThumbnailer,
                version: String = "development") throws {
        self.rules = rules; self.preferences = preferences; self.sound = sound
        self.header = header; self.statistics = statistics; self.login = login
        self.permissions = permissions; self.files = files; self.version = version
        self.appSelection = appSelection; self.thumbnailer = thumbnailer
        wordRows = try rules.words(); legacyRows = try rules.legacyWords(); appRows = try rules.apps()
        hasHeaderImage = try header.loadImageData() != nil
    }
    public func snapshot() -> [String:Any] {
        let p = permissions.current()
        let running = runtimeIsRunning?() ?? runtimeRunning
        let status: String
        if p.secureInput { status = "secureInput" }
        else if !p.listen || !p.post || !p.ax { status = "permissionRequired" }
        else if !preferences.snapshot.autoEnabled { status = "off" }
        else if running && automaticReady { status = "active" }
        else if modelState == "failed" { status = "unavailable" }
        else if !running { status = "starting" }
        else if modelVersion == "0" && (modelState == "idle" || modelState == "checking") { status = "starting" }
        else { status = "unavailable" }
        let words = wordRows
        let legacy = legacyRows
        func word(_ value:WordRule,_ legacy:Bool)->[String:Any] {
            ["id":value.id.uuidString,"normalized":value.normalized,"original":value.original,
             "createdAt":Self.iso(Date(timeIntervalSince1970:Double(value.createdAt))),"legacy":legacy]
        }
        let apps = appRows.map { ["bundleID":$0.bundleID,"displayName":$0.displayName,"mode":$0.mode.rawValue] }
        let stats = Dictionary(uniqueKeysWithValues:statistics.totals.map { ($0.key.rawValue,$0.value) })
        let loginStatus:String
        switch login.status { case .enabled:loginStatus="enabled"; case .disabled:loginStatus="disabled"; case .requiresApproval:loginStatus="requiresApproval"; case .unavailable:loginStatus="unavailable" }
        return ["preferences":Self.flags(preferences.snapshot),
                "capabilities":["listen":p.listen,"post":p.post,"axTrusted":p.ax,"secureInput":p.secureInput],
                "status":status,"words":words.map{word($0,false)}+legacy.map{word($0,true)},"apps":apps,
                "model":["version":modelVersion,"state":modelState,"lastChecked":modelLastChecked as Any? ?? NSNull()],
                "license":["state":licenseState,"expiresAt":licenseExpiresAt as Any? ?? NSNull()],
                "statistics":stats,
                "appearance":["colorIndex":preferences.settings.selectedColor,"hasCustomSound":sound.customSoundURL != nil,"hasHeaderImage":hasHeaderImage],
                "login":["enabled":login.status == .enabled,"status":loginStatus]]
    }
    public func execute(_ method:String, arguments a:[String:Any]) async throws -> [String:Any] {
        switch method {
        case "setPreferences":
            guard let patch = a["patch"] as? [String:Any], !patch.isEmpty else { throw invalid() }
            var flags = Self.flags(preferences.snapshot)
            var changes: [String: Bool] = [:]
            for (key,value) in patch {
                guard flags[key] != nil, let number=value as? NSNumber, CFGetTypeID(number)==CFBooleanGetTypeID() else { throw invalid() }
                changes[key]=number.boolValue
            }
            let shortcuts = ["singleShiftEnabled", "altShiftEnabled", "controlShiftEnabled", "commandShiftEnabled"]
            let enabled = shortcuts.filter { changes[$0] == true }
            guard enabled.count <= 1 else { throw invalid() }
            // Also support older clients sending only the single-Shift toggle.
            if let selected = enabled.first {
                for key in shortcuts { flags[key] = key == selected }
            }
            flags.merge(changes) { _, new in new }
            var encoded: [String: Any] = flags
            encoded["layoutSwitchShortcut"] = flags["singleShiftEnabled"] == true ? "singleShift" :
                flags["altShiftEnabled"] == true ? "altShift" :
                flags["controlShiftEnabled"] == true ? "controlShift" :
                flags["commandShiftEnabled"] == true ? "commandShift" : "disabled"
            try preferences.replace(JSONDecoder().decode(PreferencesSnapshot.self,from:JSONSerialization.data(withJSONObject:encoded)))
        case "addWord":
            guard try rules.words().count + rules.legacyWords().count < 10000 else { throw invalid() }
            do { _ = try rules.addWord(try string(a,"text"),at:Int64(Date().timeIntervalSince1970)); try refreshRules() }
            catch { throw NativeCommandFailure("invalidArgument") }
        case "deleteWord":
            guard let id=UUID(uuidString:try string(a,"id")) else { throw invalid() }
            try rules.deleteWord(id:id); try refreshRules()
        case "clearWords":
            guard try boolean(a,"confirmed") else { throw NativeCommandFailure("cancelled") }
            try rules.clearWords(); try refreshRules()
        case "chooseApp":
            guard let url=await files.choose(.application),let selected=appSelection.identify(url) else { throw NativeCommandFailure("cancelled") }
            try mutationGuard(a)
            try rules.setApp(AppRule(bundleID:selected.bundleID,displayName:selected.displayName,bookmark:nil,mode:.deny,updatedAt:Int64(Date().timeIntervalSince1970))); try refreshRules()
        case "setAppMode":
            let id=try string(a,"bundleID")
            guard let mode=AppRuleMode(rawValue:try string(a,"mode")),let old=try rules.apps().first(where:{$0.bundleID==id}) else { throw invalid() }
            try rules.setApp(AppRule(bundleID:id,displayName:old.displayName,bookmark:old.bookmark,mode:mode,updatedAt:Int64(Date().timeIntervalSince1970))); try refreshRules()
        case "deleteApp": try rules.deleteApp(bundleID:try string(a,"bundleID")); try refreshRules()
        case "requestPermission":
            guard let kind=PermissionKind(rawValue:try string(a,"kind")) else { throw invalid() }
            permissions.request(kind)
        case "refreshCapabilities": login.refresh(); onRefreshCapabilities?()
        case "setLoginEnabled":
            let enabled=try boolean(a,"enabled")
            let previous=login.status
            try login.setEnabled(enabled)
            do { try preferences.setLoginPreferred(enabled) }
            catch {
                // Legacy ServiceManagement cannot report status. A successful OS call may
                // have changed registration even when the status reads unavailable again.
                guard previous == .enabled || previous == .disabled else {
                    onChanged?(); throw NativeCommandFailure("partialFailure")
                }
                if login.status != previous {
                    do { try login.setEnabled(previous == .enabled) }
                    catch { onChanged?(); throw NativeCommandFailure("partialFailure") }
                    guard login.status == previous else { onChanged?(); throw NativeCommandFailure("partialFailure") }
                }
                throw error
            }
        case "setHeaderColor":
            guard let index=a["index"] as? Int else { throw invalid() }; try preferences.setSelectedColor(index)
        case "importHeaderImage":
            let handle=try string(a,"handle")
            guard let (expires,data)=dropHandles.removeValue(forKey:handle), expires>Date() else { throw invalid() }
            try header.importImage(data:data); hasHeaderImage = true
        case "removeHeaderImage": try header.remove(); hasHeaderImage = false
        case "getThumbnail": return try thumbnail()
        case "chooseSound":
            guard let url=await files.choose(.audio) else { throw NativeCommandFailure("cancelled") }
            try mutationGuard(a)
            _ = try sound.importSound(from:url)
        case "resetSound": try sound.reset()
        case "resetCounters":
            guard try boolean(a,"confirmed") else { throw NativeCommandFailure("cancelled") }; try statistics.reset()
        case "exportArchive":
            let archive = ApplicationArchiveV1(rules:try JSONDecoder().decode(RuleArchiveV1.self,from:rules.exportArchive()),preferences:preferences.settings)
            try await files.save(JSONEncoder().encode(archive),name:"necaramba-rules.json")
        case "importArchive":
            guard let url=await files.choose(.json) else { throw NativeCommandFailure("cancelled") }
            let data=try files.read(url,maximumBytes:10*1024*1024)
            guard data.count<=10*1024*1024 else { throw invalid() }
            let archive=try JSONDecoder().decode(ApplicationArchiveV1.self,from:data)
            guard archive.schemaVersion == 1,archive.rules.words.count+archive.rules.legacyWords.count<=10000,archive.rules.apps.count<=1000 else { throw invalid() }
            try archive.preferences.validate()
            try mutationGuard(a)
            try rules.importArchive(JSONEncoder().encode(archive.rules),preferences:JSONEncoder().encode(archive.preferences))
            try preferences.adoptCommittedSettings(archive.preferences)
            try refreshRules()
        case "exportDiagnostics":
            let p=permissions.current()
            let report:[String:Any] = ["version":version,
                "os":ProcessInfo.processInfo.operatingSystemVersionString,"modelVersion":modelVersion,
                "permissions":["listen":p.listen,"post":p.post,"ax":p.ax,"secureInput":p.secureInput],
                "reasonCodes":["qualificationPending"]]
            try await files.save(JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]),name:"necaramba-diagnostics.json")
        default:
            guard let externalCommand else { throw NativeCommandFailure("unavailable") }
            return try await externalCommand(method,a)
        }
        return [:]
    }
    private func refreshRules() throws {
        let words=try rules.words(), legacy=try rules.legacyWords(), apps=try rules.apps()
        wordRows=words; legacyRows=legacy; appRows=apps; onRulesChanged?()
    }
    /// Only the native drop view calls this, never an arbitrary file path from Dart.
    public func registerHeaderDrop(_ data:Data)->String? {
        guard data.count<=10*1024*1024 else { return nil }
        dropHandles=dropHandles.filter{$0.value.0>Date()}
        guard dropHandles.count<4 else { return nil }
        let handle=UUID().uuidString; dropHandles[handle]=(Date().addingTimeInterval(60),data); return handle
    }
    public func clearHeaderDrops() { dropHandles.removeAll() }
    public func thumbnail() throws -> [String:Any] {
        guard let data=try header.loadImageData(),let image=try thumbnailer.thumbnail(from:data) else {
            return ["bytes":Data(),"width":0,"height":0]
        }
        return ["bytes":image.bytes,"width":image.width,"height":image.height]
    }
    private func mutationGuard(_ arguments:[String:Any]) throws {
        try (arguments["__nativeMutationGuard"] as? (() throws -> Void))?()
    }
    private func invalid()->NativeCommandFailure { NativeCommandFailure("invalidArgument") }
    private func string(_ a:[String:Any],_ key:String) throws -> String { guard let s=a[key] as? String,!s.isEmpty,s.utf8.count<=8192 else { throw invalid() }; return s }
    private func boolean(_ a:[String:Any],_ key:String) throws -> Bool { guard let n=a[key] as? NSNumber,CFGetTypeID(n)==CFBooleanGetTypeID() else { throw invalid() }; return n.boolValue }
    public static func flags(_ p:PreferencesSnapshot)->[String:Bool] {
        ["autoEnabled":p.autoEnabled,"typoEnabled":p.typoEnabled,"yoEnabled":p.yoEnabled,"singleShiftEnabled":p.singleShiftEnabled,
         "altShiftEnabled":p.layoutSwitchShortcut == .altShift,"controlShiftEnabled":p.layoutSwitchShortcut == .controlShift,
         "commandShiftEnabled":p.layoutSwitchShortcut == .commandShift,
         "optionEnabled":p.optionEnabled,"splitShiftEnabled":p.splitShiftEnabled,"plainPasteEnabled":p.plainPasteEnabled,"soundEnabled":p.soundEnabled]
    }
    private static func iso(_ date:Date)->String { ISO8601DateFormatter().string(from:date) }
}
