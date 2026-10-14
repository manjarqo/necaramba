import AppKit

final class FixtureTextView: NSTextView {
    private(set) var keyCount = 0
    var onCount: ((Int) -> Void)?
    override func keyDown(with event: NSEvent) {
        keyCount += 1
        onCount?(keyCount)
        super.keyDown(with: event)
    }
}
final class HostDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var editors: [FixtureTextView] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 460),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Necaramba — isolated input test host"
        let stack = NSStackView(); stack.orientation = .vertical; stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor)
        ])
        stack.addArrangedSubview(NSTextField(labelWithString: "Synthetic fixture only · contents are not logged"))
        for index in 1...2 {
            let count = NSTextField(labelWithString: "Field \(index): 0 keyDown events")
            let editor = FixtureTextView(); editor.string = index == 1 ? "A ghbdtn Z" : ""
            editors.append(editor)
            editor.identifier = NSUserInterfaceItemIdentifier("field\(index)")
            editor.setAccessibilityLabel("Test field \(index)")
            editor.onCount = { [weak count] value in count?.stringValue = "Field \(index): \(value) keyDown events" }
            let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.documentView = editor
            editor.minSize = NSSize(width: 0, height: 80); editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            editor.isVerticallyResizable = true; editor.autoresizingMask = [.width]
            editor.textContainer?.widthTracksTextView = true
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true
            stack.addArrangedSubview(count); stack.addArrangedSubview(scroll)
        }
        let next = NSButton(title: "Focus second field", target: self, action: #selector(focusSecond))
        let mark = NSButton(title: "Set marked text fixture", target: self, action: #selector(markedFixture))
        stack.addArrangedSubview(next); stack.addArrangedSubview(mark)
        let secure = NSSecureTextField(); secure.placeholderString = "Secure Input fixture"
        secure.setAccessibilityLabel("Secure test field")
        stack.addArrangedSubview(secure)
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func focusSecond() { window.makeFirstResponder(editors[1]) }
    @objc private func markedFixture() {
        window.makeFirstResponder(editors[0])
        editors[0].setMarkedText("仮", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
let delegate = HostDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.setActivationPolicy(.regular)
NSApplication.shared.run()
