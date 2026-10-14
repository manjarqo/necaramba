import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/entities/native_state.dart';
import '../domain/repositories/native_repository.dart';
import '../domain/usecases/native_usecases.dart';

class NativeViewState {
  const NativeViewState({this.confirmed, this.error, this.loading = false});
  final NativeState? confirmed;
  final String? error;
  final bool loading;
}

class NativeCubit extends Cubit<NativeViewState> {
  NativeCubit(this._useCases) : super(const NativeViewState(loading: true)) {
    _subscription = _useCases.states.listen(
      (s) {
        if (!isClosed) emit(NativeViewState(confirmed: s));
      },
      onError: (Object e) {
        if (!isClosed) {
          emit(
            NativeViewState(confirmed: state.confirmed, error: 'unavailable'),
          );
        }
      },
    );
  }
  final NativeUseCases _useCases;
  late final StreamSubscription<NativeState> _subscription;
  Future<void> bootstrap() async {
    try {
      final s = await _useCases.refresh();
      if (!isClosed) emit(NativeViewState(confirmed: s));
    } on NativeFailure catch (e) {
      if (!isClosed) {
        emit(NativeViewState(confirmed: state.confirmed, error: e.code));
      }
    }
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    await super.close();
  }
}
