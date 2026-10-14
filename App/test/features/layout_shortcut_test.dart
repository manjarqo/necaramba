import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:necaramba/data/native_state_decoder.dart';
import 'package:necaramba/domain/repositories/native_repository.dart';
import 'package:necaramba/main.dart';

import '../support/native_fakes.dart';

void main() {
  test('legacy shortcut snapshots migrate and invalid choices fail', () {
    final raw = NativeStateDecoder.encode(
      fixture(sessionID: '00000000-0000-4000-8000-000000000001'),
    );
    final prefs = Map<String, Object?>.from(raw['preferences']! as Map)
      ..remove('altShiftEnabled')
      ..remove('controlShiftEnabled');
    raw['preferences'] = prefs;
    expect(
      NativeStateDecoder.decode(raw).preferences['altShiftEnabled'],
      false,
    );
    expect(
      NativeStateDecoder.decode(raw).preferences['controlShiftEnabled'],
      false,
    );
    prefs['altShiftEnabled'] = true;
    prefs['controlShiftEnabled'] = false;
    expect(() => NativeStateDecoder.decode(raw), throwsA(isA<NativeFailure>()));
    prefs['altShiftEnabled'] = 'false';
    expect(() => NativeStateDecoder.decode(raw), throwsA(isA<NativeFailure>()));
  });
  testWidgets('choices send atomic patches without optimistic changes', (
    tester,
  ) async {
    final repository = FakeNativeRepository();
    await tester.pumpWidget(
      NecarambaApp(repository: repository, locale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    for (final choice in ['alt', 'control', 'off', 'shift']) {
      final selector = find.byKey(const Key('layoutShortcut'));
      await tester.ensureVisible(selector);
      await tester.pumpAndSettle();
      await tester.tap(selector);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('layoutShortcut-$choice')));
      await tester.pumpAndSettle();
      expect(repository.calls.last.method, 'setPreferences');
      expect(repository.calls.last.arguments['patch'], {
        'singleShiftEnabled': choice == 'shift',
        'altShiftEnabled': choice == 'alt',
        'controlShiftEnabled': choice == 'control',
      });
      expect(
        find.descendant(of: selector, matching: find.text('Shift')),
        findsOneWidget,
      );
    }
  });
  testWidgets('pending command disables selector', (tester) async {
    final repository = FakeNativeRepository()
      ..pending = Completer<NativeReply>();
    await tester.pumpWidget(
      NecarambaApp(repository: repository, locale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    final selector = find.byKey(const Key('layoutShortcut'));
    await tester.ensureVisible(selector);
    await tester.pumpAndSettle();
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('layoutShortcut-alt')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.widget<PopupMenuButton<String>>(selector).enabled, false);
    repository.pending!.complete(
      NativeReply(requestID: 'test', state: repository.current, result: {}),
    );
    await tester.pumpAndSettle();
  });
  testWidgets('narrow Russian large text reflects native shortcut', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(520, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final repository = FakeNativeRepository();
    await tester.pumpWidget(
      NecarambaApp(repository: repository, locale: const Locale('ru')),
    );
    await tester.pumpAndSettle();
    final raw = NativeStateDecoder.encode(
      fixture(
        revision: 2,
        sessionID: '00000000-0000-4000-8000-000000000001',
        capabilities: repository.current.capabilities,
      ),
    );
    raw['preferences'] = {
      ...repository.current.preferences,
      'singleShiftEnabled': false,
      'controlShiftEnabled': true,
    };
    repository.publish(NativeStateDecoder.decode(raw));
    await tester.pumpAndSettle();
    final selector = find.byKey(const Key('layoutShortcut'));
    await tester.ensureVisible(selector);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: selector, matching: find.text('Ctrl + Shift')),
      findsOneWidget,
    );
    await tester.tap(selector);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('layoutShortcut-off')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
