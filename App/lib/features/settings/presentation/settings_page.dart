import 'package:flutter/material.dart';

import '../../../presentation/shared/feature_ui.dart';

class SettingsPage extends SnapshotFeature {
  const SettingsPage({super.key, required super.snapshot});
  @override
  List<Widget> content(FeatureUI ui) {
    final l = ui.l;
    final theme = Theme.of(ui.context);
    Widget toggle(
      String key,
      String label, {
      String? description,
      bool available = true,
    }) => SwitchListTile(
      key: Key(key),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      title: Text(label),
      subtitle: description == null
          ? null
          : Text(description, style: theme.textTheme.bodySmall),
      value: snapshot.preferences[key]!,
      onChanged: ui.busy || !available
          ? null
          : (value) => ui.cubit.run('setPreferences', {
              'patch': {key: value},
            }),
    );
    Widget group(List<Widget> rows) => Card(
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Divider(),
              ),
            rows[i],
          ],
        ],
      ),
    );
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8, left: 2),
      child: Text(text, style: theme.textTheme.titleMedium),
    );
    return [
      ui.intro(l.settingsIntro),
      group([
        SwitchListTile(
          key: const Key('launchAtLogin'),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 2,
          ),
          title: Text(l.login),
          subtitle: Text(switch (snapshot.login['status']) {
            'enabled' => l.enabled,
            'disabled' => l.disabled,
            'requiresApproval' => l.requiresApproval,
            _ => l.errorUnavailable,
          }, style: theme.textTheme.bodySmall),
          value:
              snapshot.login['enabled'] == true ||
              snapshot.login['status'] == 'requiresApproval',
          onChanged: ui.busy || snapshot.login['status'] == 'unavailable'
              ? null
              : (value) => ui.cubit.run('setLoginEnabled', {'enabled': value}),
        ),
      ]),
      const SizedBox(height: 12),
      group([toggle('autoEnabled', l.autoEnabled, description: l.afterSpace)]),
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 8, 2, 0),
        child: Text(l.autoAvailability, style: theme.textTheme.bodySmall),
      ),
      heading(l.keyboardShortcuts),
      group([
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.doubleShift, style: theme.textTheme.bodyLarge),
                    const SizedBox(height: 3),
                    Text(l.doubleShiftHelp, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: theme.scaffoldBackgroundColor,
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Text('⇧ ⇧', style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
        toggle('singleShiftEnabled', l.singleShiftEnabled),
        toggle('optionEnabled', l.optionEnabled),
        toggle('splitShiftEnabled', l.splitShiftEnabled),
        toggle('plainPasteEnabled', l.plainPasteEnabled),
      ]),
      heading(l.additionalCorrections),
      group([
        toggle('typoEnabled', l.typoEnabled, available: false),
        toggle('yoEnabled', l.yoEnabled, available: false),
      ]),
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 8, 2, 0),
        child: Text(l.additionalUnavailable, style: theme.textTheme.bodySmall),
      ),
      heading(l.sound),
      group([toggle('soundEnabled', l.soundEnabled)]),
      const SizedBox(height: 20),
    ];
  }
}
