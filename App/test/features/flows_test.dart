import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:necaramba/main.dart';
import 'package:necaramba/domain/repositories/native_repository.dart';

import '../support/native_fakes.dart';

void main() {
  testWidgets('eight flags retain confirmed values after permission failure', (
    tester,
  ) async {
    final repo = FakeNativeRepository();
    await tester.pumpWidget(
      NecarambaApp(repository: repo, locale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SwitchListTile &&
            widget.key != const Key('launchAtLogin'),
      ),
      findsNWidgets(8),
    );
    repo.failure = const NativeFailure('permissionDenied', retryable: false);
    await tester.tap(find.byKey(const Key('autoEnabled')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(find.byKey(const Key('autoEnabled'))).value,
      true,
    );
    expect(
      find.text('Permission denied. Review access permissions.'),
      findsOneWidget,
    );
  });
  testWidgets('clear cancellation makes no native mutation', (tester) async {
    final repo = FakeNativeRepository();
    await tester.pumpWidget(
      NecarambaApp(repository: repo, locale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Exceptions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear words'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.calls.where((call) => call.method == 'clearWords'), isEmpty);
  });
  testWidgets('share preview cancellation never confirms submission', (
    tester,
  ) async {
    final repo = FakeNativeRepository()
      ..result = {
        'previewID': 'p1',
        'preview': {
          'word': 'hello',
          'language': 'english',
          'modelVersion': '1',
          'feedback': 'test',
          'host': 'rules.example',
        },
      };
    await tester.pumpWidget(
      NecarambaApp(repository: repo, locale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rules'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('shareWord')), 'hello');
    await tester.ensureVisible(find.text('Preview submission'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preview submission'));
    await tester.pumpAndSettle();
    expect(find.text('rules.example'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.calls.where((call) => call.method == 'confirmShare'), isEmpty);
    expect(repo.calls.last.method, 'cancelShare');
  });
  testWidgets(
    'failed word save preserves draft and displays validation error',
    (tester) async {
      final repo = FakeNativeRepository();
      await tester.pumpWidget(
        NecarambaApp(repository: repo, locale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Exceptions'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('wordDraft')), 'bad%');
      repo.failure = const NativeFailure('invalidArgument', retryable: false);
      await tester.tap(find.byKey(const Key('addWord')));
      await tester.pumpAndSettle();
      expect(find.text('bad%'), findsOneWidget);
      expect(find.text('Invalid value. Review your entry.'), findsOneWidget);
    },
  );
  testWidgets(
    'capabilities display independently and react to stream changes',
    (tester) async {
      final repo = FakeNativeRepository()..current = fixture();
      await tester.pumpWidget(
        NecarambaApp(repository: repo, locale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('permissionRequired')), findsOneWidget);
      await tester.tap(find.byKey(const Key('permissionsLater')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Access'));
      await tester.pumpAndSettle();
      expect(find.text('Granted'), findsOneWidget);
      expect(find.text('Not granted'), findsNWidgets(2));
      await tester.ensureVisible(find.byKey(const Key('request-post')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('request-post')));
      await tester.pumpAndSettle();
      expect(repo.calls.last.arguments, {'kind': 'post'});
    },
  );
  testWidgets('stream failure disables changes until explicit reconnect', (
    tester,
  ) async {
    final repo = FakeNativeRepository();
    await tester.pumpWidget(
      NecarambaApp(repository: repo, locale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    repo.controller.addError(
      const NativeFailure('unavailable', retryable: true),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const Key('autoEnabled')))
          .onChanged,
      isNull,
    );
    await tester.tap(find.byTooltip('Reconnect'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const Key('autoEnabled')))
          .onChanged,
      isNotNull,
    );
  });
  testWidgets('RU locale and narrow window preserve navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(520, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = FakeNativeRepository();
    await tester.pumpWidget(
      NecarambaApp(repository: repo, locale: const Locale('ru')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Настройки'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Доступ').last);
    await tester.pumpAndSettle();
    expect(find.text('Прослушивание событий клавиатуры'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('sharing confirms only the immutable preview ID', (tester) async {
    final repo = FakeNativeRepository()
      ..result = {
        'previewID': 'p2',
        'preview': {
          'word': 'exact',
          'language': 'english',
          'modelVersion': '19',
          'feedback': null,
          'host': 'rules.example',
        },
      };
    await tester.pumpWidget(
      NecarambaApp(repository: repo, locale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rules'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('shareWord')), 'draft');
    await tester.ensureVisible(find.text('Preview submission'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preview submission'));
    await tester.pumpAndSettle();
    expect(find.text('exact'), findsOneWidget);
    expect(find.text('19'), findsOneWidget);
    await tester.tap(find.text('Send this rule'));
    await tester.pumpAndSettle();
    expect(repo.calls.last.method, 'confirmShare');
    expect(repo.calls.last.arguments, {'previewID': 'p2'});
  });
}
