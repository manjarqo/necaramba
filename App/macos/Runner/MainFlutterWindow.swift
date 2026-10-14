import Cocoa
import FlutterMacOS
import NecarambaMac

final class MainFlutterWindow: NSWindow, NSWindowDelegate, NSDraggingDestination, FlutterStreamHandler {
  var onClose: (() -> Void)?
  private var controller: FlutterViewController?
  private var control: FlutterMethodChannel?
  private var events: FlutterEventChannel?
  private var windowChannel: FlutterMethodChannel?
  private var sink: FlutterEventSink?
  private weak var services: ApplicationServices?
  private weak var coordinator: NativeCommandCoordinator?
  private var dropRegion: CGRect?
  private var pendingState: [String: Any]?
  private var publishWork: DispatchWorkItem?

  func attach(services: ApplicationServices, coordinator: NativeCommandCoordinator) {
    self.services = services; self.coordinator = coordinator; delegate = self
    let flutter = FlutterViewController(); controller = flutter; contentViewController = flutter
    RegisterGeneratedPlugins(registry: flutter)
    let messenger = flutter.engine.binaryMessenger
    control = FlutterMethodChannel(name: "necaramba/control.v1", binaryMessenger: messenger)
    control?.setMethodCallHandler { [weak self] call, reply in
      guard let self, let coordinator = self.coordinator else { reply(FlutterError(code: "unavailable", message: "Window closed", details: nil)); return }
      if call.method == "getState" { reply(coordinator.state()); return }
      guard let envelope = call.arguments as? [String: Any] else {
        reply(FlutterError(code: "invalidArgument", message: "Invalid command", details: nil)); return
      }
      Task { @MainActor in
        do {
          let result = try await coordinator.command(call.method, envelope: envelope)
          var wire = result.wire
          var payload = result.result
          if let bytes = payload["bytes"] as? Data { payload["bytes"] = FlutterStandardTypedData(bytes: bytes) }
          wire["result"] = payload
          reply(wire)
        } catch let failure as NativeCommandFailure {
          reply(FlutterError(code: failure.code, message: "The action could not be completed",
            details: ["requestID": failure.requestID, "retryable": failure.retryable]))
        } catch {
          reply(FlutterError(code: "ioFailure", message: "The action could not be completed",
            details: ["requestID": envelope["requestID"] as? String ?? "", "retryable": false]))
        }
      }
    }
    events = FlutterEventChannel(name: "necaramba/state.v1", binaryMessenger: messenger); events?.setStreamHandler(self)
    windowChannel = FlutterMethodChannel(name: "necaramba/window.v1", binaryMessenger: messenger)
    windowChannel?.setMethodCallHandler { [weak self] call, reply in
      guard call.method == "updateHeaderDropRegion" else { reply(FlutterMethodNotImplemented); return }
      guard let values = call.arguments as? [String: NSNumber], let x = values["x"], let y = values["y"], let width = values["width"], let height = values["height"],
        [x,y,width,height].allSatisfy({ $0.doubleValue.isFinite }), width.doubleValue > 0, height.doubleValue > 0 else {
        self?.dropRegion = nil; reply(nil); return
      }
      self?.dropRegion = CGRect(x:x.doubleValue,y:y.doubleValue,width:width.doubleValue,height:height.doubleValue)
      reply(nil)
    }
    registerForDraggedTypes([.tiff, .fileURL])
  }
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events; if let state = coordinator?.state() { events(state) }; return nil
  }
  func onCancel(withArguments arguments: Any?) -> FlutterError? { sink = nil; publishWork?.cancel(); publishWork = nil; pendingState = nil; return nil }
  func publish(_ state: [String: Any]) {
    guard sink != nil else { return }; pendingState = state
    guard publishWork == nil else { return }
    let work = DispatchWorkItem { [weak self] in
      guard let self else { return }; self.publishWork = nil
      if let state = self.pendingState { self.pendingState = nil; self.sink?(state) }
    }
    publishWork = work; DispatchQueue.main.asyncAfter(deadline: .now()+0.1, execute: work)
  }
  func windowWillClose(_ notification: Notification) {
    control?.setMethodCallHandler(nil); windowChannel?.setMethodCallHandler(nil); events?.setStreamHandler(nil)
    sink = nil; publishWork?.cancel(); publishWork = nil; pendingState = nil; services?.clearHeaderDrops()
    contentViewController = nil; controller?.engine.shutDownEngine(); controller = nil
    control = nil; events = nil; windowChannel = nil; onClose?()
  }
  private func accepts(_ sender: NSDraggingInfo) -> Bool {
    guard let dropRegion, let contentView else { return false }
    let p = contentView.convert(sender.draggingLocation, from: nil)
    return dropRegion.contains(CGPoint(x:p.x,y:contentView.bounds.height-p.y))
  }
  func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { accepts(sender) ? .copy : [] }
  func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { accepts(sender) ? .copy : [] }
  func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    guard accepts(sender), let services else { return false }
    let board = sender.draggingPasteboard
    guard let data = Self.readHeaderDropData(from: board), let handle = services.registerHeaderDrop(data) else { return false }
    windowChannel?.invokeMethod("headerDrop", arguments:["handle":handle]); return true
  }
  static func readHeaderDropData(from board: NSPasteboard) -> Data? {
    // data(forType: .tiff) eagerly materializes the entire provider payload. There is no
    // bounded streaming API for arbitrary TIFF pasteboard providers, so reject those.
    guard let urls = board.readObjects(forClasses:[NSURL.self], options:[.urlReadingFileURLsOnly:true]) as? [URL],
          let url = urls.first, url.isFileURL else { return nil }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    guard let file = try? FileHandle(forReadingFrom:url) else { return nil }
    defer { try? file.close() }
    guard let data = try? file.read(upToCount:10*1024*1024+1), data.count <= 10*1024*1024 else { return nil }
    return data
  }
}
