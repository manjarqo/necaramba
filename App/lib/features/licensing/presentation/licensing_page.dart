import 'package:flutter/material.dart';

import '../../../presentation/shared/feature_ui.dart';

class LicensingPage extends SnapshotFeature {
  const LicensingPage({super.key, required super.snapshot});
  @override
  List<Widget> content(FeatureUI ui) {
    final s = snapshot;
    final l = ui.l;
    return [
      ui.intro(l.licenseIntro),
      ui.card([
        ui.label(l.status, switch (s.license['state']) {
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
        ui.label(l.expires, s.license['expiresAt']),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            if (const String.fromEnvironment('NECARAMBA_PRODUCT_ID')
                .isEmpty) ...[
              OutlinedButton(onPressed: null, child: Text(l.purchase)),
              Text(l.errorUnavailable),
            ] else
              ui.button(l.purchase, 'purchase', {
                'productID': const String.fromEnvironment(
                  'NECARAMBA_PRODUCT_ID',
                ),
              }),
            ui.button(l.restore, 'restore'),
            ui.button(l.manageSubscription, 'manageSubscription'),
          ],
        ),
      ]),
    ];
  }
}
