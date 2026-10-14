// Synthetic repository only: no TCC, login items, or personal stores.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:necaramba/main.dart';
import 'package:necaramba/domain/repositories/native_repository.dart';

import '../test/support/native_fakes.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('synthetic settings reject denied command and cancel clear', (
    tester,
  ) async {
    final repository = FakeNativeRepository();
    await tester.pumpWidget(
      NecarambaApp(repository: repository, locale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    repository.failure = const NativeFailure(
      'permissionDenied',
      retryable: false,
    );
    await tester.tap(find.byKey(const Key('autoEnabled')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(find.byKey(const Key('autoEnabled'))).value,
      isTrue,
    );
    await tester.tap(find.text('Exceptions'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('clearWords')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cancelClear')));
    await tester.pumpAndSettle();
    expect(
      repository.calls.where((call) => call.method == 'clearWords'),
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await repository.dispose();
  });
}
