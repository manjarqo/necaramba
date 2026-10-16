import 'package:flutter/material.dart';

import '../../../presentation/shared/feature_ui.dart';
import '../../../presentation/shared/mac_switch.dart';
import '../../../presentation/theme/workspace_theme.dart';

class SettingsPage extends SnapshotFeature {
  const SettingsPage({super.key, required super.snapshot});
  @override
  List<Widget> content(FeatureUI ui) {
    final l = ui.l;
    final additionalAvailable =
        snapshot.model['additionalCorrectionsAvailable'] == true;
    final theme = Theme.of(ui.context);
    Widget toggle(
      String key,
      String label, {
      String? description,
      bool available = true,
    }) => MacSwitchTile(
      key: Key(key),
      title: label,
      subtitle: description,
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
      padding: const EdgeInsets.only(top: 22, bottom: 7, left: 4),
      child: Text(text, style: theme.textTheme.titleMedium),
    );
    Widget note(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 7, 4, 0),
      child: Text(text, style: theme.textTheme.bodySmall),
    );
    return [
      const CorrectionExample(),
      heading(l.autoCorrection),
      group([
        toggle('autoEnabled', l.autoEnabled, description: l.afterSpace),
        toggle('typoEnabled', l.typo, available: additionalAvailable),
        toggle('yoEnabled', l.yoEnabled, available: additionalAvailable),
      ]),
      note(l.autoAvailability),
      if (!additionalAvailable) note(l.additionalUnavailable),
      heading(l.keyboardShortcuts),
      group([
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.doubleShift, style: theme.textTheme.bodyLarge),
                    const SizedBox(height: 2),
                    Text(l.doubleShiftHelp, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const Keycaps(['⇧', '⇧']),
            ],
          ),
        ),
        LayoutShortcutSelector(preferences: snapshot.preferences, ui: ui),
        toggle('optionEnabled', l.optionEnabled),
        toggle('splitShiftEnabled', l.splitShiftEnabled),
        toggle('plainPasteEnabled', l.plainPasteEnabled),
      ]),
      heading(l.system),
      group([
        MacSwitchTile(
          key: const Key('launchAtLogin'),
          title: l.login,
          subtitle: switch (snapshot.login['status']) {
            'enabled' => l.enabled,
            'disabled' => l.disabled,
            'requiresApproval' => l.requiresApproval,
            _ => l.loginStatusUnknown,
          },
          value:
              snapshot.login['enabled'] == true ||
              snapshot.login['status'] == 'requiresApproval',
          onChanged: ui.busy
              ? null
              : (value) => ui.cubit.run('setLoginEnabled', {'enabled': value}),
        ),
        toggle('soundEnabled', l.soundEnabled),
      ]),
      note(l.settingsIntro),
    ];
  }
}

/// The signature moment of the app: a wrong-layout word and its correction.
class CorrectionExample extends StatelessWidget {
  const CorrectionExample({super.key});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = FeatureUI(context).l;
    final word = TextStyle(
      fontSize: 24,
      height: 1.2,
      fontWeight: FontWeight.w600,
      letterSpacing: .2,
      color: theme.colorScheme.onSurface,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Wrap(
          spacing: 24,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Semantics(
              label: 'ghbdtn → привет',
              child: ExcludeSemantics(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'ghbdtn',
                        style: word.copyWith(
                          color: theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: .8,
                          ),
                          decoration: TextDecoration.lineThrough,
                          decorationThickness: 2,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 22,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Text('привет', style: word),
                    ],
                  ),
                ),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: Text(l.exampleHelp, style: theme.textTheme.bodySmall),
            ),
          ],
        ),
      ),
    );
  }
}

/// Key glyphs drawn like the legends on a Mac keyboard.
class Keycaps extends StatelessWidget {
  const Keycaps(this.keys, {super.key});
  final List<String> keys;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = MacTokens.of(context);
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < keys.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Container(
              constraints: const BoxConstraints(minWidth: 26),
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: tokens.hairline),
                boxShadow: [
                  BoxShadow(
                    color: tokens.hairline,
                    offset: const Offset(0, 1.5),
                  ),
                ],
              ),
              child: Text(
                keys[i],
                style: TextStyle(
                  fontSize: 13,
                  height: 1.1,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ],
      ),
    );
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
