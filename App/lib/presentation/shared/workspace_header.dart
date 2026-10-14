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
    return Container(
      key: _headerKey,
      height: 126,
      width: double.infinity,
      decoration: BoxDecoration(
        color: color,
        image:
            view.confirmed?.appearance['hasHeaderImage'] == true &&
                view.thumbnail != null
            ? DecorationImage(
                image: MemoryImage(view.thumbnail!),
                fit: BoxFit.cover,
                opacity: .12,
              )
            : null,
      ),
      child: Semantics(
        label: l.headerImage,
        hint: l.dropHint,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
          child: Row(
            children: [
              const Icon(
                Icons.keyboard_alt_outlined,
                size: 34,
                color: Color(0xff192c21),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Necaramba',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 27,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -1,
                        color: Color(0xff192c21),
                      ),
                    ),
                    Text(
                      l.localOnly,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        letterSpacing: 2,
                        color: Color(0xff192c21),
                      ),
                    ),
                  ],
                ),
              ),
              if (view.confirmed != null)
                Flexible(
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _status(view.confirmed!.status),
                      key: Key(view.confirmed!.status),
                      style: const TextStyle(
                        color: Color(0xff192c21),
                        fontWeight: FontWeight.w600,
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
    'updateAvailable' => l.updateAvailable,
    'active' => l.active,
    _ => l.unknown,
  };
}
