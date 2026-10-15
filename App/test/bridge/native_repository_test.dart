import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:necaramba/data/native_state_decoder.dart';
import 'package:necaramba/data/platform_native_repository.dart';
import 'package:necaramba/domain/entities/native_state.dart';
import 'package:necaramba/domain/repositories/native_repository.dart';

Map<String, Object?> fixture({
  int revision = 1,
  String session = '00000000-0000-4000-8000-000000000001',
}) => {
  'schema': 1,
  'sessionID': session,
  'revision': revision,
  'preferences': {
    for (final key in NativeStateDecoder.preferenceKeys) key: false,
  },
  'capabilities': {
    'listen': false,
    'post': false,
    'axTrusted': false,
    'secureInput': false,
  },
  'status': 'off',
  'words': <Object?>[],
  'apps': <Object?>[],
  'model': {
    'version': '1',
    'lastChecked': null,
    'state': 'current',
    'additionalCorrectionsAvailable': false,
  },
  'license': {'state': 'unavailable', 'expiresAt': null},
  'statistics': <String, int>{},
  'appearance': {
    'colorIndex': 0,
    'hasCustomSound': false,
    'hasHeaderImage': false,
  },
  'login': {'enabled': false, 'status': 'disabled'},
};

class FakeTransport implements NativeTransport {
  late final events = StreamController<Object?>.broadcast(
    sync: true,
    onListen: () => listens++,
    onCancel: () => cancels++,
  );
  int calls = 0;
  int listens = 0;
  int cancels = 0;
  Future<Object?> Function(String, Map<String, Object?>)? handler;
  @override
  Stream<Object?> get states => events.stream;
  @override
  Future<Object?> invoke(String method, Map<String, Object?> arguments) async {
    calls++;
    return handler == null ? fixture() : handler!(method, arguments);
  }
}

void main() {
  test('decoder preserves initialization and unavailable runtime statuses', () {
    for (final status in ['starting', 'unavailable']) {
      final wire = {...fixture(), 'status': status};
      expect(NativeStateDecoder.decode(wire).status, status);
      expect(NativeStateDecoder.encode(NativeStateDecoder.decode(wire)), wire);
    }
  });
  test('decoder rejects unsupported schema and malformed nested state', () {
    expect(
      () => NativeStateDecoder.decode({...fixture(), 'schema': 2}),
      throwsA(isA<NativeFailure>()),
    );
    expect(
      () => NativeStateDecoder.decode({
        ...fixture(),
        'appearance': {'colorIndex': 25},
      }),
      throwsA(isA<NativeFailure>()),
    );
  });
  test('full codec round trip preserves state and rejects private fields', () {
    final wire = fixture(revision: 42);
    expect(NativeStateDecoder.encode(NativeStateDecoder.decode(wire)), wire);
    expect(
      () => NativeStateDecoder.decode({...wire, 'typedText': 'secret'}),
      throwsA(isA<NativeFailure>()),
    );
    expect(
      () => NativeStateDecoder.decode({...wire, 'revision': -1}),
      throwsA(isA<NativeFailure>()),
    );
    expect(
      () => NativeStateDecoder.decode({...wire, 'status': 'unknown'}),
      throwsA(isA<NativeFailure>()),
    );
  });
  test(
    'successful mutation publishes confirmed state before returning reply',
    () async {
      final transport = FakeTransport();
      final repo = PlatformNativeRepository(transport: transport);
      await repo.refresh();
      final revisions = <int>[];
      final subscription = repo.states.listen((s) => revisions.add(s.revision));
      transport.handler = (method, args) async {
        expect(args['expectedRevision'], 1);
        expect(args['expectedSessionID'], fixture()['sessionID']);
        return {
          'requestID': args['requestID'],
          'state': fixture(revision: 2),
          'result': <String, Object?>{},
        };
      };
      final reply = await repo.command('setPreferences', {
        'patch': {'autoEnabled': true},
      });
      expect(reply.state.revision, 2);
      expect(revisions, [2]);
      expect(transport.calls, 2);
      await subscription.cancel();
      await repo.dispose();
      await transport.events.close();
    },
  );
  test('state reducer rejects older revision and accepts new session', () {
    final reducer = NativeStateReducer();
    reducer.accept(NativeStateDecoder.decode(fixture(revision: 9)));
    reducer.accept(NativeStateDecoder.decode(fixture(revision: 8)));
    expect(reducer.current!.revision, 9);
    reducer.accept(
      NativeStateDecoder.decode(
        fixture(session: '00000000-0000-4000-8000-000000000002'),
      ),
    );
    expect(reducer.current!.revision, 1);
    expect(
      () => reducer.current!.preferences['autoEnabled'] = true,
      throwsUnsupportedError,
    );
  });
  test('refresh and events share revision reducer', () async {
    final transport = FakeTransport();
    final repo = PlatformNativeRepository(transport: transport);
    await repo.refresh();
    transport.events.add(fixture(revision: 3));
    transport.events.add(fixture(revision: 2));
    await Future<void>.delayed(Duration.zero);
    expect(repo.current!.revision, 3);
    await repo.dispose();
    await transport.events.close();
  });
  test('conflict resynchronizes and never retries mutation', () async {
    final transport = FakeTransport();
    final repo = PlatformNativeRepository(transport: transport);
    await repo.refresh();
    var mutations = 0;
    transport.handler = (method, args) async {
      if (method == 'getState') return fixture(revision: 5);
      mutations++;
      throw const NativeFailure('conflict', retryable: false);
    };
    await expectLater(
      repo.command('setPreferences', {
        'patch': {'autoEnabled': true},
      }),
      throwsA(isA<NativeFailure>()),
    );
    expect(mutations, 1);
    expect(repo.current!.revision, 5);
    await repo.dispose();
    await transport.events.close();
  });
  test('timeout after commit requires resync before next action', () async {
    final transport = FakeTransport();
    final repo = PlatformNativeRepository(
      transport: transport,
      timeout: const Duration(milliseconds: 5),
    );
    await repo.refresh();
    var reads = 0;
    var mutations = 0;
    transport.handler = (method, args) {
      if (method == 'getState') {
        reads++;
        return Future.value(fixture(revision: 2));
      }
      mutations++;
      return Completer<Object?>().future;
    };
    await expectLater(
      repo.command('resetCounters', {'confirmed': true}),
      throwsA(isA<NativeFailure>().having((e) => e.code, 'code', 'timeout')),
    );
    await expectLater(
      repo.command('resetCounters', {'confirmed': true}),
      throwsA(isA<NativeFailure>()),
    );
    expect(reads, 1);
    expect(mutations, 2);
    await repo.dispose();
    await transport.events.close();
  });
  test('reconnect replaces subscription and dispose stops events', () async {
    final transport = FakeTransport();
    final repo = PlatformNativeRepository(transport: transport);
    await repo.refresh();
    await repo.reconnect();
    expect(transport.listens, 2);
    expect(transport.cancels, 1);
    await repo.dispose();
    expect(transport.cancels, 2);
    transport.events.add(fixture(revision: 8));
    expect(repo.current!.revision, 1);
    expect(() => repo.refresh(), throwsA(isA<NativeFailure>()));
    await transport.events.close();
  });
}
