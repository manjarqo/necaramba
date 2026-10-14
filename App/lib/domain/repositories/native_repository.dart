import '../entities/native_state.dart';

abstract interface class NativeRepository {
  Stream<NativeState> get states;
  Future<NativeState> refresh();
  Future<NativeReply> command(String method, Map<String, Object?> arguments);
  Future<void> dispose();
}

class NativeReply {
  NativeReply({
    required this.requestID,
    required this.state,
    required Map<String, Object?> result,
  }) : result = Map.unmodifiable(result);
  final String requestID;
  final NativeState state;
  final Map<String, Object?> result;
}

class NativeFailure implements Exception {
  const NativeFailure(this.code, {this.requestID, required this.retryable});
  final String code;
  final String? requestID;
  final bool retryable;
  @override
  String toString() => 'NativeFailure($code)';
}
