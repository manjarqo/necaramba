import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';

import '../domain/entities/native_state.dart';
import '../domain/repositories/native_repository.dart';
import 'native_state_decoder.dart';

abstract interface class NativeTransport {
  Stream<Object?> get states;
  Future<Object?> invoke(String method, Map<String, Object?> arguments);
}

class ChannelNativeTransport implements NativeTransport {
  const ChannelNativeTransport();
  static const _control = MethodChannel('necaramba/control.v1');
  static const _events = EventChannel('necaramba/state.v1');
  @override
  Stream<Object?> get states => _events.receiveBroadcastStream();
  @override
  Future<Object?> invoke(String method, Map<String, Object?> arguments) =>
      _control.invokeMethod<Object?>(method, arguments);
}

class PlatformNativeRepository implements NativeRepository {
  PlatformNativeRepository({
    NativeTransport? transport,
    this.timeout = const Duration(seconds: 10),
  }) : _transport = transport ?? const ChannelNativeTransport();
  final NativeTransport _transport;
  final Duration timeout;
  final _reducer = NativeStateReducer();
  final _states = StreamController<NativeState>.broadcast(sync: true);
  StreamSubscription<Object?>? _subscription;
  bool _disposed = false, _needsSync = true;
  Future<NativeState>? _refreshing;
  NativeState? get current => _reducer.current;
  @override
  Stream<NativeState> get states => _states.stream;
  void _check() {
    if (_disposed) throw const NativeFailure('unavailable', retryable: false);
  }

  void _accept(Object? value) {
    final state = NativeStateDecoder.decode(value);
    if (_reducer.accept(state) && !_disposed) _states.add(state);
  }

  void _listen() {
    _subscription ??= _transport.states.listen(
      (v) {
        try {
          _accept(v);
        } on NativeFailure catch (e) {
          _needsSync = true;
          _states.addError(e);
        }
      },
      onError: (Object error) {
        _needsSync = true;
        _states.addError(const NativeFailure('unavailable', retryable: true));
      },
    );
  }

  Future<Object?> _invoke(
    String method,
    Map<String, Object?> args, {
    bool timed = true,
  }) async {
    try {
      final call = _transport.invoke(method, args);
      return await (timed ? call.timeout(timeout) : call);
    } on TimeoutException {
      _needsSync = true;
      throw NativeFailure(
        'timeout',
        requestID: args['requestID'] as String?,
        retryable: false,
      );
    } on MissingPluginException {
      throw const NativeFailure('unavailable', retryable: true);
    } on PlatformException catch (e) {
      const codes = {
        'invalidArgument',
        'conflict',
        'permissionDenied',
        'unavailable',
        'cancelled',
        'ioFailure',
        'unsupportedSchema',
        'timeout',
      };
      throw NativeFailure(
        codes.contains(e.code) ? e.code : 'unavailable',
        requestID: args['requestID'] as String?,
        retryable: e.code == 'unavailable',
      );
    }
  }

  @override
  Future<NativeState> refresh() {
    _check();
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  Future<NativeState> _refresh() async {
    _listen();
    _accept(await _invoke('getState', {}));
    _check();
    _needsSync = false;
    return current!;
  }

  Future<NativeState> reconnect() async {
    _check();
    await _subscription?.cancel();
    _subscription = null;
    _needsSync = true;
    return refresh();
  }

  static const commands = {
    'setPreferences',
    'addWord',
    'deleteWord',
    'clearWords',
    'chooseApp',
    'setAppMode',
    'deleteApp',
    'requestPermission',
    'refreshCapabilities',
    'setLoginEnabled',
    'setHeaderColor',
    'importHeaderImage',
    'removeHeaderImage',
    'getThumbnail',
    'chooseSound',
    'resetSound',
    'resetCounters',
    'checkRules',
    'previewShare',
    'confirmShare',
    'cancelShare',
    'purchase',
    'restore',
    'manageSubscription',
    'exportDiagnostics',
    'exportArchive',
    'importArchive',
  };
  static const dialogs = {
    'chooseApp',
    'chooseSound',
    'purchase',
    'restore',
    'manageSubscription',
    'exportDiagnostics',
    'exportArchive',
    'importArchive',
    'importHeaderImage',
    'requestPermission',
  };
  String _requestID() {
    final r = Random.secure();
    return List.generate(
      16,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  @override
  Future<NativeReply> command(
    String method,
    Map<String, Object?> arguments,
  ) async {
    _check();
    if (!commands.contains(method)) {
      throw const NativeFailure('invalidArgument', retryable: false);
    }
    if (_needsSync || current == null) await refresh();
    final id = _requestID();
    final envelope = <String, Object?>{
      'requestID': id,
      'arguments': Map<String, Object?>.from(arguments),
      if (method != 'getThumbnail') ...{
        'expectedSessionID': current!.sessionID,
        'expectedRevision': current!.revision,
      },
    };
    try {
      final response = NativeStateDecoder.map(
        await _invoke(method, envelope, timed: !dialogs.contains(method)),
      );
      _check();
      NativeStateDecoder.keys(response, {'requestID', 'state', 'result'});
      if (response['requestID'] != id) NativeStateDecoder.invalid();
      final state = NativeStateDecoder.decode(response['state']);
      final result = NativeStateDecoder.map(response['result']);
      final bytes = result['bytes'];
      if (bytes != null && (bytes is! Uint8List || bytes.length > 256 * 1024)) {
        NativeStateDecoder.invalid();
      }
      if (_reducer.accept(state)) _states.add(state);
      return NativeReply(requestID: id, state: state, result: result);
    } on NativeFailure catch (e) {
      if (e.code == 'conflict') {
        _needsSync = true;
        try {
          await refresh();
        } on NativeFailure {
          /* Original conflict remains actionable. */
        }
      }
      rethrow;
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _subscription?.cancel();
    await _states.close();
  }
}
