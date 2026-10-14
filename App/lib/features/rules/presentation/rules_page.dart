import 'package:flutter/material.dart';

import '../../../domain/entities/native_state.dart';
import '../../../presentation/shared/feature_ui.dart';

class RulesPage extends StatefulWidget {
  const RulesPage({super.key, required this.snapshot});
  final NativeState snapshot;
  @override
  State<RulesPage> createState() => _RulesPageState();
}

class _RulesPageState extends State<RulesPage>
    with FeatureDraftState<RulesPage> {
  final shareWord = TextEditingController();
  final feedback = TextEditingController();
  String shareLanguage = 'english';
  @override
  void dispose() {
    shareWord.dispose();
    feedback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: _rules(widget.snapshot),
  );
  List<Widget> _rules(NativeState s) => [
    ui.intro(l.rulesIntro),
    ui.card([
      ui.label(l.version, s.model['version']),
      ui.label(l.status, _modelStatus('${s.model['state']}')),
      ui.label(l.lastChecked, s.model['lastChecked']),
      Align(
        alignment: Alignment.centerLeft,
        child: ui.button(l.checkRules, 'checkRules'),
      ),
    ]),
    const SizedBox(height: 18),
    ui.card([
      Text(l.share, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      ui.intro(l.shareIntro),
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
            content: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 420,
                maxHeight: MediaQuery.sizeOf(dialogContext).height * .55,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ui.label(l.word, preview['word']),
                    ui.label(l.language, preview['language']),
                    ui.label(l.modelVersion, preview['modelVersion']),
                    ui.label(l.feedback, preview['feedback'] ?? ''),
                    ui.label(l.destination, preview['host']),
                  ],
                ),
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
}
