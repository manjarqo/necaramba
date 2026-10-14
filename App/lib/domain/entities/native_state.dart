/// Confirmed native snapshot. Contains no keyboard input or platform APIs.
class NativeState {
  NativeState({
    required this.sessionID,
    required this.revision,
    required Map<String, bool> preferences,
    required Map<String, bool> capabilities,
    required this.status,
    required List<Map<String, Object?>> words,
    required List<Map<String, Object?>> apps,
    required Map<String, Object?> model,
    required Map<String, Object?> license,
    required Map<String, int> statistics,
    required Map<String, Object?> appearance,
    required Map<String, Object?> login,
  }) : preferences = Map.unmodifiable(preferences),
       capabilities = Map.unmodifiable(capabilities),
       words = List.unmodifiable(
         words.map((v) => Map<String, Object?>.unmodifiable(v)),
       ),
       apps = List.unmodifiable(
         apps.map((v) => Map<String, Object?>.unmodifiable(v)),
       ),
       model = Map.unmodifiable(model),
       license = Map.unmodifiable(license),
       statistics = Map.unmodifiable(statistics),
       appearance = Map.unmodifiable(appearance),
       login = Map.unmodifiable(login);
  final String sessionID;
  final int revision;
  final Map<String, bool> preferences, capabilities;
  final String status;
  final List<Map<String, Object?>> words, apps;
  final Map<String, Object?> model, license, appearance, login;
  final Map<String, int> statistics;
}

class NativeStateReducer {
  NativeState? _current;
  NativeState? get current => _current;
  bool accept(NativeState state) {
    if (_current?.sessionID == state.sessionID &&
        state.revision <= _current!.revision) {
      return false;
    }
    _current = state;
    return true;
  }
}
