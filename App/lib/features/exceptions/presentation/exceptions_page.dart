import 'package:flutter/material.dart';

import '../../../domain/entities/native_state.dart';
import '../../../presentation/shared/feature_ui.dart';
import '../../applications/presentation/applications_page.dart';

class ExceptionsPage extends StatefulWidget {
  const ExceptionsPage({super.key, required this.snapshot});
  final NativeState snapshot;
  @override
  State<ExceptionsPage> createState() => _ExceptionsPageState();
}

class _ExceptionsPageState extends State<ExceptionsPage>
    with FeatureDraftState<ExceptionsPage> {
  final wordDraft = TextEditingController();
  @override
  void dispose() {
    wordDraft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: _exceptions(widget.snapshot),
  );
  List<Widget> _exceptions(NativeState s) => [
    ui.section(l.words, [
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
                    if (await ui.confirm(
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
                            if (await ui.confirm(
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
    ApplicationsPage(snapshot: s),
  ];
  Future<void> _addWord() async {
    final reply = await cubit.run('addWord', {'text': wordDraft.text});
    if (reply != null) wordDraft.clear();
  }
}
