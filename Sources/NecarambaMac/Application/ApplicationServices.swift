import AppKit
import UniformTypeIdentifiers
import ImageIO
import NecarambaCore

/// Application use cases compose native domain ports. Flutter transport stays outside this type.
@MainActor public final class ApplicationServices {
    public let rules: SQLiteStore
    public let preferences: PreferencesController
    public let sound: SoundStore
    public let header: HeaderImageStore
    public let statistics: StatisticsStore
    public let login: LoginController
    public let permissions: PermissionReading
    public var onRulesChanged: (() -> Void)?
    public var externalCommand: ((String, [String:Any]) async throws -> [String:Any])?
    public var runtimeRunning = false
    public var automaticQualified = false
    public var modelVersion: String = "0"
    public var modelState = "idle"
    public var modelLastChecked: String?
    public var licenseState = "unavailable"
    public var licenseExpiresAt: String?
    public var onChanged: (() -> Void)?
    private var dropHandles: [String:(Date,Data)] = [:]
    private let directory: URL
    private var wordRows: [WordRule] = []
    private var legacyRows: [WordRule] = []
    private var appRows: [AppRule] = []
    private var hasHeaderImage = false
    private let chooseFile: (([UTType]) async -> URL?)?

    public init(directory:URL, defaults:UserDefaults, permissions:PermissionReading,
                loginBackend:LoginBackend, onPreferences:@escaping (PreferencesSnapshot)->Void,
                defaultSoundURL:URL? = nil, preferencesWrite: ((Data) throws -> Void)? = nil,
                chooseFile: (([UTType]) async -> URL?)? = nil) throws {
        self.directory = directory; self.permissions = permissions
        self.chooseFile = chooseFile
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        rules = try SQLiteStore(url:directory.appendingPathComponent("rules.sqlite"))
        let store = rules
        preferences = try PreferencesController(defaults:defaults,storedData:store.preferencesData(),persist:{ bytes in
            try preferencesWrite?(bytes); try store.savePreferences(bytes)
        },publish:onPreferences)
        sound = SoundStore(directory:directory.appendingPathComponent("Sounds"),defaultSoundURL:defaultSoundURL)
        header = try HeaderImageStore(directory:directory.appendingPathComponent("Appearance"))
        statistics = try StatisticsStore(directory:directory.appendingPathComponent("Statistics"))
        login = LoginController(backend:loginBackend)
        wordRows = try rules.words(); legacyRows = try rules.legacyWords(); appRows = try rules.apps()
        hasHeaderImage = try header.loadImageData() != nil
    }
    public func snapshot() -> [String:Any] {
        let p = permissions.current()
        let status = p.secureInput ? "secureInput" : (!p.listen || !p.post ? "permissionRequired" : (preferences.snapshot.autoEnabled && runtimeRunning && automaticQualified ? "active" : "off"))
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
            for (key,value) in patch {
                guard flags[key] != nil, let number=value as? NSNumber, CFGetTypeID(number)==CFBooleanGetTypeID() else { throw invalid() }
                flags[key]=number.boolValue
            }
            try preferences.replace(JSONDecoder().decode(PreferencesSnapshot.self,from:JSONSerialization.data(withJSONObject:flags)))
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
            guard let url=await choose(types:[.applicationBundle]),let bundle=Bundle(url:url),let id=bundle.bundleIdentifier else { throw NativeCommandFailure("cancelled") }
            try mutationGuard(a)
            let name=bundle.object(forInfoDictionaryKey:"CFBundleDisplayName") as? String ?? url.deletingPathExtension().lastPathComponent
            try rules.setApp(AppRule(bundleID:id,displayName:name,bookmark:nil,mode:.deny,updatedAt:Int64(Date().timeIntervalSince1970))); try refreshRules()
        case "setAppMode":
            let id=try string(a,"bundleID")
            guard let mode=AppRuleMode(rawValue:try string(a,"mode")),let old=try rules.apps().first(where:{$0.bundleID==id}) else { throw invalid() }
            try rules.setApp(AppRule(bundleID:id,displayName:old.displayName,bookmark:old.bookmark,mode:mode,updatedAt:Int64(Date().timeIntervalSince1970))); try refreshRules()
        case "deleteApp": try rules.deleteApp(bundleID:try string(a,"bundleID")); try refreshRules()
        case "requestPermission":
            guard let kind=PermissionKind(rawValue:try string(a,"kind")) else { throw invalid() }
            permissions.request(kind)
        case "refreshCapabilities": login.refresh()
        case "setLoginEnabled":
            let enabled=try boolean(a,"enabled")
            let previous=login.status
            try login.setEnabled(enabled)
            do { try preferences.setLoginPreferred(enabled) }
            catch {
                if login.status != previous {
                    guard previous == .enabled || previous == .disabled else {
                        onChanged?(); throw NativeCommandFailure("partialFailure")
                    }
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
            guard let url=await choose(types:[.audio]) else { throw NativeCommandFailure("cancelled") }
            try mutationGuard(a)
            _ = try sound.importSound(from:url)
        case "resetSound": try sound.reset()
        case "resetCounters":
            guard try boolean(a,"confirmed") else { throw NativeCommandFailure("cancelled") }; try statistics.reset()
        case "exportArchive":
            let archive = ApplicationArchiveV1(rules:try JSONDecoder().decode(RuleArchiveV1.self,from:rules.exportArchive()),preferences:preferences.settings)
            try await save(JSONEncoder().encode(archive),name:"necaramba-rules.json")
        case "importArchive":
            guard let url=await choose(types:[.json]) else { throw NativeCommandFailure("cancelled") }
            let file=try FileHandle(forReadingFrom:url); defer { try? file.close() }
            let data=try file.read(upToCount:10*1024*1024+1) ?? Data()
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
            let report:[String:Any] = ["version":Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "development",
                "os":ProcessInfo.processInfo.operatingSystemVersionString,"modelVersion":modelVersion,
                "permissions":["listen":p.listen,"post":p.post,"ax":p.ax,"secureInput":p.secureInput],
                "reasonCodes":["qualificationPending"]]
            try await save(JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]),name:"necaramba-diagnostics.json")
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
        guard let data=try header.loadImageData(),let source=CGImageSourceCreateWithData(data as CFData,nil),
              let image=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:256] as CFDictionary) else {
            return ["bytes":Data(),"width":0,"height":0]
        }
        let output=NSMutableData()
        guard let target=CGImageDestinationCreateWithData(output,UTType.png.identifier as CFString,1,nil) else { throw invalid() }
        CGImageDestinationAddImage(target,image,nil)
        guard CGImageDestinationFinalize(target),output.length<=256*1024 else { throw invalid() }
        return ["bytes":output as Data,"width":image.width,"height":image.height]
    }
    private func choose(types:[UTType]) async -> URL? {
        if let chooseFile { return await chooseFile(types) }
        let panel=NSOpenPanel(); panel.allowedContentTypes=types; panel.allowsMultipleSelection=false; panel.canChooseDirectories=false
        return await withCheckedContinuation { continuation in panel.begin { response in continuation.resume(returning:response == .OK ? panel.url:nil) } }
    }
    private func mutationGuard(_ arguments:[String:Any]) throws {
        try (arguments["__nativeMutationGuard"] as? (() throws -> Void))?()
    }
    private func save(_ data:Data,name:String) async throws {
        let panel=NSSavePanel(); panel.nameFieldStringValue=name; panel.allowedContentTypes=[.json]
        let response=await withCheckedContinuation { continuation in panel.begin { continuation.resume(returning:$0) } }
        guard response == .OK,let url=panel.url else { throw NativeCommandFailure("cancelled") }
        try data.write(to:url,options:.atomic)
    }
    private func invalid()->NativeCommandFailure { NativeCommandFailure("invalidArgument") }
    private func string(_ a:[String:Any],_ key:String) throws -> String { guard let s=a[key] as? String,!s.isEmpty,s.utf8.count<=8192 else { throw invalid() }; return s }
    private func boolean(_ a:[String:Any],_ key:String) throws -> Bool { guard let n=a[key] as? NSNumber,CFGetTypeID(n)==CFBooleanGetTypeID() else { throw invalid() }; return n.boolValue }
    public static func flags(_ p:PreferencesSnapshot)->[String:Bool] {
        ["autoEnabled":p.autoEnabled,"typoEnabled":p.typoEnabled,"yoEnabled":p.yoEnabled,"singleShiftEnabled":p.singleShiftEnabled,
         "optionEnabled":p.optionEnabled,"splitShiftEnabled":p.splitShiftEnabled,"plainPasteEnabled":p.plainPasteEnabled,"soundEnabled":p.soundEnabled]
    }
    private static func iso(_ date:Date)->String { ISO8601DateFormatter().string(from:date) }
}
