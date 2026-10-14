import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import NecarambaCore

@MainActor public struct MacApplicationFiles: ApplicationFiles {
    private let customChooser: (([UTType]) async -> URL?)?
    public init(chooseFile: (([UTType]) async -> URL?)? = nil) { customChooser = chooseFile }
    public func choose(_ kind: ApplicationFileKind) async -> URL? {
        let types: [UTType]
        switch kind { case .application: types = [.applicationBundle]; case .audio: types = [.audio]; case .json: types = [.json] }
        if let customChooser { return await customChooser(types) }
        let panel = NSOpenPanel(); panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        return await withCheckedContinuation { continuation in
            panel.begin { response in continuation.resume(returning: response == .OK ? panel.url : nil) }
        }
    }
    public func read(_ url: URL, maximumBytes: Int) throws -> Data {
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        let data = try file.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else { throw NativeCommandFailure("invalidArgument") }
        return data
    }
    public func save(_ data: Data, name: String) async throws {
        let panel = NSSavePanel(); panel.nameFieldStringValue = name; panel.allowedContentTypes = [.json]
        let response = await withCheckedContinuation { continuation in panel.begin { continuation.resume(returning: $0) } }
        guard response == .OK, let url = panel.url else { throw NativeCommandFailure("cancelled") }
        try data.write(to: url, options: .atomic)
    }
}
public struct MacApplicationSelection: ApplicationSelection {
    public init() {}
    public func identify(_ url: URL) -> SelectedApplication? {
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return nil }
        let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? url.deletingPathExtension().lastPathComponent
        return SelectedApplication(bundleID: id, displayName: name)
    }
}
public struct MacApplicationThumbnailer: ApplicationThumbnailer {
    public init() {}
    public func thumbnail(from data: Data) throws -> ApplicationThumbnail? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0,
                [kCGImageSourceCreateThumbnailFromImageAlways: true,
                 kCGImageSourceThumbnailMaxPixelSize: 256] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let target = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            throw NativeCommandFailure("invalidArgument")
        }
        CGImageDestinationAddImage(target, image, nil)
        guard CGImageDestinationFinalize(target), output.length <= 256 * 1024 else {
            throw NativeCommandFailure("invalidArgument")
        }
        return ApplicationThumbnail(bytes: output as Data, width: image.width, height: image.height)
    }
}

@MainActor public enum ApplicationComposition {
    public static func make(directory: URL, defaults: UserDefaults, permissions: PermissionReading,
                            loginBackend: LoginBackend, onPreferences: @escaping (PreferencesSnapshot) -> Void,
                            defaultSoundURL: URL? = nil, preferencesWrite: ((Data) throws -> Void)? = nil,
                            chooseFile: (([UTType]) async -> URL?)? = nil) throws -> ApplicationServices {
        try ApplicationServices(directory: directory, defaults: defaults, permissions: permissions,
            loginBackend: loginBackend, onPreferences: onPreferences, defaultSoundURL: defaultSoundURL,
            preferencesWrite: preferencesWrite, chooseFile: chooseFile)
    }
}

@MainActor public extension ApplicationServices {
    convenience init(directory: URL, defaults: UserDefaults, permissions: PermissionReading,
                     loginBackend: LoginBackend, onPreferences: @escaping (PreferencesSnapshot) -> Void,
                     defaultSoundURL: URL? = nil, preferencesWrite: ((Data) throws -> Void)? = nil,
                     chooseFile: (([UTType]) async -> URL?)? = nil) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let rules = try SQLiteStore(url: directory.appendingPathComponent("rules.sqlite"))
        let preferences = try PreferencesController(defaults: defaults, storedData: rules.preferencesData(),
            persist: { bytes in try preferencesWrite?(bytes); try rules.savePreferences(bytes) }, publish: onPreferences)
        try self.init(rules: rules, preferences: preferences,
            sound: SoundStore(directory: directory.appendingPathComponent("Sounds"), defaultSoundURL: defaultSoundURL),
            header: HeaderImageStore(directory: directory.appendingPathComponent("Appearance")),
            statistics: StatisticsStore(directory: directory.appendingPathComponent("Statistics")),
            login: LoginController(backend: loginBackend), permissions: permissions,
            files: MacApplicationFiles(chooseFile: chooseFile), appSelection: MacApplicationSelection(),
            thumbnailer: MacApplicationThumbnailer(), version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development")
    }
}
