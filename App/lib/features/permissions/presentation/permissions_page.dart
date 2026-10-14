import 'package:flutter/material.dart';

import '../../../presentation/shared/feature_ui.dart';

class PermissionsPage extends SnapshotFeature {
  const PermissionsPage({super.key, required super.snapshot});
  @override
  List<Widget> content(FeatureUI ui) {
    final s = snapshot;
    final l = ui.l;
    return [
      ui.intro(l.accessIntro),
      ui.card([
        PermissionControls(snapshot: s),
        ui.label(
          l.secureInput,
          s.capabilities['secureInput'] == true ? l.active : l.inactive,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: ui.button(l.refresh, 'refreshCapabilities'),
        ),
      ]),
    ];
  }
}

class PermissionControls extends SnapshotFeature {
  const PermissionControls({super.key, required super.snapshot});
  @override
  List<Widget> content(FeatureUI ui) => [
    for (final permission in [
      ('listen', 'listen', ui.l.listen, ui.l.listenHelp),
      ('post', 'post', ui.l.post, ui.l.postHelp),
      ('ax', 'axTrusted', ui.l.ax, ui.l.axHelp),
    ])
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              permission.$3,
              style: Theme.of(ui.context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(permission.$4),
            const SizedBox(height: 4),
            if (snapshot.capabilities[permission.$2] == true)
              Text(ui.l.granted)
            else ...[
              Text(ui.l.notGranted),
              OutlinedButton(
                key: Key('request-${permission.$1}'),
                onPressed: ui.busy
                    ? null
                    : () => ui.cubit.run('requestPermission', {
                        'kind': permission.$1,
                      }),
                child: Text(ui.l.request),
              ),
            ],
          ],
        ),
      ),
  ];
}
