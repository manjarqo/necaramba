import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:necaramba/domain/entities/native_state.dart';
import 'package:necaramba/main.dart';

import '../support/native_fakes.dart';

NativeState themed(String mode, {int revision = 2}) {
  final base = fixture(revision: revision);
  return fixture(
    revision: revision,
    capabilities: base.capabilities,
    appearance: {...base.appearance, 'themeMode': mode},
  );
}

void main() {
  testWidgets('the app follows the system theme until another is chosen', (
    tester,
  ) async {
    final repository = FakeNativeRepository();
    await tester.pumpWidget(
      NecarambaApp(repository: repository, locale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    MaterialApp app() => tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app().themeMode, ThemeMode.system);
    repository.publish(themed('dark'));
    await tester.pumpAndSettle();
    expect(app().themeMode, ThemeMode.dark);
    repository.publish(themed('light', revision: 3));
    await tester.pumpAndSettle();
    expect(app().themeMode, ThemeMode.light);
  });

  testWidgets('appearance offers system, light and dark themes', (
    tester,
  ) async {
    final repository = FakeNativeRepository();
    await tester.pumpWidget(
      NecarambaApp(repository: repository, locale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appearance').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('theme-system')), findsOneWidget);
    expect(find.byKey(const Key('theme-light')), findsOneWidget);
    await tester.tap(find.byKey(const Key('theme-dark')));
    await tester.pumpAndSettle();
    expect(repository.calls.last.method, 'setThemeMode');
    expect(repository.calls.last.arguments, {'mode': 'dark'});
  });
}
