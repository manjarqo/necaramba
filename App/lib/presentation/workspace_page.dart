import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/entities/native_state.dart';
import '../domain/repositories/window_interaction.dart';
import '../l10n/app_localizations.dart';
import 'native_cubit.dart';

import '../features/settings/presentation/settings_page.dart';
import '../features/exceptions/presentation/exceptions_page.dart';
import '../features/permissions/presentation/permissions_page.dart';
import '../features/permissions/domain/permission_readiness.dart';
import '../features/appearance/presentation/appearance_page.dart';
import '../features/rules/presentation/rules_page.dart';
import '../features/statistics/presentation/statistics_page.dart';
import '../features/about/presentation/about_page.dart';
import 'shared/workspace_header.dart';
import 'shared/workspace_sidebar.dart';
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
  String? _permissionSession;
  bool? _previouslyGranted;
  DialogRoute<void>? _permissionRoute;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkPermissions(cubit.state);
  }

  void _checkPermissions(NativeViewState view) {
    final snapshot = view.confirmed;
    if (snapshot == null || !view.connected) return;
    final granted = hasKeyboardPermissions(snapshot);
    final shouldOpen =
        !granted &&
        (_permissionSession != snapshot.sessionID ||
            _previouslyGranted == true);
    _permissionSession = snapshot.sessionID;
    _previouslyGranted = granted;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final latest = cubit.state.confirmed;
      if (latest == null) return;
      if (hasKeyboardPermissions(latest)) {
        final route = _permissionRoute;
        if (route != null && route.isActive) {
          route.navigator?.removeRoute(route);
        }
      } else if (shouldOpen) {
        _showPermissions();
      }
    });
  }

  void _showPermissions() {
    final snapshot = cubit.state.confirmed;
    if (!mounted ||
        _permissionRoute != null ||
        snapshot == null ||
        hasKeyboardPermissions(snapshot)) {
      return;
    }
    final nativeCubit = cubit;
    final route = DialogRoute<void>(
      context: context,
      builder: (dialogContext) => BlocProvider.value(
        value: nativeCubit,
        child: BlocBuilder<NativeCubit, NativeViewState>(
          builder: (context, view) => AlertDialog(
            title: Text(l.permissionSetupTitle),
            scrollable: true,
            content: SizedBox(
              width: 480,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l.permissionSetupIntro),
                  const SizedBox(height: 20),
                  const PermissionRefreshControl(),
                  const SizedBox(height: 12),
                  PermissionControls(snapshot: view.confirmed!),
                  if (view.error != null && view.error != 'cancelled')
                    Text(
                      _error(view.error!),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                key: const Key('permissionsLater'),
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(l.permissionsLater),
              ),
            ],
          ),
        ),
      ),
    );
    _permissionRoute = route;
    Navigator.of(context).push(route).whenComplete(() {
      if (identical(_permissionRoute, route)) _permissionRoute = null;
    });
  }

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
    final route = _permissionRoute;
    if (route != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (route.isActive) route.navigator?.removeRoute(route);
      });
    }
    super.dispose();
  }

  List<String> get titles => [
    l.general,
    l.exceptions,
    l.permissions,
    l.appearance,
    l.rules,
    l.statistics,
    l.about,
  ];
  static const icons = [
    Icons.tune_rounded,
    Icons.block_rounded,
    Icons.verified_user_rounded,
    Icons.contrast_rounded,
    Icons.sync_rounded,
    Icons.bar_chart_rounded,
    Icons.info_outline_rounded,
  ];
  static const tints = [
    Color(0xff636366),
    Color(0xffe8870a),
    Color(0xff2e9c4f),
    Color(0xffa04fd0),
    Color(0xff5e5ce6),
    Color(0xff0a74e8),
    Color(0xff7c7c82),
  ];
  @override
  Widget build(
    BuildContext context,
  ) => BlocConsumer<NativeCubit, NativeViewState>(
    listener: (context, view) => _checkPermissions(view),
    builder: (context, view) {
      final s = view.confirmed;
      return Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 640;
              final content = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  WorkspaceHeader(
                    view: view,
                    title: titles[selected],
                    windowInteraction: widget.windowInteraction,
                  ),
                  if (s != null && !hasKeyboardPermissions(s))
                    Material(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 6,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.lock_outline_rounded,
                              size: 16,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSecondaryContainer,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                l.permissionsMissing,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSecondaryContainer,
                                ),
                              ),
                            ),
                            TextButton(
                              key: const Key('reviewPermissions'),
                              onPressed: _showPermissions,
                              child: Text(l.reviewPermissions),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (view.error != null && view.error != 'cancelled')
                    _notice(_error(view.error!), Icons.error_outline),
                  if (view.pending.isNotEmpty)
                    const LinearProgressIndicator(minHeight: 2),
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
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    12,
                                    16,
                                    0,
                                  ),
                                  child: DropdownButtonFormField<int>(
                                    initialValue: selected,
                                    items: [
                                      for (var i = 0; i < titles.length; i++)
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
                                    for (var i = 0; i < titles.length; i++)
                                      ListView(
                                        padding: EdgeInsets.fromLTRB(
                                          wide ? 32 : 16,
                                          wide ? 20 : 16,
                                          wide ? 32 : 16,
                                          28,
                                        ),
                                        children: [
                                          Align(
                                            alignment: Alignment.topLeft,
                                            child: ConstrainedBox(
                                              constraints: const BoxConstraints(
                                                maxWidth: 720,
                                              ),
                                              child: _feature(s, i),
                                            ),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
              );
              if (!wide) return content;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 220,
                    child: WorkspaceSidebar(
                      destinations: [
                        for (var i = 0; i < titles.length; i++)
                          SidebarDestination(titles[i], icons[i], tints[i]),
                      ],
                      selected: selected,
                      onSelected: (i) => setState(() => selected = i),
                    ),
                  ),
                  Expanded(child: content),
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
    _ => AboutPage(snapshot: s),
  };
}
