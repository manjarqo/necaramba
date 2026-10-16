import 'package:flutter/material.dart';

import '../../../presentation/shared/feature_ui.dart';

class ApplicationsPage extends SnapshotFeature {
  const ApplicationsPage({super.key, required super.snapshot});
  @override
  List<Widget> content(FeatureUI ui) {
    final s = snapshot;
    final l = ui.l;
    final cubit = ui.cubit;
    final busy = ui.busy;
    return [
      ui.section(l.applications, [
        ui.intro(l.appHint),
        Align(
          alignment: Alignment.centerLeft,
          child: ui.button(l.chooseApp, 'chooseApp'),
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
                              if (await ui.confirm(
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
  }
}
