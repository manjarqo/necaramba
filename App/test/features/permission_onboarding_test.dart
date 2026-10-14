import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:necaramba/main.dart';

import '../support/native_fakes.dart';

const missing = {
  'listen': false,
  'post': false,
  'axTrusted': false,
  'secureInput': false,
};
const granted = {
  'listen': true,
  'post': true,
  'axTrusted': true,
  'secureInput': false,
};
Future<void> mount(WidgetTester tester, FakeNativeRepository repo) async {
  await tester.pumpWidget(
    NecarambaApp(repository: repo, locale: const Locale('en')),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('missing permissions open dialog without requesting OS access', (
    tester,
  ) async {
    final repo = FakeNativeRepository()
      ..current = fixture(capabilities: missing);
    await mount(tester, repo);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(repo.calls.where((c) => c.method == 'requestPermission'), isEmpty);
    for (final kind in ['listen', 'post', 'ax']) {
      await tester.ensureVisible(find.byKey(Key('request-$kind')));
      await tester.tap(find.byKey(Key('request-$kind')));
      await tester.pumpAndSettle();
      expect(repo.calls.last.method, 'requestPermission');
      expect(repo.calls.last.arguments, {'kind': kind});
    }
    repo.publish(fixture(revision: 2, capabilities: granted));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
  testWidgets('dialog allows explicit permission refresh without OS request', (
    tester,
  ) async {
    final repo = FakeNativeRepository()
      ..current = fixture(capabilities: missing);
    await mount(tester, repo);
    await tester.tap(find.byKey(const Key('refreshPermissions')));
    await tester.pumpAndSettle();
    expect(repo.calls.last.method, 'refreshCapabilities');
    expect(repo.calls.where((c) => c.method == 'requestPermission'), isEmpty);
  });
  testWidgets('latest missing snapshot wins over a grant in the same frame', (
    tester,
  ) async {
    final repo = FakeNativeRepository()
      ..current = fixture(capabilities: missing);
    await mount(tester, repo);
    repo.publish(fixture(revision: 2, capabilities: granted));
    repo.publish(fixture(revision: 3, capabilities: missing));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
  });
  testWidgets('all permissions granted never opens onboarding', (tester) async {
    await mount(
      tester,
      FakeNativeRepository()..current = fixture(capabilities: granted),
    );
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byKey(const Key('reviewPermissions')), findsNothing);
  });
  testWidgets('later stays dismissed across updates and banner reopens', (
    tester,
  ) async {
    final repo = FakeNativeRepository()
      ..current = fixture(capabilities: missing);
    await mount(tester, repo);
    await tester.tap(find.byKey(const Key('permissionsLater')));
    await tester.pumpAndSettle();
    for (var revision = 2; revision < 8; revision++) {
      repo.publish(fixture(revision: revision, capabilities: missing));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    }
    await tester.tap(find.byKey(const Key('reviewPermissions')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
  });
  testWidgets('revocation and new native session reopen onboarding', (
    tester,
  ) async {
    final repo = FakeNativeRepository()
      ..current = fixture(capabilities: granted);
    await mount(tester, repo);
    repo.publish(fixture(revision: 2, capabilities: missing));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.byKey(const Key('permissionsLater')));
    await tester.pumpAndSettle();
    repo.publish(fixture(sessionID: 'new', capabilities: missing));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
  });
  testWidgets('partial grants update actions and small window scrolls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(520, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = FakeNativeRepository()
      ..current = fixture(capabilities: missing);
    await mount(tester, repo);
    repo.publish(
      fixture(revision: 2, capabilities: {...missing, 'listen': true}),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('request-listen')), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('request-ax')));
    await tester.tap(find.byKey(const Key('request-ax')));
    await tester.pumpAndSettle();
    expect(repo.calls.last.arguments, {'kind': 'ax'});
    expect(tester.takeException(), isNull);
  });
}
