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
  Future<NativeState>? _reconnecting;
  int _generation = 0;
  NativeState? get current => _reducer.current;
  @override
  Stream<NativeState> get states => _states.stream;
  void _check() {
    if (_disposed) throw const NativeFailure('unavailable', retryable: false);
  }

  void _accept(Object? value) {
    if (_disposed) return;
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
      final details = e.details == null
          ? null
          : NativeStateDecoder.map(e.details);
      if (details != null) {
        NativeStateDecoder.keys(details, {'requestID', 'retryable'});
        final requestID = NativeStateDecoder.string(
          details['requestID'],
          limit: 128,
        );
        if (requestID.isEmpty) NativeStateDecoder.invalid();
        NativeStateDecoder.boolean(details['retryable']);
        if (args['requestID'] != null &&
            details['requestID'] != args['requestID']) {
          NativeStateDecoder.invalid();
        }
      }
      throw NativeFailure(
        codes.contains(e.code) ? e.code : 'unavailable',
        requestID:
            details?['requestID'] as String? ?? args['requestID'] as String?,
        retryable: details?['retryable'] as bool? ?? e.code == 'unavailable',
      );
    }
  }

  @override
  Future<NativeState> refresh() {
    _check();
    return _reconnecting ?? _startRefresh();
  }

  Future<NativeState> _startRefresh() {
    if (_refreshing != null) return _refreshing!;
    late final Future<NativeState> pending;
    pending = _refresh(_generation).whenComplete(() {
      if (identical(_refreshing, pending)) _refreshing = null;
    });
    _refreshing = pending;
    return pending;
  }

  Future<NativeState> _refresh(int generation) async {
    _listen();
    final snapshot = await _invoke('getState', {});
    _check();
    if (generation == _generation) {
      _accept(snapshot);
      _needsSync = false;
    }
    if (current == null) {
      throw const NativeFailure('unavailable', retryable: true);
    }
    return current!;
  }

  Future<NativeState> reconnect() {
    _check();
    if (_reconnecting != null) return _reconnecting!;
    late final Future<NativeState> pending;
    pending = _reconnect().whenComplete(() {
      if (identical(_reconnecting, pending)) _reconnecting = null;
    });
    _reconnecting = pending;
    return pending;
  }

  Future<NativeState> _reconnect() async {
    _generation++;
    _refreshing = null;
    _needsSync = true;
    final previous = _subscription;
    _subscription = null;
    await previous?.cancel();
    _check();
    return _startRefresh();
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
      final result = _decodeResult(method, response['result']);
      if (_reducer.accept(state)) _states.add(state);
      if (current!.sessionID != state.sessionID) {
        throw NativeFailure('conflict', requestID: id, retryable: false);
      }
      return NativeReply(requestID: id, state: current!, result: result);
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

  Map<String, Object?> _decodeResult(String method, Object? value) {
    final result = NativeStateDecoder.map(value);
    if (method == 'getThumbnail') {
      NativeStateDecoder.keys(result, {'bytes', 'width', 'height'});
      final bytes = result['bytes'];
      final width = NativeStateDecoder.integer(result['width']);
      final height = NativeStateDecoder.integer(result['height']);
      if (bytes is! Uint8List ||
          bytes.length > 256 * 1024 ||
          width > 512 ||
          height > 512 ||
          (bytes.isEmpty
              ? width != 0 || height != 0
              : width == 0 || height == 0)) {
        NativeStateDecoder.invalid();
      }
    } else if (method == 'previewShare') {
      NativeStateDecoder.keys(result, {'previewID', 'preview'});
      final id = NativeStateDecoder.string(result['previewID']);
      if (!RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(id)) {
        NativeStateDecoder.invalid();
      }
      final preview = NativeStateDecoder.map(result['preview']);
      NativeStateDecoder.keys(preview, {
        'word',
        'language',
        'modelVersion',
        'feedback',
        'host',
      });
      if (NativeStateDecoder.string(preview['word']).isEmpty) {
        NativeStateDecoder.invalid();
      }
      NativeStateDecoder.enumeration(preview['language'], {
        'english',
        'russian',
      });
      if (!RegExp(r'^\d+$')
          .hasMatch(NativeStateDecoder.string(preview['modelVersion']))) {
        NativeStateDecoder.invalid();
      }
      if (preview['feedback'] != null) {
        NativeStateDecoder.string(preview['feedback']);
      }
      final host = NativeStateDecoder.string(preview['host'], limit: 253);
      if (!RegExp(r'^[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$')
              .hasMatch(host) ||
          host.contains('..')) {
        NativeStateDecoder.invalid();
      }
    } else {
      NativeStateDecoder.keys(result, {});
    }
    return result;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _subscription?.cancel();
    await _states.close();
  }
}
