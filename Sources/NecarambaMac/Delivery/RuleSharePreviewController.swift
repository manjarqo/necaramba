import Foundation
import NecarambaCore
/// Bridge value consumed by the Flutter confirmation dialog. No native dialog or automatic submit.
public struct RuleSharePreviewController {
    public let endpointHost: String?
    public init(endpoint: URL?) { endpointHost = endpoint?.scheme == "https" ? endpoint?.host : nil }
    public func fields(_ payload: RuleSharePayload) throws -> [String: Any] {
        let p = try payload.validated()
        return ["word": p.word, "language": p.language.rawValue, "modelVersion": String(p.modelVersion), "feedback": p.feedback ?? "", "endpointHost": endpointHost ?? "unavailable"]
    }
}
