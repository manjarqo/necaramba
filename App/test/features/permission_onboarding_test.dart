import 'dart:async';

import 'package:flutter/material.dart';
import 'package:necaramba/domain/repositories/native_repository.dart';
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
  testWidgets(
    'explicit refresh acknowledges missing access locally and clears on request',
    (tester) async {
      final repo = FakeNativeRepository()
        ..current = fixture(capabilities: missing);
      await mount(tester, repo);
      final checked = find.textContaining('Checked. macOS');
      expect(checked, findsNothing);
      await tester.tap(find.byKey(const Key('refreshPermissions')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: find.byType(AlertDialog), matching: checked),
        findsOneWidget,
      );
      repo.pending = Completer<NativeReply>();
      await tester.ensureVisible(find.byKey(const Key('request-listen')));
      await tester.tap(find.byKey(const Key('request-listen')));
      await tester.pump();
      expect(checked, findsNothing);
      repo.pending!.completeError(
        const NativeFailure('unavailable', retryable: true),
      );
      await tester.pumpAndSettle();
      expect(checked, findsNothing);
    },
  );
  testWidgets(
    'failed refresh never reports checked and successful grant closes dialog',
    (tester) async {
      final repo = FakeNativeRepository()
        ..current = fixture(capabilities: missing);
      await mount(tester, repo);
      repo.failure = const NativeFailure('unavailable', retryable: true);
      await tester.tap(find.byKey(const Key('refreshPermissions')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Checked. macOS'), findsNothing);
      expect(find.byType(AlertDialog), findsOneWidget);
      repo.current = fixture(revision: 2, capabilities: granted);
      await tester.tap(find.byKey(const Key('refreshPermissions')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
  testWidgets(
    'Permissions page acknowledges explicit refresh only on that page',
    (tester) async {
      final repo = FakeNativeRepository()
        ..current = fixture(capabilities: missing);
      await mount(tester, repo);
      await tester.tap(find.byKey(const Key('permissionsLater')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Access').first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Refresh status'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Refresh status'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Checked. macOS'), findsOneWidget);
      await tester.tap(find.text('Settings').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Checked. macOS'), findsNothing);
    },
  );
  testWidgets(
    'refresh feedback uses newer confirmed state than delayed reply',
    (tester) async {
      final repo = FakeNativeRepository()
        ..current = fixture(capabilities: missing);
      await mount(tester, repo);
      repo.pending = Completer<NativeReply>();
      await tester.tap(find.byKey(const Key('refreshPermissions')));
      await tester.pump();
      expect(find.textContaining('Checked. macOS'), findsNothing);
      repo.publish(fixture(revision: 3, capabilities: missing));
      await tester.pump();
      repo.pending!.complete(
        NativeReply(
          requestID: 'check',
          state: fixture(revision: 2, capabilities: granted),
          result: {},
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('Checked. macOS'), findsOneWidget);
    },
  );
  testWidgets(
    'checked feedback survives unrelated snapshots but expires on capability change',
    (tester) async {
      final repo = FakeNativeRepository()
        ..current = fixture(capabilities: missing);
      await mount(tester, repo);
      await tester.tap(find.byKey(const Key('refreshPermissions')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Checked. macOS'), findsOneWidget);
      repo.publish(fixture(revision: 2, auto: false, capabilities: missing));
      await tester.pumpAndSettle();
      expect(find.textContaining('Checked. macOS'), findsOneWidget);
      repo.publish(
        fixture(revision: 3, capabilities: {...missing, 'listen': true}),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Checked. macOS'), findsNothing);
      repo.publish(fixture(revision: 4, capabilities: missing));
      await tester.pumpAndSettle();
      expect(find.textContaining('Checked. macOS'), findsNothing);
    },
  );
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
