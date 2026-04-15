import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../theme/app_colors.dart';
import '../models/appointment_model.dart';
import '../providers/owner_providers.dart';
import '../services/app_localizations.dart';
import '../services/database_service.dart';
import '../utils/currency_helper.dart';

class OwnerClientsScreen extends ConsumerWidget {
  const OwnerClientsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final appointmentsAsync = ref.watch(ownerAppointmentsProvider);
    final salonAsync = ref.watch(ownerSalonProvider);
    final salonId = salonAsync.value?.id;

    return Scaffold(
      backgroundColor: AppColors.secondary50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          l?.tr('clients_title') ?? 'Mes clients',
          style: GoogleFonts.dmSans(
            fontWeight: FontWeight.bold,
            color: AppColors.brand950,
            fontSize: 20,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.brand950),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: appointmentsAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.brand600)),
        error: (e, _) => Center(child: Text('${l?.tr('common_error_short') ?? 'Erreur'} : $e')),
        data: (appointments) => _ClientsBody(appointments: appointments, salonId: salonId ?? ''),
      ),
    );
  }
}

class _ClientsBody extends StatefulWidget {
  const _ClientsBody({required this.appointments, required this.salonId});
  final List<AppointmentModel> appointments;
  final String salonId;

  @override
  State<_ClientsBody> createState() => _ClientsBodyState();
}

class _ClientsBodyState extends State<_ClientsBody> {
  String _search = '';
  bool _showWalkIn = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final completed =
        widget.appointments.where((a) => a.status == 'completed').toList();

    final clientData = <String, _ClientInfo>{};
    for (final a in completed) {
      final cid = a.clientId;
      if (cid.isEmpty) continue;

      if (_showWalkIn) {
        if (cid != 'walk-in') continue;
        final phone = a.clientPhone ?? '';
        if (phone.isEmpty) continue;
        final info = clientData.putIfAbsent(
            phone, () => _ClientInfo(name: a.clientName ?? '—', phone: phone, isWalkIn: true));
        info.totalSpent += a.price;
        info.visitCount++;
        if (a.dateTime.isAfter(info.lastVisit)) info.lastVisit = a.dateTime;
        if (a.dateTime.isBefore(info.firstVisit)) info.firstVisit = a.dateTime;
        info.serviceCounts[a.serviceName] =
            (info.serviceCounts[a.serviceName] ?? 0) + 1;
      } else {
        if (cid == 'walk-in') continue;
        final info = clientData.putIfAbsent(
            cid, () => _ClientInfo(name: a.clientName ?? '—', phone: a.clientPhone, userId: cid));
        info.totalSpent += a.price;
        info.visitCount++;
        if (a.dateTime.isAfter(info.lastVisit)) info.lastVisit = a.dateTime;
        if (a.dateTime.isBefore(info.firstVisit)) info.firstVisit = a.dateTime;
        info.serviceCounts[a.serviceName] =
            (info.serviceCounts[a.serviceName] ?? 0) + 1;
      }
    }

    var clients = clientData.values.toList()
      ..sort((a, b) => b.totalSpent.compareTo(a.totalSpent));

    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      clients = clients
          .where((c) =>
              c.name.toLowerCase().contains(q) ||
              (c.phone?.toLowerCase().contains(q) ?? false))
          .toList();
    }

    return Column(
      children: [
        // Toggle tabs
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: AppColors.secondary100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                _buildTab(
                  icon: Icons.smartphone,
                  label: l?.tr('clients_app') ?? 'Clients app',
                  isActive: !_showWalkIn,
                  onTap: () => setState(() => _showWalkIn = false),
                ),
                _buildTab(
                  icon: Icons.language,
                  label: l?.tr('clients_walkin') ?? 'Réservations site',
                  isActive: _showWalkIn,
                  onTap: () => setState(() => _showWalkIn = true),
                ),
              ],
            ),
          ),
        ),

        // Blacklist button
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: GestureDetector(
            onTap: () => _openBlacklist(context),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.secondary200),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.block, size: 16, color: Colors.red),
                  const SizedBox(width: 8),
                  Text(
                    l?.tr('clients_blacklist') ?? 'Blacklist',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: TextField(
            onChanged: (v) => setState(() => _search = v),
            decoration: InputDecoration(
              hintText: l?.tr('clients_search_hint') ?? 'Rechercher un client…',
              hintStyle: const TextStyle(
                  color: AppColors.secondary400, fontSize: 14),
              prefixIcon:
                  const Icon(Icons.search, color: AppColors.secondary400),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),

        // Count
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              (l?.tr('clients_count') ?? '{count} client(s)').replaceAll('{count}', '${clients.length}'),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.secondary500,
              ),
            ),
          ),
        ),

        // List
        Expanded(
          child: clients.isEmpty
              ? Center(
                  child: Text(
                    _search.isNotEmpty
                        ? l?.tr('clients_not_found') ?? 'Aucun client trouvé'
                        : l?.tr('clients_empty') ?? 'Aucun client pour le moment',
                    style: const TextStyle(
                        color: AppColors.secondary400, fontSize: 14),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                  itemCount: clients.length,
                  itemBuilder: (_, i) =>
                      _ClientCard(
                        client: clients[i],
                        rank: i + 1,
                        salonId: widget.salonId,
                      ),
                ),
        ),
      ],
    );
  }

  Widget _buildTab({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isActive
                ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4, offset: const Offset(0, 1))]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: isActive ? AppColors.brand600 : AppColors.secondary400),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isActive ? AppColors.brand600 : AppColors.secondary400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openBlacklist(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _BlacklistScreen(salonId: widget.salonId),
      ),
    );
  }
}

// ─── Blacklist Screen ─────────────────────────────────────────────────────────

class _BlacklistScreen extends StatefulWidget {
  const _BlacklistScreen({required this.salonId});
  final String salonId;

  @override
  State<_BlacklistScreen> createState() => _BlacklistScreenState();
}

class _BlacklistScreenState extends State<_BlacklistScreen> {
  List<Map<String, dynamic>> _blacklist = [];
  bool _loading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _loadBlacklist();
  }

  Future<void> _loadBlacklist() async {
    final list = await DatabaseService().getBlacklist(widget.salonId);
    setState(() {
      _blacklist = list;
      _loading = false;
    });
  }

  Future<void> _removeFromBlacklist(Map<String, dynamic> entry) async {
    final l = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l?.tr('clients_bl_remove_title') ?? 'Débloquer ce client ?'),
        content: Text(
          (l?.tr('clients_bl_remove_msg') ?? '{name} pourra à nouveau réserver.')
              .replaceAll('{name}', entry['name'] ?? entry['phone'] ?? ''),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l?.tr('common_cancel') ?? 'Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              l?.tr('clients_bl_unblock') ?? 'Débloquer',
              style: const TextStyle(color: AppColors.brand600),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DatabaseService().removeFromBlacklist(widget.salonId, entry);
      _loadBlacklist();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: AppColors.secondary50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          l?.tr('clients_blacklist') ?? 'Blacklist',
          style: GoogleFonts.dmSans(
            fontWeight: FontWeight.bold,
            color: AppColors.brand950,
            fontSize: 20,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.brand950),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.brand600))
          : _blacklist.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle_outline, size: 48, color: AppColors.secondary300),
                      const SizedBox(height: 12),
                      Text(
                        l?.tr('clients_bl_empty') ?? 'Aucun client bloqué',
                        style: const TextStyle(color: AppColors.secondary400, fontSize: 14),
                      ),
                    ],
                  ),
                )
              : _buildBlacklistContent(l),
    );
  }

  Widget _buildBlacklistContent(AppLocalizations? l) {
    final filtered = _search.isEmpty
        ? _blacklist
        : _blacklist.where((entry) {
            final q = _search.toLowerCase();
            final name = (entry['name'] ?? '').toString().toLowerCase();
            final phone = (entry['phone'] ?? '').toString().toLowerCase();
            return name.contains(q) || phone.contains(q);
          }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: TextField(
            onChanged: (v) => setState(() => _search = v),
            decoration: InputDecoration(
              hintText: l?.tr('clients_search_hint') ?? 'Rechercher…',
              hintStyle: const TextStyle(color: AppColors.secondary400, fontSize: 14),
              prefixIcon: const Icon(Icons.search, color: AppColors.secondary400),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle_outline, size: 48, color: AppColors.secondary300),
                      const SizedBox(height: 12),
                      Text(
                        l?.tr('clients_bl_empty') ?? 'Aucun client bloqué',
                        style: const TextStyle(color: AppColors.secondary400, fontSize: 14),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final entry = filtered[i];
                    final name = entry['name'] ?? '—';
                    final phone = entry['phone'] ?? '';
                    final blockedAt = entry['blockedAt'] != null
                        ? (entry['blockedAt'] as Timestamp).toDate()
                        : null;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: const BoxDecoration(
                              color: Color(0xFFFEE2E2),
                              shape: BoxShape.circle,
                            ),
                            child: const Center(
                              child: Icon(Icons.block, size: 20, color: Colors.red),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                    color: AppColors.brand950,
                                  ),
                                ),
                                if (phone.isNotEmpty)
                                  Text(phone,
                                      style: const TextStyle(fontSize: 12, color: AppColors.secondary500)),
                                if (blockedAt != null)
                                  Text(
                                    '${l?.tr('clients_bl_since') ?? 'Bloqué le'} ${blockedAt.day}/${blockedAt.month}/${blockedAt.year}',
                                    style: const TextStyle(fontSize: 11, color: AppColors.secondary400),
                                  ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () => _removeFromBlacklist(entry),
                            child: Text(
                              l?.tr('clients_bl_unblock') ?? 'Débloquer',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.brand600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ─── Client Info ──────────────────────────────────────────────────────────────

class _ClientInfo {
  String name;
  String? phone;
  String? userId;
  double totalSpent;
  int visitCount;
  DateTime lastVisit;
  DateTime firstVisit;
  Map<String, int> serviceCounts;
  bool isWalkIn;

  _ClientInfo({required this.name, this.phone, this.userId, this.isWalkIn = false})
      : totalSpent = 0,
        visitCount = 0,
        lastVisit = DateTime(2000),
        firstVisit = DateTime(2100),
        serviceCounts = {};

  String get favoriteService {
    if (serviceCounts.isEmpty) return '—';
    final sorted = serviceCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.key;
  }
}

// ─── Client Card ──────────────────────────────────────────────────────────────

class _ClientCard extends StatelessWidget {
  const _ClientCard({required this.client, required this.rank, required this.salonId});
  final _ClientInfo client;
  final int rank;
  final String salonId;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final daysSinceLast =
        DateTime.now().difference(client.lastVisit).inDays;
    final lastVisitLabel = daysSinceLast == 0
        ? l?.tr('clients_today') ?? "Aujourd'hui"
        : daysSinceLast == 1
            ? l?.tr('clients_yesterday') ?? 'Hier'
            : (l?.tr('clients_days_ago') ?? 'Il y a {days} jours').replaceAll('{days}', '$daysSinceLast');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              // Avatar
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: rank <= 3 ? AppColors.brand50 : AppColors.secondary50,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: rank <= 3
                      ? Icon(Icons.star_rounded,
                          size: 20,
                          color: rank == 1
                              ? const Color(0xFFD97706)
                              : rank == 2
                                  ? const Color(0xFF9CA3AF)
                                  : const Color(0xFFB45309))
                      : Text(
                          client.name.isNotEmpty
                              ? client.name[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: AppColors.brand600,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      client.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: AppColors.brand950,
                      ),
                    ),
                    if (client.phone != null && client.phone!.isNotEmpty)
                      Text(
                        client.phone!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.secondary500,
                        ),
                      ),
                  ],
                ),
              ),
              // Menu button
              PopupMenuButton<String>(
                onSelected: (value) => _handleMenuAction(context, value),
                icon: const Icon(Icons.more_vert, size: 20, color: AppColors.secondary400),
                itemBuilder: (_) => [
                  if (client.phone != null && client.phone!.isNotEmpty)
                    PopupMenuItem(
                      value: 'call',
                      child: Row(
                        children: [
                          const Icon(Icons.phone_outlined, size: 18, color: AppColors.brand600),
                          const SizedBox(width: 10),
                          Text(l?.tr('clients_call') ?? 'Appeler'),
                        ],
                      ),
                    ),
                  PopupMenuItem(
                    value: 'block',
                    child: Row(
                      children: [
                        const Icon(Icons.block, size: 18, color: Colors.red),
                        const SizedBox(width: 10),
                        Text(
                          l?.tr('clients_block') ?? 'Bloquer',
                          style: const TextStyle(color: Colors.red),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Stats row
          Row(
            children: [
              _MiniStat(
                icon: Icons.receipt_long,
                label: (l?.tr('clients_visits_count') ?? '{count} visite(s)').replaceAll('{count}', '${client.visitCount}'),
              ),
              const SizedBox(width: 16),
              _MiniStat(
                icon: Icons.payments_outlined,
                label: CurrencyHelper.format(client.totalSpent),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _MiniStat(
                  icon: Icons.content_cut,
                  label: client.favoriteService,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Last visit
          Text(
            (l?.tr('clients_last_visit') ?? 'Dernière visite : {label}').replaceAll('{label}', lastVisitLabel),
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.secondary400,
            ),
          ),
        ],
      ),
    );
  }

  void _handleMenuAction(BuildContext context, String action) {
    if (action == 'call' && client.phone != null) {
      launchUrl(Uri.parse('tel:${client.phone}'));
    } else if (action == 'block') {
      _blockClient(context);
    }
  }

  void _blockClient(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l?.tr('clients_block_title') ?? 'Bloquer ce client ?'),
        content: Text(
          (l?.tr('clients_block_msg') ?? '{name} ne pourra plus réserver dans votre salon.')
              .replaceAll('{name}', client.name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l?.tr('common_cancel') ?? 'Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              l?.tr('clients_block') ?? 'Bloquer',
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      final entry = <String, dynamic>{
        'name': client.name,
        'blockedAt': Timestamp.now(),
      };
      if (client.phone != null && client.phone!.isNotEmpty) {
        entry['phone'] = client.phone!;
      }
      if (client.userId != null && client.userId!.isNotEmpty) {
        entry['userId'] = client.userId!;
      }

      await DatabaseService().addToBlacklist(salonId, entry);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              (l?.tr('clients_blocked_success') ?? '{name} a été bloqué')
                  .replaceAll('{name}', client.name),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.secondary400),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.secondary600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
