import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;

import '../services/database_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_constants.dart';
import '../models/team_member_model.dart';
import '../services/app_localizations.dart';
import '../services/auth_service.dart';
import 'member_avatar.dart';
import '../utils/currency_helper.dart';
import '../utils/media_compressor.dart';

/// Shared service creation/editing dialog.
///
/// Takes and returns a `Map<String, dynamic>` with keys:
///   name, category, description, price, duration, assignedMembers,
///   isComplex, options
///
/// Used by both owner_salon_screen and owner_onboarding_step4_screen.
class ServiceFormDialog extends StatefulWidget {
  const ServiceFormDialog({
    super.key,
    this.existing,
    this.assignedMembers = const {},
    required this.teamMembers,
    required this.onSave,
    required this.salonId,
    this.salonType = 'femme',
    this.isPremium = false,
    this.galleryStorageUsed = 0,
    this.currency = 'MAD',
  });

  final Map<String, dynamic>? existing;
  final Set<String> assignedMembers;
  final List<TeamMemberModel> teamMembers;
  final void Function(Map<String, dynamic> entry) onSave;
  final String salonId;
  final String salonType; // 'femme' | 'homme' | 'mixte' — filters category list
  final bool isPremium;
  final int galleryStorageUsed;
  final String currency;

  @override
  State<ServiceFormDialog> createState() => _ServiceFormDialogState();
}

class _ServiceFormDialogState extends State<ServiceFormDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _descCtrl;
  late String _category;
  late int _duration;
  late Set<String> _selectedMembers;
  String? _memberError;
  bool _isComplex = false;
  List<Map<String, dynamic>> _optionSteps = [];
  bool _showLongPressHint = false;
  static const _hintKey = 'hasSeenLongPressHint';

  // ── Online card payment (Stripe Connect) ──
  /// 'none' | 'full' | 'percentage' | 'fixed_above'
  String _paymentMode = 'none';
  late final TextEditingController _paymentValueCtrl;
  late final TextEditingController _paymentThresholdCtrl;

  @override
  void initState() {
    super.initState();
    _checkLongPressHint();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?['name'] as String? ?? '');
    _priceCtrl = TextEditingController(
      text: e != null && (e['price'] as num?) != null && (e['price'] as num) > 0
          ? (e['price'] as num).toStringAsFixed(0)
          : '',
    );
    _descCtrl = TextEditingController(text: e?['description'] as String? ?? '');
    final cats = AppConstants.categoryNamesFor(widget.salonType);
    _category = e?['category'] as String? ?? cats.first;
    if (!cats.contains(_category)) {
      _category = cats.first;
    }
    _duration = e?['duration'] as int? ?? 30;
    _selectedMembers = Set<String>.from(widget.assignedMembers);
    _isComplex = e?['isComplex'] == true;
    if (e?['options'] != null) {
      _optionSteps = List<Map<String, dynamic>>.from(
        (e!['options'] as List).map((o) => Map<String, dynamic>.from(o as Map)),
      );
    }
    _paymentMode = (e?['paymentMode'] as String?) ?? 'none';
    final pv = e?['paymentValue'];
    _paymentValueCtrl = TextEditingController(
      text: pv is num && pv > 0 ? pv.toStringAsFixed(0) : '',
    );
    final pt = e?['paymentThreshold'];
    _paymentThresholdCtrl = TextEditingController(
      text: pt is num && pt > 0 ? pt.toStringAsFixed(0) : '',
    );
  }

  @override
  Future<void> _checkLongPressHint() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_hintKey) != true) {
      setState(() => _showLongPressHint = true);
    }
  }

  Future<void> _dismissLongPressHint() async {
    setState(() => _showLongPressHint = false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hintKey, true);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _descCtrl.dispose();
    _paymentValueCtrl.dispose();
    _paymentThresholdCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final l = AppLocalizations.of(context);
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l?.tr('salon_service_form_name_required') ?? 'Le nom du service est requis')),
      );
      return;
    }
    if (_selectedMembers.isEmpty && widget.teamMembers.isNotEmpty) {
      setState(() => _memberError = l?.tr('salon_service_form_assigned_error') ?? 'Assignez au moins un employé');
      return;
    }
    final entry = <String, dynamic>{
      'name': _nameCtrl.text.trim(),
      'category': _category,
      'description': _descCtrl.text.trim(),
      'price': double.tryParse(_priceCtrl.text.trim()) ?? 0.0,
      'duration': _duration,
      'assignedMembers': _selectedMembers.toList(),
      'isComplex': _isComplex,
      'paymentMode': _paymentMode,
      if (_paymentMode == 'percentage' || _paymentMode == 'fixed_above')
        'paymentValue':
            double.tryParse(_paymentValueCtrl.text.trim()) ?? 0.0,
      if (_paymentMode == 'fixed_above')
        'paymentThreshold':
            double.tryParse(_paymentThresholdCtrl.text.trim()) ?? 0.0,
    };
    if (_isComplex && _optionSteps.isNotEmpty) {
      entry['options'] = _optionSteps.map((step) {
        final choices = (step['choices'] as List? ?? []).map((c) {
          return Map<String, dynamic>.from(c as Map);
        }).toList();
        return {
          'id': step['id'],
          'label': step['label'],
          'choices': choices,
        };
      }).toList();
    }
    Navigator.pop(context);
    widget.onSave(entry);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final isEdit = widget.existing != null;

    return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 1,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.brand950),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            isEdit
                ? (l?.tr('salon_service_form_edit') ?? 'Modifier le service')
                : (l?.tr('salon_service_form_new') ?? 'Nouveau service'),
            style: GoogleFonts.dmSans(
              fontWeight: FontWeight.bold,
              color: AppColors.brand950,
              fontSize: 18,
            ),
          ),
          centerTitle: false,
        ),
        body: Column(
          children: [
            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Name
                    _label(l?.tr('salon_service_form_name') ?? 'Nom du service *'),
                    const SizedBox(height: 6),
                    _field(_nameCtrl, l?.tr('salon_service_form_name_hint') ?? 'ex. Coupe & Brushing'),
                    const SizedBox(height: 14),

                    // Category
                    _label(l?.tr('salon_service_form_category') ?? 'Catégorie *'),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.secondary300),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: _category,
                          items: AppConstants.categoryNamesFor(widget.salonType)
                              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                              .toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _category = val);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Duration + Price row
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label(l?.tr('salon_service_form_duration') ?? 'Durée *'),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                  border: Border.all(color: AppColors.secondary300),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<int>(
                                    isExpanded: true,
                                    value: _duration,
                                    items: const [15, 30, 45, 60, 90, 120, 150, 180, 240]
                                        .map((d) => DropdownMenuItem(value: d, child: Text('$d min')))
                                        .toList(),
                                    onChanged: (val) {
                                      if (val != null) setState(() => _duration = val);
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label(l?.tr('salon_service_form_price') ?? 'Prix (${CurrencyHelper.symbol(widget.currency)})'),
                              const SizedBox(height: 6),
                              _field(_priceCtrl, '0', keyboardType: TextInputType.number),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Description
                    _label(l?.tr('salon_service_form_description') ?? 'Description'),
                    const SizedBox(height: 6),
                    _field(_descCtrl, l?.tr('salon_service_form_description_hint') ?? 'Description optionnelle…', maxLines: 2),
                    const SizedBox(height: 14),

                    // Online card payment (Stripe Connect) — visible only
                    // when the salon has an active connected account.
                    _buildPaymentSection(l),

                    // Complex service toggle
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        border: Border.all(color: _isComplex ? AppColors.brand400 : AppColors.secondary200),
                        borderRadius: BorderRadius.circular(10),
                        color: _isComplex ? AppColors.brand50 : Colors.white,
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.account_tree_outlined, size: 18, color: AppColors.brand600),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l?.tr('salon_service_complex') ?? 'Service avec options',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.brand950),
                            ),
                          ),
                          Switch(
                            value: _isComplex,
                            onChanged: (v) => setState(() {
                              _isComplex = v;
                              if (v && _optionSteps.isEmpty) _addOptionStep();
                            }),
                            activeColor: AppColors.brand600,
                          ),
                        ],
                      ),
                    ),

                    // Option builder
                    if (_isComplex) ...[
                      const SizedBox(height: 12),
                      Text(
                        l?.tr('salon_service_complex_hint') ?? 'Le client choisira parmi les options. Chaque option peut modifier le prix et la durée.',
                        style: const TextStyle(fontSize: 11, color: AppColors.secondary400),
                      ),
                      const SizedBox(height: 8),
                      // Long press hint tooltip
                      if (_showLongPressHint && _optionSteps.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.brand950,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.touch_app, size: 18, color: Colors.white),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  l?.tr('salon_service_longpress_hint') ?? 'Appuyez sur ⋮ à côté d\'un choix pour plus d\'options (WhatsApp, galerie, sous-options)',
                                  style: const TextStyle(fontSize: 11, color: Colors.white, height: 1.4),
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: _dismissLongPressHint,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text('OK', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ..._buildOptionSteps(l),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () => setState(() {
                          final newId = 'step_${DateTime.now().millisecondsSinceEpoch}';
                          _optionSteps.add({'id': newId, 'label': '', 'choices': []});
                        }),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.add, size: 16, color: AppColors.brand600),
                            const SizedBox(width: 6),
                            Text(
                              l?.tr('salon_service_add_step') ?? 'Ajouter une étape',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.brand600),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),

                    // Member assignment
                    if (widget.teamMembers.isNotEmpty) ...[
                      _label(l?.tr('salon_service_form_assigned') ?? 'Réalisé par *'),
                      const SizedBox(height: 2),
                      Text(
                        l?.tr('salon_service_form_assigned_hint') ?? 'Sélectionnez tous les employés capables de réaliser ce service',
                        style: const TextStyle(fontSize: 11, color: AppColors.secondary400),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: widget.teamMembers.map((m) {
                          final isSelected = _selectedMembers.contains(m.name);
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                if (isSelected) {
                                  _selectedMembers.remove(m.name);
                                } else {
                                  _selectedMembers.add(m.name);
                                }
                                _memberError = null;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected ? AppColors.brand100 : Colors.white,
                                border: Border.all(
                                  color: isSelected ? AppColors.brand400 : AppColors.secondary200,
                                ),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  isSelected
                                      ? const CircleAvatar(
                                          radius: 10,
                                          backgroundColor: AppColors.brand500,
                                          child: Icon(Icons.check, size: 10, color: Colors.white),
                                        )
                                      : MemberAvatar(
                                          name: m.name,
                                          photoUrl: m.photoUrl,
                                          radius: 10,
                                        ),
                                  const SizedBox(width: 6),
                                  Text(
                                    m.name,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                      color: isSelected ? AppColors.brand700 : AppColors.secondary600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      if (_memberError != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          _memberError!,
                          style: const TextStyle(fontSize: 12, color: Color(0xFFDC2626)),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),

            // Bottom action bar
            Container(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + MediaQuery.of(context).padding.bottom),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: AppColors.secondary200)),
              ),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brand600,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(isEdit ? (l?.tr('common_save') ?? 'Enregistrer') : (l?.tr('common_add') ?? 'Ajouter'),
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                ),
              ),
            ),
          ],
        ),
    );
  }

  // ── Online card payment section (Stripe Connect) ───────────────

  Widget _buildPaymentSection(AppLocalizations? l) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('salons')
          .doc(widget.salonId)
          .snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? {};
        final raw = data['stripeConnect'];
        final connect = raw is Map
            ? Map<String, dynamic>.from(raw)
            : <String, dynamic>{};
        final chargesEnabled = connect['chargesEnabled'] == true;
        if (!chargesEnabled) {
          // No connect account → don't expose the payment options at all.
          return const SizedBox.shrink();
        }
        final symbol = CurrencyHelper.symbol(widget.currency);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label(l?.tr('payment.section_label') ?? 'Paiement en ligne'),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.secondary200),
                borderRadius: BorderRadius.circular(10),
                color: Colors.white,
              ),
              child: Column(
                children: [
                  _paymentRadio(
                    value: 'none',
                    title: l?.tr('payment.mode_none') ?? 'Aucun',
                    subtitle: l?.tr('payment.mode_none_desc') ??
                        'Le client paie en salon',
                  ),
                  _paymentRadio(
                    value: 'full',
                    title: l?.tr('payment.mode_full') ?? 'Paiement intégral',
                    subtitle: l?.tr('payment.mode_full_desc') ??
                        'Le client paie 100% à la réservation',
                  ),
                  _paymentRadio(
                    value: 'percentage',
                    title: l?.tr('payment.mode_percentage') ??
                        'Acompte en pourcentage',
                    subtitle: l?.tr('payment.mode_percentage_desc') ??
                        'Le client paie un % du prix à la réservation',
                  ),
                  _paymentRadio(
                    value: 'fixed_above',
                    title: l?.tr('payment.mode_fixed_above') ??
                        'Acompte fixe au-delà d\'un montant',
                    subtitle: l?.tr('payment.mode_fixed_above_desc') ??
                        'Acompte fixe demandé si le prix dépasse un seuil',
                  ),
                ],
              ),
            ),
            if (_paymentMode == 'percentage') ...[
              const SizedBox(height: 10),
              _label(l?.tr('payment.percentage_label') ?? 'Pourcentage (%)'),
              const SizedBox(height: 6),
              _field(_paymentValueCtrl, '20',
                  keyboardType: TextInputType.number),
            ],
            if (_paymentMode == 'fixed_above') ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label((l?.tr('payment.fixed_amount_label') ??
                                'Acompte ({symbol})')
                            .replaceAll('{symbol}', symbol)),
                        const SizedBox(height: 6),
                        _field(_paymentValueCtrl, '100',
                            keyboardType: TextInputType.number),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label((l?.tr('payment.threshold_label') ??
                                'Seuil ({symbol})')
                            .replaceAll('{symbol}', symbol)),
                        const SizedBox(height: 6),
                        _field(_paymentThresholdCtrl, '500',
                            keyboardType: TextInputType.number),
                      ],
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
          ],
        );
      },
    );
  }

  Widget _paymentRadio({
    required String value,
    required String title,
    required String subtitle,
  }) {
    final selected = _paymentMode == value;
    return InkWell(
      onTap: () => setState(() => _paymentMode = value),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          children: [
            Radio<String>(
              value: value,
              groupValue: _paymentMode,
              onChanged: (v) =>
                  setState(() => _paymentMode = v ?? 'none'),
              activeColor: AppColors.brand600,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                      color: AppColors.brand950,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.secondary500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Complex service option builder ─────────────────────────────

  void _addOptionStep() {
    setState(() {
      final stepTs = DateTime.now().millisecondsSinceEpoch;
      _optionSteps.add({
        'id': 'step$stepTs',
        'label': '',
        'choices': <Map<String, dynamic>>[
          {
            'id': 'c${stepTs}_1',
            'label': '',
            'priceModifier': 0,
            'durationModifier': 0,
            'nextOptionId': null,
          },
          {
            'id': 'c${stepTs}_2',
            'label': '',
            'priceModifier': 0,
            'durationModifier': 0,
            'nextOptionId': null,
          },
        ],
      });
    });
  }

  /// Find the root step (first step, or the one not referenced as nextOptionId by any choice)
  String? get _rootStepId {
    if (_optionSteps.isEmpty) return null;
    final referenced = <String>{};
    for (final s in _optionSteps) {
      for (final c in (s['choices'] as List? ?? [])) {
        final next = c['nextOptionId'];
        if (next != null) referenced.add(next as String);
      }
    }
    // First step not referenced by anyone
    for (final s in _optionSteps) {
      if (!referenced.contains(s['id'])) return s['id'] as String;
    }
    return _optionSteps.first['id'] as String;
  }

  Map<String, dynamic>? _findStep(String id) {
    for (final s in _optionSteps) {
      if (s['id'] == id) return s;
    }
    return null;
  }

  List<Widget> _buildOptionSteps(AppLocalizations? l) {
    // Only render root steps (not sub-steps referenced by choices)
    final linkedIds = <String>{};
    for (final step in _optionSteps) {
      for (final c in (step['choices'] as List? ?? [])) {
        if (c is Map && c['nextOptionId'] != null) linkedIds.add(c['nextOptionId'] as String);
      }
    }
    final rootSteps = _optionSteps.where((s) => !linkedIds.contains(s['id'])).toList();
    return rootSteps.asMap().entries.map((e) => _buildStepWidget(l, e.value['id'] as String, 0, rootIndex: e.key)).toList();
  }

  Widget _buildStepWidget(AppLocalizations? l, String stepId, int depth, {int rootIndex = 0}) {
    final stepIdx = _optionSteps.indexWhere((s) => s['id'] == stepId);
    if (stepIdx < 0) return const SizedBox.shrink();
    final step = _optionSteps[stepIdx];
    final choices = List<Map<String, dynamic>>.from(step['choices'] ?? []);

    return Container(
      margin: EdgeInsets.only(bottom: 10, left: depth > 0 ? 16.0 : 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: depth == 0 ? AppColors.brand200 : AppColors.secondary200),
        borderRadius: BorderRadius.circular(10),
        color: depth == 0 ? Colors.white : AppColors.secondary50,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Step header
          Row(
            children: [
              Container(
                width: 24, height: 24,
                decoration: BoxDecoration(
                  color: depth == 0 ? AppColors.brand600 : AppColors.brand400,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(
                  child: depth == 0
                      ? Text('${rootIndex + 1}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))
                      : const Icon(Icons.subdirectory_arrow_right, size: 14, color: Colors.white),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: TextEditingController(text: step['label'] ?? ''),
                  onChanged: (v) => _optionSteps[stepIdx]['label'] = v,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    hintText: l?.tr('salon_service_step_label') ?? 'Nom de l\'étape (ex. Type)',
                    hintStyle: const TextStyle(fontSize: 12, color: AppColors.secondary400),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: InputBorder.none,
                  ),
                ),
              ),
              if (depth > 0)
                GestureDetector(
                  onTap: () => setState(() {
                    _removeStepAndChildren(stepId);
                  }),
                  child: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFDC2626)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 8),

          // Choices
          ...choices.asMap().entries.map((cEntry) {
            final cIdx = cEntry.key;
            final choice = cEntry.value;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Choice row
                Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: depth == 0 ? AppColors.secondary50 : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      // Custom badge
                      if (choice['isCustom'] == true)
                        Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF25D366).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF25D366).withValues(alpha: 0.3)),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.whatshot, size: 12, color: Color(0xFF25D366)),
                            const SizedBox(width: 4),
                            Text(l?.tr('salon_service_custom_choice') ?? 'Choix personnalisé → WhatsApp',
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF25D366))),
                          ]),
                        ),
                      // Gallery badge
                      if (choice['isGallery'] == true)
                        Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.purple.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.photo_library_outlined, size: 12, color: Colors.purple),
                            const SizedBox(width: 4),
                            Text('${l?.tr('salon_service_gallery_badge') ?? 'Galerie de designs'} (${(choice['galleryItems'] as List?)?.length ?? 0})',
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.purple)),
                          ]),
                        ),
                      // Label + options + delete
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: TextEditingController(text: choice['label'] ?? ''),
                              onChanged: (v) {
                                final ch = List<Map<String, dynamic>>.from(_optionSteps[stepIdx]['choices']);
                                ch[cIdx]['label'] = v;
                                _optionSteps[stepIdx]['choices'] = ch;
                              },
                              style: TextStyle(fontSize: 13, color: choice['isCustom'] == true ? const Color(0xFF25D366) : choice['isGallery'] == true ? Colors.purple : null),
                              decoration: InputDecoration(
                                hintText: choice['isCustom'] == true
                                    ? (l?.tr('salon_service_custom_hint') ?? 'Ex: Design personnalisé')
                                    : (l?.tr('salon_service_choice_label') ?? 'Nom du choix'),
                                hintStyle: const TextStyle(fontSize: 12, color: AppColors.secondary400),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: choice['isCustom'] == true ? const Color(0xFF25D366) : choice['isGallery'] == true ? Colors.purple : AppColors.secondary200)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: choice['isCustom'] == true ? const Color(0xFF25D366) : choice['isGallery'] == true ? Colors.purple : AppColors.secondary200)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          // Options menu button
                          GestureDetector(
                            onTap: () => _showChoiceOptions(stepIdx, cIdx, l),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              child: const Icon(Icons.more_vert, size: 18, color: AppColors.secondary400),
                            ),
                          ),
                          const SizedBox(width: 2),
                          GestureDetector(
                            onTap: () => setState(() {
                              if (choice['nextOptionId'] != null) {
                                _removeStepAndChildren(choice['nextOptionId'] as String);
                              }
                              if (choice['isGallery'] == true) {
                                _deleteAllGalleryFilesFromChoice(choice);
                              }
                              final ch = List<Map<String, dynamic>>.from(_optionSteps[stepIdx]['choices']);
                              ch.removeAt(cIdx);
                              _optionSteps[stepIdx]['choices'] = ch;
                            }),
                            child: const Icon(Icons.close, size: 16, color: AppColors.secondary400),
                          ),
                        ],
                      ),
                      // Price + Duration (hidden for custom/gallery choices)
                      if (choice['isCustom'] != true && choice['isGallery'] != true) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(child: _modifierField(stepIdx, cIdx, 'priceModifier', '+/- ${CurrencyHelper.symbol(widget.currency)}', Icons.payments_outlined)),
                            const SizedBox(width: 6),
                            Expanded(child: _modifierField(stepIdx, cIdx, 'durationModifier', '+/- min', Icons.schedule)),
                          ],
                        ),
                      ],
                      // Gallery manage button
                      if (choice['isGallery'] == true)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: GestureDetector(
                            onTap: () => _showGalleryManager(stepIdx, cIdx, l),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.purple.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.purple.withValues(alpha: 0.2)),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.photo_library, size: 16, color: Colors.purple),
                                  const SizedBox(width: 6),
                                  Text(l?.tr('salon_service_manage_gallery') ?? 'Gérer la galerie',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.purple)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      // Sub-options indicator
                      if (choice['nextOptionId'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(children: [
                            const Icon(Icons.subdirectory_arrow_right, size: 14, color: AppColors.brand500),
                            const SizedBox(width: 4),
                            Text(l?.tr('salon_service_has_suboptions') ?? 'A des sous-options ↓',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.brand500)),
                          ]),
                        ),
                    ],
                  ),
                ),
                // Render linked sub-step inline
                if (choice['nextOptionId'] != null)
                  _buildStepWidget(l, choice['nextOptionId'] as String, depth + 1),
              ],
            );
          }),

          // Add choice button
          GestureDetector(
            onTap: () => setState(() {
              final ch = List<Map<String, dynamic>>.from(_optionSteps[stepIdx]['choices'] ?? []);
              ch.add({
                'id': 'c${DateTime.now().millisecondsSinceEpoch}',
                'label': '',
                'priceModifier': 0,
                'durationModifier': 0,
                'nextOptionId': null,
              });
              _optionSteps[stepIdx]['choices'] = ch;
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add_circle_outline, size: 16, color: AppColors.brand600),
                  const SizedBox(width: 6),
                  Text(
                    l?.tr('salon_service_add_choice') ?? 'Ajouter un choix',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.brand600),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modifierField(int stepIdx, int choiceIdx, String field, String hint, IconData icon) {
    final choices = List<Map<String, dynamic>>.from(_optionSteps[stepIdx]['choices']);
    final value = choices[choiceIdx][field] ?? 0;

    return TextField(
      controller: TextEditingController(text: value == 0 ? '' : '$value'),
      onChanged: (v) {
        final ch = List<Map<String, dynamic>>.from(_optionSteps[stepIdx]['choices']);
        ch[choiceIdx][field] = int.tryParse(v) ?? 0;
        _optionSteps[stepIdx]['choices'] = ch;
      },
      keyboardType: TextInputType.number,
      style: const TextStyle(fontSize: 12),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 11, color: AppColors.secondary400),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Icon(icon, size: 14, color: AppColors.secondary400),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 28),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.secondary200)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.secondary200)),
      ),
    );
  }

  void _showChoiceOptions(int stepIdx, int choiceIdx, AppLocalizations? l) {
    final ch = List<Map<String, dynamic>>.from(_optionSteps[stepIdx]['choices']);
    final choice = ch[choiceIdx];
    final isCustom = choice['isCustom'] == true;
    final isGallery = choice['isGallery'] == true;
    final hasSubOptions = choice['nextOptionId'] != null;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: AppColors.secondary200, borderRadius: BorderRadius.circular(2))),
              Text(l?.tr('salon_service_choice_options') ?? 'Options du choix',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              // Option 1: Custom WhatsApp
              ListTile(
                leading: Icon(
                  isCustom ? Icons.check_circle : Icons.circle_outlined,
                  color: isCustom ? const Color(0xFF25D366) : AppColors.secondary300,
                ),
                title: Text(l?.tr('salon_service_make_custom') ?? 'Choix personnalisé (→ WhatsApp)',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                subtitle: Text(l?.tr('salon_service_make_custom_desc') ?? 'Le client sera redirigé vers WhatsApp avec un récapitulatif',
                  style: const TextStyle(fontSize: 12, color: AppColors.secondary400)),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    ch[choiceIdx]['isCustom'] = !isCustom;
                    if (!isCustom) {
                      ch[choiceIdx]['priceModifier'] = 0;
                      ch[choiceIdx]['durationModifier'] = 0;
                      // Remove sub-options if making custom
                      if (ch[choiceIdx]['nextOptionId'] != null) {
                        _removeStepAndChildren(ch[choiceIdx]['nextOptionId'] as String);
                        ch[choiceIdx]['nextOptionId'] = null;
                      }
                    }
                    _optionSteps[stepIdx]['choices'] = ch;
                  });
                },
              ),
              // Option 2: Sub-options
              if (!isCustom)
                ListTile(
                  leading: Icon(
                    hasSubOptions ? Icons.check_circle : Icons.circle_outlined,
                    color: hasSubOptions ? AppColors.brand600 : AppColors.secondary300,
                  ),
                  title: Text(l?.tr('salon_service_add_suboptions') ?? 'Sous-options',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Text(
                    hasSubOptions
                        ? (l?.tr('salon_service_remove_suboptions') ?? 'Appuyez pour retirer les sous-options')
                        : (l?.tr('salon_service_suboptions_desc') ?? 'Ajouter des choix supplémentaires liés à cette option'),
                    style: const TextStyle(fontSize: 12, color: AppColors.secondary400)),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      if (hasSubOptions) {
                        // Remove sub-options
                        _removeStepAndChildren(choice['nextOptionId'] as String);
                        ch[choiceIdx]['nextOptionId'] = null;
                      } else {
                        // Add sub-options
                        final newId = 'step_${DateTime.now().millisecondsSinceEpoch}';
                        _optionSteps.add({'id': newId, 'label': '', 'choices': []});
                        ch[choiceIdx]['nextOptionId'] = newId;
                      }
                      _optionSteps[stepIdx]['choices'] = ch;
                    });
                  },
                ),
              // Option 3: Gallery of designs
              if (!isCustom)
                ListTile(
                  leading: Icon(
                    isGallery ? Icons.check_circle : Icons.circle_outlined,
                    color: isGallery ? Colors.purple : AppColors.secondary300,
                  ),
                  title: Text(l?.tr('salon_service_make_gallery') ?? 'Galerie de designs',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Text(l?.tr('salon_service_gallery_desc') ?? 'Le client choisira un design depuis vos images/vidéos',
                    style: const TextStyle(fontSize: 12, color: AppColors.secondary400)),
                  onTap: () {
                    Navigator.pop(ctx);
                    if (isGallery) {
                      _deleteAllGalleryFilesFromChoice(ch[choiceIdx]);
                      setState(() {
                        ch[choiceIdx]['isGallery'] = false;
                        ch[choiceIdx].remove('galleryItems');
                        _optionSteps[stepIdx]['choices'] = ch;
                      });
                    } else {
                      setState(() {
                        ch[choiceIdx]['isGallery'] = true;
                        ch[choiceIdx]['galleryItems'] = ch[choiceIdx]['galleryItems'] ?? [];
                        ch[choiceIdx]['priceModifier'] = 0;
                        ch[choiceIdx]['durationModifier'] = 0;
                        _optionSteps[stepIdx]['choices'] = ch;
                      });
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showGalleryManager(int stepIdx, int choiceIdx, AppLocalizations? l) {
    final ch = List<Map<String, dynamic>>.from(_optionSteps[stepIdx]['choices']);
    final items = List<Map<String, dynamic>>.from(ch[choiceIdx]['galleryItems'] ?? []);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModalState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(color: AppColors.secondary200, borderRadius: BorderRadius.circular(2)))),
                Row(children: [
                  const Icon(Icons.photo_library, size: 20, color: Colors.purple),
                  const SizedBox(width: 8),
                  Expanded(child: Text(l?.tr('salon_service_gallery_title') ?? 'Galerie de designs',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                  Text('${items.length}', style: const TextStyle(fontSize: 14, color: AppColors.secondary400)),
                ]),
                const SizedBox(height: 12),
                // Gallery grid
                if (items.isNotEmpty)
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.45),
                    child: GridView.builder(
                      shrinkWrap: true,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 0.75,
                      ),
                      itemCount: items.length,
                      itemBuilder: (_, i) {
                        final item = items[i];
                        return Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.secondary200),
                          ),
                          clipBehavior: Clip.hardEdge,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Image.network(item['thumbnailUrl'] ?? item['url'] ?? '', fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(color: AppColors.secondary100,
                                        child: const Icon(Icons.broken_image, color: AppColors.secondary300))),
                                    if (item['isVideo'] == true)
                                      const Center(child: Icon(Icons.play_circle_filled, size: 28, color: Colors.white70)),
                                    Positioned(top: 4, right: 4,
                                      child: GestureDetector(
                                        onTap: () => setModalState(() {
                                          _deleteGalleryFileFromStorage(Map<String, dynamic>.from(items[i]));
                                          items.removeAt(i);
                                          ch[choiceIdx]['galleryItems'] = items;
                                          _optionSteps[stepIdx]['choices'] = ch;
                                        }),
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                                          child: const Icon(Icons.close, size: 14, color: Colors.white),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(6),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item['label'] ?? '', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                      maxLines: 1, overflow: TextOverflow.ellipsis),
                                    Text('+${item['priceModifier'] ?? 0} ${CurrencyHelper.symbol(widget.currency)} · +${item['durationModifier'] ?? 0} min',
                                      style: const TextStyle(fontSize: 10, color: AppColors.secondary400)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                if (items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Column(children: [
                      const Icon(Icons.photo_library_outlined, size: 40, color: AppColors.secondary300),
                      const SizedBox(height: 8),
                      Text(l?.tr('salon_service_gallery_empty') ?? 'Aucun design ajouté',
                        style: const TextStyle(color: AppColors.secondary400, fontSize: 13)),
                    ]),
                  ),
                const SizedBox(height: 12),
                // Add buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _pickGalleryItem(ctx, setModalState, stepIdx, choiceIdx, ch, items, l, false),
                        icon: const Icon(Icons.add_photo_alternate, size: 16),
                        label: const Text('Photo', style: TextStyle(fontSize: 13)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple, foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: widget.isPremium
                            ? () => _pickGalleryItem(ctx, setModalState, stepIdx, choiceIdx, ch, items, l, true)
                            : () => _showVideoPremiumDialog(ctx, l),
                        icon: Icon(
                          widget.isPremium ? Icons.videocam : Icons.lock_outline,
                          size: 16,
                        ),
                        label: const Text('Vidéo', style: TextStyle(fontSize: 13)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: widget.isPremium ? Colors.purple : Colors.grey,
                          side: BorderSide(color: widget.isPremium ? Colors.purple : Colors.grey),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showVideoPremiumDialog(BuildContext ctx, AppLocalizations? l) {
    showDialog(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            color: Colors.purple.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.workspace_premium_rounded, color: Colors.purple, size: 28),
        ),
        title: Text(
          l?.tr('video_premium_dialog_title') ?? 'Fonctionnalité Business',
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        ),
        content: Text(
          l?.tr('gallery_premium_required') ?? 'Les vidéos sont disponibles avec le plan Business',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: AppColors.secondary600),
        ),
        actions: [
          Center(
            child: TextButton(
              onPressed: () => Navigator.pop(dCtx),
              child: Text(l?.tr('ok') ?? 'OK'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickGalleryItem(
    BuildContext ctx,
    void Function(VoidCallback) setModalState,
    int stepIdx, int choiceIdx,
    List<Map<String, dynamic>> ch,
    List<Map<String, dynamic>> items,
    AppLocalizations? l,
    bool isVideo,
  ) async {
    final picker = ImagePicker();
    XFile? picked;

    if (isVideo) {
      picked = await picker.pickVideo(source: ImageSource.gallery);
    } else {
      picked = await picker.pickImage(source: ImageSource.gallery);
    }
    if (picked == null) return;

    // Compress media before upload
    File fileToUpload = File(picked.path);
    OverlayEntry? compressOverlay;
    if (ctx.mounted) {
      compressOverlay = MediaCompressor.showCompressionOverlay(ctx, isVideo: isVideo);
    }
    try {
      final result = isVideo
          ? await MediaCompressor.compressVideo(fileToUpload)
          : await MediaCompressor.compressImage(fileToUpload);
      compressOverlay?.remove();
      compressOverlay = null;

      if (result == null) {
        if (ctx.mounted) {
          await MediaCompressor.showSizeErrorDialog(ctx, isVideo: isVideo, afterCompression: false);
        }
        return;
      }

      final finalSize = result.compressedSize;
      final maxSize = isVideo ? MediaCompressor.maxVideoSizeBytes : MediaCompressor.maxImageSizeBytes;
      if (finalSize > maxSize) {
        if (ctx.mounted) {
          await MediaCompressor.showSizeErrorDialog(ctx, isVideo: isVideo, afterCompression: true);
        }
        return;
      }

      fileToUpload = result.file;
      debugPrint('📦 Compressed ${isVideo ? "video" : "image"}: ${(result.originalSize / 1024 / 1024).toStringAsFixed(1)} MB → ${(finalSize / 1024 / 1024).toStringAsFixed(1)} MB (${result.savedPercent.toStringAsFixed(0)}% saved)');
    } catch (e) {
      compressOverlay?.remove();
      debugPrint('Compression error: $e');
      if (ctx.mounted) {
        await MediaCompressor.showSizeErrorDialog(ctx, isVideo: isVideo, afterCompression: false);
      }
      return;
    }

    // Check storage limit
    final fileSize = await fileToUpload.length();
    final maxStorage = widget.isPremium ? 5 * 1024 * 1024 * 1024 : 3 * 1024 * 1024 * 1024;
    if (widget.galleryStorageUsed + fileSize > maxStorage) {
      if (ctx.mounted) {
        showDialog(
          context: ctx,
          builder: (dialogCtx) => AlertDialog(
            icon: const Icon(Icons.cloud_off_rounded, color: Colors.orange, size: 48),
            title: const Text('Stockage plein'),
            content: Text('Vous avez atteint la limite de ${widget.isPremium ? "5" : "3"} GB. Supprimez des fichiers pour en ajouter.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('OK')),
            ],
          ),
        );
      }
      return;
    }

    // Show progress overlay
    final progressNotifier = ValueNotifier<double>(0);
    OverlayEntry? progressOverlay;
    if (ctx.mounted) {
      progressOverlay = OverlayEntry(
        builder: (_) => ValueListenableBuilder<double>(
          valueListenable: progressNotifier,
          builder: (_, progress, __) => Container(
            color: Colors.black54,
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  CircularProgressIndicator(value: progress > 0 ? progress : null, color: AppColors.brand600),
                  const SizedBox(height: 12),
                  Text('Upload ${(progress * 100).toInt()}%', style: const TextStyle(fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ),
        ),
      );
      Overlay.of(ctx).insert(progressOverlay);
    }

    try {
      final uid = AuthService().currentUserId ?? '';
      final ts = DateTime.now().millisecondsSinceEpoch;
      final ext = fileToUpload.path.split('.').last;

      // Upload main file with progress.
      // Cache-Control: 7 days — clients re-viewing the same gallery media
      // cache it locally instead of re-downloading from Storage (saves egress).
      final storageRef = FirebaseStorage.instance.ref()
          .child('salons/$uid/designs/$ts.$ext');
      final uploadTask = storageRef.putFile(
        fileToUpload,
        SettableMetadata(cacheControl: 'public, max-age=604800'),
      );
      uploadTask.snapshotEvents.listen((snap) {
        if (snap.totalBytes > 0) {
          progressNotifier.value = snap.bytesTransferred / snap.totalBytes;
        }
      });
      await uploadTask;
      final url = await storageRef.getDownloadURL();

      // Update storage counter
      await DatabaseService().updateSalonField(
        widget.salonId, 'galleryStorageUsed', widget.galleryStorageUsed + fileSize,
      );

      // Generate and upload thumbnail for videos
      String? thumbnailUrl;
      if (isVideo) {
        try {
          final Uint8List? thumbData = await vt.VideoThumbnail.thumbnailData(
            video: fileToUpload.path,
            imageFormat: vt.ImageFormat.JPEG,
            maxWidth: 400,
            quality: 75,
          );
          if (thumbData != null) {
            final thumbRef = FirebaseStorage.instance.ref()
                .child('salons/$uid/designs/${ts}_thumb.jpg');
            await thumbRef.putData(thumbData, SettableMetadata(
              contentType: 'image/jpeg',
              cacheControl: 'public, max-age=604800',
            ));
            thumbnailUrl = await thumbRef.getDownloadURL();
          }
        } catch (e) {
          debugPrint('Thumbnail generation error: $e');
        }
      }

      progressOverlay?.remove();
      if (!ctx.mounted) return;

      // Show label/price dialog
      final labelCtrl = TextEditingController();
      final priceCtrl = TextEditingController(text: '0');
      final durationCtrl = TextEditingController(text: '0');
      final previewUrl = thumbnailUrl ?? url;
      final confirmed = await showDialog<bool>(
        context: ctx,
        builder: (dc) => AlertDialog(
          title: Text(l?.tr('salon_service_gallery_item_title') ?? 'Détails du design'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            ClipRRect(borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 120, width: 280,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(previewUrl, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(color: AppColors.secondary100,
                        child: const Icon(Icons.check_circle, color: Colors.green, size: 40))),
                    if (isVideo)
                      const Center(child: Icon(Icons.play_circle_filled, size: 40, color: Colors.white70)),
                  ],
                ))),
            const SizedBox(height: 12),
            TextField(controller: labelCtrl,
              decoration: InputDecoration(labelText: l?.tr('salon_service_gallery_item_label') ?? 'Nom du design',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: priceCtrl, keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: '+${CurrencyHelper.symbol(widget.currency)}', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: durationCtrl, keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: '+min', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dc, false), child: Text(l?.tr('common_cancel') ?? 'Annuler')),
            ElevatedButton(onPressed: () => Navigator.pop(dc, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.brand600),
              child: Text(l?.tr('common_add') ?? 'Ajouter', style: const TextStyle(color: Colors.white))),
          ],
        ),
      );

      if (confirmed == true) {
        setModalState(() {
          items.add({
            'url': url,
            if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
            'isVideo': isVideo,
            'label': labelCtrl.text.trim().isEmpty ? 'Design ${items.length + 1}' : labelCtrl.text.trim(),
            'priceModifier': int.tryParse(priceCtrl.text) ?? 0,
            'durationModifier': int.tryParse(durationCtrl.text) ?? 0,
          });
          ch[choiceIdx]['galleryItems'] = items;
          _optionSteps[stepIdx]['choices'] = ch;
        });
        setState(() {});
      }
    } catch (e) {
      progressOverlay?.remove();
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red));
      }
    }
  }

  void _removeStepAndChildren(String stepId) {
    final step = _findStep(stepId);
    if (step == null) return;
    // Remove children first
    for (final c in (step['choices'] as List? ?? [])) {
      if (c['nextOptionId'] != null) {
        _removeStepAndChildren(c['nextOptionId'] as String);
      }
    }
    // Remove references to this step
    for (final s in _optionSteps) {
      for (final c in (s['choices'] as List? ?? [])) {
        if (c['nextOptionId'] == stepId) c['nextOptionId'] = null;
      }
    }
    _optionSteps.removeWhere((s) => s['id'] == stepId);
  }

  /// Delete a gallery item's files (main + thumbnail) from Firebase Storage.
  void _deleteGalleryFileFromStorage(Map<String, dynamic> item) {
    final url = item['url'] as String?;
    final thumbUrl = item['thumbnailUrl'] as String?;
    if (url != null && url.isNotEmpty) {
      try {
        FirebaseStorage.instance.refFromURL(url).delete();
      } catch (e) {
        debugPrint('Error deleting gallery file: $e');
      }
    }
    if (thumbUrl != null && thumbUrl.isNotEmpty) {
      try {
        FirebaseStorage.instance.refFromURL(thumbUrl).delete();
      } catch (e) {
        debugPrint('Error deleting gallery thumbnail: $e');
      }
    }
  }

  /// Delete all gallery items' files from a choice.
  void _deleteAllGalleryFilesFromChoice(Map<String, dynamic> choice) {
    final items = choice['galleryItems'] as List?;
    if (items == null) return;
    for (final item in items) {
      _deleteGalleryFileFromStorage(Map<String, dynamic>.from(item));
    }
  }

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.secondary700,
        ),
      );

  Widget _field(TextEditingController ctrl, String hint,
      {int maxLines = 1, TextInputType? keyboardType}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 14, color: AppColors.brand950),
      decoration: InputDecoration(
        hintText: hint,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.secondary300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.secondary300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.brand500),
        ),
      ),
    );
  }
}
