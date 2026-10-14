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
        for (final capability in [
          ('listen', l.listen),
          ('post', l.post),
          ('ax', l.ax),
        ])
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              s.capabilities[capability.$1 == 'ax'
                          ? 'axTrusted'
                          : capability.$1] ==
                      true
                  ? Icons.check_circle_outline
                  : Icons.radio_button_unchecked,
            ),
            title: Text(capability.$2),
            subtitle: Text(
              s.capabilities[capability.$1 == 'ax'
                          ? 'axTrusted'
                          : capability.$1] ==
                      true
                  ? l.granted
                  : l.notGranted,
            ),
            trailing: ui.button(l.request, 'requestPermission', {
              'kind': capability.$1,
            }),
          ),
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
