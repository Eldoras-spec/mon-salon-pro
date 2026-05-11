import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/appointment_model.dart';
import '../models/client_summary_model.dart';
import '../models/salon_model.dart';
import '../models/team_member_model.dart';
import '../providers/owner_providers.dart';
import '../screens/owner_appointments_screen.dart';
import '../services/app_localizations.dart';
import '../services/database_service.dart';
import '../theme/app_colors.dart';
import '../utils/currency_helper.dart';

/// Show the full client-detail bottom sheet for [client]. Returns when
/// the user dismisses the sheet.
Future<void> showClientDetailSheet(
  BuildContext context, {
  required ClientSummaryModel client,
  required SalonModel salon,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      child: ClientDetailSheet(client: client, salon: salon),
    ),
  );
}

/// In-memory cache of the async fetches needed by the detail sheet
/// (loyalty balance, upcoming RDV list, past RDV list, blacklist
/// status, no-show reputation). Re-opening the same client within
/// `_ttl` returns instantly with no Firestore reads. Re-opening after
/// expiry, or hitting Edit notes / VIP toggle, refreshes the entry.
///
/// Lives at module scope so it survives sheet dismissal but resets on
/// app restart — adequate for a per-session optimisation.
class _ClientDetailCache {
  static const Duration _ttl = Duration(minutes: 5);
  static final Map<String, _CacheEntry> _store = {};

  static _ClientDetailData? get(String key) {
    final e = _store[key];
    if (e == null) return null;
    if (DateTime.now().difference(e.cachedAt) > _ttl) {
      _store.remove(key);
      return null;
    }
    return e.data;
  }

  static void put(String key, _ClientDetailData data) {
    _store[key] = _CacheEntry(data, DateTime.now());
  }

  static void invalidate(String key) => _store.remove(key);

  /// Returns the cache key used for a given (salonId, client) pair.
  static String makeKey(String salonId, ClientSummaryModel c) =>
      '$salonId|${c.id}';
}

class _CacheEntry {
  _CacheEntry(this.data, this.cachedAt);
  final _ClientDetailData data;
  final DateTime cachedAt;
}

/// Aggregated payload returned by a single load() call. All fields
/// are nullable / default-safe so a partial fetch failure (e.g. one
/// of the queries timing out) still renders most of the sheet.
class _ClientDetailData {
  _ClientDetailData({
    required this.loyaltyBalance,
    required this.upcoming,
    required this.past,
    required this.isBlocked,
    required this.reputationCancelRate,
    required this.reputationTotal,
    required this.isVip,
    required this.ownerNotes,
  });
  final double loyaltyBalance;
  final List<AppointmentModel> upcoming;
  final List<AppointmentModel> past;
  final bool isBlocked;
  final int? reputationCancelRate; // 0-100, null if no global rep doc
  final int? reputationTotal; // total lifetime bookings cross-salon
  final bool isVip;
  final String? ownerNotes;
}

/// Tier thresholds based on visitCount. Returns the tier name + emoji
/// + color. Picked low thresholds so even modest-traffic salons see
/// tiers move — owners want recognition of recurring clients fast.
class _LoyaltyTier {
  const _LoyaltyTier(this.key, this.emoji, this.bg, this.fg);
  final String key; // 'starter' | 'silver' | 'gold' | 'vip'
  final String emoji;
  final Color bg;
  final Color fg;

  static _LoyaltyTier of(int visitCount) {
    if (visitCount >= 25) return const _LoyaltyTier('vip', '👑', Color(0xFFFEF3C7), Color(0xFF92400E));
    if (visitCount >= 10) return const _LoyaltyTier('gold', '🥇', Color(0xFFFEF3C7), Color(0xFFB45309));
    if (visitCount >= 3) return const _LoyaltyTier('silver', '🥈', Color(0xFFE5E7EB), Color(0xFF4B5563));
    return const _LoyaltyTier('starter', '🌱', Color(0xFFD1FAE5), Color(0xFF065F46));
  }

  String label(AppLocalizations? l) {
    switch (key) {
      case 'vip': return l?.tr('client_tier_vip') ?? 'VIP';
      case 'gold': return l?.tr('client_tier_gold') ?? 'Gold';
      case 'silver': return l?.tr('client_tier_silver') ?? 'Silver';
      default: return l?.tr('client_tier_starter') ?? 'Nouveau';
    }
  }
}

class ClientDetailSheet extends ConsumerStatefulWidget {
  const ClientDetailSheet({super.key, required this.client, required this.salon});
  final ClientSummaryModel client;
  final SalonModel salon;

  @override
  ConsumerState<ClientDetailSheet> createState() => _ClientDetailSheetState();
}

class _ClientDetailSheetState extends ConsumerState<ClientDetailSheet> {
  late final String _cacheKey;
  _ClientDetailData? _data;
  bool _loading = false;
  String? _error;
  bool _showAllUpcoming = false;
  bool _showAllPast = false;
  bool _vipToggling = false;
  bool _notesEditing = false;
  final _notesCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cacheKey = _ClientDetailCache.makeKey(widget.salon.id, widget.client);
    final cached = _ClientDetailCache.get(_cacheKey);
    if (cached != null) {
      _data = cached;
      _notesCtrl.text = cached.ownerNotes ?? '';
    } else {
      _refresh();
    }
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh({bool bypassCache = false}) async {
    if (bypassCache) _ClientDetailCache.invalidate(_cacheKey);
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final db = DatabaseService();
      final fs = FirebaseFirestore.instance;
      final salonId = widget.salon.id;
      final client = widget.client;
      final now = DateTime.now();
      // Reputation key — `clientReputation/{userId}` for registered,
      // `walkin_{digits}` mirror for walk-ins (CF maintains both).
      final repDocId = client.isWalkIn
          ? client.id // already 'walkin_<digits>'
          : client.clientId;

      // Past / upcoming queries are routed differently depending on
      // whether we have a Firebase UID or only a phone number:
      //
      // • Registered client → query by clientId. Uses existing
      //   composite indexes:
      //     #1 appointments(clientId, status, dateTime ASC)
      //     #2 appointments(clientId, status, dateTime DESC)
      //   salonId is filtered client-side (small result set, ≤ 30 docs).
      //
      // • Walk-in client → query by clientPhone since appointment.clientId
      //   for walk-ins is the literal string 'walk-in'. Uses existing:
      //     #6 appointments(salonId, clientPhone, dateTime ASC)
      //
      // The previous version queried salonId+clientId+dateTime which had
      // no matching index — catchError swallowed the error and the
      // history rendered empty even for clients with 80+ visits.
      Future<List<AppointmentModel>> fetchPast;
      Future<List<AppointmentModel>> fetchUpcoming;

      if (client.isWalkIn) {
        final phoneE164 = _normalisePhoneToE164(client.clientPhone);
        if (phoneE164.isEmpty) {
          fetchPast = Future.value([]);
          fetchUpcoming = Future.value([]);
        } else {
          // Past: dateTime ≤ now, dateTime ASC index, reverse in memory.
          fetchPast = fs
              .collection('appointments')
              .where('salonId', isEqualTo: salonId)
              .where('clientPhone', isEqualTo: phoneE164)
              .where('dateTime', isLessThanOrEqualTo: Timestamp.fromDate(now))
              .orderBy('dateTime', descending: false)
              .limit(50)
              .get()
              .then((s) {
            final list = s.docs.map((d) => AppointmentModel.fromFirestore(d)).toList()
              ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
            return list.take(10).toList();
          });
          // Upcoming: dateTime > now, status=upcoming, dateTime ASC.
          fetchUpcoming = fs
              .collection('appointments')
              .where('salonId', isEqualTo: salonId)
              .where('clientPhone', isEqualTo: phoneE164)
              .where('dateTime', isGreaterThan: Timestamp.fromDate(now))
              .orderBy('dateTime')
              .limit(20)
              .get()
              .then((s) => s.docs
                  .map((d) => AppointmentModel.fromFirestore(d))
                  .where((a) => a.status == 'upcoming')
                  .toList());
        }
      } else {
        final uid = client.clientId;
        if (uid.isEmpty) {
          fetchPast = Future.value([]);
          fetchUpcoming = Future.value([]);
        } else {
          // Past: 3 status branches × index #2, filter salonId in-memory.
          // whereIn on status would also work but limits us to a single
          // index hit; explicit 3 queries are clearer when reasoning
          // about which composite is being used.
          fetchPast = Future.wait([
            for (final s in ['completed', 'cancelled', 'no_show'])
              fs
                  .collection('appointments')
                  .where('clientId', isEqualTo: uid)
                  .where('status', isEqualTo: s)
                  .orderBy('dateTime', descending: true)
                  .limit(10)
                  .get()
                  .then((q) => q.docs.map((d) => AppointmentModel.fromFirestore(d)).toList()),
          ]).then((lists) {
            final merged = <AppointmentModel>[
              for (final l in lists) ...l,
            ];
            merged.removeWhere((a) => a.salonId != salonId);
            merged.sort((a, b) => b.dateTime.compareTo(a.dateTime));
            return merged.take(10).toList();
          });
          // Upcoming: clientId + status='upcoming' + dateTime ASC →
          // index #1. Filter salonId + future-only client-side.
          fetchUpcoming = fs
              .collection('appointments')
              .where('clientId', isEqualTo: uid)
              .where('status', isEqualTo: 'upcoming')
              .orderBy('dateTime')
              .limit(30)
              .get()
              .then((s) => s.docs
                  .map((d) => AppointmentModel.fromFirestore(d))
                  .where((a) => a.salonId == salonId && a.dateTime.isAfter(now))
                  .take(20)
                  .toList());
        }
      }

      // Run independent reads in parallel.
      final results = await Future.wait<dynamic>([
        // Loyalty balance — registered users only (walk-ins have no UID
        // in our points system).
        if (!client.isWalkIn && client.clientId.isNotEmpty)
          db.getUserPointsForSalon(client.clientId, salonId)
        else
          Future.value(0.0),
        fetchUpcoming.catchError((e) {
          debugPrint('[ClientDetail] upcoming query failed: $e');
          return <AppointmentModel>[];
        }),
        fetchPast.catchError((e) {
          debugPrint('[ClientDetail] past query failed: $e');
          return <AppointmentModel>[];
        }),
        // Blacklist check — single doc read on the salon.
        db.isBlacklisted(
          salonId,
          phone: client.clientPhone.isNotEmpty ? client.clientPhone : null,
          userId: client.isWalkIn ? null : client.clientId,
        ),
        // Cross-salon no-show reputation. May not exist for fresh
        // clients — null-safe handle.
        if (repDocId.isNotEmpty)
          fs.collection('clientReputation').doc(repDocId).get().then(
                (d) => d.exists ? d.data() : null,
              ).catchError((_) => null)
        else
          Future.value(null),
        // Re-read the client summary to pick up isVip + ownerNotes —
        // these are written by Zayna or our new CFs and may have
        // changed since the parent screen loaded the list.
        fs
            .collection('salons')
            .doc(salonId)
            .collection('clientSummaries')
            .doc(client.id)
            .get()
            .then((d) => d.data())
            .catchError((_) => null),
      ]);

      final loyaltyBalance = (results[0] as num).toDouble();
      final upcoming = results[1] as List<AppointmentModel>;
      final past = results[2] as List<AppointmentModel>;
      final isBlocked = results[3] as bool;
      final rep = results[4] as Map<String, dynamic>?;
      final summary = results[5] as Map<String, dynamic>?;

      final data = _ClientDetailData(
        loyaltyBalance: loyaltyBalance,
        upcoming: upcoming,
        past: past,
        isBlocked: isBlocked,
        reputationCancelRate: (rep?['cancellationRate'] as num?)?.toInt(),
        reputationTotal: (rep?['totalPast'] as num?)?.toInt(),
        isVip: summary?['isVip'] == true,
        ownerNotes: summary?['ownerNotes'] as String?,
      );
      _ClientDetailCache.put(_cacheKey, data);
      if (mounted) {
        setState(() {
          _data = data;
          _notesCtrl.text = data.ownerNotes ?? '';
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  // ── Actions ───────────────────────────────────────────────────

  Future<void> _toggleVip() async {
    final d = _data;
    if (d == null) return;
    if (widget.client.clientPhone.isEmpty) {
      _toast(AppLocalizations.of(context)?.tr('client_detail_no_phone') ??
          'Numéro WhatsApp manquant pour ce client.');
      return;
    }
    setState(() => _vipToggling = true);
    try {
      await FirebaseFunctions.instance.httpsCallable('ownerSetClientVip').call({
        'salonId': widget.salon.id,
        'clientPhone': widget.client.clientPhone,
        'isVip': !d.isVip,
      });
      // Optimistic local update + cache invalidation so next open
      // re-fetches truth.
      _ClientDetailCache.invalidate(_cacheKey);
      if (mounted) {
        setState(() {
          _data = _ClientDetailData(
            loyaltyBalance: d.loyaltyBalance,
            upcoming: d.upcoming,
            past: d.past,
            isBlocked: d.isBlocked,
            reputationCancelRate: d.reputationCancelRate,
            reputationTotal: d.reputationTotal,
            isVip: !d.isVip,
            ownerNotes: d.ownerNotes,
          );
          _vipToggling = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _vipToggling = false);
        _toast((AppLocalizations.of(context)?.tr('client_detail_action_failed') ??
                'Action échouée : {error}')
            .replaceAll('{error}', e.toString()));
      }
    }
  }

  Future<void> _saveNotes() async {
    final d = _data;
    if (d == null) return;
    if (widget.client.clientPhone.isEmpty) {
      _toast(AppLocalizations.of(context)?.tr('client_detail_no_phone') ??
          'Numéro WhatsApp manquant pour ce client.');
      return;
    }
    final newNotes = _notesCtrl.text.trim();
    try {
      await FirebaseFunctions.instance.httpsCallable('ownerUpdateClientNotes').call({
        'salonId': widget.salon.id,
        'clientPhone': widget.client.clientPhone,
        'notes': newNotes,
      });
      _ClientDetailCache.invalidate(_cacheKey);
      if (mounted) {
        setState(() {
          _data = _ClientDetailData(
            loyaltyBalance: d.loyaltyBalance,
            upcoming: d.upcoming,
            past: d.past,
            isBlocked: d.isBlocked,
            reputationCancelRate: d.reputationCancelRate,
            reputationTotal: d.reputationTotal,
            isVip: d.isVip,
            ownerNotes: newNotes,
          );
          _notesEditing = false;
        });
        _toast(AppLocalizations.of(context)?.tr('client_detail_notes_saved') ??
            'Notes enregistrées.');
      }
    } catch (e) {
      if (mounted) {
        _toast((AppLocalizations.of(context)?.tr('client_detail_action_failed') ??
                'Action échouée : {error}')
            .replaceAll('{error}', e.toString()));
      }
    }
  }

  Future<void> _blockClient() async {
    final l = AppLocalizations.of(context);
    final c = widget.client;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l?.tr('clients_block_title') ?? 'Bloquer ce client ?'),
        content: Text((l?.tr('clients_block_msg') ?? '{name} ne pourra plus réserver dans votre salon.')
            .replaceAll('{name}', c.clientName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l?.tr('common_cancel') ?? 'Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l?.tr('clients_block') ?? 'Bloquer',
                style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final entry = <String, dynamic>{
      'name': c.clientName,
      'blockedAt': Timestamp.now(),
    };
    if (c.clientPhone.isNotEmpty) entry['phone'] = c.clientPhone;
    if (!c.isWalkIn && c.clientId.isNotEmpty) entry['userId'] = c.clientId;
    await DatabaseService().addToBlacklist(widget.salon.id, entry);
    _ClientDetailCache.invalidate(_cacheKey);
    if (mounted) {
      _toast((l?.tr('clients_blocked_success') ?? '{name} a été bloqué')
          .replaceAll('{name}', c.clientName));
      Navigator.pop(context);
    }
  }

  void _openWhatsApp() {
    final phone = widget.client.clientPhone;
    if (phone.isEmpty) {
      _toast(AppLocalizations.of(context)?.tr('client_detail_no_phone') ??
          'Numéro WhatsApp manquant pour ce client.');
      return;
    }
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    launchUrl(Uri.parse('https://wa.me/$digits'),
        mode: LaunchMode.externalApplication);
  }

  void _openBookNow() {
    final team = ref.read(ownerTeamProvider).value ?? <TeamMemberModel>[];
    final phone = widget.client.clientPhone;
    final phoneE164 = phone.isNotEmpty
        ? (phone.startsWith('+') ? phone : '+${phone.replaceAll(RegExp(r'\D'), '')}')
        : null;
    Navigator.pop(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: OwnerAddAppointmentSheet(
          salon: widget.salon,
          teamMembers: team,
          initialClientName: widget.client.clientName,
          initialClientPhoneE164: phoneE164,
          onCreated: () => ref.invalidate(ownerAppointmentsRangeProvider),
        ),
      ),
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Normalise an arbitrary phone string to E.164 (`+212...`) so we can
  /// match Firestore `clientPhone` fields, which are always stored in
  /// that form. Returns empty when there isn't enough material.
  String _normalisePhoneToE164(String raw) {
    if (raw.isEmpty) return '';
    if (raw.startsWith('+')) return raw;
    var digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    // Single leading 0 → Moroccan local format (legacy) → +212.
    if (digits.startsWith('0') && digits.length == 10) {
      digits = '212' + digits.substring(1);
    }
    return '+$digits';
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = widget.client;
    final currency = widget.salon.currency;
    final tier = _LoyaltyTier.of(c.visitCount);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 44, height: 4,
            decoration: BoxDecoration(
              color: AppColors.secondary200,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(l, c, tier),
                  const SizedBox(height: 20),
                  _buildActionButtons(l),
                  const SizedBox(height: 24),
                  if (_data == null && _loading) ...[
                    const Center(child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: CircularProgressIndicator(color: AppColors.brand600),
                    )),
                  ] else if (_error != null) ...[
                    _buildErrorBlock(l),
                  ] else if (_data != null) ...[
                    _buildKeyStats(l, c, currency, tier),
                    const SizedBox(height: 14),
                    _buildHistoryStats(l, c, currency),
                    const SizedBox(height: 14),
                    _buildDetailsRows(l, c),
                    const SizedBox(height: 18),
                    if (_data!.reputationCancelRate != null)
                      _buildReputationBadge(l, _data!),
                    _buildAppointmentSection(
                      l,
                      title: l?.tr('client_detail_upcoming_rdv') ?? 'Prochains RDV',
                      items: _data!.upcoming,
                      showAll: _showAllUpcoming,
                      onToggleShowAll: () => setState(() => _showAllUpcoming = !_showAllUpcoming),
                      currency: currency,
                      emptyLabel: l?.tr('client_detail_no_upcoming') ?? 'Aucun RDV à venir.',
                    ),
                    const SizedBox(height: 14),
                    _buildAppointmentSection(
                      l,
                      title: l?.tr('client_detail_past_rdv') ?? 'Historique',
                      items: _data!.past,
                      showAll: _showAllPast,
                      onToggleShowAll: () => setState(() => _showAllPast = !_showAllPast),
                      currency: currency,
                      emptyLabel: l?.tr('client_detail_no_past') ?? 'Pas encore de visite.',
                    ),
                    const SizedBox(height: 18),
                    _buildNotesSection(l),
                    const SizedBox(height: 14),
                    _buildOwnerActions(l),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(AppLocalizations? l, ClientSummaryModel c, _LoyaltyTier tier) {
    final initial = c.clientName.isNotEmpty ? c.clientName[0].toUpperCase() : '?';
    return Column(
      children: [
        Container(
          width: 96, height: 96,
          decoration: BoxDecoration(
            color: AppColors.brand50,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.brand200, width: 2),
          ),
          child: Center(
            child: Text(
              initial,
              style: GoogleFonts.dmSans(
                fontSize: 38,
                fontWeight: FontWeight.w800,
                color: AppColors.brand600,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                c.clientName,
                style: GoogleFonts.dmSans(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brand950,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_data?.isVip == true) ...[
              const SizedBox(width: 6),
              const Icon(Icons.workspace_premium_rounded,
                  color: Color(0xFFB45309), size: 22),
            ],
          ],
        ),
        if (c.clientEmail != null && c.clientEmail!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              c.clientEmail!,
              style: const TextStyle(color: AppColors.secondary500, fontSize: 13),
            ),
          ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: tier.bg,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: tier.fg.withValues(alpha: 0.15)),
          ),
          child: Text(
            '${tier.emoji} ${tier.label(l)}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: tier.fg,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(AppLocalizations? l) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _openWhatsApp,
            icon: const Icon(FontAwesomeIcons.whatsapp, size: 16, color: Color(0xFF25D366)),
            label: Text(
              l?.tr('client_detail_message') ?? 'Message',
              style: const TextStyle(color: AppColors.brand950, fontWeight: FontWeight.w600),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: const BorderSide(color: AppColors.secondary200),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _openBookNow,
            icon: const Icon(Icons.event_available_rounded, size: 18),
            label: Text(l?.tr('client_detail_book_now') ?? 'Réserver'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brand950,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
              elevation: 0,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildKeyStats(AppLocalizations? l, ClientSummaryModel c, String currency, _LoyaltyTier tier) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.event_rounded,
            label: l?.tr('client_detail_upcoming') ?? 'Prochains',
            value: '${_data!.upcoming.length}',
            iconColor: const Color(0xFF0EA5E9),
            iconBg: const Color(0xFFE0F2FE),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            icon: Icons.diamond_outlined,
            label: l?.tr('client_detail_loyalty_balance') ?? 'Fidélité',
            value: CurrencyHelper.format(_data!.loyaltyBalance, currency),
            iconColor: const Color(0xFF7C3AED),
            iconBg: const Color(0xFFEDE9FE),
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryStats(AppLocalizations? l, ClientSummaryModel c, String currency) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.payments_outlined,
            label: l?.tr('client_detail_total_spent') ?? 'Total dépensé',
            value: CurrencyHelper.format(c.totalSpent, currency),
            iconColor: const Color(0xFF059669),
            iconBg: const Color(0xFFD1FAE5),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            icon: Icons.bar_chart_rounded,
            label: l?.tr('client_detail_avg_basket') ?? 'Panier moyen',
            value: CurrencyHelper.format(c.averageBasket, currency),
            iconColor: const Color(0xFFDB2777),
            iconBg: const Color(0xFFFCE7F3),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailsRows(AppLocalizations? l, ClientSummaryModel c) {
    final memberSince = DateFormat('MMM yyyy').format(c.firstVisit);
    final lastVisitDays = DateTime.now().difference(c.lastVisit).inDays;
    final lastVisit = lastVisitDays == 0
        ? l?.tr('clients_today') ?? "Aujourd'hui"
        : lastVisitDays == 1
            ? l?.tr('clients_yesterday') ?? 'Hier'
            : (l?.tr('clients_days_ago') ?? 'Il y a {days} jours').replaceAll('{days}', '$lastVisitDays');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.secondary50,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          _detailRow(Icons.cake_outlined, l?.tr('client_detail_member_since') ?? 'Membre depuis', memberSince),
          const Divider(height: 1, color: AppColors.secondary200),
          _detailRow(Icons.history_rounded, l?.tr('client_detail_last_visit') ?? 'Dernière visite', lastVisit),
          const Divider(height: 1, color: AppColors.secondary200),
          _detailRow(Icons.receipt_long_outlined, l?.tr('clients_visits_count_short') ?? 'Visites', '${c.visitCount}'),
          const Divider(height: 1, color: AppColors.secondary200),
          _detailRow(Icons.content_cut, l?.tr('client_detail_fav_service') ?? 'Service favori', c.favoriteService),
          if (c.clientPhone.isNotEmpty) ...[
            const Divider(height: 1, color: AppColors.secondary200),
            InkWell(
              onTap: _openWhatsApp,
              child: _detailRow(
                FontAwesomeIcons.whatsapp,
                l?.tr('client_detail_whatsapp') ?? 'WhatsApp',
                c.clientPhone,
                trailingColor: const Color(0xFF25D366),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value, {Color? trailingColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.secondary500),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: const TextStyle(fontSize: 13, color: AppColors.secondary600)),
          ),
          Text(value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: trailingColor ?? AppColors.brand950,
              )),
        ],
      ),
    );
  }

  Widget _buildReputationBadge(AppLocalizations? l, _ClientDetailData d) {
    final rate = d.reputationCancelRate ?? 0;
    final total = d.reputationTotal ?? 0;
    if (total < 3) return const SizedBox.shrink();
    final isRisky = rate >= 30;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isRisky ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isRisky ? const Color(0xFFFCA5A5) : const Color(0xFFBBF7D0),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isRisky ? Icons.warning_amber_rounded : Icons.verified_user_rounded,
            color: isRisky ? const Color(0xFFB91C1C) : const Color(0xFF15803D),
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isRisky
                  ? (l?.tr('client_detail_reputation_risky') ??
                          '{rate}% d\'annulation sur {total} RDV cross-salon')
                      .replaceAll('{rate}', '$rate')
                      .replaceAll('{total}', '$total')
                  : (l?.tr('client_detail_reputation_good') ??
                          'Client fiable · {rate}% annulation ({total} RDV cumul)')
                      .replaceAll('{rate}', '$rate')
                      .replaceAll('{total}', '$total'),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: isRisky ? const Color(0xFFB91C1C) : const Color(0xFF15803D),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppointmentSection(
    AppLocalizations? l, {
    required String title,
    required List<AppointmentModel> items,
    required bool showAll,
    required VoidCallback onToggleShowAll,
    required String currency,
    required String emptyLabel,
  }) {
    final visible = showAll ? items : items.take(3).toList();
    return Container(
      padding: const EdgeInsets.all(14),
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
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brand950,
                  ),
                ),
              ),
              if (items.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.brand50,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '${items.length}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brand700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                emptyLabel,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.secondary500,
                ),
              ),
            ),
          ...visible.map((a) => _appointmentRow(a, currency)),
          if (items.length > 3)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onToggleShowAll,
                child: Text(showAll
                    ? (l?.tr('common_show_less') ?? 'Voir moins')
                    : (l?.tr('common_show_more') ?? 'Voir tout (${items.length})')
                        .replaceAll('${items.length}', '${items.length}')),
              ),
            ),
        ],
      ),
    );
  }

  Widget _appointmentRow(AppointmentModel a, String currency) {
    final date = DateFormat('dd MMM yyyy · HH:mm').format(a.dateTime);
    final statusColor = switch (a.status) {
      'completed' => const Color(0xFF15803D),
      'cancelled' => const Color(0xFFB91C1C),
      'no_show' => const Color(0xFFB91C1C),
      _ => AppColors.brand700,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 6, height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: statusColor,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.serviceName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.brand950,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(date,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.secondary500,
                    )),
              ],
            ),
          ),
          Text(
            CurrencyHelper.format(a.price, currency),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.brand950,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotesSection(AppLocalizations? l) {
    final has = (_data?.ownerNotes ?? '').isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.sticky_note_2_outlined,
                  size: 16, color: Color(0xFFB45309)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l?.tr('client_detail_owner_notes') ?? 'Notes privées',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF78350F),
                  ),
                ),
              ),
              if (!_notesEditing)
                TextButton(
                  onPressed: () => setState(() => _notesEditing = true),
                  child: Text(has
                      ? (l?.tr('common_edit') ?? 'Modifier')
                      : (l?.tr('common_add') ?? 'Ajouter')),
                ),
            ],
          ),
          if (_notesEditing) ...[
            const SizedBox(height: 6),
            TextField(
              controller: _notesCtrl,
              maxLines: 4,
              maxLength: 1000,
              decoration: InputDecoration(
                hintText: l?.tr('client_detail_notes_hint') ??
                    'Préférences, infos utiles…',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFFDE68A)),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      _notesEditing = false;
                      _notesCtrl.text = _data?.ownerNotes ?? '';
                    });
                  },
                  child: Text(l?.tr('common_cancel') ?? 'Annuler'),
                ),
                ElevatedButton(
                  onPressed: _saveNotes,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFB45309),
                    foregroundColor: Colors.white,
                  ),
                  child: Text(l?.tr('common_save') ?? 'Enregistrer'),
                ),
              ],
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                has
                    ? _data!.ownerNotes!
                    : (l?.tr('client_detail_notes_empty') ??
                        'Aucune note pour ce client.'),
                style: TextStyle(
                  fontSize: 13,
                  color: has ? const Color(0xFF78350F) : AppColors.secondary500,
                  fontStyle: has ? FontStyle.normal : FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOwnerActions(AppLocalizations? l) {
    final d = _data!;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _vipToggling ? null : _toggleVip,
            icon: _vipToggling
                ? const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(
                    d.isVip
                        ? Icons.workspace_premium_rounded
                        : Icons.workspace_premium_outlined,
                    size: 16,
                    color: const Color(0xFFB45309),
                  ),
            label: Text(
              d.isVip
                  ? (l?.tr('client_detail_unmark_vip') ?? 'Retirer VIP')
                  : (l?.tr('client_detail_mark_vip') ?? 'Marquer VIP'),
              style: const TextStyle(color: AppColors.brand950, fontWeight: FontWeight.w600),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              side: BorderSide(color: d.isVip ? const Color(0xFFB45309) : AppColors.secondary200),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        if (!d.isBlocked) ...[
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _blockClient,
              icon: const Icon(Icons.block_rounded, size: 16, color: Color(0xFFB91C1C)),
              label: Text(
                l?.tr('clients_block') ?? 'Bloquer',
                style: const TextStyle(color: Color(0xFFB91C1C), fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                side: const BorderSide(color: Color(0xFFFCA5A5)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildErrorBlock(AppLocalizations? l) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFB91C1C)),
          const SizedBox(height: 8),
          Text(
            (l?.tr('client_detail_load_error') ?? 'Erreur de chargement : {error}')
                .replaceAll('{error}', _error ?? ''),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Color(0xFFB91C1C)),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => _refresh(bypassCache: true),
            child: Text(l?.tr('common_retry') ?? 'Réessayer'),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.iconColor,
    required this.iconBg,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color iconColor;
  final Color iconBg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.secondary100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: GoogleFonts.dmSans(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.brand950,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.secondary500,
            ),
          ),
        ],
      ),
    );
  }
}
