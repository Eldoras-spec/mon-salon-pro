import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_colors.dart';
import '../models/appointment_model.dart';
import '../providers/owner_providers.dart';

class OwnerClientsScreen extends ConsumerWidget {
  const OwnerClientsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appointmentsAsync = ref.watch(ownerAppointmentsProvider);

    return Scaffold(
      backgroundColor: AppColors.secondary50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'Mes clients',
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
        error: (e, _) => Center(child: Text('Erreur : $e')),
        data: (appointments) => _ClientsBody(appointments: appointments),
      ),
    );
  }
}

class _ClientsBody extends StatefulWidget {
  const _ClientsBody({required this.appointments});
  final List<AppointmentModel> appointments;

  @override
  State<_ClientsBody> createState() => _ClientsBodyState();
}

class _ClientsBodyState extends State<_ClientsBody> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final completed =
        widget.appointments.where((a) => a.status == 'completed').toList();

    // Build client data from completed appointments
    final clientData = <String, _ClientInfo>{};
    for (final a in completed) {
      final cid = a.clientId;
      if (cid.isEmpty || cid == 'walk-in') continue;
      final info = clientData.putIfAbsent(
          cid, () => _ClientInfo(name: a.clientName ?? '—', phone: a.clientPhone));
      info.totalSpent += a.price;
      info.visitCount++;
      if (a.dateTime.isAfter(info.lastVisit)) info.lastVisit = a.dateTime;
      if (a.dateTime.isBefore(info.firstVisit)) info.firstVisit = a.dateTime;
      info.serviceCounts[a.serviceName] =
          (info.serviceCounts[a.serviceName] ?? 0) + 1;
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
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: TextField(
            onChanged: (v) => setState(() => _search = v),
            decoration: InputDecoration(
              hintText: 'Rechercher un client…',
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
              '${clients.length} client${clients.length > 1 ? 's' : ''}',
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
                        ? 'Aucun client trouvé'
                        : 'Aucun client pour le moment',
                    style: const TextStyle(
                        color: AppColors.secondary400, fontSize: 14),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                  itemCount: clients.length,
                  itemBuilder: (_, i) =>
                      _ClientCard(client: clients[i], rank: i + 1),
                ),
        ),
      ],
    );
  }
}

class _ClientInfo {
  String name;
  String? phone;
  double totalSpent;
  int visitCount;
  DateTime lastVisit;
  DateTime firstVisit;
  Map<String, int> serviceCounts;

  _ClientInfo({required this.name, this.phone})
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

class _ClientCard extends StatelessWidget {
  const _ClientCard({required this.client, required this.rank});
  final _ClientInfo client;
  final int rank;

  @override
  Widget build(BuildContext context) {
    final daysSinceLast =
        DateTime.now().difference(client.lastVisit).inDays;
    final lastVisitLabel = daysSinceLast == 0
        ? "Aujourd'hui"
        : daysSinceLast == 1
            ? 'Hier'
            : 'Il y a $daysSinceLast jours';

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
              // Call button
              if (client.phone != null && client.phone!.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.phone_outlined,
                      size: 20, color: AppColors.brand600),
                  onPressed: () =>
                      launchUrl(Uri.parse('tel:${client.phone}')),
                  tooltip: 'Appeler',
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Stats row
          Row(
            children: [
              _MiniStat(
                icon: Icons.receipt_long,
                label: '${client.visitCount} visite${client.visitCount > 1 ? 's' : ''}',
              ),
              const SizedBox(width: 16),
              _MiniStat(
                icon: Icons.payments_outlined,
                label: '${client.totalSpent.toStringAsFixed(0)} MAD',
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
            'Dernière visite : $lastVisitLabel',
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.secondary400,
            ),
          ),
        ],
      ),
    );
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
