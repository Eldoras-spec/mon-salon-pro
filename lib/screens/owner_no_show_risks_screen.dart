import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/owner_tasks_provider.dart';
import '../services/app_localizations.dart';
import '../theme/app_colors.dart';

class OwnerNoShowRisksScreen extends ConsumerWidget {
  const OwnerNoShowRisksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final clientsAsync = ref.watch(noShowRiskClientsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: AppColors.brand950, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          l?.tr('noshow_title') ?? 'RDV à risque',
          style: GoogleFonts.dmSans(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.brand950),
        ),
      ),
      body: clientsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _buildEmpty(context, l),
        data: (clients) => clients.isEmpty
            ? _buildEmpty(context, l)
            : Column(
                children: [
                  _buildInfoBanner(context, l),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: clients.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => _RiskClientCard(client: clients[i]),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildInfoBanner(BuildContext context, AppLocalizations? l) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              color: Color(0xFFD97706), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l?.tr('noshow_info_title') ?? 'Comment sécuriser ces RDV ?',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF854D0E)),
                ),
                const SizedBox(height: 4),
                Text(
                  l?.tr('noshow_info_desc') ??
                      'Appelez le client pour confirmer, ou demandez une avance par virement bancaire pour garantir la venue.',
                  style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF854D0E),
                      height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context, AppLocalizations? l) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(Icons.verified_rounded,
                  color: Color(0xFF16A34A), size: 40),
            ),
            const SizedBox(height: 20),
            Text(
              l?.tr('noshow_empty_title') ?? 'Aucun RDV à risque',
              style: GoogleFonts.dmSans(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.brand950),
            ),
            const SizedBox(height: 8),
            Text(
              l?.tr('noshow_empty_desc') ??
                  'Tous vos RDV d\'aujourd\'hui sont avec des clients fiables.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.secondary500,
                  height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _RiskClientCard extends StatelessWidget {
  const _RiskClientCard({required this.client});
  final NoShowRiskClient client;

  String _cleanPhone(String? p) {
    if (p == null) return '';
    return p.replaceAll(RegExp(r'[^\d+]'), '');
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final phone = _cleanPhone(client.clientPhone);
    final hasPhone = phone.isNotEmpty;
    final time = DateFormat('HH:mm').format(client.todayAppt.dateTime);
    final initial = client.clientName.isNotEmpty
        ? client.clientName.substring(0, 1).toUpperCase()
        : '?';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.secondary100),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: avatar + name + rate badge
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: Color(0xFFFEE2E2),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  initial,
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFDC2626)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      client.clientName,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.brand950),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasPhone ? phone : (l?.tr('noshow_no_phone') ?? 'Pas de téléphone'),
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.secondary500),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${client.rate}%',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFDC2626)),
                ),
              ),
            ],
          ),
          if (client.isCrossSalon) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.travel_explore_rounded,
                      size: 14, color: Color(0xFF1D4ED8)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l?.tr('noshow_cross_salon_hint') ??
                          'Historique cumulé sur d\'autres salons (jamais venu chez vous)',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF1D4ED8),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          // Stats row
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.secondary50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _StatItem(
                    label: client.isCrossSalon
                        ? (l?.tr('noshow_past_total_global') ?? 'RDV totaux')
                        : (l?.tr('noshow_past_total') ?? 'RDV passés'),
                    value: '${client.totalPast}',
                  ),
                ),
                Container(width: 1, height: 30, color: AppColors.secondary200),
                Expanded(
                  child: _StatItem(
                    label: l?.tr('noshow_past_cancelled') ?? 'Annulés',
                    value: '${client.cancelledPast}',
                    color: const Color(0xFFDC2626),
                  ),
                ),
                Container(width: 1, height: 30, color: AppColors.secondary200),
                Expanded(
                  child: _StatItem(
                    label: l?.tr('noshow_today_time') ?? "Aujourd'hui",
                    value: time,
                    color: AppColors.brand600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Service
          Row(
            children: [
              const Icon(Icons.content_cut_rounded,
                  size: 14, color: AppColors.secondary400),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  client.todayAppt.serviceName,
                  style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.secondary600,
                      fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Actions
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: Icons.phone_rounded,
                  label: l?.tr('noshow_call') ?? 'Appeler',
                  color: AppColors.brand600,
                  onTap: hasPhone
                      ? () async {
                          final uri = Uri.parse('tel:$phone');
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri);
                          }
                        }
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(
                  icon: Icons.chat_rounded,
                  label: 'WhatsApp',
                  color: const Color(0xFF25D366),
                  onTap: hasPhone
                      ? () async {
                          final msg = Uri.encodeComponent(
                              (l?.tr('noshow_wa_template') ??
                                      'Bonjour {name}, je vous confirme votre RDV chez nous aujourd\'hui à {time} pour {service}. Merci de me confirmer votre venue.')
                                  .replaceAll('{name}', client.clientName.split(' ').first)
                                  .replaceAll('{time}', time)
                                  .replaceAll('{service}', client.todayAppt.serviceName));
                          final uri = Uri.parse(
                              'https://wa.me/${phone.replaceAll("+", "")}?text=$msg');
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri,
                                mode: LaunchMode.externalApplication);
                          }
                        }
                      : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.label,
    required this.value,
    this.color,
  });
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: color ?? AppColors.brand950),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.secondary400),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: enabled ? color : AppColors.secondary200,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
