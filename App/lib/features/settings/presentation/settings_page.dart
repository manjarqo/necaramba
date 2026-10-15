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
            _ => l.loginStatusUnknown,
          }, style: theme.textTheme.bodySmall),
          value:
              snapshot.login['enabled'] == true ||
              snapshot.login['status'] == 'requiresApproval',
          onChanged: ui.busy
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
        LayoutShortcutSelector(preferences: snapshot.preferences, ui: ui),
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

/// One native preference transaction; the confirmed snapshot owns selection.
class LayoutShortcutSelector extends StatelessWidget {
  const LayoutShortcutSelector({
    super.key,
    required this.preferences,
    required this.ui,
  });
  final Map<String, bool> preferences;
  final FeatureUI ui;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = ui.l;
    final choices = {
      'shift': (l.shortcutShift, '⇧'),
      'alt': (l.shortcutAltShift, '⌥ ⇧'),
      'control': (l.shortcutControlShift, '⌃ ⇧'),
      'command': (l.shortcutCommandShift, '⌘ ⇧'),
      'off': (l.shortcutOff, ''),
    };
    final selected = preferences['altShiftEnabled'] == true
        ? 'alt'
        : preferences['controlShiftEnabled'] == true
        ? 'control'
        : preferences['commandShiftEnabled'] == true
        ? 'command'
        : preferences['singleShiftEnabled'] == true
        ? 'shift'
        : 'off';
    Widget keycap(String value) => ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Text(value, style: const TextStyle(fontSize: 16, height: 1.2)),
      ),
    );
    final selector = PopupMenuButton<String>(
      key: const Key('layoutShortcut'),
      enabled: !ui.busy,
      tooltip: l.layoutShortcut,
      initialValue: selected,
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 360),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onSelected: (value) => ui.cubit.run('setPreferences', {
        'patch': {
          'singleShiftEnabled': value == 'shift',
          'altShiftEnabled': value == 'alt',
          'controlShiftEnabled': value == 'control',
          'commandShiftEnabled': value == 'command',
        },
      }),
      itemBuilder: (_) => [
        for (final choice in choices.entries)
          PopupMenuItem<String>(
            key: Key('layoutShortcut-${choice.key}'),
            value: choice.key,
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: choice.key == selected
                      ? Icon(
                          Icons.check_rounded,
                          size: 17,
                          color: theme.colorScheme.primary,
                        )
                      : null,
                ),
                const SizedBox(width: 6),
                Expanded(child: Text(choice.value.$1)),
                if (choice.value.$2.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  keycap(choice.value.$2),
                ],
              ],
            ),
          ),
      ],
      child: Semantics(
        label: l.layoutShortcut,
        value: choices[selected]!.$1,
        button: true,
        enabled: !ui.busy,
        child: Opacity(
          opacity: ui.busy ? 0.45 : 1,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    choices[selected]!.$1,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  Icons.unfold_more_rounded,
                  size: 17,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.layoutShortcut, style: theme.textTheme.bodyLarge),
        const SizedBox(height: 3),
        Text(l.layoutShortcutHelp, style: theme.textTheme.bodySmall),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stack =
              constraints.maxWidth < 560 ||
              MediaQuery.textScalerOf(context).scale(14) > 18;
          return stack
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [copy, const SizedBox(height: 12), selector],
                )
              : Row(
                  children: [
                    Expanded(child: copy),
                    const SizedBox(width: 24),
                    selector,
                  ],
                );
        },
      ),
    );
  }
}
