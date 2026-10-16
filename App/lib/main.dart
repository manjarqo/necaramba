import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'data/platform_native_repository.dart';
import 'data/platform_window_interaction.dart';
import 'domain/repositories/native_repository.dart';
import 'domain/repositories/window_interaction.dart';
import 'domain/usecases/native_usecases.dart';
import 'l10n/app_localizations.dart';
import 'presentation/native_cubit.dart';
import 'presentation/workspace_page.dart';
import 'presentation/theme/workspace_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(NecarambaApp(windowInteraction: PlatformWindowInteraction()));
}

class NecarambaApp extends StatefulWidget {
  const NecarambaApp({
    super.key,
    this.repository,
    this.locale,
    this.windowInteraction,
  });
  final NativeRepository? repository;
  final Locale? locale;
  final WindowInteractionPort? windowInteraction;
  @override
  State<NecarambaApp> createState() => _NecarambaAppState();
}

class _NecarambaAppState extends State<NecarambaApp> {
  late final NativeRepository _repository =
      widget.repository ?? PlatformNativeRepository();
  late final NativeCubit _cubit = NativeCubit(NativeUseCases(_repository))
    ..bootstrap().then((_) => _cubit.loadThumbnail());
  StreamSubscription<String>? _drops;
  @override
  void initState() {
    super.initState();
    _drops = widget.windowInteraction?.headerDropHandles.listen(
      _cubit.importHeaderDrop,
      onError: _cubit.reportWindowFailure,
    );
  }

  @override
  void dispose() {
    _drops?.cancel();
    _cubit.close();
    if (widget.repository == null) _repository.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<NativeCubit, NativeViewState>(
        bloc: _cubit,
        buildWhen: (a, b) => themeModeOf(a) != themeModeOf(b),
        builder: (context, view) => _app(themeModeOf(view)),
      );

  /// Native owns the saved choice; until it is confirmed the app follows macOS.
  static ThemeMode themeModeOf(NativeViewState view) =>
      switch (view.confirmed?.appearance['themeMode']) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  Widget _app(ThemeMode mode) => MaterialApp(
    title: 'Necaramba',
    themeMode: mode,
    debugShowCheckedModeBanner: false,
    locale: widget.locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: WorkspaceTheme.build(Brightness.light),
    darkTheme: WorkspaceTheme.build(Brightness.dark),
    home: BlocProvider.value(
      value: _cubit,
      child: WorkspacePage(windowInteraction: widget.windowInteraction),
    ),
  );
}
