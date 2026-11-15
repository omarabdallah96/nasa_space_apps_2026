import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import 'auth_screen.dart';

/// Firesight Pro: what it adds, and how to get it. Returns true when Pro is on
/// after the sheet closes.
///
/// Payments are not wired up yet: a Pro plan is set on the account by the
/// server. Debug builds can turn Pro on locally to try the features.
Future<bool> showPaywall(BuildContext context, {String? reasonKey}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _Paywall(reasonKey: reasonKey),
  );
  return context.mounted && AppScope.read(context).isPro;
}

class _Paywall extends StatelessWidget {
  const _Paywall({this.reasonKey});
  final String? reasonKey;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = S.of(context);
    final text = Theme.of(context).textTheme;
    final features = [
      (Icons.radar, 'pro_f_zones', 'pro_f_zones_sub'),
      (Icons.summarize_outlined, 'pro_f_report', 'pro_f_report_sub'),
      (Icons.notifications_active_outlined, 'pro_f_alerts', 'pro_f_alerts_sub'),
    ];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Icon(Icons.workspace_premium, color: Ember.amber, size: 30),
              const SizedBox(width: 10),
              Text(s.t('pro_title'),
                  style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            ]),
            if (reasonKey != null) ...[
              const SizedBox(height: 10),
              Text(s.t(reasonKey!), style: TextStyle(color: Ember.textMuted, height: 1.4)),
            ],
            const SizedBox(height: 18),
            for (final (icon, title, sub) in features)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(icon, color: Ember.ember),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s.t(title), style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(s.t(sub), style: TextStyle(color: Ember.textMuted, fontSize: 13)),
                    ]),
                  ),
                ]),
              ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Ember.calm.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                const Icon(Icons.health_and_safety_outlined, color: Ember.calm, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(s.t('pro_free_note'), style: const TextStyle(fontSize: 13))),
              ]),
            ),
            const SizedBox(height: 20),
            if (state.isPro)
              FilledButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.check),
                label: Text(s.t('pro_active')),
              )
            else if (state.isGuest && state.accountsAvailable)
              FilledButton(
                onPressed: () => AuthScreen.open(context),
                style: _primary,
                child: Text(s.t('pro_sign_in_first')),
              )
            else
              FilledButton(
                key: const ValueKey('pro_upgrade'),
                onPressed: () => ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(s.t('pro_coming_soon')))),
                style: _primary,
                child: Text(s.t('pro_upgrade')),
              ),
            if (kDebugMode) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                key: const ValueKey('pro_test_switch'),
                value: state.proTest,
                onChanged: state.setProTest,
                title: Text(s.t('pro_test')),
                subtitle: Text(s.t('pro_test_sub'), style: TextStyle(color: Ember.textMuted)),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ],
        ),
      ),
    );
  }

  static final _primary = FilledButton.styleFrom(
    minimumSize: const Size.fromHeight(50),
    backgroundColor: Ember.ember,
    foregroundColor: Colors.black,
  );
}
