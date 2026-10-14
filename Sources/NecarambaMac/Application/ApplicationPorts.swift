import Foundation
import NecarambaCore

public protocol ApplicationRuleStore: WordRuleStore, AppRuleStore {
    func legacyWords() throws -> [WordRule]
    func runtimeWordExclusions() throws -> Set<String>
    func exportArchive() throws -> Data
    func importArchive(_ data: Data, preferences: Data?) throws
    func preferencesData() throws -> Data?
    func savePreferences(_ data: Data) throws
}

@MainActor public protocol ApplicationPreferences: AnyObject {
    var settings: StoredPreferencesV1 { get }
    var snapshot: PreferencesSnapshot { get }
    func replace(_ value: PreferencesSnapshot) throws
    func setLoginPreferred(_ value: Bool) throws
    func setSelectedColor(_ value: Int) throws
    func setAuto(_ value: Bool) throws
    func adoptCommittedSettings(_ value: StoredPreferencesV1) throws
}

public protocol ApplicationSound: AnyObject {
    var customSoundURL: URL? { get }
    func importSound(from source: URL) throws -> URL
    func reset() throws
    func setEnabled(_ value: Bool)
    func playCorrection(committedID: UUID)
}
public protocol ApplicationHeader: AnyObject {
    func importImage(data: Data) throws
    func loadImageData() throws -> Data?
    func remove() throws
}
public protocol ApplicationStatistics: AnyObject {
    var totals: [CounterKind: Int] { get }
    func recordCommitted(id: UUID, kind: CounterKind, day: String) throws
    func reset() throws
}
@MainActor public protocol ApplicationLogin: AnyObject {
    var status: LoginStatus { get }
    func refresh()
    func setEnabled(_ value: Bool) throws
}

public enum ApplicationFileKind { case application, audio, json }
@MainActor public protocol ApplicationFiles {
    func choose(_ kind: ApplicationFileKind) async -> URL?
    func read(_ url: URL, maximumBytes: Int) throws -> Data
    func save(_ data: Data, name: String) async throws
}
public struct SelectedApplication {
    public let bundleID: String
    public let displayName: String
    public init(bundleID: String, displayName: String) {
        self.bundleID = bundleID; self.displayName = displayName
    }
}
public protocol ApplicationSelection {
    func identify(_ url: URL) -> SelectedApplication?
}
public struct ApplicationThumbnail {
    public let bytes: Data
    public let width: Int
    public let height: Int
    public init(bytes: Data, width: Int, height: Int) {
        self.bytes = bytes; self.width = width; self.height = height
    }
}
public protocol ApplicationThumbnailer {
    func thumbnail(from data: Data) throws -> ApplicationThumbnail?
}

extension SQLiteStore: ApplicationRuleStore {}
extension PreferencesController: ApplicationPreferences {}
extension SoundStore: ApplicationSound {}
extension HeaderImageStore: ApplicationHeader {}
extension StatisticsStore: ApplicationStatistics {}
extension LoginController: ApplicationLogin {}
