import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/repositories/window_interaction.dart';
import '../../features/appearance/presentation/header_palette.dart';
import '../../l10n/app_localizations.dart';
import '../native_cubit.dart';

class WorkspaceHeader extends StatefulWidget {
  const WorkspaceHeader({
    super.key,
    required this.view,
    this.windowInteraction,
  });
  final NativeViewState view;
  final WindowInteractionPort? windowInteraction;
  @override
  State<WorkspaceHeader> createState() => _WorkspaceHeaderState();
}

class _WorkspaceHeaderState extends State<WorkspaceHeader>
    with WidgetsBindingObserver {
  final _headerKey = GlobalKey();
  HeaderDropRegion? _lastRegion;
  late final NativeCubit cubit;
  AppLocalizations get l => AppLocalizations.of(context)!;
  @override
  void initState() {
    super.initState();
    cubit = context.read<NativeCubit>();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeMetrics() => _reportHeader();
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final port = widget.windowInteraction;
    if (port != null) unawaited(cubit.updateHeaderRegion(port, null));
    super.dispose();
  }

  void _reportHeader() {
    if (widget.windowInteraction == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = _headerKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final point = box.localToGlobal(Offset.zero);
      final region = HeaderDropRegion(
        point.dx,
        point.dy,
        box.size.width,
        box.size.height,
      );
      final old = _lastRegion;
      if (old?.x == region.x &&
          old?.y == region.y &&
          old?.width == region.width &&
          old?.height == region.height) {
        return;
      }
      _lastRegion = region;
      unawaited(cubit.updateHeaderRegion(widget.windowInteraction!, region));
    });
  }

  @override
  Widget build(BuildContext context) {
    _reportHeader();
    final view = widget.view;
    final index = (view.confirmed?.appearance['colorIndex'] as int? ?? 0).clamp(
      0,
      24,
    );
    final color = headerColors[index];
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = view.connected ? view.confirmed?.status : null;
    final statusLabel = status == null
        ? (view.loading ? l.runtimeStarting : l.runtimeDisconnected)
        : _status(status);
    final statusColor = switch (status) {
      'active' =>
        theme.brightness == Brightness.dark
            ? const Color(0xff75cd9a)
            : const Color(0xff287247),
      'permissionRequired' || 'secureInput' || 'licensingBlocked' =>
        theme.brightness == Brightness.dark
            ? const Color(0xffe8bd74)
            : const Color(0xff946114),
      _ => scheme.onSurfaceVariant,
    };
    return Container(
      key: _headerKey,
      height: 64,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(
            alpha: theme.brightness == Brightness.dark ? .06 : .13,
          ),
          scheme.surface,
        ),
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
        image:
            view.confirmed?.appearance['hasHeaderImage'] == true &&
                view.thumbnail != null
            ? DecorationImage(
                image: MemoryImage(view.thumbnail!),
                fit: BoxFit.cover,
                opacity: .15,
              )
            : null,
      ),
      child: Semantics(
        label: l.headerImage,
        hint: l.dropHint,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  Icons.keyboard_alt_outlined,
                  size: 20,
                  color: scheme.onPrimary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Necaramba',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontSize: 15,
                    letterSpacing: -.3,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * .48,
                ),
                child: Semantics(
                  liveRegion: true,
                  child: Tooltip(
                    message: '${l.status}: $statusLabel',
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: .09),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: statusColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 7),
                          Flexible(
                            child: Text(
                              statusLabel,
                              key: status == null ? null : Key(status),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: statusColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _status(String value) => switch (value) {
    'permissionRequired' => l.permissionRequired,
    'secureInput' => l.secureInput,
    'licensingBlocked' => l.licensingBlocked,
    'off' => l.off,
    'starting' => l.runtimeStarting,
    'unavailable' => l.runtimeUnavailable,
    'updateAvailable' => l.updateAvailable,
    'active' => l.active,
    _ => l.unknown,
  };
}
