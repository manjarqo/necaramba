import 'package:flutter/material.dart';

import '../../../presentation/shared/feature_ui.dart';

class AboutPage extends SnapshotFeature {
  const AboutPage({super.key, required super.snapshot});
  @override
  List<Widget> content(FeatureUI ui) {
    final s = snapshot;
    final context = ui.context;
    final l = ui.l;
    final cubit = ui.cubit;
    final busy = ui.busy;
    return [
      ui.intro(l.aboutIntro),
      ui.card([
        ui.label(l.version, '1.0.0+1'),
        ui.label(l.modelVersion, s.model['version']),
        Text(l.help, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        Text(l.helpText),
      ]),
      const SizedBox(height: 16),
      ui.section(l.diagnostics, [
        ui.intro(l.privacy),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            ui.button(l.exportDiagnostics, 'exportDiagnostics'),
            ui.button(l.exportArchive, 'exportArchive'),
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (await ui.confirm(
                        l.importArchive,
                        message: l.importQuestion,
                      )) {
                        await cubit.run('importArchive', {});
                      }
                    },
              child: Text(l.importArchive),
            ),
          ],
        ),
      ]),
    ];
  }
}
