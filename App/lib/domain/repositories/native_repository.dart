import 'dart:typed_data';

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
  }) : result = Map.unmodifiable(
         result.map((key, value) => MapEntry(key, _freeze(value))),
       );
  final String requestID;
  final NativeState state;
  final Map<String, Object?> result;
}

Object? _freeze(Object? value) {
  if (value is Uint8List) return Uint8List.fromList(value).asUnmodifiableView();
  if (value is Map) {
    return Map.unmodifiable(value.map((key, v) => MapEntry(key, _freeze(v))));
  }
  if (value is List) return List.unmodifiable(value.map(_freeze));
  return value;
}

class NativeFailure implements Exception {
  const NativeFailure(this.code, {this.requestID, required this.retryable});
  final String code;
  final String? requestID;
  final bool retryable;
  @override
  String toString() => 'NativeFailure($code)';
}
