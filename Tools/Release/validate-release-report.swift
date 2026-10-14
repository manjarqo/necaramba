#!/usr/bin/env swift
import Foundation
struct Manifest:Decodable { let schemaVersion:Int; let required:[String] }
struct Result:Decodable { let status:String; let evidencePath:String; let evidenceSHA256:String?; let buildSHA:String; let architecture:String; let osBuild:String }
struct Report:Decodable { let schemaVersion:Int; let manifest:String; let buildSHA:String; let results:[String:Result] }
func fail(_ message:String)->Never { FileHandle.standardError.write(Data((message+"\n").utf8)); exit(1) }
guard CommandLine.arguments.count==2 else { fail("Usage: validate-release-report.swift report.json") }
do {
 let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).standardizedFileURL
 let reportURL=URL(fileURLWithPath:CommandLine.arguments[1],relativeTo:root).standardizedFileURL
 let report=try JSONDecoder().decode(Report.self,from:Data(contentsOf:reportURL))
 let manifest=try JSONDecoder().decode(Manifest.self,from:Data(contentsOf:URL(fileURLWithPath:report.manifest,relativeTo:root)))
 guard report.schemaVersion==1,manifest.schemaVersion==1,!manifest.required.isEmpty,Set(manifest.required).count==manifest.required.count else { fail("Invalid report or manifest") }
 guard report.buildSHA.range(of:"^[0-9a-f]{40,64}$",options:.regularExpression) != nil else { fail("Missing final artifact build SHA") }
 var missing=[String]()
 for key in manifest.required {
  guard let r=report.results[key],r.status=="passed",r.buildSHA==report.buildSHA,!r.osBuild.isEmpty,!r.evidencePath.isEmpty else { missing.append(key); continue }
  let fields=key.split(separator:"/"); guard fields.count==5,String(fields[1])==r.architecture else { missing.append(key); continue }
  let evidence=URL(fileURLWithPath:r.evidencePath,relativeTo:root).standardizedFileURL.resolvingSymlinksInPath()
  guard evidence.path.hasPrefix(root.path+"/"),FileManager.default.fileExists(atPath:evidence.path),let digest=r.evidenceSHA256,digest.range(of:"^[0-9a-f]{64}$",options:.regularExpression) != nil else { missing.append(key);continue }
  let process=Process();process.executableURL=URL(fileURLWithPath:"/usr/bin/shasum");process.arguments=["-a","256",evidence.path];let output=Pipe();process.standardOutput=output;try process.run();let bytes=output.fileHandleForReading.readDataToEndOfFile();process.waitUntilExit()
  guard process.terminationStatus==0,String(data:bytes,encoding:.utf8)?.split(separator:" ").first.map(String.init)==digest else { missing.append(key);continue }
 }
 guard missing.isEmpty else { fail("Release blocked: \(missing.count) required tuples missing/invalid: \(missing.prefix(8).joined(separator:", "))") }
 print("Release evidence gate PASS")
} catch { fail("Invalid release evidence: \(type(of:error))") }
