import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:necaramba/domain/repositories/native_repository.dart';
import 'package:necaramba/domain/repositories/window_interaction.dart';
import 'package:necaramba/main.dart';

import '../support/native_fakes.dart';

class FailingWindow implements WindowInteractionPort {
  final events = StreamController<String>.broadcast();
  bool failGeometry = false;
  @override
  Stream<String> get headerDropHandles => events.stream;
  @override
  Future<void> updateHeaderDropRegion(HeaderDropRegion? region) async {
    if (failGeometry) throw const NativeFailure('ioFailure', retryable: false);
  }
}

void main() {
  testWidgets('window geometry failures are redacted visible errors', (
    tester,
  ) async {
    final repository = FakeNativeRepository();
    final window = FailingWindow()..failGeometry = true;
    await tester.pumpWidget(
      NecarambaApp(
        repository: repository,
        windowInteraction: window,
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Unable to save. Your confirmed settings were preserved.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await window.events.close();
    await repository.dispose();
  });
  testWidgets('drop stream failures become redacted visible errors', (
    tester,
  ) async {
    final repository = FakeNativeRepository();
    final window = FailingWindow();
    await tester.pumpWidget(
      NecarambaApp(
        repository: repository,
        windowInteraction: window,
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();
    window.events.addError(
      const NativeFailure('permissionDenied', retryable: false),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Permission denied. Review access permissions.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await window.events.close();
    await repository.dispose();
  });
  testWidgets(
    'long feedback preview scrolls in short window and cancels safely',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = FakeNativeRepository()
        ..result = {
          'previewID': 'bounded',
          'preview': {
            'word': 'word',
            'language': 'english',
            'modelVersion': '1',
            'feedback': List.filled(200, 'Long feedback').join(' '),
            'host': 'rules.example',
          },
        };
      await tester.pumpWidget(
        NecarambaApp(repository: repository, locale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rules'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Preview submission'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Preview submission'));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(800, 450);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(SingleChildScrollView),
        ),
        findsWidgets,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repository.calls.last.method, 'cancelShare');
      expect(
        repository.calls.where((call) => call.method == 'confirmShare'),
        isEmpty,
      );
    },
  );
  testWidgets('feature-owned draft survives navigation between screens', (
    tester,
  ) async {
    final repository = FakeNativeRepository();
    await tester.pumpWidget(
      NecarambaApp(repository: repository, locale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Exceptions'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('wordDraft')), 'unfinished');
    await tester.tap(find.text('General').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Exceptions'));
    await tester.pumpAndSettle();
    expect(find.text('unfinished'), findsOneWidget);
    expect(repository.calls.where((call) => call.method == 'addWord'), isEmpty);
  });
}
