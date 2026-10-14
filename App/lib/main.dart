import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'data/platform_native_repository.dart';
import 'domain/repositories/native_repository.dart';
import 'domain/repositories/window_interaction.dart';
import 'domain/usecases/native_usecases.dart';
import 'l10n/app_localizations.dart';
import 'presentation/native_cubit.dart';
import 'presentation/workspace_page.dart';

void main() => runApp(const NecarambaApp());

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
  Widget build(BuildContext context) => MaterialApp(
    title: 'Necaramba',
    locale: widget.locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    home: BlocProvider.value(
      value: _cubit,
      child: WorkspacePage(windowInteraction: widget.windowInteraction),
    ),
  );
  ThemeData _theme(Brightness brightness) => ThemeData(
    brightness: brightness,
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xff42634e),
      brightness: brightness,
    ),
    scaffoldBackgroundColor: brightness == Brightness.light
        ? const Color(0xfff5f5f1)
        : const Color(0xff151b18),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w600,
        letterSpacing: -1,
      ),
      titleLarge: TextStyle(fontWeight: FontWeight.w600),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      filled: true,
    ),
  );
}
