import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/native_state.dart';
import '../../l10n/app_localizations.dart';
import '../native_cubit.dart';

/// Shared rendering/actions; confirmed state belongs only to NativeCubit.
class FeatureUI {
  const FeatureUI(this.context);
  final BuildContext context;
  AppLocalizations get l => AppLocalizations.of(context)!;
  NativeCubit get cubit => context.read<NativeCubit>();
  bool get busy => cubit.state.pending.isNotEmpty || !cubit.state.connected;
  Widget intro(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodyLarge
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
  Widget card(List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );

  /// A grouped block: a quiet heading above its rounded group, as in macOS.
  Widget section(String title, List<Widget> children) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 7),
        child: Semantics(
          header: true,
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
      ),
      card(children),
    ],
  );
  Widget button(
    String text,
    String method, [
    Map<String, Object?> args = const {},
  ]) => OutlinedButton(
    onPressed: busy ? null : () => cubit.run(method, args),
    child: Text(text),
  );
  Widget label(String name, Object? value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(name)),
        const SizedBox(width: 16),
        Flexible(
          child: SelectableText(
            '${value ?? l.never}',
            textAlign: TextAlign.right,
          ),
        ),
      ],
    ),
  );
  Future<bool> confirm(String title, {String? message}) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: message == null ? null : Text(message),
          actions: [
            TextButton(
              key: const Key('cancelClear'),
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.confirm),
            ),
          ],
        ),
      ) ??
      false;
}

abstract class SnapshotFeature extends StatelessWidget {
  const SnapshotFeature({super.key, required this.snapshot});
  final NativeState snapshot;
  List<Widget> content(FeatureUI ui);
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: content(FeatureUI(context)),
  );
}

mixin FeatureDraftState<T extends StatefulWidget> on State<T> {
  FeatureUI get ui => FeatureUI(context);
  AppLocalizations get l => ui.l;
  NativeCubit get cubit => ui.cubit;
  bool get busy => ui.busy;
}
