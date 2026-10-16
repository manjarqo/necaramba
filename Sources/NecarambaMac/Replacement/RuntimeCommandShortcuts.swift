import NecarambaCore

/// Posts command shortcuts through the active event tap of an input runtime.
public final class RuntimeCommandShortcuts: CommandShortcutPosting {
  private weak var runtime: InputRuntime?
  public init(runtime: InputRuntime) { self.runtime = runtime }
  @MainActor public func post(_ shortcut: CommandShortcut, in context: ContextToken, generation: UInt64) async -> Bool {
    runtime?.postCommandShortcut(shortcut, context: context, generation: generation) ?? false
  }
}
