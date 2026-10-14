import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:necaramba/main.dart';

import '../support/native_fakes.dart';

void main() {
  testWidgets(
    'login toggle is available in settings and sends native command',
    (tester) async {
      final repository = FakeNativeRepository();
      await tester.pumpWidget(
        NecarambaApp(repository: repository, locale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      final toggle = find.byKey(const Key('launchAtLogin'));
      expect(toggle, findsOneWidget);
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(repository.calls.last.method, 'setLoginEnabled');
      expect(repository.calls.last.arguments, {'enabled': true});
      // The native reply still reports disabled; no optimistic enabled state.
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    },
  );

  testWidgets('free app navigation has no purchase or license destination', (
    tester,
  ) async {
    final repository = FakeNativeRepository();
    await tester.pumpWidget(
      NecarambaApp(repository: repository, locale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    expect(find.text('License'), findsNothing);
    expect(find.text('About'), findsOneWidget);
  });

  testWidgets(
    'settings explain the boundary and keep manual shortcut discoverable',
    (tester) async {
      final repository = FakeNativeRepository();
      await tester.pumpWidget(
        NecarambaApp(repository: repository, locale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      expect(find.text('After you press Space'), findsOneWidget);
      expect(find.text('Double Shift'), findsOneWidget);
      expect(find.text('Keyboard shortcuts'), findsOneWidget);
      expect(find.byKey(const Key('autoEnabled')), findsOneWidget);
    },
  );

  testWidgets(
    'unavailable extra corrections preserve values without offering ineffective toggles',
    (tester) async {
      final repository = FakeNativeRepository();
      await tester.pumpWidget(
        NecarambaApp(repository: repository, locale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      for (final key in ['typoEnabled', 'yoEnabled']) {
        final toggle = tester.widget<SwitchListTile>(find.byKey(Key(key)));
        expect(toggle.value, isTrue);
        expect(toggle.onChanged, isNull);
      }
    },
  );

  testWidgets(
    'toolbar distinguishes native readiness from the saved automatic preference',
    (tester) async {
      final repository = FakeNativeRepository();
      await tester.pumpWidget(
        NecarambaApp(repository: repository, locale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      var revision = 2;
      for (final status in {
        'starting': 'Starting…',
        'unavailable': 'Automatic correction unavailable',
        'active': 'Active',
        'off': 'Automation off',
      }.entries) {
        repository.publish(
          fixture(
            revision: revision++,
            status: status.key,
            capabilities: {
              'listen': true,
              'post': true,
              'axTrusted': true,
              'secureInput': false,
            },
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(status.value), findsOneWidget);
        expect(
          tester
              .widget<SwitchListTile>(find.byKey(const Key('autoEnabled')))
              .value,
          isTrue,
        );
      }
      repository.controller.addError(Exception('disconnected'));
      await tester.pumpAndSettle();
      expect(find.text('Not connected'), findsOneWidget);
      expect(find.text('Automation off'), findsNothing);
    },
  );

  testWidgets(
    'narrow dark workspace supports large text and every destination',
    (tester) async {
      tester.view.physicalSize = const Size(520, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final repository = FakeNativeRepository();
      await tester.pumpWidget(
        NecarambaApp(repository: repository, locale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      for (final destination in [
        'Exceptions',
        'Access',
        'Appearance',
        'Rules',
        'Statistics',
        'About',
        'Settings',
      ]) {
        await tester.tap(find.byType(DropdownButtonFormField<int>));
        await tester.pumpAndSettle();
        await tester.tap(find.text(destination).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: destination);
      }
    },
  );
}
