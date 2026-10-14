import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/platform_native_repository.dart';
import 'domain/repositories/native_repository.dart';
import 'domain/usecases/native_usecases.dart';
import 'presentation/native_cubit.dart';

void main() {
  runApp(const NecarambaApp());
}

class NecarambaApp extends StatefulWidget {
  const NecarambaApp({super.key, this.repository});
  final NativeRepository? repository;
  @override
  State<NecarambaApp> createState() => _NecarambaAppState();
}

class _NecarambaAppState extends State<NecarambaApp> {
  late final NativeRepository _repository =
      widget.repository ?? PlatformNativeRepository();
  late final NativeCubit _cubit = NativeCubit(NativeUseCases(_repository))
    ..bootstrap();
  @override
  void dispose() {
    _cubit.close();
    if (widget.repository == null) _repository.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Necaramba',
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    supportedLocales: const [Locale('en'), Locale('ru')],
    theme: ThemeData(
      colorSchemeSeed: const Color(0xff375d70),
      useMaterial3: true,
    ),
    home: BlocBuilder<NativeCubit, NativeViewState>(
      bloc: _cubit,
      builder: (context, state) => Scaffold(
        appBar: AppBar(title: const Text('Necaramba')),
        body: Center(
          child: state.loading
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      state.confirmed == null
                          ? 'Native runtime unavailable'
                          : 'Native runtime: ${state.confirmed!.status}',
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: _cubit.bootstrap,
                      child: const Text('Reconnect'),
                    ),
                  ],
                ),
        ),
      ),
    ),
  );
}
