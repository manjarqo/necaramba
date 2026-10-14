import '../entities/native_state.dart';
import '../repositories/native_repository.dart';

class NativeUseCases {
  const NativeUseCases(this._repository);
  final NativeRepository _repository;
  Stream<NativeState> get states => _repository.states;
  Future<NativeState> refresh() => _repository.refresh();
  Future<NativeReply> command(String method, Map<String, Object?> arguments) =>
      _repository.command(method, arguments);
}
