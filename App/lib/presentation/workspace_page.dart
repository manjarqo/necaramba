import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/entities/native_state.dart';
import '../domain/repositories/window_interaction.dart';
import '../l10n/app_localizations.dart';
import 'native_cubit.dart';

import '../features/settings/presentation/settings_page.dart';
import '../features/exceptions/presentation/exceptions_page.dart';
import '../features/permissions/presentation/permissions_page.dart';
import '../features/appearance/presentation/appearance_page.dart';
import '../features/rules/presentation/rules_page.dart';
import '../features/statistics/presentation/statistics_page.dart';
import '../features/licensing/presentation/licensing_page.dart';
import '../features/about/presentation/about_page.dart';
import 'shared/workspace_header.dart';
export '../features/appearance/presentation/header_palette.dart';

class WorkspacePage extends StatefulWidget {
  const WorkspacePage({super.key, this.windowInteraction});
  final WindowInteractionPort? windowInteraction;
  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage>
    with WidgetsBindingObserver {
  int selected = 0;
  AppLocalizations get l => AppLocalizations.of(context)!;
  NativeCubit get cubit => context.read<NativeCubit>();
  bool get busy => cubit.state.pending.isNotEmpty || !cubit.state.connected;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        cubit.state.confirmed != null &&
        !busy) {
      cubit.run('refreshCapabilities', {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  List<String> get titles => [
    l.settings,
    l.exceptions,
    l.permissions,
    l.appearance,
    l.rules,
    l.statistics,
    l.account,
    l.about,
  ];
  static const icons = [
    Icons.tune,
    Icons.rule,
    Icons.verified_user_outlined,
    Icons.palette_outlined,
    Icons.cloud_sync_outlined,
    Icons.bar_chart,
    Icons.key_outlined,
    Icons.info_outline,
  ];
  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<NativeCubit, NativeViewState>(
    builder: (context, view) {
      final s = view.confirmed;
      return Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 740;
              return Column(
                children: [
                  WorkspaceHeader(
                    view: view,
                    windowInteraction: widget.windowInteraction,
                  ),
                  if (view.error != null && view.error != 'cancelled')
                    _notice(_error(view.error!), Icons.error_outline),
                  if (view.pending.isNotEmpty)
                    const LinearProgressIndicator(minHeight: 2),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (wide)
                          SizedBox(
                            width: 186,
                            child: ListView(
                              padding: const EdgeInsets.fromLTRB(
                                12,
                                20,
                                10,
                                16,
                              ),
                              children: [
                                for (var i = 0; i < titles.length; i++)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 5),
                                    child: ListTile(
                                      dense: true,
                                      selected: selected == i,
                                      selectedTileColor: Theme.of(context)
                                          .colorScheme
                                          .secondaryContainer,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      leading: Icon(icons[i], size: 21),
                                      title: Text(titles[i]),
                                      onTap: () => setState(() => selected = i),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        Expanded(
                          child: s == null
                              ? Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (view.loading)
                                        const CircularProgressIndicator()
                                      else
                                        Text(l.unavailable),
                                      const SizedBox(height: 16),
                                      OutlinedButton(
                                        onPressed: view.loading
                                            ? null
                                            : cubit.bootstrap,
                                        child: Text(l.reconnect),
                                      ),
                                    ],
                                  ),
                                )
                              : Column(
                                  children: [
                                    if (!wide)
                                      Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: DropdownButtonFormField<int>(
                                          initialValue: selected,
                                          items: [
                                            for (
                                              var i = 0;
                                              i < titles.length;
                                              i++
                                            )
                                              DropdownMenuItem(
                                                value: i,
                                                child: Text(titles[i]),
                                              ),
                                          ],
                                          onChanged: (value) =>
                                              setState(() => selected = value!),
                                        ),
                                      ),
                                    Expanded(
                                      child: IndexedStack(
                                        index: selected,
                                        children: [
                                          for (
                                            var i = 0;
                                            i < titles.length;
                                            i++
                                          )
                                            ListView(
                                              padding: EdgeInsets.all(
                                                wide ? 28 : 16,
                                              ),
                                              children: [
                                                Text(
                                                  titles[i],
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .headlineLarge,
                                                ),
                                                const SizedBox(height: 18),
                                                _feature(s, i),
                                              ],
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
    },
  );
  String _error(String code) => switch (code) {
    'permissionDenied' => l.errorPermission,
    'conflict' => l.errorConflict,
    'invalidArgument' || 'invalidWord' => l.errorInvalid,
    'duplicateWord' => l.errorDuplicate,
    'ioFailure' => l.errorIO,
    'timeout' => l.errorTimeout,
    _ => l.errorUnavailable,
  };
  Widget _notice(String text, IconData icon) => Semantics(
    liveRegion: true,
    child: Material(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
            IconButton(
              tooltip: l.reconnect,
              onPressed: cubit.state.pending.isNotEmpty
                  ? null
                  : cubit.bootstrap,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
    ),
  );
  Widget _feature(NativeState s, int index) => switch (index) {
    0 => SettingsPage(snapshot: s),
    1 => ExceptionsPage(snapshot: s),
    2 => PermissionsPage(snapshot: s),
    3 => AppearancePage(snapshot: s),
    4 => RulesPage(snapshot: s),
    5 => StatisticsPage(snapshot: s),
    6 => LicensingPage(snapshot: s),
    _ => AboutPage(snapshot: s),
  };
}
