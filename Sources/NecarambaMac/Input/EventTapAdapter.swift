import Foundation
import CoreGraphics
import NecarambaCore
public final class EventTapAdapter {
 public static let ownMarker=Int64.random(in:1...Int64.max)
 private weak var runtime:InputRuntime?
 private let lock=NSLock()
 private var thread:Thread?
 private var loop:CFRunLoop?
 private var tap:CFMachPort?
 private var stopped=false
 private var timeouts:[UInt64]=[]
 public init(runtime:InputRuntime) { self.runtime=runtime }
 public func start()->Bool {
  guard CGPreflightListenEventAccess() else { return false }
  lock.lock(); defer { lock.unlock() }; guard thread == nil else { return true }; stopped=false
  let worker=Thread { [weak self] in self?.run() }; worker.name="Necaramba input"; thread=worker; worker.start(); return true
 }
 public func stop() { lock.lock(); stopped=true; let runloop=loop; lock.unlock(); if let runloop { CFRunLoopStop(runloop) } }
 private func run() {
  let mask:[CGEventType]=[.keyDown,.keyUp,.flagsChanged,.leftMouseDown,.rightMouseDown,.otherMouseDown,.scrollWheel]
  let bits=mask.reduce(CGEventMask(0)) { $0 | (CGEventMask(1)<<$1.rawValue) }
  guard let port=CGEvent.tapCreate(tap:.cgSessionEventTap,place:.headInsertEventTap,options:.listenOnly,eventsOfInterest:bits,callback:{ _,type,event,reference in
   guard let reference else { return Unmanaged.passUnretained(event) }
   let owner=Unmanaged<EventTapAdapter>.fromOpaque(reference).takeUnretainedValue()
   owner.receive(type,event); return Unmanaged.passUnretained(event)
  },userInfo:Unmanaged.passUnretained(self).toOpaque()) else { lock.lock(); thread=nil; lock.unlock(); return }
  let runloop=CFRunLoopGetCurrent()
  lock.lock(); tap=port; loop=runloop; let halt=stopped; lock.unlock()
  guard !halt,let source=CFMachPortCreateRunLoopSource(nil,port,0) else { CFMachPortInvalidate(port); return }
  CFRunLoopAddSource(runloop,source,.commonModes)
  let timer=CFRunLoopTimerCreateWithHandler(nil,CFAbsoluteTimeGetCurrent()+0.02,0.02,0,0) { [weak self] _ in self?.runtime?.advance(to:DispatchTime.now().uptimeNanoseconds) }
  CFRunLoopAddTimer(runloop,timer,.commonModes); CGEvent.tapEnable(tap:port,enable:true); CFRunLoopRun()
  CFRunLoopTimerInvalidate(timer); CFRunLoopRemoveSource(runloop,source,.commonModes); CFMachPortInvalidate(port)
  lock.lock(); loop=nil; tap=nil; thread=nil; lock.unlock()
 }
 private func receive(_ type:CGEventType,_ event:CGEvent) {
  guard let runtime else { return }
  if type == .tapDisabledByUserInput { runtime.invalidateContext(reason:.permissionRevoked); stop(); return }
  if type == .tapDisabledByTimeout {
   let now=DispatchTime.now().uptimeNanoseconds; timeouts=timeouts.filter { now-$0<60_000_000_000 }; runtime.invalidateContext(reason:.unknownInput)
   if timeouts.count<3,let tap { timeouts.append(now); CGEvent.tapEnable(tap:tap,enable:true) } else { stop() }; return
  }
  guard [.keyDown,.keyUp,.flagsChanged].contains(type) else { runtime.invalidateContext(reason:.mouseNavigation); return }
  guard let (context,layout)=runtime.cachedInputContext() else { runtime.invalidateContext(reason:.unknownInput); return }
  let marker=event.getIntegerValueField(.eventSourceUserData)
  let sourcePID=event.getIntegerValueField(.eventSourceUnixProcessID)
  let origin:EventOrigin = marker == Self.ownMarker ? .ours : (sourcePID==0 ? .physical:.foreignSynthetic)
  var modifiers:Set<Modifier>=[]
  for (flag,modifier):(CGEventFlags,Modifier) in [(.maskShift,.shift),(.maskAlternate,.option),(.maskCommand,.command),(.maskControl,.control),(.maskAlphaShift,.capsLock),(.maskSecondaryFn,.function)] { if event.flags.contains(flag) { modifiers.insert(modifier) } }
  var chars=[UniChar](repeating:0,count:8); var count=0
  event.keyboardGetUnicodeString(maxStringLength:8,actualStringLength:&count,unicodeString:&chars)
  let text=count>0 && count<=8 ? String(utf16CodeUnits:chars,count:count):nil
  _=runtime.accept(InputEvent(kind:type == .keyDown ? .down : (type == .keyUp ? .up:.flagsChanged),keyCode:UInt16(event.getIntegerValueField(.keyboardEventKeycode)),modifiers:modifiers,timestampNanos:DispatchTime.now().uptimeNanoseconds,layout:layout,context:context,origin:origin,text:text,isRepeat:event.getIntegerValueField(.keyboardEventAutorepeat) != 0))
 }
}
