import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:necaramba/domain/repositories/native_repository.dart';
import 'package:necaramba/domain/usecases/native_usecases.dart';
import 'package:necaramba/presentation/native_cubit.dart';

import '../support/native_fakes.dart';

void main() {
  test('pending and failed save preserve authoritative preferences', () async {
    final repo = FakeNativeRepository();
    final cubit = NativeCubit(NativeUseCases(repo));
    await cubit.bootstrap();
    repo.pending = Completer<NativeReply>();
    final save = cubit.run('setPreferences', {
      'patch': {'autoEnabled': false},
    });
    expect(cubit.state.pending, contains('setPreferences'));
    expect(cubit.state.confirmed!.preferences['autoEnabled'], true);
    repo.publish(fixture(revision: 3));
    await Future<void>.delayed(Duration.zero);
    repo.pending!.completeError(
      const NativeFailure('permissionDenied', retryable: false),
    );
    await save;
    expect(cubit.state.confirmed!.revision, 3);
    expect(cubit.state.error, 'permissionDenied');
    expect(cubit.state.pending, isEmpty);
    await cubit.close();
    await repo.dispose();
  });
  test('stale response cannot roll back streamed snapshot', () async {
    final repo = FakeNativeRepository();
    final cubit = NativeCubit(NativeUseCases(repo));
    await cubit.bootstrap();
    repo.pending = Completer<NativeReply>();
    final action = cubit.run('checkRules', {});
    repo.publish(fixture(revision: 7));
    await Future<void>.delayed(Duration.zero);
    repo.pending!.complete(
      NativeReply(requestID: 'r', state: fixture(revision: 2), result: {}),
    );
    await action;
    expect(cubit.state.confirmed!.revision, 7);
    await cubit.close();
    await repo.dispose();
  });
}
