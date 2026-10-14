import NecarambaCore

/// External observations synchronize the runtime after publishing authoritative focus.
/// Explicit edit-time refreshes deliberately do not take this path.
enum ObservedFocusRefresh {
  static func perform(state: ContextState, refresh: () -> ContextToken?, synchronizeLayout: () -> Void) {
    state.reconcileFocus(refresh)
    synchronizeLayout()
  }
}
