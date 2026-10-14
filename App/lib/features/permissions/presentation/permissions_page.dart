import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/entities/native_state.dart';
import '../../../presentation/native_cubit.dart';
import '../../../presentation/shared/feature_ui.dart';
import '../domain/permission_readiness.dart';

class PermissionsPage extends SnapshotFeature {
  const PermissionsPage({super.key, required super.snapshot});
  @override
  List<Widget> content(FeatureUI ui) {
    final s = snapshot;
    final l = ui.l;
    return [
      ui.intro(l.accessIntro),
      ui.card([
        const PermissionRefreshControl(),
        const SizedBox(height: 12),
        PermissionControls(snapshot: s),
        ui.label(
          l.secureInput,
          s.capabilities['secureInput'] == true ? l.active : l.inactive,
        ),
      ]),
    ];
  }
}

class PermissionControls extends SnapshotFeature {
  const PermissionControls({super.key, required super.snapshot});
  @override
  List<Widget> content(FeatureUI ui) => [
    for (final permission in [
      ('listen', 'listen', ui.l.listen, ui.l.listenHelp),
      ('post', 'post', ui.l.post, ui.l.postHelp),
      ('ax', 'axTrusted', ui.l.ax, ui.l.axHelp),
    ])
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              permission.$3,
              style: Theme.of(ui.context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(permission.$4),
            const SizedBox(height: 4),
            if (snapshot.capabilities[permission.$2] == true)
              Text(ui.l.granted)
            else ...[
              Text(ui.l.notGranted),
              OutlinedButton(
                key: Key('request-${permission.$1}'),
                onPressed: ui.busy
                    ? null
                    : () => ui.cubit.run('requestPermission', {
                        'kind': permission.$1,
                      }),
                child: Text(ui.l.request),
              ),
            ],
          ],
        ),
      ),
  ];
}

/// Feedback belongs to this permission surface and only to an explicit check.
class PermissionRefreshControl extends StatefulWidget {
  const PermissionRefreshControl({super.key});

  @override
  State<PermissionRefreshControl> createState() =>
      _PermissionRefreshControlState();
}

class _PermissionRefreshControlState extends State<PermissionRefreshControl> {
  NativeState? _checked;

  bool _matchesCheck(NativeState? current) =>
      current != null &&
      _checked != null &&
      current.sessionID == _checked!.sessionID &&
      mapEquals(current.capabilities, _checked!.capabilities);

  Future<void> _refresh(NativeCubit cubit) async {
    setState(() => _checked = null);
    final reply = await cubit.run('refreshCapabilities', {});
    if (!mounted || reply == null) return;
    final current = cubit.state.confirmed;
    if (cubit.state.connected &&
        current != null &&
        current.sessionID == reply.state.sessionID &&
        current.revision >= reply.state.revision &&
        !hasKeyboardPermissions(current)) {
      setState(() => _checked = current);
    }
  }

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<NativeCubit, NativeViewState>(
        listener: (context, view) {
          if (_checked != null &&
              (view.pending.isNotEmpty || !_matchesCheck(view.confirmed))) {
            setState(() => _checked = null);
          }
        },
        builder: (context, view) {
          final ui = FeatureUI(context);
          final current = view.confirmed;
          final showFeedback =
              _matchesCheck(current) &&
              view.connected &&
              view.error == null &&
              view.pending.isEmpty &&
              current != null &&
              !hasKeyboardPermissions(current);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OutlinedButton(
                key: const Key('refreshPermissions'),
                onPressed: ui.busy ? null : () => _refresh(ui.cubit),
                child: Text(ui.l.refresh),
              ),
              if (view.pending.contains('refreshCapabilities'))
                const LinearProgressIndicator(),
              if (showFeedback)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(ui.l.permissionCheckMissing),
                  ),
                ),
            ],
          );
        },
      );
}
