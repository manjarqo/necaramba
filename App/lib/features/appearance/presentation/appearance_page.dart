import 'package:flutter/material.dart';

import '../../../presentation/shared/feature_ui.dart';
import 'header_palette.dart';

class AppearancePage extends SnapshotFeature {
  const AppearancePage({super.key, required super.snapshot});
  @override
  List<Widget> content(FeatureUI ui) {
    final s = snapshot;
    final context = ui.context;
    final l = ui.l;
    final cubit = ui.cubit;
    final busy = ui.busy;
    return [
      ui.card([
        Text(l.color, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < headerColors.length; i++)
              Semantics(
                label: '${l.color} ${i + 1}',
                selected: s.appearance['colorIndex'] == i,
                button: true,
                child: Tooltip(
                  message: '${l.color} ${i + 1}',
                  child: InkWell(
                    onTap: busy
                        ? null
                        : () => cubit.run('setHeaderColor', {'index': i}),
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: headerColors[i],
                        shape: BoxShape.circle,
                        border: Border.all(
                          width: s.appearance['colorIndex'] == i ? 3 : 1,
                          color: s.appearance['colorIndex'] == i
                              ? const Color(0xff192c21)
                              : Colors.black26,
                        ),
                      ),
                      child: s.appearance['colorIndex'] == i
                          ? const Icon(
                              Icons.check,
                              size: 18,
                              color: Color(0xff192c21),
                            )
                          : null,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: ui.button(l.resetColor, 'setHeaderColor', {'index': 0}),
        ),
      ]),
      const SizedBox(height: 16),
      ui.card([
        Text(l.headerImage, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        ui.intro(l.dropHint),
        Wrap(
          spacing: 10,
          children: [
            OutlinedButton(
              onPressed: busy ? null : cubit.loadThumbnail,
              child: Text(l.previewImage),
            ),
            ui.button(l.removeImage, 'removeHeaderImage'),
          ],
        ),
      ]),
      const SizedBox(height: 16),
      ui.card([
        Text(l.sound, style: Theme.of(context).textTheme.titleLarge),
        ui.label(
          l.sound,
          s.appearance['hasCustomSound'] == true
              ? l.customSound
              : l.defaultSound,
        ),
        Wrap(
          spacing: 10,
          children: [
            ui.button(l.chooseSound, 'chooseSound'),
            ui.button(l.resetSound, 'resetSound'),
          ],
        ),
      ]),
    ];
  }
}
