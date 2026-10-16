import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../theme/workspace_theme.dart';

/// One destination: a System Settings style tile with a colored glyph.
class SidebarDestination {
  const SidebarDestination(this.title, this.icon, this.tint);
  final String title;
  final IconData icon;
  final Color tint;
}

/// Full-height source list with search, used when the window is wide.
class WorkspaceSidebar extends StatefulWidget {
  const WorkspaceSidebar({
    super.key,
    required this.destinations,
    required this.selected,
    required this.onSelected,
  });
  final List<SidebarDestination> destinations;
  final int selected;
  final ValueChanged<int> onSelected;
  @override
  State<WorkspaceSidebar> createState() => _WorkspaceSidebarState();
}

class _WorkspaceSidebarState extends State<WorkspaceSidebar> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<int> get _visible {
    final query = _query.text.trim().toLowerCase();
    return [
      for (var i = 0; i < widget.destinations.length; i++)
        if (query.isEmpty ||
            widget.destinations[i].title.toLowerCase().contains(query))
          i,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = MacTokens.of(context);
    final l = AppLocalizations.of(context)!;
    final visible = _visible;
    return Material(
      color: tokens.sidebar,
      shape: Border(right: BorderSide(color: tokens.hairline)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 12),
              child: Row(
                children: [
                  ExcludeSemantics(
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: tokens.selection,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: const Icon(
                        Icons.keyboard_alt_outlined,
                        size: 17,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Necaramba',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontSize: 14,
                        letterSpacing: -.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 30,
              child: TextField(
                key: const Key('sidebarSearch'),
                controller: _query,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) {
                  if (visible.length == 1) widget.onSelected(visible.single);
                },
                style: theme.textTheme.bodyMedium,
                decoration: InputDecoration(
                  hintText: l.searchSettings,
                  hintStyle: theme.textTheme.bodyMedium?.copyWith(
                    color: tokens.secondary,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 16,
                    color: tokens.secondary,
                  ),
                  prefixIconConstraints: const BoxConstraints(minWidth: 30),
                  filled: true,
                  fillColor: theme.brightness == Brightness.dark
                      ? Colors.white.withValues(alpha: .07)
                      : Colors.black.withValues(alpha: .055),
                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(7),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(7),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: [
                  for (final i in visible)
                    _SidebarItem(
                      destination: widget.destinations[i],
                      selected: widget.selected == i,
                      onTap: () => widget.onSelected(i),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });
  final SidebarDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = MacTokens.of(context);
    final ink = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: selected ? tokens.selection : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          child: InkWell(
            borderRadius: BorderRadius.circular(7),
            hoverColor: selected
                ? Colors.transparent
                : ink.withValues(alpha: .06),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              child: Row(
                children: [
                  ExcludeSemantics(
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: destination.tint,
                        borderRadius: BorderRadius.circular(6),
                        border: selected
                            ? Border.all(
                                color: Colors.white.withValues(alpha: .55),
                              )
                            : null,
                      ),
                      child: Icon(
                        destination.icon,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      destination.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.3,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: selected ? tokens.onSelection : ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
