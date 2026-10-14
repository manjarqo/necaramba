import 'package:flutter/material.dart';

import '../../../presentation/shared/feature_ui.dart';

class SettingsPage extends SnapshotFeature {
  const SettingsPage({super.key, required super.snapshot});
  @override
  List<Widget> content(FeatureUI ui) {
    final s = snapshot;
    final l = ui.l;
    final cubit = ui.cubit;
    final busy = ui.busy;

    final names = {
      'autoEnabled': l.autoEnabled,
      'typoEnabled': l.typoEnabled,
      'yoEnabled': l.yoEnabled,
      'singleShiftEnabled': l.singleShiftEnabled,
      'optionEnabled': l.optionEnabled,
      'splitShiftEnabled': l.splitShiftEnabled,
      'plainPasteEnabled': l.plainPasteEnabled,
      'soundEnabled': l.soundEnabled,
    };
    return [
      ui.intro(l.settingsIntro),
      ui.card([
        for (final entry in names.entries)
          SwitchListTile(
            key: Key(entry.key),
            contentPadding: EdgeInsets.zero,
            title: Text(entry.value),
            value: s.preferences[entry.key]!,
            onChanged: busy
                ? null
                : (value) => cubit.run('setPreferences', {
                    'patch': {entry.key: value},
                  }),
          ),
      ]),
      const SizedBox(height: 16),
      ui.intro(l.manualHint),
    ];
  }
}
