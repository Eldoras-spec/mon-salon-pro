import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import '../theme/app_constants.dart';
import '../models/team_member_model.dart';
import '../services/app_localizations.dart';

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
  });

  final Map<String, dynamic>? existing;
  final Set<String> assignedMembers;
  final List<TeamMemberModel> teamMembers;
  final void Function(Map<String, dynamic> entry) onSave;

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

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?['name'] as String? ?? '');
    _priceCtrl = TextEditingController(
      text: e != null && (e['price'] as num?) != null && (e['price'] as num) > 0
          ? (e['price'] as num).toStringAsFixed(0)
          : '',
    );
    _descCtrl = TextEditingController(text: e?['description'] as String? ?? '');
    _category = e?['category'] as String? ?? AppConstants.categoryNames.first;
    if (!AppConstants.categoryNames.contains(_category)) {
      _category = AppConstants.categoryNames.first;
    }
    _duration = e?['duration'] as int? ?? 30;
    _selectedMembers = Set<String>.from(widget.assignedMembers);
    _isComplex = e?['isComplex'] == true;
    if (e?['options'] != null) {
      _optionSteps = List<Map<String, dynamic>>.from(
        (e!['options'] as List).map((o) => Map<String, dynamic>.from(o as Map)),
      );
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _descCtrl.dispose();
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

    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
          maxWidth: 500,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      isEdit
                          ? (l?.tr('salon_service_form_edit') ?? 'Modifier le service')
                          : (l?.tr('salon_service_form_new') ?? 'Nouveau service'),
                      style: GoogleFonts.dmSans(
                        fontWeight: FontWeight.bold,
                        color: AppColors.brand950,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.close, color: AppColors.secondary400, size: 22),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Name
                    _label(l?.tr('salon_service_form_name') ?? 'Nom du service *'),
                    const SizedBox(height: 6),
                    _field(_nameCtrl, l?.tr('salon_service_form_name_hint') ?? 'ex. Coupe femme & Brushing'),
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
                          items: AppConstants.categoryNames
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
                                    items: const [15, 30, 45, 60, 90, 120]
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
                              _label(l?.tr('salon_service_form_price') ?? 'Prix (MAD)'),
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
                      ..._buildOptionSteps(l),
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
                                  CircleAvatar(
                                    radius: 10,
                                    backgroundColor: isSelected ? AppColors.brand500 : AppColors.secondary200,
                                    child: isSelected
                                        ? const Icon(Icons.check, size: 10, color: Colors.white)
                                        : Text(
                                            m.name.isNotEmpty ? m.name[0].toUpperCase() : '?',
                                            style: const TextStyle(fontSize: 8, color: AppColors.secondary500),
                                          ),
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

            // Actions
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(l?.tr('common_cancel') ?? 'Annuler',
                        style: const TextStyle(color: AppColors.secondary400)),
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

  // ── Complex service option builder ─────────────────────────────

  void _addOptionStep() {
    setState(() {
      _optionSteps.add({
        'id': 'step${DateTime.now().millisecondsSinceEpoch}',
        'label': '',
        'choices': <Map<String, dynamic>>[],
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

  int _getStepDepth(String stepId, [Set<String>? visited]) {
    visited ??= {};
    if (visited.contains(stepId)) return 0;
    visited.add(stepId);
    final step = _findStep(stepId);
    if (step == null) return 0;
    int maxChild = 0;
    for (final c in (step['choices'] as List? ?? [])) {
      final next = c['nextOptionId'];
      if (next != null) {
        final d = _getStepDepth(next as String, visited);
        if (d > maxChild) maxChild = d;
      }
    }
    return 1 + maxChild;
  }

  int get _totalDepth {
    final root = _rootStepId;
    if (root == null) return 0;
    return _getStepDepth(root);
  }

  List<Widget> _buildOptionSteps(AppLocalizations? l) {
    // Only render root steps (not sub-steps referenced by choices)
    final root = _rootStepId;
    if (root == null) return [];
    return [_buildStepWidget(l, root, 0)];
  }

  Widget _buildStepWidget(AppLocalizations? l, String stepId, int depth) {
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
                      ? Text('${depth + 1}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))
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
            final hasSubOptions = choice['nextOptionId'] != null;
            final canAddSub = _totalDepth < 3;

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
                      // Label + delete
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
                              style: const TextStyle(fontSize: 13),
                              decoration: InputDecoration(
                                hintText: l?.tr('salon_service_choice_label') ?? 'Nom du choix',
                                hintStyle: const TextStyle(fontSize: 12, color: AppColors.secondary400),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.secondary200)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.secondary200)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () => setState(() {
                              // Remove linked sub-step if exists
                              if (choice['nextOptionId'] != null) {
                                _removeStepAndChildren(choice['nextOptionId'] as String);
                              }
                              final ch = List<Map<String, dynamic>>.from(_optionSteps[stepIdx]['choices']);
                              ch.removeAt(cIdx);
                              _optionSteps[stepIdx]['choices'] = ch;
                            }),
                            child: const Icon(Icons.close, size: 16, color: AppColors.secondary400),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Price + Duration
                      Row(
                        children: [
                          Expanded(child: _modifierField(stepIdx, cIdx, 'priceModifier', '+/- MAD', Icons.payments_outlined)),
                          const SizedBox(width: 6),
                          Expanded(child: _modifierField(stepIdx, cIdx, 'durationModifier', '+/- min', Icons.schedule)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Sub-options button
                      if (!hasSubOptions && canAddSub)
                        GestureDetector(
                          onTap: () => _addSubOptions(stepIdx, cIdx),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                const Icon(Icons.add, size: 14, color: AppColors.brand600),
                                const SizedBox(width: 4),
                                Text(
                                  l?.tr('salon_service_add_suboptions') ?? 'Sous-options',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.brand600),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (hasSubOptions)
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.subdirectory_arrow_right, size: 14, color: AppColors.brand500),
                              const SizedBox(width: 4),
                              Text(
                                '${l?.tr('salon_service_has_suboptions') ?? 'A des sous-options'} ↓',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.brand500),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                // Render linked sub-step inline
                if (hasSubOptions)
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

  void _addSubOptions(int stepIdx, int choiceIdx) {
    setState(() {
      final newStepId = 'step${DateTime.now().millisecondsSinceEpoch}';
      _optionSteps.add({
        'id': newStepId,
        'label': '',
        'choices': <Map<String, dynamic>>[],
      });
      final ch = List<Map<String, dynamic>>.from(_optionSteps[stepIdx]['choices']);
      ch[choiceIdx]['nextOptionId'] = newStepId;
      _optionSteps[stepIdx]['choices'] = ch;
    });
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
