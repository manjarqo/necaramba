#!/usr/bin/env swift
import Foundation

struct Manifest: Decodable { let schemaVersion: Int; let required: [String] }
struct Result: Decodable {
    let status: String
    let evidencePath: String
    let evidenceSHA256: String
    let buildSHA: String
    let architecture: String
    let osMajor: String
    let osBuild: String
    let host: String
    let adapter: String
}
struct Evidence: Decodable {
    let tuple: String
    let artifactSHA256: String
    let architecture: String
    let osMajor: String
    let osBuild: String
    let host: String
    let adapter: String
    let status: String
}
struct Report: Decodable {
    let schemaVersion: Int
    let manifest: String
    let artifactPath: String
    let buildSHA: String
    let results: [String: Result]
}
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}
func isSHA(_ value: String) -> Bool {
    value.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
}
func containedFile(_ path: String, root: URL) -> URL? {
    guard !path.isEmpty else { return nil }
    let url = URL(fileURLWithPath: path, relativeTo: root).standardizedFileURL.resolvingSymlinksInPath()
    guard url.path.hasPrefix(root.path + "/"), FileManager.default.isReadableFile(atPath: url.path) else { return nil }
    return url
}
func sha256(_ url: URL) throws -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
    process.arguments = ["-a", "256", url.path]
    let output = Pipe()
    process.standardOutput = output
    try process.run()
    let bytes = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return nil }
    return String(data: bytes, encoding: .utf8)?.split(separator: " ").first.map(String.init)
}

guard CommandLine.arguments.count == 2 else { fail("Usage: validate-release-report.swift report.json") }
do {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).standardizedFileURL
    guard let reportURL = containedFile(CommandLine.arguments[1], root: root) else { fail("Invalid report path") }
    let report = try JSONDecoder().decode(Report.self, from: Data(contentsOf: reportURL))
    guard let manifestURL = containedFile(report.manifest, root: root),
          let artifactURL = containedFile(report.artifactPath, root: root) else { fail("Invalid manifest or artifact path") }
    let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
    guard report.schemaVersion == 1, manifest.schemaVersion == 1, !manifest.required.isEmpty,
          Set(manifest.required).count == manifest.required.count, isSHA(report.buildSHA),
          try sha256(artifactURL) == report.buildSHA else { fail("Invalid report, manifest, or final artifact hash") }
    var missing = [String]()
    for key in manifest.required {
        let fields = key.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 5, fields[1] == "arm64" || fields[1] == "x86_64",
              Int(fields[2]).map({ $0 >= 12 }) == true,
              !fields[3].isEmpty, fields[3] != "qualified-hosts", !fields[4].isEmpty,
              let result = report.results[key], result.status == "passed",
              result.buildSHA == report.buildSHA,
              result.architecture == fields[1], result.osMajor == fields[2],
              !result.osBuild.isEmpty, result.host == fields[3], result.adapter == fields[4],
              isSHA(result.evidenceSHA256),
              let evidenceURL = containedFile(result.evidencePath, root: root),
              try sha256(evidenceURL) == result.evidenceSHA256,
              let evidence = try? JSONDecoder().decode(Evidence.self, from: Data(contentsOf: evidenceURL)),
              evidence.status == "passed", evidence.tuple == key,
              evidence.artifactSHA256 == report.buildSHA,
              evidence.architecture == result.architecture, evidence.osMajor == result.osMajor,
              evidence.osBuild == result.osBuild, evidence.host == result.host,
              evidence.adapter == result.adapter else { missing.append(key); continue }
    }
    guard missing.isEmpty else {
        fail("Release blocked: \(missing.count) required tuples missing/invalid: \(missing.prefix(8).joined(separator: ", "))")
    }
    print("Release evidence gate PASS")
} catch {
    fail("Invalid release evidence: \(type(of: error))")
}
