import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import '../models/salon_model.dart';
import '../models/team_member_model.dart';
import '../providers/owner_providers.dart';
import '../services/app_localizations.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../services/database_service.dart';
import '../widgets/service_form_dialog.dart';
import '../utils/currency_helper.dart';

class OwnerServicesScreen extends ConsumerStatefulWidget {
  const OwnerServicesScreen({super.key});

  @override
  ConsumerState<OwnerServicesScreen> createState() => _OwnerServicesScreenState();
}

class _OwnerServicesScreenState extends ConsumerState<OwnerServicesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _services = [];
  List<Map<String, dynamic>> _packs = [];
  bool _loading = false;
  bool _initialized = false;
  String? _categoryFilter; // null = all
  bool _showPersonalized = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _initFromSalon(SalonModel salon) {
    if (_initialized) return;
    _services = List<Map<String, dynamic>>.from(
        salon.services.map((s) => Map<String, dynamic>.from(s)));
    _packs = List<Map<String, dynamic>>.from(
        salon.servicePacks.map((p) => Map<String, dynamic>.from(p)));
    _initialized = true;
  }

  Map<String, Set<String>> _buildServiceMemberMap(List<TeamMemberModel> members) {
    final map = <String, Set<String>>{};
    for (final m in members) {
      for (final sName in m.assignedServiceNames) {
        map.putIfAbsent(sName, () => {}).add(m.name);
      }
    }
    return map;
  }

  Future<void> _save(SalonModel salon) async {
    setState(() => _loading = true);
    try {
      final categories = _services
          .map((s) => s['category'] as String? ?? '')
          .where((c) => c.isNotEmpty)
          .toSet()
          .toList();

      final updated = SalonModel(
        id: salon.id,
        ownerId: salon.ownerId,
        name: salon.name,
        city: salon.city,
        country: salon.country,
        address: salon.address,
        description: salon.description,
        category: salon.category,
        rating: salon.rating,
        reviewCount: salon.reviewCount,
        images: salon.images,
        logoUrl: salon.logoUrl,
        workingHours: salon.workingHours,
        services: _services,
        serviceCategories: categories,
        servicePacks: _packs,
        latitude: salon.latitude,
        longitude: salon.longitude,
        createdAt: salon.createdAt,
        socialLinks: salon.socialLinks,
        slug: salon.slug,
        currency: salon.currency,
        rewardPointsEnabled: salon.rewardPointsEnabled,
        aiPromosEnabled: salon.aiPromosEnabled,
        aiPromoConfig: salon.aiPromoConfig,
        googleReviewReward: salon.googleReviewReward,
        isPremium: salon.isPremium,
        galleryStorageUsed: salon.galleryStorageUsed,
        salonType: salon.salonType,
        timezone: salon.timezone,
      );
      await DatabaseService().saveSalon(updated);

      // Update team member assignments
      final hasAssignments = _services.any((s) =>
          (s['assignedMembers'] as List?)?.isNotEmpty == true);
      if (hasAssignments) {
        final teamMembers = ref.read(ownerTeamProvider).value ?? [];
        for (final member in teamMembers) {
          final assignedServices = _services
              .where((s) {
                final members = List<String>.from(s['assignedMembers'] ?? []);
                return members.contains(member.name);
              })
              .map((s) => s['name'] as String)
              .toList();
          await DatabaseService().updateTeamMember(
            salon.id, member.id, {'assignedServiceNames': assignedServices},
          );
        }
      }

      if (mounted) {
        ref.invalidate(ownerSalonProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)?.tr('common_saved') ?? 'Sauvegardé'),
            backgroundColor: AppColors.brand600,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final salonAsync = ref.watch(ownerSalonProvider);
    final salon = salonAsync.value;

    if (salon != null) _initFromSalon(salon);

    return Scaffold(
      backgroundColor: AppColors.secondary50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.brand950, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          l?.tr('services_title') ?? 'Services & Packs',
          style: GoogleFonts.dmSans(fontWeight: FontWeight.bold, color: AppColors.brand950, fontSize: 20),
        ),
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brand600)),
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.brand600,
          unselectedLabelColor: AppColors.secondary400,
          indicatorColor: AppColors.brand600,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          tabs: [
            Tab(text: '${l?.tr('services_tab') ?? 'Services'} (${_services.length})'),
            Tab(text: '${l?.tr('packs_tab') ?? 'Packs'} (${_packs.length})'),
            Tab(text: l?.tr('services_priority_tab') ?? 'Priorité'),
          ],
        ),
      ),
      floatingActionButton: _tabController.index < 2
          ? FloatingActionButton(
              onPressed: () {
                if (_tabController.index == 0) {
                  _showServiceDialog(null, salon);
                } else {
                  _showPackDialog(null, salon);
                }
              },
              backgroundColor: AppColors.brand600,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
      body: salon == null
          ? const Center(child: CircularProgressIndicator(color: AppColors.brand600))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildServicesList(l, salon),
                _buildPacksList(l, salon),
                _buildPriorityTab(l, salon),
              ],
            ),
    );
  }

  // ── Services tab ──────────────────────────────────────────────

  Widget _buildServicesList(AppLocalizations? l, SalonModel salon) {
    if (_services.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.content_cut, size: 48, color: AppColors.secondary300),
            const SizedBox(height: 12),
            Text(l?.tr('services_empty') ?? 'Aucun service', style: const TextStyle(color: AppColors.secondary400)),
          ],
        ),
      );
    }

    // Categories
    final categories = _services
        .where((s) => s['visibleTo'] == null)
        .map((s) => s['category'] as String? ?? '')
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList();
    final hasPersonalized = _services.any((s) => s['visibleTo'] != null);

    // Filtered list
    final filtered = _services.where((s) {
      final isPersonalized = s['visibleTo'] != null;
      if (_showPersonalized) return isPersonalized;
      if (isPersonalized) return false;
      if (_categoryFilter != null && s['category'] != _categoryFilter) return false;
      return true;
    }).toList();

    return Column(
      children: [
        // Filter row
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _filterChip(l?.tr('common_all') ?? 'Tous', _categoryFilter == null && !_showPersonalized, () => setState(() { _categoryFilter = null; _showPersonalized = false; })),
              ...categories.map((c) => _filterChip(c, _categoryFilter == c, () => setState(() { _categoryFilter = c; _showPersonalized = false; }))),
              if (hasPersonalized)
                _filterChip(l?.tr('services_personalized') ?? 'Personnalisé', _showPersonalized, () => setState(() { _showPersonalized = true; _categoryFilter = null; })),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        // List
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 80),
            itemCount: filtered.length,
            itemBuilder: (_, i) {
              final realIndex = _services.indexOf(filtered[i]);
              final svc = filtered[i];
        final name = svc['name'] ?? 'Service';
        final category = svc['category'] ?? '';
        final duration = svc['duration'] ?? 30;
        final price = (svc['price'] as num?)?.toDouble() ?? 0;
        final isComplex = svc['isComplex'] == true;
        final assignedMembers = List<String>.from(svc['assignedMembers'] ?? []);

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.brand950)),
                            ),
                            if (isComplex) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: AppColors.brand50, borderRadius: BorderRadius.circular(4)),
                                child: const Text('Options', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.brand600)),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (category.isNotEmpty) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(color: AppColors.secondary50, borderRadius: BorderRadius.circular(6)),
                                child: Text(category, style: const TextStyle(fontSize: 11, color: AppColors.secondary500)),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Text('$duration min', style: const TextStyle(fontSize: 12, color: AppColors.secondary400)),
                            const SizedBox(width: 8),
                            Text(CurrencyHelper.format(price, salon.currency), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.brand600)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.secondary400),
                    onPressed: () => _showServiceDialog(realIndex, salon),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFDC2626)),
                    onPressed: () => _deleteService(realIndex, l, salon),
                  ),
                ],
              ),
              if (assignedMembers.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: assignedMembers.map((name) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.secondary50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('👤 $name', style: const TextStyle(fontSize: 11, color: AppColors.secondary600)),
                  )).toList(),
                ),
              ],
            ],
          ),
        );
            },
          ),
        ),
      ],
    );
  }

  Widget _filterChip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? AppColors.brand600 : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? AppColors.brand600 : AppColors.secondary200),
          ),
          child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: selected ? Colors.white : AppColors.brand950)),
        ),
      ),
    );
  }

  void _showServiceDialog(int? index, SalonModel? salon) {
    if (salon == null) return;
    final teamMembers = ref.read(ownerTeamProvider).value ?? [];
    final serviceMemberMap = _buildServiceMemberMap(teamMembers);

    final isNew = index == null;
    final existing = isNew ? null : _services[index];

    Set<String> currentAssigned = {};
    if (existing != null) {
      final fromData = existing['assignedMembers'];
      if (fromData != null) {
        currentAssigned = Set<String>.from(fromData);
      } else {
        currentAssigned = serviceMemberMap[existing['name']] ?? {};
      }
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ServiceFormDialog(
          existing: existing,
          assignedMembers: currentAssigned,
          teamMembers: teamMembers,
          salonId: salon.id,
          salonType: salon.salonType,
          isPremium: salon.isPremium,
          galleryStorageUsed: salon.galleryStorageUsed,
          currency: salon.currency,
          onSave: (entry) {
            setState(() {
              if (isNew) {
                _services.add(entry);
              } else {
                _services[index] = entry;
              }
            });
            _save(salon);
          },
        ),
      ),
    );
  }

  /// Generic confirm dialog used before any destructive item removal
  /// (service or pack). Returns true when the user explicitly accepts.
  Future<bool> _confirmDelete(
    AppLocalizations? l, {
    required String title,
    required String message,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l?.tr('common_cancel') ?? 'Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFDC2626)),
            child: Text(l?.tr('common_delete') ?? 'Supprimer',
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _deleteService(int index, AppLocalizations? l, [SalonModel? salon]) async {
    final serviceName = _services[index]['name'] as String? ?? '';
    final packUsingService = _packs.where((pack) {
      final packServices = List<String>.from(pack['services'] ?? []);
      return packServices.contains(serviceName);
    }).toList();

    if (packUsingService.isNotEmpty) {
      final packName = packUsingService.first['name'] ?? 'Pack';
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l?.tr('common_error_short') ?? 'Erreur'),
          content: Text(
            (l?.tr('salon_service_delete_pack_error') ?? 'Ce service fait partie du pack "{pack}". Supprimez d\'abord le pack.')
                .replaceAll('{pack}', packName),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l?.tr('common_ok') ?? 'OK'))],
        ),
      );
      return;
    }

    final confirmed = await _confirmDelete(
      l,
      title: l?.tr('salon_service_delete_title') ?? 'Supprimer ce service ?',
      message: (l?.tr('salon_service_delete_message') ??
              'Vous êtes sur le point de supprimer « {name} ». Cette action est définitive.')
          .replaceAll('{name}', serviceName),
    );
    if (!confirmed) return;
    if (!mounted) return;

    // Clean up gallery files from Storage
    final service = _services[index];
    if (service['isComplex'] == true && service['options'] != null) {
      for (final step in (service['options'] as List)) {
        for (final choice in (step['choices'] as List? ?? [])) {
          if (choice['isGallery'] == true && choice['galleryItems'] != null) {
            for (final item in (choice['galleryItems'] as List)) {
              final url = item['url'] as String?;
              final thumbUrl = item['thumbnailUrl'] as String?;
              if (url != null && url.isNotEmpty) {
                try { FirebaseStorage.instance.refFromURL(url).delete(); } catch (_) {}
              }
              if (thumbUrl != null && thumbUrl.isNotEmpty) {
                try { FirebaseStorage.instance.refFromURL(thumbUrl).delete(); } catch (_) {}
              }
            }
          }
        }
      }
    }
    setState(() => _services.removeAt(index));
    if (salon != null) _save(salon);
  }

  // ── Packs tab ─────────────────────────────────────────────────

  Widget _buildPacksList(AppLocalizations? l, SalonModel salon) {
    if (_packs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inventory_2_outlined, size: 48, color: AppColors.secondary300),
            const SizedBox(height: 12),
            Text(l?.tr('packs_empty') ?? 'Aucun pack', style: const TextStyle(color: AppColors.secondary400)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 80),
      itemCount: _packs.length,
      itemBuilder: (_, i) {
        final pack = _packs[i];
        final name = pack['name'] ?? 'Pack';
        final packServices = List<String>.from(pack['services'] ?? []);
        final price = (pack['price'] as num?)?.toDouble() ?? 0;
        final originalPrice = (pack['originalPrice'] as num?)?.toDouble() ?? 0;
        final discount = originalPrice > 0 ? ((1 - price / originalPrice) * 100).round() : 0;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.brand100),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: AppColors.brand600, borderRadius: BorderRadius.circular(4)),
                    child: const Text('Pack', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.brand950)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.secondary400),
                    onPressed: () => _showPackDialog(i, salon),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFDC2626)),
                    onPressed: () async {
                      final confirmed = await _confirmDelete(
                        l,
                        title: l?.tr('salon_pack_delete_title') ?? 'Supprimer ce pack ?',
                        message: (l?.tr('salon_pack_delete_message') ??
                                'Vous êtes sur le point de supprimer « {name} ». Cette action est définitive.')
                            .replaceAll('{name}', '$name'),
                      );
                      if (!confirmed || !mounted) return;
                      setState(() => _packs.removeAt(i));
                      _save(salon);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(packServices.join(' · '), style: const TextStyle(fontSize: 12, color: AppColors.secondary400)),
              const SizedBox(height: 6),
              Row(
                children: [
                  if (discount > 0) ...[
                    Text(CurrencyHelper.format(originalPrice, salon.currency),
                        style: const TextStyle(fontSize: 12, decoration: TextDecoration.lineThrough, color: AppColors.secondary400)),
                    const SizedBox(width: 6),
                  ],
                  Text(CurrencyHelper.format(price, salon.currency),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.brand600)),
                  if (discount > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0xFFF0FDF4), borderRadius: BorderRadius.circular(4)),
                      child: Text('-$discount%', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF16A34A))),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Priority tab ───────────────────────────────────────────────

  Widget _buildPriorityTab(AppLocalizations? l, SalonModel salon) {
    final teamMembers = ref.watch(ownerTeamProvider).value ?? [];

    if (_services.isEmpty) {
      return Center(
        child: Text(l?.tr('services_empty') ?? 'Aucun service', style: const TextStyle(color: AppColors.secondary400)),
      );
    }

    final serviceWidgets = <Widget>[];
    for (final svc in _services) {
      final svcName = (svc['name'] ?? svc['title'] ?? '') as String;
      final duration = svc['duration'] ?? 30;
      final category = svc['category'] ?? '';

      final assignedMembers = teamMembers
          .where((m) => m.isActive && m.assignedServiceNames.contains(svcName))
          .toList();

      if (assignedMembers.isEmpty) continue;

      final priorityList = List<String>.from(svc['memberPriority'] ?? []);
      final sortedMembers = List<TeamMemberModel>.from(assignedMembers);
      sortedMembers.sort((a, b) {
        final ai = priorityList.indexOf(a.id);
        final bi = priorityList.indexOf(b.id);
        if (ai >= 0 && bi >= 0) return ai.compareTo(bi);
        if (ai >= 0) return -1;
        if (bi >= 0) return 1;
        return 0;
      });

      serviceWidgets.add(Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(svcName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.brand950)),
                      Text('$category · $duration min', style: const TextStyle(fontSize: 12, color: AppColors.secondary400)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.brand50, borderRadius: BorderRadius.circular(6)),
                  child: Text('${sortedMembers.length}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.brand600)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),
            ...sortedMembers.asMap().entries.map((entry) {
              final idx = entry.key;
              final member = entry.value;
              final isFirst = idx == 0;
              final isLast = idx == sortedMembers.length - 1;

              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Container(
                      width: 24, height: 24,
                      decoration: BoxDecoration(
                        color: isFirst ? AppColors.brand600 : AppColors.secondary100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Center(
                        child: Text('${idx + 1}', style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.bold,
                          color: isFirst ? Colors.white : AppColors.secondary500,
                        )),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(member.name, style: TextStyle(
                        fontSize: 14,
                        fontWeight: isFirst ? FontWeight.w600 : FontWeight.normal,
                        color: AppColors.brand950,
                      )),
                    ),
                    if (!isFirst)
                      GestureDetector(
                        onTap: () => _movePriority(svcName, sortedMembers, idx, -1, salon),
                        child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.keyboard_arrow_up, size: 20, color: AppColors.secondary500)),
                      )
                    else
                      const SizedBox(width: 28),
                    if (!isLast)
                      GestureDetector(
                        onTap: () => _movePriority(svcName, sortedMembers, idx, 1, salon),
                        child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.keyboard_arrow_down, size: 20, color: AppColors.secondary500)),
                      )
                    else
                      const SizedBox(width: 28),
                  ],
                ),
              );
            }),
          ],
        ),
      ));
    }

    if (serviceWidgets.isEmpty) {
      return Center(
        child: Text(l?.tr('team_no_services') ?? 'Aucun service avec membres assignés', style: const TextStyle(color: AppColors.secondary400)),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Text(
          l?.tr('team_priority_hint') ?? 'Classez les employés par ordre de priorité pour l\'auto-assignation.',
          style: const TextStyle(fontSize: 12, color: AppColors.secondary400),
        ),
        const SizedBox(height: 16),
        ...serviceWidgets,
      ],
    );
  }

  void _movePriority(String serviceName, List<TeamMemberModel> currentOrder, int fromIdx, int direction, SalonModel salon) {
    final toIdx = fromIdx + direction;
    if (toIdx < 0 || toIdx >= currentOrder.length) return;

    final temp = currentOrder[fromIdx];
    currentOrder[fromIdx] = currentOrder[toIdx];
    currentOrder[toIdx] = temp;

    final newPriority = currentOrder.map((m) => m.id).toList();

    for (final svc in _services) {
      final name = (svc['name'] ?? svc['title'] ?? '') as String;
      if (name == serviceName) {
        svc['memberPriority'] = newPriority;
        break;
      }
    }

    setState(() {});

    // Save silently
    DatabaseService().updateSalonField(salon.id, 'services', _services);
  }

  void _showPackDialog(int? index, SalonModel? salon) {
    if (salon == null) return;
    final isNew = index == null;
    final existing = isNew ? null : _packs[index];

    showDialog(
      context: context,
      builder: (_) => _PackFormDialog(
        existing: existing,
        availableServices: _services,
        currency: salon.currency,
        onSave: (entry) {
          setState(() {
            if (isNew) {
              _packs.add(entry);
            } else {
              _packs[index] = entry;
            }
          });
          if (salon != null) _save(salon);
        },
      ),
    );
  }
}

// ── Pack Form Dialog ────────────────────────────────────────────────────────────

class _PackFormDialog extends StatefulWidget {
  const _PackFormDialog({
    this.existing,
    required this.availableServices,
    required this.onSave,
    required this.currency,
  });
  final Map<String, dynamic>? existing;
  final List<Map<String, dynamic>> availableServices;
  final void Function(Map<String, dynamic>) onSave;
  final String currency;

  @override
  State<_PackFormDialog> createState() => _PackFormDialogState();
}

class _PackFormDialogState extends State<_PackFormDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _descCtrl;
  late Set<String> _selectedServices;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?['name'] ?? '');
    _priceCtrl = TextEditingController(
      text: e != null && (e['price'] as num?) != null ? (e['price'] as num).toStringAsFixed(0) : '',
    );
    _descCtrl = TextEditingController(text: e?['description'] ?? '');
    _selectedServices = Set<String>.from(e?['services'] ?? []);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  double get _originalPrice {
    return _selectedServices.fold(0.0, (sum, sName) {
      final svc = widget.availableServices.firstWhere(
        (s) => (s['name'] ?? s['title']) == sName,
        orElse: () => <String, dynamic>{},
      );
      return sum + ((svc['price'] as num?)?.toDouble() ?? 0);
    });
  }

  void _submit() {
    final l = AppLocalizations.of(context);
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l?.tr('pack_name_required') ?? 'Le nom du pack est requis')),
      );
      return;
    }
    if (_selectedServices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l?.tr('pack_services_required') ?? 'Sélectionnez au moins un service')),
      );
      return;
    }

    final entry = <String, dynamic>{
      'name': _nameCtrl.text.trim(),
      'description': _descCtrl.text.trim(),
      'services': _selectedServices.toList(),
      'price': double.tryParse(_priceCtrl.text.trim()) ?? 0.0,
      'originalPrice': _originalPrice,
    };
    Navigator.pop(context);
    widget.onSave(entry);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final isEdit = widget.existing != null;

    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85, maxWidth: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      isEdit ? (l?.tr('pack_edit') ?? 'Modifier le pack') : (l?.tr('pack_new') ?? 'Nouveau pack'),
                      style: GoogleFonts.dmSans(fontWeight: FontWeight.bold, color: AppColors.brand950, fontSize: 18),
                    ),
                  ),
                  GestureDetector(onTap: () => Navigator.pop(context), child: const Icon(Icons.close, color: AppColors.secondary400, size: 22)),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _label(l?.tr('pack_name') ?? 'Nom du pack *'),
                    const SizedBox(height: 6),
                    _field(_nameCtrl, 'ex. Pack Mariée'),
                    const SizedBox(height: 14),
                    _label(l?.tr('pack_select_services') ?? 'Services inclus *'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: widget.availableServices.map((svc) {
                        final name = (svc['name'] ?? svc['title'] ?? '') as String;
                        final isSelected = _selectedServices.contains(name);
                        return GestureDetector(
                          onTap: () => setState(() {
                            if (isSelected) { _selectedServices.remove(name); } else { _selectedServices.add(name); }
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: isSelected ? AppColors.brand100 : Colors.white,
                              border: Border.all(color: isSelected ? AppColors.brand400 : AppColors.secondary200),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(name, style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                              color: isSelected ? AppColors.brand700 : AppColors.secondary600,
                            )),
                          ),
                        );
                      }).toList(),
                    ),
                    if (_selectedServices.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        '${l?.tr('pack_original_price') ?? 'Prix original'} : ${CurrencyHelper.format(_originalPrice, widget.currency)}',
                        style: const TextStyle(fontSize: 12, color: AppColors.secondary400),
                      ),
                    ],
                    const SizedBox(height: 14),
                    _label(l?.tr('pack_price') ?? 'Prix du pack (${CurrencyHelper.symbol(widget.currency)}) *'),
                    const SizedBox(height: 6),
                    _field(_priceCtrl, '0', keyboardType: TextInputType.number),
                    const SizedBox(height: 14),
                    _label(l?.tr('pack_description') ?? 'Description (optionnel)'),
                    const SizedBox(height: 6),
                    _field(_descCtrl, 'Description...', maxLines: 2),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(l?.tr('common_cancel') ?? 'Annuler', style: const TextStyle(color: AppColors.secondary400)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brand600,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    child: Text(isEdit ? (l?.tr('common_save') ?? 'Enregistrer') : (l?.tr('common_add') ?? 'Ajouter')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.secondary700));

  Widget _field(TextEditingController ctrl, String hint, {int maxLines = 1, TextInputType? keyboardType}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 14, color: AppColors.brand950),
      decoration: InputDecoration(
        hintText: hint,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.secondary300)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.secondary300)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.brand500)),
      ),
    );
  }
}
