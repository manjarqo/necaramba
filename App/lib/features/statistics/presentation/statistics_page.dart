import 'package:flutter/material.dart';

import '../../../presentation/shared/feature_ui.dart';
import '../../../domain/usecases/estimate_time_saved.dart';

class StatisticsPage extends SnapshotFeature {
  const StatisticsPage({super.key, required super.snapshot});
  @override
  List<Widget> content(FeatureUI ui) {
    final s = snapshot;
    final context = ui.context;
    final l = ui.l;
    final cubit = ui.cubit;
    final busy = ui.busy;

    final counts = s.statistics;
    final estimate = const EstimateTimeSaved().seconds(counts);
    final names = {
      'layout': l.layout,
      'typo': l.typo,
      'doubleCaps': l.doubleCaps,
      'yo': l.yo,
      'manual': l.manual,
      'undo': l.undo,
    };
    return [
      ui.intro(l.statisticsIntro),
      ui.card([
        Text(l.estimate, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Text(
          '$estimate ${l.seconds}',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 12),
        Text(l.formula),
      ]),
      const SizedBox(height: 16),
      ui.card([
        for (final entry in names.entries)
          ui.label(entry.value, counts[entry.key] ?? 0),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: busy
                ? null
                : () async {
                    if (await ui.confirm(
                      l.resetCounters,
                      message: l.resetQuestion,
                    )) {
                      await cubit.run('resetCounters', {'confirmed': true});
                    }
                  },
            child: Text(l.resetCounters),
          ),
        ),
      ]),
    ];
  }
}
