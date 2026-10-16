import 'package:flutter/material.dart';

import '../theme/workspace_theme.dart';

/// A compact macOS-style switch: 38×22 track, white knob, accent when on.
class MacSwitch extends StatelessWidget {
  const MacSwitch({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = MacTokens.of(context);
    final enabled = onChanged != null;
    final track = value ? theme.colorScheme.primary : tokens.offTrack;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Opacity(
      opacity: enabled ? 1 : .45,
      child: AnimatedContainer(
        duration: reduce ? Duration.zero : const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        width: 38,
        height: 22,
        padding: const EdgeInsets.all(2),
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        decoration: BoxDecoration(
          color: track,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Container(
          width: 18,
          height: 18,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Color(0x40000000),
                blurRadius: 2,
                offset: Offset(0, 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One grouped-list row with a title, optional detail and a trailing switch.
/// The whole row toggles, and it reads as a single switch to assistive tools.
class MacSwitchTile extends StatelessWidget {
  const MacSwitchTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onChanged != null;
    return MergeSemantics(
      child: Semantics(
        toggled: value,
        enabled: enabled,
        label: title,
        hint: subtitle,
        child: InkWell(
          onTap: enabled ? () => onChanged!(!value) : null,
          hoverColor: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            child: Row(
              children: [
                Expanded(
                  child: ExcludeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: enabled
                                ? null
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 1),
                          Text(subtitle!, style: theme.textTheme.bodySmall),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                ExcludeSemantics(
                  child: MacSwitch(value: value, onChanged: onChanged),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
