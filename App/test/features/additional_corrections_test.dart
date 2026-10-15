import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:necaramba/data/native_state_decoder.dart';
import 'package:necaramba/domain/repositories/native_repository.dart';
import 'package:necaramba/main.dart';
import 'package:necaramba/l10n/app_localizations.dart';

import '../support/native_fakes.dart';

Map<String, Object?> snapshot() => NativeStateDecoder.encode(
  fixture(
    sessionID: '00000000-0000-4000-8000-000000000001',
    capabilities: {
      'listen': true,
      'post': true,
      'axTrusted': true,
      'secureInput': false,
    },
  ),
);
void main() {
  test(
    'legacy model defaults unavailable and availability requires a bool',
    () {
      final raw = snapshot();
      expect(
        NativeStateDecoder.decode(raw).model['additionalCorrectionsAvailable'],
        false,
      );
      final model = Map<String, Object?>.from(raw['model']! as Map);
      raw['model'] = model;
      model['additionalCorrectionsAvailable'] = true;
      expect(
        NativeStateDecoder.decode(raw).model['additionalCorrectionsAvailable'],
        true,
      );
      for (final invalid in [null, 1, 'true']) {
        model['additionalCorrectionsAvailable'] = invalid;
        expect(
          () => NativeStateDecoder.decode(raw),
          throwsA(isA<NativeFailure>()),
        );
      }
    },
  );
  for (final available in [false, true]) {
    testWidgets('additional correction toggles availability $available', (
      tester,
    ) async {
      final raw = snapshot();
      raw['model'] = {
        ...raw['model']! as Map,
        'additionalCorrectionsAvailable': available,
      };
      final repository = FakeNativeRepository()
        ..current = NativeStateDecoder.decode(raw);
      await tester.pumpWidget(
        NecarambaApp(repository: repository, locale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      final l = AppLocalizations.of(
        tester.element(find.byKey(const Key('typoEnabled'))),
      )!;
      expect(
        find.text(l.additionalUnavailable),
        available ? findsNothing : findsOneWidget,
      );
      for (final key in ['typoEnabled', 'yoEnabled']) {
        final finder = find.byKey(Key(key));
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        expect(
          tester.widget<SwitchListTile>(finder).onChanged != null,
          available,
        );
        if (available) {
          await tester.tap(finder);
          await tester.pumpAndSettle();
          expect(repository.calls.last.arguments['patch'], {key: false});
        }
      }
    });
  }
}
