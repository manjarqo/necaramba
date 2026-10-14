import AppKit
// Expected nesting: Main.app/Contents/Library/LoginItems/Main.LoginHelper.app.
let helper=Bundle.main.bundleURL.standardizedFileURL
let loginItems=helper.deletingLastPathComponent()
let library=loginItems.deletingLastPathComponent()
let contents=library.deletingLastPathComponent()
let mainURL=contents.deletingLastPathComponent()
guard loginItems.lastPathComponent=="LoginItems",library.lastPathComponent=="Library",contents.lastPathComponent=="Contents",mainURL.pathExtension=="app",let mainBundle=Bundle(url:mainURL),let mainID=mainBundle.bundleIdentifier,Bundle.main.bundleIdentifier==mainID+".LoginHelper" else { exit(1) }
if NSRunningApplication.runningApplications(withBundleIdentifier:mainID).isEmpty {
 let configuration=NSWorkspace.OpenConfiguration()
 configuration.activates=false
 configuration.arguments=["--background"]
 let semaphore=DispatchSemaphore(value:0)
 NSWorkspace.shared.openApplication(at:mainURL,configuration:configuration) { _,_ in semaphore.signal() }
 // Keep the process alive for asynchronous NSWorkspace completion without blocking its main queue.
 let deadline=Date().addingTimeInterval(10)
 while semaphore.wait(timeout:.now()) != .success && Date()<deadline { RunLoop.current.run(until:Date().addingTimeInterval(0.05)) }
}
