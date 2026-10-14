import AppKit
import NecarambaCore

/// Transport configuration belongs to the application's signed bundle, never Flutter input.
public struct DeliveryConfiguration {
    public let rulesEndpoint:URL?
    public let shareEndpoint:URL?
    public let productIDs:Set<String>
    public let bundleID:String
    public init(rulesEndpoint:URL?=nil,shareEndpoint:URL?=nil,productIDs:Set<String>=[],bundleID:String) {
        self.rulesEndpoint=rulesEndpoint;self.shareEndpoint=shareEndpoint;self.productIDs=productIDs;self.bundleID=bundleID
    }
}
private final class MainActorRuleConsumer:RuleSnapshotConsumer {
    private let installBlock:@MainActor (RuleSnapshot)->Void
    init(_ install:@escaping @MainActor (RuleSnapshot)->Void) { installBlock=install }
    func install(_ snapshot:RuleSnapshot) { Task { @MainActor in installBlock(snapshot) } }
}

/// Native delivery orchestration. The input core keeps working when optional services are unavailable.
@MainActor public final class ApplicationDeliveryServices {
    private weak var application:ApplicationServices?
    private let configuration:DeliveryConfiguration
    private let share:RuleShareCoordinator
    private let licensing:LicensingAdapter
    private var previewID:String?
    private var previewExpiry:Date?
    private var updater:RuleUpdateCoordinator?
    private var statusTask:Task<Void,Never>?
    public init(application:ApplicationServices,configuration:DeliveryConfiguration,licensing:LicensingAdapter?=nil,shareTransport:RuleShareTransport?=nil) {
        self.application=application; self.configuration=configuration
        share=RuleShareCoordinator(transport:shareTransport ?? HTTPSRuleShareTransport(endpoint:configuration.shareEndpoint,allowedHost:configuration.shareEndpoint?.host ?? ""))
        self.licensing=licensing ?? StoreKitLicensingAdapter(productIDs:configuration.productIDs,bundleID:configuration.bundleID)
    }
    public func start(bundle:Bundle,root:URL,install:@escaping @MainActor (RuleSnapshot,@escaping (UInt64)->Void)->Void) async {
        applyLicense(await licensing.current())
        do {
            guard let resources=bundle.resourceURL else { throw NativeCommandFailure("unavailable") }
            let development=(bundle.object(forInfoDictionaryKey:"NecarambaDevelopmentRules") as? String)=="YES"
            let directory=resources.appendingPathComponent(development ? "Rules/Development" : "Rules/Production")
            let keyName=development ? "DevelopmentTrustedRuleKeys.json" : "TrustedRuleKeys.json"
            let version=bundle.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "1.0.0"
            // Disk reads, signature verification and lexicon decoding never run on the main/input executor.
            let loaded=try await Task.detached { () throws -> (RulePackage,RulePackageVerifier) in
                let encoded=try JSONDecoder().decode([String:String].self,from:Data(contentsOf:directory.appendingPathComponent(keyName)))
                var keys:[String:Data]=[:]
                for (id,value) in encoded { guard let bytes=Data(base64Encoded:value),bytes.count==32 else { throw NativeCommandFailure("unavailable") };keys[id]=bytes }
                guard !keys.isEmpty,development || !keys.keys.contains(where:{$0.contains("development") || $0.contains("test")}) else { throw NativeCommandFailure("unavailable") }
                let package=RulePackage(manifest:try Data(contentsOf:directory.appendingPathComponent("manifest.json")),signature:try Data(contentsOf:directory.appendingPathComponent("signature.ed25519")),payload:try Data(contentsOf:directory.appendingPathComponent("payload.json")))
                return (package,RulePackageVerifier(trustedKeys:keys,appVersion:version))
            }.value
            try Task.checkCancellation()
            let consumer=MainActorRuleConsumer { [weak self] snapshot in
                install(snapshot) { [weak self] installedVersion in
                    self?.application?.modelVersion=String(installedVersion)
                    self?.application?.modelState="current"
                    self?.application?.onChanged?()
                }
            }
            let coordinator=RuleUpdateCoordinator(store:RuleSlotStore(root:root,verifier:loaded.1),bundled:loaded.0,consumer:consumer,downloader:RuleDownloader(allowedHost:configuration.rulesEndpoint?.host ?? ""),endpoint:configuration.rulesEndpoint)
            updater=coordinator
            statusTask=Task { [weak self] in
                for await status in await coordinator.statuses() {
                    guard !Task.isCancelled,let self else { return }
                    switch status {
                    case .idle:self.application?.modelState="idle"
                    case .checking:self.application?.modelState="checking"
                    case .current(let version):self.application?.modelState=self.application?.modelVersion==String(version) ? "current" : "checking"
                    case .failed:self.application?.modelState="failed"
                    }
                    self.application?.onChanged?()
                }
            }
            await coordinator.start()
        } catch { application?.modelState="failed";application?.onChanged?() }
    }
    public func execute(_ method:String,arguments:[String:Any]) async throws -> [String:Any] {
        switch method {
        case "checkRules":
            guard configuration.rulesEndpoint != nil,let updater else { throw NativeCommandFailure("unavailable") }
            await updater.checkNow();application?.modelLastChecked=ISO8601DateFormatter().string(from:Date())
        case "previewShare":
            cancelPendingShare()
            guard let endpoint=configuration.shareEndpoint,endpoint.scheme=="https",let host=endpoint.host else { throw NativeCommandFailure("unavailable") }
            guard let word=arguments["word"] as? String,let languageName=arguments["language"] as? String,let language=Language(rawValue:languageName),let version=arguments["modelVersion"] as? String,version==application?.modelVersion,let modelVersion=UInt64(version),arguments["feedback"] == nil || arguments["feedback"] is NSNull || arguments["feedback"] is String else { throw NativeCommandFailure("invalidArgument") }
            let payload=try share.preview(.init(word:word,language:language,modelVersion:modelVersion,feedback:arguments["feedback"] as? String))
            let id=UUID().uuidString;previewID=id;previewExpiry=Date().addingTimeInterval(300)
            return ["previewID":id,"preview":["word":payload.word,"language":payload.language.rawValue,"modelVersion":String(payload.modelVersion),"feedback":payload.feedback as Any? ?? NSNull(),"host":host]]
        case "confirmShare","cancelShare":
            guard let id=arguments["previewID"] as? String,id==previewID else { throw NativeCommandFailure("conflict") }
            let valid=(previewExpiry ?? .distantPast)>Date();previewID=nil;previewExpiry=nil
            if method=="cancelShare" { share.cancel() }
            else { guard valid else { share.cancel();throw NativeCommandFailure("conflict") };try await share.confirm() }
        case "purchase":
            guard let product=arguments["productID"] as? String,configuration.productIDs.contains(product) else { throw NativeCommandFailure("unavailable") }
            switch try await licensing.purchase(productID:product) {
            case .entitled(let value):applyLicense(value)
            case .cancelled:throw NativeCommandFailure("cancelled")
            case .pending:applyLicense(.pending)
            }
        case "restore":applyLicense(try await licensing.restore())
        // Apple documents this account URL: developer.apple.com/documentation/storekit/handling-subscriptions-billing
        case "manageSubscription":
            guard !configuration.productIDs.isEmpty,let url=URL(string:"https://apps.apple.com/account/subscriptions"),NSWorkspace.shared.open(url) else { throw NativeCommandFailure("unavailable") }
        default:throw NativeCommandFailure("unavailable")
        }
        return [:]
    }
    public func cancelPendingShare() { previewID=nil;previewExpiry=nil;share.cancel() }
    public func stop() { statusTask?.cancel();statusTask=nil;if let updater { Task { await updater.stop() } };previewID=nil;share.cancel() }
    private func applyLicense(_ value:EntitlementState) {
        var expiry:Date?
        let state:String
        switch value {
        case .checking:state="checking"
        case .trial(let date):state="trial";expiry=date
        case .active(let date,_):state="active";expiry=date
        case .grace(let date):state="grace";expiry=date
        case .pending:state="pending"
        case .expired:state="expired"
        case .revoked:state="revoked"
        case .unavailable:state="unavailable"
        }
        application?.licenseState=state;application?.licenseExpiresAt=expiry.map{ISO8601DateFormatter().string(from:$0)};application?.onChanged?()
    }
    deinit { statusTask?.cancel() }
}
