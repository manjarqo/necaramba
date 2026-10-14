import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/entities/native_state.dart';
import '../domain/repositories/native_repository.dart';
import '../domain/repositories/window_interaction.dart';
import '../domain/usecases/native_usecases.dart';

class NativeViewState {
  NativeViewState({
    this.confirmed,
    this.error,
    this.loading = false,
    this.connected = false,
    Set<String> pending = const {},
    this.thumbnail,
  }) : pending = Set.unmodifiable(pending);
  final NativeState? confirmed;
  final String? error;
  final bool loading, connected;
  final Set<String> pending;
  final Uint8List? thumbnail;
}

class NativeCubit extends Cubit<NativeViewState> {
  NativeCubit(this._useCases) : super(NativeViewState(loading: true)) {
    _subscription = _useCases.states.listen(
      _accept,
      onError: (Object _) => _emit(error: 'unavailable', connected: false),
      onDone: () => _emit(error: 'unavailable', connected: false),
    );
  }
  final NativeUseCases _useCases;
  final _reducer = NativeStateReducer();
  late final StreamSubscription<NativeState> _subscription;
  void _emit({
    String? error,
    bool loading = false,
    bool? connected,
    Set<String>? pending,
    Uint8List? thumbnail,
    bool clearThumbnail = false,
  }) {
    if (!isClosed) {
      emit(
        NativeViewState(
          confirmed: _reducer.current,
          error: error,
          loading: loading,
          connected: connected ?? state.connected,
          pending: pending ?? state.pending,
          thumbnail: clearThumbnail ? null : thumbnail ?? state.thumbnail,
        ),
      );
    }
  }

  void _accept(NativeState value) {
    final sessionChanged = _reducer.current?.sessionID != value.sessionID;
    if (_reducer.accept(value)) {
      _emit(
        error: state.error,
        connected: true,
        clearThumbnail:
            sessionChanged || value.appearance['hasHeaderImage'] != true,
      );
    }
  }

  Future<void> bootstrap() async {
    _emit(loading: _reducer.current == null);
    try {
      _accept(await _useCases.refresh());
      _emit(connected: true);
    } on NativeFailure catch (e) {
      _emit(error: e.code, connected: false);
    } catch (_) {
      _emit(error: 'unavailable', connected: false);
    }
  }

  Future<NativeReply?> run(
    String method,
    Map<String, Object?> arguments,
  ) async {
    if (isClosed || !state.connected || state.pending.isNotEmpty) return null;
    _emit(pending: {method});
    try {
      final reply = await _useCases.command(method, arguments);
      _accept(reply.state);
      final bytes = reply.result['bytes'];
      _emit(
        pending: {},
        thumbnail: method == 'getThumbnail' && bytes is Uint8List
            ? bytes
            : null,
      );
      return reply;
    } on NativeFailure catch (e) {
      _emit(error: e.code, pending: {});
    } catch (_) {
      _emit(error: 'unavailable', pending: {});
    }
    return null;
  }

  void reportWindowFailure(Object error) {
    _emit(error: error is NativeFailure ? error.code : 'unavailable');
  }

  Future<void> updateHeaderRegion(
    WindowInteractionPort port,
    HeaderDropRegion? region,
  ) async {
    try {
      await port.updateHeaderDropRegion(region);
    } catch (error) {
      reportWindowFailure(error);
    }
  }

  /// Drop handles originate exclusively from the native header overlay.
  Future<void> importHeaderDrop(String handle) async {
    final reply = await run('importHeaderImage', {'handle': handle});
    if (reply != null) await loadThumbnail();
  }

  Future<void> loadThumbnail() async {
    if (state.confirmed?.appearance['hasHeaderImage'] == true) {
      await run('getThumbnail', {});
    }
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    await super.close();
  }
}
