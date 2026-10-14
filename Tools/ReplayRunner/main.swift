import Foundation
import NecarambaCore
import NecarambaMac
let args=CommandLine.arguments
func value(_ flag:String)->String? { guard let i=args.firstIndex(of:flag),i+1<args.count else { return nil }; return args[i+1] }
let count=Int(value("--events") ?? "100000") ?? 0
if let path=value("--scenarios") {
 do { _=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:path))) }
 catch { fputs("Invalid scenarios\n",stderr); exit(2) }
}
guard count>=100000 else { fputs("Replay requires at least 100000 events\n",stderr); exit(2) }
let context=ContextState(); let layout=LayoutID(rawValue:"US")
context.update(pid:42,bundleID:"replay.synthetic",focusID:"a",layout:layout,qualified:true)
let runtime=InputRuntime(context:context,initialLayout:layout)
var expected:[UInt16]=[]; var forwarded:[UInt16]=[]
let start=DispatchTime.now().uptimeNanoseconds
for n in 0..<count {
 if n%997==0 { context.update(pid:42,bundleID:"replay.synthetic",focusID:String(n),layout:layout,qualified:true); runtime.invalidateContext(reason:.focusChanged) }
 let event=InputEvent(kind:n%2==0 ? .down:.up,keyCode:UInt16(n%128),modifiers:[],timestampNanos:UInt64(n)*1000,layout:layout,context:context.current()!,origin:n%7==0 ? .ours:(n%13==0 ? .foreignSynthetic:.physical),text:n%5==0 ? " ":"a",isRepeat:n%11==0)
 expected.append(event.keyCode)
 if runtime.accept(event) == .pass { forwarded.append(event.keyCode) }
}
guard expected==forwarded,runtime.forwardedCount==count else { fputs("Order/count mismatch\n",stderr); exit(1) }
let elapsed=DispatchTime.now().uptimeNanoseconds-start
print("Replay PASS: \(count) events, exact ordered pass-through; elapsed \(elapsed) ns. Host latency and compatibility UNRUN.")
