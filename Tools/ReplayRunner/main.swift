import Foundation
import NecarambaCore
import NecarambaMac

let args = CommandLine.arguments
func value(_ flag: String) -> String? {
  guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
  return args[i + 1]
}
let count = Int(value("--events") ?? "100000") ?? 0
var scenarios: [String] = []
if let path = value("--scenarios") {
  do {
    let json =
      try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path)))
      as? [String: Any]
    guard let names = json?["scenarios"] as? [String] else {
      throw NSError(domain: "Replay", code: 1)
    }
    scenarios = names
  } catch {
    fputs("Invalid scenarios\n", stderr)
    exit(2)
  }
}
guard count >= 100000 else {
  fputs("Replay requires at least 100000 events\n", stderr)
  exit(2)
}
let context = ContextState()
let layout = LayoutID(rawValue: "US")
context.update(pid: 42, bundleID: "replay.synthetic", focusID: "a", layout: layout, qualified: true)
let runtime = InputRuntime(context: context, initialLayout: layout)
var expected: [UInt16] = []
var forwarded: [UInt16] = []
let start = DispatchTime.now().uptimeNanoseconds
for n in 0..<count {
  if n % 997 == 0 {
    context.update(
      pid: 42, bundleID: "replay.synthetic", focusID: String(n), layout: layout, qualified: true)
    runtime.invalidateContext(reason: .focusChanged)
  }
  let event = InputEvent(
    kind: n % 2 == 0 ? .down : .up, keyCode: UInt16(n % 128), modifiers: [],
    timestampNanos: UInt64(n) * 1000, layout: layout, context: context.current()!,
    origin: n % 7 == 0 ? .ours : (n % 13 == 0 ? .foreignSynthetic : .physical),
    text: n % 5 == 0 ? " " : "a", isRepeat: n % 11 == 0)
  expected.append(event.keyCode)
  if runtime.accept(event) == .pass { forwarded.append(event.keyCode) }
}
guard expected == forwarded, runtime.forwardedCount == count else {
  fputs("Order/count mismatch\n", stderr)
  exit(1)
}
let elapsed = DispatchTime.now().uptimeNanoseconds - start
print(
  "Replay PASS: \(count) events, exact ordered pass-through; elapsed \(elapsed) ns. Host latency and compatibility UNRUN."
)

// Execute every declared scenario; none of these simulated checks claim native host qualification.
let known: Set<String> = [
  "own-marker", "foreign-synthetic", "repeat", "focus-change", "layout-change", "secure-transition",
  "partial-edit", "clipboard-concurrent-copy", "overflow", "deadline", "commit",
]
for scenario in scenarios {
  guard known.contains(scenario) else {
    fputs("Unknown replay scenario: \(scenario)\n", stderr)
    exit(2)
  }
  switch scenario {
  case "overflow":
    let owner = EditOwnership<Int>()
    guard owner.begin(now: 0) else { exit(1) }
    for n in 0..<16 { guard owner.intercept(n, now: 1) == .held else { exit(1) } }
    guard owner.intercept(16, now: 1) == .replay(Array(0...16)) else { exit(1) }
  case "deadline", "partial-edit", "commit", "focus-change", "layout-change", "secure-transition":
    let owner = EditOwnership<Int>(deadlineNanos: 100)
    guard owner.begin(now: 0) else { exit(1) }
    _ = owner.intercept(1, now: 1)
    var writes = 0
    let stale = ["focus-change", "layout-change", "secure-transition"].contains(scenario)
    let result = owner.commit(
      expectedGeneration: 0, currentGeneration: { stale ? 1 : 0 },
      now: scenario == "deadline" ? 101 : 2
    ) {
      writes += 1
      return scenario == "partial-edit" ? .uncertain : .committed
    }
    let expected: ApplyResult =
      stale || scenario == "deadline"
      ? .aborted : (scenario == "partial-edit" ? .uncertain : .committed)
    guard result.result == expected, result.replay == [1], writes == (expected == .aborted ? 0 : 1)
    else { exit(1) }
  case "clipboard-concurrent-copy":
    let board = ReplayClipboard()
    let transaction = try ClipboardTransaction(access: board)
    try transaction.replace(with: [
      .init(representations: ["public.utf8-plain-text": Data("ours".utf8)])
    ])
    _ = try board.write([.init(representations: ["public.utf8-plain-text": Data("newer".utf8)])])
    guard !transaction.restoreIfOwned(),
      board.items[0].representations["public.utf8-plain-text"] == Data("newer".utf8)
    else { exit(1) }
  default:
    // The 100000-event production-runtime pass above explicitly includes these origins/repeats.
    guard runtime.forwardedCount == count else { exit(1) }
  }
  print("Scenario PASS: \(scenario) (simulated)")
}
// Exercise 100000 queued physical events across successful edits, stale preparation, overflow and partial failure.
var incoming: [Int] = []
var released: [Int] = []
for group in 0..<5000 {
  let owner = EditOwnership<Int>()
  guard owner.begin(now: 0) else { exit(1) }
  for offset in 0..<20 {
    let event = group * 20 + offset
    incoming.append(event)
    switch owner.intercept(event, now: 1) {
    case .pass: released.append(event)
    case .held: break
    case .replay(let events): released += events
    }
    if offset == 3, group % 4 != 1 {
      let result = owner.commit(
        expectedGeneration: 0, currentGeneration: { group % 4 == 2 ? 1 : 0 }, now: 2,
        mutation: { group % 4 == 3 ? .uncertain : .committed })
      released += result.replay
    }
  }
}
guard incoming == released, released.count == 100000 else {
  fputs("Edit/overflow replay mismatch\n", stderr)
  exit(1)
}
print("Ownership replay PASS: 100000 events across commit/stale/overflow/uncertain, exact order")
private final class ReplayClipboard: ClipboardAccess {
  var changeCount = 0
  var items: [PasteboardItem] = [
    .init(representations: ["public.utf8-plain-text": Data("before".utf8)])
  ]
  func snapshot(maxBytes: Int) throws -> PasteboardSnapshot {
    .init(items: items, changeCount: changeCount)
  }
  func write(_ items: [PasteboardItem]) throws -> Int {
    self.items = items
    changeCount += 1
    return changeCount
  }
}
