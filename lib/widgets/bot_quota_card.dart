import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_colors.dart';

const String _kBotBillingUrl = 'https://monsalon.web.app/bot-billing.html';

/// Live read of the salon's `botMessageQuota` map; renders a usage bar +
/// sub badge + a button that opens the web billing page in an external
/// browser. Reused by:
/// - `owner_subscription_screen.dart` (Mon abonnement)
/// - `owner_bot_settings_screen.dart` (Assistant BOT — under "Zayna est active")
///
/// Bypasses `SalonModel` because the quota fields are billing-only
/// (managed by Stripe webhook + monthly reset CF) and don't belong in the
/// canonical model used across all screens.
class BotQuotaCard extends StatelessWidget {
  final String salonId;
  const BotQuotaCard({super.key, required this.salonId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('salons')
          .doc(salonId)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || snap.data == null || !snap.data!.exists) {
          return const SizedBox(
            height: 80,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final data = snap.data!.data()!;
        final rawQuota = data['botMessageQuota'];
        final q = rawQuota is Map
            ? Map<String, dynamic>.from(rawQuota)
            : <String, dynamic>{};
        final allocated = (q['monthlyAllocated'] as num?)?.toInt() ?? 1000;
        final used = (q['monthlyUsed'] as num?)?.toInt() ?? 0;
        final oneShot = (q['oneShotRemaining'] as num?)?.toInt() ?? 0;
        final pct =
            allocated > 0 ? (used / allocated).clamp(0.0, 1.0) : 0.0;
        final rawSub = q['bonusSubscription'];
        final Map<String, dynamic>? sub = rawSub is Map
            ? Map<String, dynamic>.from(rawSub)
            : null;
        final subTier = (sub?['tier'] as num?)?.toInt();
        final cancelAtEnd = sub?['cancelAtPeriodEnd'] == true;

        Color barColor = AppColors.brand500;
        if (pct >= 0.9) {
          barColor = Colors.red.shade600;
        } else if (pct >= 0.7) {
          barColor = Colors.orange.shade700;
        }

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.secondary100),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.bolt_rounded, color: barColor, size: 22),
                  const SizedBox(width: 8),
                  Text.rich(
                    TextSpan(
                      style: GoogleFonts.dmSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.brand950,
                      ),
                      children: [
                        TextSpan(text: '$used '),
                        TextSpan(
                          text: '/ $allocated msg',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppColors.secondary500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 8,
                  backgroundColor: AppColors.secondary100,
                  valueColor: AlwaysStoppedAnimation(barColor),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.inventory_2_outlined,
                      size: 14, color: AppColors.secondary500),
                  const SizedBox(width: 6),
                  Text(
                    'One-shot restants : $oneShot',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.secondary600,
                    ),
                  ),
                ],
              ),
              if (subTier != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.brand50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.subscriptions_rounded,
                          size: 16, color: AppColors.brand700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          cancelAtEnd
                              ? 'Bonus +$subTier msg/mois — annulation programmée'
                              : 'Abonnement bonus actif : +$subTier msg/mois',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.brand700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _openBilling(context),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('Gérer mon abonnement bot'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brand600,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openBilling(BuildContext context) async {
    final uri = Uri.parse(_kBotBillingUrl);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Impossible d\'ouvrir la page de facturation.')),
      );
    }
  }
}
