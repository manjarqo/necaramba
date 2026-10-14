import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:necaramba/data/native_state_decoder.dart';
import 'package:necaramba/data/platform_native_repository.dart';
import 'package:necaramba/domain/repositories/native_repository.dart';

import 'native_repository_test.dart' show fixture, FakeTransport;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('encoded method channel error preserves validated details', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('necaramba/control.v1'),
      (call) async {
        throw PlatformException(
          code: 'permissionDenied',
          message: 'private text',
          details: {'requestID': 'native-request', 'retryable': false},
        );
      },
    );
    final repo = PlatformNativeRepository(transport: MethodOnlyTransport());
    await expectLater(
      repo.refresh(),
      throwsA(
        isA<NativeFailure>()
            .having((e) => e.requestID, 'id', 'native-request')
            .having(
              (e) => e.toString(),
              'redaction',
              'NativeFailure(permissionDenied)',
            ),
      ),
    );
    await repo.dispose();
    messenger.setMockMethodCallHandler(
      const MethodChannel('necaramba/control.v1'),
      null,
    );
  });
  test(
    'result schema validates immutable preview and bounded thumbnail',
    () async {
      final t = FakeTransport();
      final repo = PlatformNativeRepository(transport: t);
      await repo.refresh();
      final preview = <String, Object?>{
        'previewID': '00000000-0000-4000-8000-000000000003',
        'preview': {
          'word': 'hello',
          'language': 'english',
          'modelVersion': '1',
          'feedback': null,
          'host': 'share.necaramba.example',
        },
      };
      Map<String, Object?> result = preview;
      t.handler = (method, args) async => {
        'requestID': args['requestID'],
        'state': fixture(revision: 2),
        'result': result,
      };
      final reply = await repo.command('previewShare', {});
      expect(
        () => (reply.result['preview'] as Map)['word'] = 'changed',
        throwsUnsupportedError,
      );
      result = {
        ...preview,
        'preview': {...(preview['preview'] as Map), 'typedText': 'private'},
      };
      await expectLater(
        repo.command('previewShare', {}),
        throwsA(isA<NativeFailure>()),
      );
      result = {
        'bytes': Uint8List.fromList([1]),
        'width': 513,
        'height': 1,
      };
      await expectLater(
        repo.command('getThumbnail', {}),
        throwsA(isA<NativeFailure>()),
      );
      result = {'bytes': Uint8List(0), 'width': 0, 'height': 0};
      final thumbnail = await repo.command('getThumbnail', {});
      expect((thumbnail.result['bytes'] as Uint8List).isEmpty, true);
      result = {
        'bytes': Uint8List(256 * 1024 + 1),
        'width': 512,
        'height': 512,
      };
      await expectLater(
        repo.command('getThumbnail', {}),
        throwsA(isA<NativeFailure>()),
      );
      await repo.dispose();
      await t.events.close();
    },
  );
  test('malformed platform details reject nested private fields', () async {
    final t = FakeTransport();
    final repo = PlatformNativeRepository(transport: t);
    t.handler = (method, args) async => throw PlatformException(
      code: 'ioFailure',
      details: {'requestID': 'id', 'retryable': 'yes', 'typedText': 'private'},
    );
    await expectLater(
      repo.refresh(),
      throwsA(
        isA<NativeFailure>().having((e) => e.code, 'code', 'invalidArgument'),
      ),
    );
    await repo.dispose();
    await t.events.close();
  });

  test(
    'schema rejects double one',
    () => expect(
      () => NativeStateDecoder.decode({...fixture(), 'schema': 1.0}),
      throwsA(isA<NativeFailure>()),
    ),
  );
  test('retired session command reply cannot replace new session', () async {
    final t = FakeTransport();
    final repo = PlatformNativeRepository(transport: t);
    await repo.refresh();
    final blocked = Completer<Object?>();
    String? id;
    t.handler = (method, args) {
      if (method == 'getState') {
        return Future.value(
          fixture(session: '00000000-0000-4000-8000-000000000002'),
        );
      }
      id = args['requestID'] as String;
      return blocked.future;
    };
    final command = repo.command('resetCounters', {'confirmed': true});
    t.events.add(fixture(session: '00000000-0000-4000-8000-000000000002'));
    blocked.complete({
      'requestID': id,
      'state': fixture(revision: 9),
      'result': <String, Object?>{},
    });
    await expectLater(
      command,
      throwsA(isA<NativeFailure>().having((e) => e.code, 'code', 'conflict')),
    );
    expect(repo.current!.sessionID, '00000000-0000-4000-8000-000000000002');
    await repo.dispose();
    await t.events.close();
  });
  test(
    'reconnect during blocked refresh installs new listener and read',
    () async {
      final t = FakeTransport();
      final repo = PlatformNativeRepository(transport: t);
      final first = Completer<Object?>();
      var reads = 0;
      t.handler = (method, args) {
        reads++;
        return reads == 1 ? first.future : Future.value(fixture(revision: 2));
      };
      final oldRead = repo.refresh();
      final reconnected = repo.reconnect();
      await Future<void>.delayed(Duration.zero);
      first.complete(fixture());
      await oldRead;
      await reconnected;
      expect(t.listens, 2);
      expect(reads, 2);
      t.events.add(fixture(revision: 3));
      expect(repo.current!.revision, 3);
      await repo.dispose();
      await t.events.close();
    },
  );
  test(
    'ordinary result rejects nested private fields before state commit',
    () async {
      final t = FakeTransport();
      final repo = PlatformNativeRepository(transport: t);
      await repo.refresh();
      t.handler = (method, args) async => {
        'requestID': args['requestID'],
        'state': fixture(revision: 2),
        'result': {'typedText': 'private', 'path': '/private'},
      };
      await expectLater(
        repo.command('resetCounters', {'confirmed': true}),
        throwsA(isA<NativeFailure>()),
      );
      expect(repo.current!.revision, 1);
      await repo.dispose();
      await t.events.close();
    },
  );
  test('reply deeply copies and freezes maps lists bytes', () {
    final bytes = Uint8List.fromList([1]);
    final nested = <String, Object?>{
      'items': [bytes],
    };
    final reply = NativeReply(
      requestID: 'r',
      state: NativeStateDecoder.decode(fixture()),
      result: {'preview': nested},
    );
    bytes[0] = 9;
    final preview = reply.result['preview'] as Map;
    final items = preview['items'] as List;
    expect((items.first as Uint8List)[0], 1);
    expect(() => preview['extra'] = true, throwsUnsupportedError);
    expect(() => items.add(2), throwsUnsupportedError);
    expect(() => (items.first as Uint8List)[0] = 3, throwsUnsupportedError);
  });
  test(
    'PlatformException details preserve validated ID retryability',
    () async {
      final t = FakeTransport();
      final repo = PlatformNativeRepository(transport: t);
      t.handler = (method, args) async => throw PlatformException(
        code: 'ioFailure',
        message: 'private',
        details: {'requestID': 'native-request', 'retryable': true},
      );
      await expectLater(
        repo.refresh(),
        throwsA(
          isA<NativeFailure>()
              .having((e) => e.requestID, 'id', 'native-request')
              .having((e) => e.retryable, 'retryable', true),
        ),
      );
      await repo.dispose();
      await t.events.close();
    },
  );
}

class MethodOnlyTransport implements NativeTransport {
  @override
  Stream<Object?> get states => const Stream.empty();
  @override
  Future<Object?> invoke(String method, Map<String, Object?> args) =>
      const ChannelNativeTransport().invoke(method, args);
}
