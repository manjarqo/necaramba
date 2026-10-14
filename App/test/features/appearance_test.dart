import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:necaramba/main.dart';
import 'package:necaramba/domain/repositories/window_interaction.dart';
import 'package:necaramba/domain/usecases/estimate_time_saved.dart';
import 'package:necaramba/presentation/workspace_page.dart';

import '../support/native_fakes.dart';

class FakeWindow implements WindowInteractionPort {
  final events = StreamController<String>.broadcast();
  HeaderDropRegion? region;
  @override
  Stream<String> get headerDropHandles => events.stream;
  @override
  Future<void> updateHeaderDropRegion(HeaderDropRegion? value) async {
    region = value;
  }
}

void main() {
  test('palette has25 original colors with readable header contrast', () {
    expect(headerColors.length, 25);
    for (final color in headerColors) {
      final ratio =
          (color.computeLuminance() + .05) /
          (const Color(0xff192c21).computeLuminance() + .05);
      expect(ratio, greaterThanOrEqualTo(4.5));
    }
  });
  test('time estimate uses documented weights and ignores undo', () {
    expect(
      const EstimateTimeSaved().seconds({
        'layout': 3,
        'manual': 4,
        'typo': 2,
        'doubleCaps': 1,
        'yo': 2,
        'undo': 100,
      }),
      17,
    );
  });
  testWidgets(
    'header exposes only its rect and consumes opaque native handles',
    (tester) async {
      final repository = FakeNativeRepository();
      final window = FakeWindow();
      await tester.pumpWidget(
        NecarambaApp(
          repository: repository,
          windowInteraction: window,
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      expect(window.region!.height, 126);
      expect(window.region!.width, 800);
      window.events.add('opaque-drop-handle');
      await tester.pumpAndSettle();
      expect(repository.calls.last.method, 'importHeaderImage');
      expect(repository.calls.last.arguments, {'handle': 'opaque-drop-handle'});
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(window.region, isNull);
      await window.events.close();
      await repository.dispose();
    },
  );
}
