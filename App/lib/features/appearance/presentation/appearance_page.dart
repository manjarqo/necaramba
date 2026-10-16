import 'package:flutter/material.dart';

import '../../../presentation/shared/feature_ui.dart';
import '../../../presentation/theme/workspace_theme.dart';
import 'header_palette.dart';

class AppearancePage extends SnapshotFeature {
  const AppearancePage({super.key, required super.snapshot});
  @override
  List<Widget> content(FeatureUI ui) {
    final s = snapshot;
    final context = ui.context;
    final theme = Theme.of(context);
    final tokens = MacTokens.of(context);
    final l = ui.l;
    final cubit = ui.cubit;
    final busy = ui.busy;
    final mode = s.appearance['themeMode'] as String? ?? 'system';
    final selectedColor = s.appearance['colorIndex'] as int? ?? 0;
    Widget heading(String text, {bool first = false}) => Padding(
      padding: EdgeInsets.only(top: first ? 0 : 22, bottom: 7, left: 4),
      child: Text(text, style: theme.textTheme.titleMedium),
    );
    Widget row(List<Widget> children) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
    return [
      heading(l.theme, first: true),
      ui.card([
        Wrap(
          spacing: 16,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<String>(
              key: const Key('themeMode'),
              showSelectedIcon: false,
              segments: [
                for (final (value, label, icon) in [
                  ('system', l.themeSystem, Icons.brightness_auto_rounded),
                  ('light', l.themeLight, Icons.light_mode_rounded),
                  ('dark', l.themeDark, Icons.dark_mode_rounded),
                ])
                  ButtonSegment<String>(
                    value: value,
                    icon: Icon(icon, size: 16),
                    label: Text(label, key: Key('theme-$value')),
                  ),
              ],
              selected: {mode},
              onSelectionChanged: busy
                  ? null
                  : (value) => cubit.run('setThemeMode', {'mode': value.first}),
            ),
            Text(l.themeHelp, style: theme.textTheme.bodySmall),
          ],
        ),
      ]),
      heading(l.color),
      Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            row([
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < headerColors.length; i++)
                    Semantics(
                      label: '${l.color} ${i + 1}',
                      selected: selectedColor == i,
                      button: true,
                      child: Tooltip(
                        message: '${l.color} ${i + 1}',
                        child: InkWell(
                          onTap: busy
                              ? null
                              : () => cubit.run('setHeaderColor', {'index': i}),
                          customBorder: const CircleBorder(),
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: headerColors[i],
                              shape: BoxShape.circle,
                              border: Border.all(
                                width: selectedColor == i ? 2.5 : 1,
                                color: selectedColor == i
                                    ? theme.colorScheme.primary
                                    : tokens.hairline,
                              ),
                            ),
                            child: selectedColor == i
                                ? const Icon(
                                    Icons.check_rounded,
                                    size: 15,
                                    color: Color(0xff192c21),
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ]),
            const Divider(indent: 16, endIndent: 16),
            row([
              Align(
                alignment: Alignment.centerLeft,
                child: ui.button(l.resetColor, 'setHeaderColor', {'index': 0}),
              ),
            ]),
          ],
        ),
      ),
      heading(l.headerImage),
      Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            row([Text(l.dropHint, style: theme.textTheme.bodyMedium)]),
            const Divider(indent: 16, endIndent: 16),
            row([
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: busy ? null : cubit.loadThumbnail,
                    child: Text(l.previewImage),
                  ),
                  ui.button(l.removeImage, 'removeHeaderImage'),
                ],
              ),
            ]),
          ],
        ),
      ),
      heading(l.sound),
      Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: ui.label(
                l.sound,
                s.appearance['hasCustomSound'] == true
                    ? l.customSound
                    : l.defaultSound,
              ),
            ),
            const Divider(indent: 16, endIndent: 16),
            row([
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ui.button(l.chooseSound, 'chooseSound'),
                  ui.button(l.resetSound, 'resetSound'),
                ],
              ),
            ]),
          ],
        ),
      ),
    ];
  }
}
