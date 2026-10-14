import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/entities/native_state.dart';
import '../domain/usecases/estimate_time_saved.dart';
import '../domain/repositories/window_interaction.dart';
import '../l10n/app_localizations.dart';
import 'native_cubit.dart';

const headerColors = <Color>[
  Color(0xffdae8de),
  Color(0xffd8e6e8),
  Color(0xffdce3f1),
  Color(0xffe5def0),
  Color(0xffefdaea),
  Color(0xfff2dedb),
  Color(0xfff4e2cc),
  Color(0xffeee9cb),
  Color(0xffe3eacb),
  Color(0xffcfe7df),
  Color(0xffb6d2c1),
  Color(0xffb5d0d7),
  Color(0xffb8c6e3),
  Color(0xffc8b9dd),
  Color(0xffdeb8d0),
  Color(0xffe3bcb6),
  Color(0xffe7c7a5),
  Color(0xffddd5a2),
  Color(0xffcbd8a6),
  Color(0xffa9d1c4),
  Color(0xffaac2b3),
  Color(0xff9ab4c0),
  Color(0xffb5a8bd),
  Color(0xffc3aa9c),
  Color(0xffb4b998),
];

class WorkspacePage extends StatefulWidget {
  const WorkspacePage({super.key, this.windowInteraction});
  final WindowInteractionPort? windowInteraction;
  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage>
    with WidgetsBindingObserver {
  int selected = 0;
  final wordDraft = TextEditingController();
  final shareWord = TextEditingController();
  final feedback = TextEditingController();
  String shareLanguage = 'english';
  final _headerKey = GlobalKey();
  HeaderDropRegion? _lastRegion;
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
  void didChangeMetrics() => _reportHeader();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.windowInteraction?.updateHeaderDropRegion(null);
    wordDraft.dispose();
    shareWord.dispose();
    feedback.dispose();
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
      unawaited(widget.windowInteraction!.updateHeaderDropRegion(region));
    });
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
      _reportHeader();
      final s = view.confirmed;
      return Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 740;
              return Column(
                children: [
                  _header(view),
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
                              : ListView(
                                  padding: EdgeInsets.all(wide ? 28 : 16),
                                  children: [
                                    if (!wide)
                                      DropdownButtonFormField<int>(
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
                                    const SizedBox(height: 8),
                                    Text(
                                      titles[selected],
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineLarge,
                                    ),
                                    const SizedBox(height: 18),
                                    ..._content(s),
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
  Widget _header(NativeViewState view) {
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
  Widget _intro(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
  );
  Widget _card(List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );
  Widget _button(
    String text,
    String method, [
    Map<String, Object?> args = const {},
  ]) => OutlinedButton(
    onPressed: busy ? null : () => cubit.run(method, args),
    child: Text(text),
  );
  Widget _label(String name, Object? value) => Padding(
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
  Future<bool> _confirm(String title, {String? message}) async =>
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
  List<Widget> _content(NativeState s) => switch (selected) {
    0 => _settings(s),
    1 => _exceptions(s),
    2 => _permissions(s),
    3 => _appearance(s),
    4 => _rules(s),
    5 => _statistics(s),
    6 => _account(s),
    _ => _about(s),
  };
  List<Widget> _settings(NativeState s) {
    final names = {
      'autoEnabled': l.autoEnabled,
      'typoEnabled': l.typoEnabled,
      'yoEnabled': l.yoEnabled,
      'singleShiftEnabled': l.singleShiftEnabled,
      'optionEnabled': l.optionEnabled,
      'splitShiftEnabled': l.splitShiftEnabled,
      'plainPasteEnabled': l.plainPasteEnabled,
      'soundEnabled': l.soundEnabled,
    };
    return [
      _intro(l.settingsIntro),
      _card([
        for (final entry in names.entries)
          SwitchListTile(
            key: Key(entry.key),
            contentPadding: EdgeInsets.zero,
            title: Text(entry.value),
            value: s.preferences[entry.key]!,
            onChanged: busy
                ? null
                : (value) => cubit.run('setPreferences', {
                    'patch': {entry.key: value},
                  }),
          ),
      ]),
      const SizedBox(height: 16),
      _intro(l.manualHint),
    ];
  }

  List<Widget> _exceptions(NativeState s) => [
    _card([
      Text(l.words, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 14),
      TextField(
        key: const Key('wordDraft'),
        enabled: !busy,
        controller: wordDraft,
        decoration: InputDecoration(labelText: l.word, helperText: l.wordHint),
        onSubmitted: busy ? null : (_) => _addWord(),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 10,
        runSpacing: 8,
        children: [
          FilledButton(
            key: const Key('addWord'),
            onPressed: busy ? null : _addWord,
            child: Text(l.addWord),
          ),
          OutlinedButton(
            key: const Key('clearWords'),
            onPressed: busy
                ? null
                : () async {
                    if (await _confirm(
                      l.clearWords,
                      message: l.clearQuestion,
                    )) {
                      await cubit.run('clearWords', {'confirmed': true});
                    }
                  },
            child: Text(l.clearWords),
          ),
        ],
      ),
      const SizedBox(height: 16),
      Column(
        key: const Key('wordRulesTable'),
        children: [
          if (s.words.isEmpty) Text(l.emptyWords),
          for (final word in s.words)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: SelectableText('${word['original']}'),
              subtitle: word['legacy'] == true ? Text(l.legacy) : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: l.delete,
                    onPressed: busy
                        ? null
                        : () async {
                            if (await _confirm(
                              l.delete,
                              message: '${word['original']}',
                            )) {
                              await cubit.run('deleteWord', {'id': word['id']});
                            }
                          },
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
        ],
      ),
    ]),
    const SizedBox(height: 16),
    _card([
      Text(l.applications, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      _intro(l.appHint),
      Align(
        alignment: Alignment.centerLeft,
        child: _button(l.chooseApp, 'chooseApp'),
      ),
      const SizedBox(height: 12),
      Column(
        key: const Key('appRulesTable'),
        children: [
          if (s.apps.isEmpty) Text(l.emptyApps),
          for (final app in s.apps)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${app['displayName']}'),
              subtitle: SelectableText('${app['bundleID']}'),
              trailing: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  DropdownButton<String>(
                    value: app['mode'] as String,
                    items: [
                      DropdownMenuItem(value: 'allow', child: Text(l.allow)),
                      DropdownMenuItem(value: 'deny', child: Text(l.deny)),
                    ],
                    onChanged: busy
                        ? null
                        : (value) => cubit.run('setAppMode', {
                            'bundleID': app['bundleID'],
                            'mode': value,
                          }),
                  ),
                  IconButton(
                    tooltip: l.delete,
                    onPressed: busy
                        ? null
                        : () async {
                            if (await _confirm(
                              l.delete,
                              message:
                                  '${app['displayName']}\n${app['bundleID']}',
                            )) {
                              await cubit.run('deleteApp', {
                                'bundleID': app['bundleID'],
                              });
                            }
                          },
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
        ],
      ),
    ]),
  ];
  Future<void> _addWord() async {
    final reply = await cubit.run('addWord', {'text': wordDraft.text});
    if (reply != null) wordDraft.clear();
  }

  List<Widget> _permissions(NativeState s) => [
    _intro(l.accessIntro),
    _card([
      for (final capability in [
        ('listen', l.listen),
        ('post', l.post),
        ('ax', l.ax),
      ])
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            s.capabilities[capability.$1 == 'ax'
                        ? 'axTrusted'
                        : capability.$1] ==
                    true
                ? Icons.check_circle_outline
                : Icons.radio_button_unchecked,
          ),
          title: Text(capability.$2),
          subtitle: Text(
            s.capabilities[capability.$1 == 'ax'
                        ? 'axTrusted'
                        : capability.$1] ==
                    true
                ? l.granted
                : l.notGranted,
          ),
          trailing: _button(l.request, 'requestPermission', {
            'kind': capability.$1,
          }),
        ),
      _label(
        l.secureInput,
        s.capabilities['secureInput'] == true ? l.active : l.inactive,
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: _button(l.refresh, 'refreshCapabilities'),
      ),
    ]),
  ];
  List<Widget> _appearance(NativeState s) => [
    _card([
      Text(l.color, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < headerColors.length; i++)
            Semantics(
              label: '${l.color} ${i + 1}',
              selected: s.appearance['colorIndex'] == i,
              button: true,
              child: Tooltip(
                message: '${l.color} ${i + 1}',
                child: InkWell(
                  onTap: busy
                      ? null
                      : () => cubit.run('setHeaderColor', {'index': i}),
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: headerColors[i],
                      shape: BoxShape.circle,
                      border: Border.all(
                        width: s.appearance['colorIndex'] == i ? 3 : 1,
                        color: s.appearance['colorIndex'] == i
                            ? const Color(0xff192c21)
                            : Colors.black26,
                      ),
                    ),
                    child: s.appearance['colorIndex'] == i
                        ? const Icon(
                            Icons.check,
                            size: 18,
                            color: Color(0xff192c21),
                          )
                        : null,
                  ),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: _button(l.resetColor, 'setHeaderColor', {'index': 0}),
      ),
    ]),
    const SizedBox(height: 16),
    _card([
      Text(l.headerImage, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 10),
      _intro(l.dropHint),
      Wrap(
        spacing: 10,
        children: [
          OutlinedButton(
            onPressed: busy ? null : cubit.loadThumbnail,
            child: Text(l.previewImage),
          ),
          _button(l.removeImage, 'removeHeaderImage'),
        ],
      ),
    ]),
    const SizedBox(height: 16),
    _card([
      Text(l.sound, style: Theme.of(context).textTheme.titleLarge),
      _label(
        l.sound,
        s.appearance['hasCustomSound'] == true ? l.customSound : l.defaultSound,
      ),
      Wrap(
        spacing: 10,
        children: [
          _button(l.chooseSound, 'chooseSound'),
          _button(l.resetSound, 'resetSound'),
        ],
      ),
    ]),
  ];
  List<Widget> _rules(NativeState s) => [
    _intro(l.rulesIntro),
    _card([
      _label(l.version, s.model['version']),
      _label(l.status, _modelStatus('${s.model['state']}')),
      _label(l.lastChecked, s.model['lastChecked']),
      Align(
        alignment: Alignment.centerLeft,
        child: _button(l.checkRules, 'checkRules'),
      ),
    ]),
    const SizedBox(height: 18),
    _card([
      Text(l.share, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      _intro(l.shareIntro),
      TextField(
        key: const Key('shareWord'),
        enabled: !busy,
        controller: shareWord,
        decoration: InputDecoration(labelText: l.word),
      ),
      const SizedBox(height: 14),
      DropdownButtonFormField<String>(
        initialValue: shareLanguage,
        decoration: InputDecoration(labelText: l.language),
        items: [
          DropdownMenuItem(value: 'english', child: Text(l.english)),
          DropdownMenuItem(value: 'russian', child: Text(l.russian)),
        ],
        onChanged: busy
            ? null
            : (value) => setState(() => shareLanguage = value!),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: feedback,
        decoration: InputDecoration(labelText: l.feedback),
        maxLines: 2,
      ),
      const SizedBox(height: 14),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton(
          onPressed: busy ? null : () => _share(s),
          child: Text(l.previewSubmission),
        ),
      ),
    ]),
  ];
  String _modelStatus(String state) => switch (state) {
    'idle' => l.idle,
    'current' => l.current,
    'offline' => l.offline,
    'checking' => l.checking,
    'failed' => l.failed,
    'updateAvailable' => l.updateAvailable,
    _ => l.unknown,
  };
  Future<void> _share(NativeState s) async {
    final reply = await cubit.run('previewShare', {
      'word': shareWord.text,
      'language': shareLanguage,
      'modelVersion': s.model['version'],
      'feedback': feedback.text.isEmpty ? null : feedback.text,
    });
    if (reply == null || !mounted) return;
    final preview = reply.result['preview'];
    final id = reply.result['previewID'];
    if (preview is! Map || id is! String) return;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(l.sharePreview),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _label(l.word, preview['word']),
                  _label(l.language, preview['language']),
                  _label(l.modelVersion, preview['modelVersion']),
                  _label(l.feedback, preview['feedback'] ?? ''),
                  _label(l.destination, preview['host']),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(l.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(l.send),
              ),
            ],
          ),
        ) ??
        false;
    await cubit.run(confirmed ? 'confirmShare' : 'cancelShare', {
      'previewID': id,
    });
  }

  List<Widget> _statistics(NativeState s) {
    final counts = s.statistics;
    final estimate = const EstimateTimeSaved().seconds(counts);
    final names = {
      'layout': l.layout,
      'typo': l.typo,
      'doubleCaps': l.doubleCaps,
      'yo': l.yo,
      'manual': l.manual,
      'undo': l.undo,
    };
    return [
      _intro(l.statisticsIntro),
      _card([
        Text(l.estimate, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Text(
          '$estimate ${l.seconds}',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 12),
        Text(l.formula),
      ]),
      const SizedBox(height: 16),
      _card([
        for (final entry in names.entries)
          _label(entry.value, counts[entry.key] ?? 0),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: busy
                ? null
                : () async {
                    if (await _confirm(
                      l.resetCounters,
                      message: l.resetQuestion,
                    )) {
                      await cubit.run('resetCounters', {'confirmed': true});
                    }
                  },
            child: Text(l.resetCounters),
          ),
        ),
      ]),
    ];
  }

  List<Widget> _account(NativeState s) => [
    _intro(l.licenseIntro),
    _card([
      _label(l.status, switch (s.license['state']) {
        'trial' => l.trial,
        'expired' => l.expired,
        'active' => l.licensed,
        'grace' => l.grace,
        'pending' => l.pending,
        'revoked' => l.revoked,
        'unavailable' => l.errorUnavailable,
        'checking' => l.checking,
        _ => l.unknown,
      }),
      _label(l.expires, s.license['expiresAt']),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          if (const String.fromEnvironment('NECARAMBA_PRODUCT_ID').isEmpty) ...[
            OutlinedButton(onPressed: null, child: Text(l.purchase)),
            Text(l.errorUnavailable),
          ] else
            _button(l.purchase, 'purchase', {
              'productID': const String.fromEnvironment('NECARAMBA_PRODUCT_ID'),
            }),
          _button(l.restore, 'restore'),
          _button(l.manageSubscription, 'manageSubscription'),
        ],
      ),
    ]),
  ];
  List<Widget> _about(NativeState s) => [
    _intro(l.aboutIntro),
    _card([
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(l.login),
        value: s.login['enabled'] == true,
        subtitle: Text(_loginStatus('${s.login['status']}')),
        onChanged: busy
            ? null
            : (value) => cubit.run('setLoginEnabled', {'enabled': value}),
      ),
      _label(l.version, '1.0.0+1'),
      _label(l.modelVersion, s.model['version']),
      Text(l.help, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 10),
      Text(l.helpText),
    ]),
    const SizedBox(height: 16),
    _card([
      Text(l.diagnostics, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 10),
      _intro(l.privacy),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _button(l.exportDiagnostics, 'exportDiagnostics'),
          _button(l.exportArchive, 'exportArchive'),
          OutlinedButton(
            onPressed: busy
                ? null
                : () async {
                    if (await _confirm(
                      l.importArchive,
                      message: l.importQuestion,
                    )) {
                      await cubit.run('importArchive', {});
                    }
                  },
            child: Text(l.importArchive),
          ),
        ],
      ),
    ]),
  ];
  String _loginStatus(String value) => switch (value) {
    'enabled' => l.enabled,
    'disabled' => l.disabled,
    'requiresApproval' => l.requiresApproval,
    _ => l.errorUnavailable,
  };
}
