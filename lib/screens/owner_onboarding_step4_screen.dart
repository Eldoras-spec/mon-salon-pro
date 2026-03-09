import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/team_member_model.dart';
import '../theme/app_colors.dart';
import '../services/database_service.dart';
import '../models/salon_model.dart';
import '../widgets/custom_button.dart';
import 'registration_success_screen.dart';
import '../theme/app_constants.dart';

class ServiceEntry {
  String name;
  String category;
  String description;
  double price;
  int durationMins;
  Set<String> assignedMemberNames;

  ServiceEntry({
    required this.name,
    required this.category,
    this.description = '',
    required this.price,
    required this.durationMins,
    Set<String>? assignedMemberNames,
  }) : assignedMemberNames = assignedMemberNames ?? {};
}

class OwnerOnboardingStep4Screen extends StatefulWidget {
  final Map<String, dynamic> salonData;
  final List<TeamMemberModel> teamMembers;
  const OwnerOnboardingStep4Screen({
    super.key,
    required this.salonData,
    this.teamMembers = const [],
  });

  @override
  State<OwnerOnboardingStep4Screen> createState() =>
      _OwnerOnboardingStep4ScreenState();
}

class _OwnerOnboardingStep4ScreenState
    extends State<OwnerOnboardingStep4Screen> {
  bool _isLoading = false;
  final _databaseService = DatabaseService();
  final List<ServiceEntry> _services = [];

  // ── Finish setup ─────────────────────────────────────────────────────────────

  Future<void> _finishSetup() async {
    if (_services.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez ajouter au moins un service'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    for (final s in _services) {
      if (s.assignedMemberNames.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Le service "${s.name}" doit être assigné à au moins un employé'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      final selectedServices = _services
          .map(
            (s) => {
              'name': s.name,
              'category': s.category,
              'description': s.description,
              'price': s.price,
              'duration': s.durationMins,
            },
          )
          .toList();

      final Map<String, dynamic> finalSalonData =
          Map<String, dynamic>.from(widget.salonData);
      finalSalonData['services'] = selectedServices;
      finalSalonData['createdAt'] = DateTime.now();

      final salonId = finalSalonData['ownerId'] as String;

      final salon = SalonModel(
        id: salonId,
        ownerId: salonId,
        name: finalSalonData['name'],
        address: finalSalonData['address'],
        city: finalSalonData['city'],
        description: finalSalonData['description'],
        category: finalSalonData['category'],
        rating: 0.0,
        reviewCount: 0,
        images: List<String>.from(finalSalonData['images'] ?? []),
        logoUrl: finalSalonData['logoUrl'],
        workingHours: Map<String, dynamic>.from(
          finalSalonData['workingHours'] ?? {},
        ),
        services: List<Map<String, dynamic>>.from(
          finalSalonData['services'] ?? [],
        ),
        serviceCategories: List<String>.from(
          _services.map((s) => s.category).toSet().toList(),
        ),
        latitude: finalSalonData['latitude'] as double?,
        longitude: finalSalonData['longitude'] as double?,
        createdAt: DateTime.now(),
        socialLinks: finalSalonData['socialLinks'] != null
            ? Map<String, String>.from(finalSalonData['socialLinks'])
            : {},
      );

      await _databaseService.saveSalon(salon);

      // Update each team member's assignedServiceNames
      for (final member in widget.teamMembers) {
        if (member.id.isEmpty) continue;
        final assignedServices = _services
            .where((s) => s.assignedMemberNames.contains(member.name))
            .map((s) => s.name)
            .toList();
        await _databaseService.updateTeamMember(
          salonId,
          member.id,
          {'assignedServiceNames': assignedServices},
        );
      }

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) =>
                const RegistrationSuccessScreen(isOwner: true),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de la sauvegarde : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Show service dialog ───────────────────────────────────────────────────

  void _showServiceModal({ServiceEntry? existing, int? index}) {
    showDialog(
      context: context,
      builder: (_) => _ServiceFormDialog(
        existing: existing,
        teamMembers: widget.teamMembers,
        onSave: (entry) {
          setState(() {
            if (index != null) {
              _services[index] = entry;
            } else {
              _services.add(entry);
            }
          });
        },
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        // Nav + progress
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        size: 18, color: AppColors.brand950),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.brand50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'Étape 6 sur 6',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.brand600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: 1.0,
                  minHeight: 5,
                  backgroundColor: AppColors.secondary100,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.brand600),
                ),
              ),
            ],
          ),
        ),

        // Content
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Text(
                  'Vos Services',
                  style: GoogleFonts.dmSans(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.brand950,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Créez vos services et assignez-les aux membres de votre équipe.',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.secondary500,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 28),

                // Services list
                if (_services.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        vertical: 32, horizontal: 24),
                    decoration: BoxDecoration(
                      color: AppColors.secondary50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.secondary200),
                    ),
                    child: const Column(
                      children: [
                        Icon(Icons.design_services_outlined,
                            size: 40, color: AppColors.secondary300),
                        SizedBox(height: 12),
                        Text(
                          'Aucun service ajouté',
                          style: TextStyle(
                            color: AppColors.secondary400,
                            fontSize: 14,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Ajoutez au moins un service pour votre salon',
                          style: TextStyle(
                            color: AppColors.secondary400,
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                else
                  ..._services.asMap().entries.map(
                        (entry) =>
                            _buildServiceCard(entry.key, entry.value),
                      ),

                const SizedBox(height: 20),

                // Add service button
                OutlinedButton.icon(
                  onPressed: () => _showServiceModal(),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Ajouter un service'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.brand600,
                    side: const BorderSide(color: AppColors.brand300),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    textStyle: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Bottom button
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: CustomButton(
            text: 'Terminer la configuration',
            onPressed: _finishSetup,
            isLoading: _isLoading,
            icon: Icons.check,
          ),
        ),
      ],
    );
  }

  Widget _buildServiceCard(int index, ServiceEntry service) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.brand50,
        border: Border.all(color: AppColors.brand200),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.brand700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.brand100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            service.category,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.brand600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${service.durationMins} min',
                          style: const TextStyle(
                            color: AppColors.secondary500,
                            fontSize: 12,
                          ),
                        ),
                        if (service.price > 0) ...[
                          const SizedBox(width: 8),
                          Text(
                            '${service.price.toStringAsFixed(2)} \$',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: () => _showServiceModal(
                        existing: service, index: index),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    color: AppColors.secondary400,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () =>
                        setState(() => _services.removeAt(index)),
                    icon: const Icon(Icons.close, size: 18),
                    color: AppColors.secondary400,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ],
          ),
          if (service.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              service.description,
              style: const TextStyle(
                color: AppColors.secondary500,
                fontSize: 13,
                height: 1.4,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: service.assignedMemberNames.map((name) {
              return Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: AppColors.brand300),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.person_outline,
                        size: 12, color: AppColors.brand600),
                    const SizedBox(width: 4),
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.brand700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ─── Separate StatefulWidget for the service form dialog ─────────────────────

class _ServiceFormDialog extends StatefulWidget {
  const _ServiceFormDialog({
    this.existing,
    required this.teamMembers,
    required this.onSave,
  });

  final ServiceEntry? existing;
  final List<TeamMemberModel> teamMembers;
  final void Function(ServiceEntry entry) onSave;

  @override
  State<_ServiceFormDialog> createState() => _ServiceFormDialogState();
}

class _ServiceFormDialogState extends State<_ServiceFormDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _descCtrl;
  late String _category;
  late int _duration;
  late Set<String> _selectedMembers;
  String? _memberError;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _priceCtrl = TextEditingController(
      text: widget.existing != null && widget.existing!.price > 0
          ? widget.existing!.price.toStringAsFixed(2)
          : '',
    );
    _descCtrl =
        TextEditingController(text: widget.existing?.description ?? '');
    _category =
        widget.existing?.category ?? AppConstants.categoryNames.first;
    _duration = widget.existing?.durationMins ?? 30;
    _selectedMembers =
        Set<String>.from(widget.existing?.assignedMemberNames ?? {});
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Le nom du service est requis')),
      );
      return;
    }
    if (_selectedMembers.isEmpty) {
      setState(() => _memberError = 'Assignez au moins un employé');
      return;
    }
    final entry = ServiceEntry(
      name: _nameCtrl.text.trim(),
      category: _category,
      description: _descCtrl.text.trim(),
      price: double.tryParse(_priceCtrl.text) ?? 0.0,
      durationMins: _duration,
      assignedMemberNames: _selectedMembers,
    );
    Navigator.pop(context);
    widget.onSave(entry);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.existing != null
            ? 'Modifier le service'
            : 'Ajouter un service',
        style: GoogleFonts.dmSans(
          fontWeight: FontWeight.bold,
          color: AppColors.brand950,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Name
            _fieldLabel('Nom du service *'),
            const SizedBox(height: 6),
            TextField(
              controller: _nameCtrl,
              decoration: _fieldDeco('ex. Coupe femme & Brushing'),
            ),
            const SizedBox(height: 16),

            // Category
            _fieldLabel('Catégorie *'),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.secondary300),
                borderRadius: BorderRadius.circular(12),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: _category,
                  items: AppConstants.categoryNames
                      .map((e) =>
                          DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _category = val);
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Duration + Price
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _fieldLabel('Durée *'),
                      const SizedBox(height: 6),
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border:
                              Border.all(color: AppColors.secondary300),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: '$_duration mins',
                            items: const [
                              '15 mins',
                              '30 mins',
                              '45 mins',
                              '60 mins',
                              '90 mins',
                              '120 mins',
                            ]
                                .map((e) => DropdownMenuItem(
                                    value: e, child: Text(e)))
                                .toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _duration =
                                    int.parse(val.split(' ')[0]));
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _fieldLabel('Prix'),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _priceCtrl,
                        keyboardType: TextInputType.number,
                        decoration: _fieldDeco('0.00'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Description
            _fieldLabel('Description (optionnel)'),
            const SizedBox(height: 6),
            TextField(
              controller: _descCtrl,
              maxLines: 2,
              decoration:
                  _fieldDeco('Décrivez brièvement ce qui est inclus…'),
            ),
            const SizedBox(height: 16),

            // Member assignment
            _fieldLabel('Réalisé par *'),
            const SizedBox(height: 2),
            const Text(
              'Sélectionnez tous les employés capables de réaliser ce service',
              style: TextStyle(fontSize: 11, color: AppColors.secondary400),
            ),
            const SizedBox(height: 8),
            if (widget.teamMembers.isEmpty)
              const Text(
                'Aucun membre disponible',
                style: TextStyle(
                    fontSize: 12, color: AppColors.secondary400),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: widget.teamMembers.map((m) {
                  final isSelected =
                      _selectedMembers.contains(m.name);
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.brand100
                            : Colors.white,
                        border: Border.all(
                          color: isSelected
                              ? AppColors.brand400
                              : AppColors.secondary200,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(
                            radius: 10,
                            backgroundColor: isSelected
                                ? AppColors.brand500
                                : AppColors.secondary200,
                            child: isSelected
                                ? const Icon(Icons.check,
                                    size: 10, color: Colors.white)
                                : Text(
                                    m.name.isNotEmpty
                                        ? m.name[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                        fontSize: 8,
                                        color:
                                            AppColors.secondary500),
                                  ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            m.name,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              color: isSelected
                                  ? AppColors.brand700
                                  : AppColors.secondary600,
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
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFFDC2626)),
              ),
            ],
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.all(16),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'Annuler',
            style: TextStyle(color: AppColors.secondary600),
          ),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.brand600,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 12,
            ),
          ),
          child: Text(
              widget.existing != null ? 'Enregistrer' : 'Ajouter'),
        ),
      ],
    );
  }

  Widget _fieldLabel(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.secondary700,
        ),
      );

  InputDecoration _fieldDeco(String hint) => InputDecoration(
        hintText: hint,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.secondary300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.secondary300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.brand500),
        ),
      );
}
