import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../theme/app_colors.dart';
import '../theme/app_constants.dart';
import '../models/salon_model.dart';
import '../models/team_member_model.dart';
import '../providers/owner_providers.dart';
import '../services/database_service.dart';
import 'owner_onboarding_step1_screen.dart';

// ── Screen ───────────────────────────────────────────────────────────────────

class OwnerSalonScreen extends ConsumerWidget {
  const OwnerSalonScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salonAsync = ref.watch(ownerSalonProvider);

    return Scaffold(
      backgroundColor: AppColors.secondary50,
      body: salonAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.brand600),
        ),
        error: (e, _) => Center(child: Text('Erreur : $e')),
        data: (salon) {
          if (salon == null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.storefront_outlined,
                      size: 56, color: AppColors.secondary300),
                  const SizedBox(height: 16),
                  Text(
                    'Salon non configuré',
                    style: GoogleFonts.dmSans(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.brand950,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Complétez la configuration de votre salon.',
                    style: TextStyle(
                        color: AppColors.secondary400, fontSize: 13),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const OwnerOnboardingStep1Screen(),
                        ),
                      ).then((_) => ref.invalidate(ownerSalonProvider));
                    },
                    icon: const Icon(Icons.settings_outlined, size: 18),
                    label: const Text('Configurer mon salon'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brand700,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                  ),
                ],
              ),
            );
          }
          return _SalonBody(salon: salon, ref: ref);
        },
      ),
    );
  }
}

// ── Body ─────────────────────────────────────────────────────────────────────

class _SalonBody extends StatelessWidget {
  const _SalonBody({required this.salon, required this.ref});
  final SalonModel salon;
  final WidgetRef ref;

  void _invalidate() => ref.invalidate(ownerSalonProvider);

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        // ── App bar with cover ──────────────────────────────────────────────
        SliverAppBar(
          expandedHeight: 180,
          pinned: true,
          backgroundColor: AppColors.brand900,
          elevation: 0,
          centerTitle: false,
          title: Text(
            'Mon Salon',
            style: GoogleFonts.dmSans(
              fontWeight: FontWeight.bold,
              color: Colors.white,
              fontSize: 20,
            ),
          ),
          flexibleSpace: FlexibleSpaceBar(
            background: salon.images.isNotEmpty
                ? Image.network(
                    salon.images.first,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _coverPlaceholder(),
                  )
                : _coverPlaceholder(),
          ),
        ),

        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Identity card ─────────────────────────────────────────────
              _IdentityCard(salon: salon),

              const SizedBox(height: 8),

              // ── Informations ──────────────────────────────────────────────
              _SectionCard(
                title: 'Informations',
                actionLabel: 'Modifier',
                onAction: () => _showEditInfoSheet(context, salon),
                child: _InfoRows(salon: salon),
              ),

              const SizedBox(height: 8),

              // ── Horaires ──────────────────────────────────────────────────
              _SectionCard(
                title: "Horaires d'ouverture",
                actionLabel: 'Modifier',
                onAction: () => _showEditHoursSheet(context, salon),
                child: _HoursRows(workingHours: salon.workingHours),
              ),

              const SizedBox(height: 8),

              // ── Galerie ───────────────────────────────────────────────────
              _GallerySection(salon: salon),

              const SizedBox(height: 8),

              // ── Avant / Après ──────────────────────────────────────────
              _BeforeAfterSection(salonId: salon.id),

              const SizedBox(height: 8),

              // ── Services ──────────────────────────────────────────────────
              _SectionCard(
                title: 'Services (${salon.services.length})',
                actionLabel: 'Gérer',
                onAction: () => _showServicesSheet(context, salon),
                child: _ServicesPreview(services: salon.services),
              ),

              const SizedBox(height: 8),

              // ── Paramètres ─────────────────────────────────────────────
              _RewardToggle(salon: salon, onChanged: _invalidate),
              _AiPromoToggle(salon: salon, onChanged: _invalidate),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ],
    );
  }

  Widget _coverPlaceholder() => Container(
        color: AppColors.brand900,
        child: const Center(
          child: Icon(Icons.storefront_outlined,
              size: 48, color: Colors.white38),
        ),
      );

  // ── Edit info ─────────────────────────────────────────────────────────────

  void _showEditInfoSheet(BuildContext context, SalonModel salon) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: _EditInfoSheet(salon: salon, onSaved: _invalidate),
      ),
    );
  }

  // ── Edit hours ────────────────────────────────────────────────────────────

  void _showEditHoursSheet(BuildContext context, SalonModel salon) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _EditHoursSheet(salon: salon, onSaved: _invalidate),
    );
  }

  // ── Manage services ───────────────────────────────────────────────────────

  void _showServicesSheet(BuildContext context, SalonModel salon) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ServicesSheet(salon: salon, onSaved: _invalidate),
    );
  }
}

// ── Identity card (logo + name + stats) ─────────────────────────────────────

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.salon});
  final SalonModel salon;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: salon.logoUrl != null
                ? Image.network(salon.logoUrl!,
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _logoFallback())
                : _logoFallback(),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  salon.name,
                  style: GoogleFonts.dmSans(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.brand950,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${salon.city} · ${salon.category}',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.secondary500),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _StatChip(
                      icon: Icons.star_rounded,
                      color: const Color(0xFFD97706),
                      label:
                          '${salon.rating.toStringAsFixed(1)} (${salon.reviewCount})',
                    ),
                    const SizedBox(width: 10),
                    _StatChip(
                      icon: Icons.content_cut_rounded,
                      color: AppColors.brand600,
                      label: '${salon.services.length} services',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _logoFallback() => Container(
        width: 64,
        height: 64,
        color: AppColors.brand50,
        child: const Icon(Icons.storefront_outlined,
            color: AppColors.brand300, size: 30),
      );
}

class _StatChip extends StatelessWidget {
  const _StatChip(
      {required this.icon, required this.color, required this.label});
  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(label,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }
}

// ── Section card wrapper ─────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.actionLabel,
    this.onAction,
  });
  final String title;
  final Widget child;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.dmSans(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.brand950,
                  ),
                ),
              ),
              if (actionLabel != null && onAction != null)
                GestureDetector(
                  onTap: onAction,
                  child: Text(
                    actionLabel!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.brand600,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

// ── Info rows ────────────────────────────────────────────────────────────────

class _InfoRows extends StatelessWidget {
  const _InfoRows({required this.salon});
  final SalonModel salon;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _InfoRow(icon: Icons.storefront_outlined, label: 'Nom', value: salon.name),
        _InfoRow(icon: Icons.location_city_outlined, label: 'Ville', value: salon.city),
        _InfoRow(icon: Icons.map_outlined, label: 'Adresse', value: salon.address),
        _InfoRow(
          icon: Icons.description_outlined,
          label: 'Description',
          value: salon.description.isNotEmpty ? salon.description : '—',
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(
      {required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.secondary400),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.secondary400)),
                const SizedBox(height: 1),
                Text(value,
                    style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.brand950,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Hours rows ───────────────────────────────────────────────────────────────

class _HoursRows extends StatelessWidget {
  const _HoursRows({required this.workingHours});
  final Map<String, dynamic> workingHours;

  static const _days = [
    ('lundi', 'Lundi'),
    ('mardi', 'Mardi'),
    ('mercredi', 'Mercredi'),
    ('jeudi', 'Jeudi'),
    ('vendredi', 'Vendredi'),
    ('samedi', 'Samedi'),
    ('dimanche', 'Dimanche'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: _days.map((entry) {
        final dayKey = entry.$1;
        final dayLabel = entry.$2;
        final data =
            workingHours[dayKey] as Map<String, dynamic>?;
        final isOpen = data?['isOpen'] == true;
        final hours = isOpen
            ? '${data!['open']} – ${data['close']}'
            : 'Fermé';
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isOpen
                      ? const Color(0xFF16A34A)
                      : AppColors.secondary300,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 90,
                child: Text(
                  dayLabel,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.brand950),
                ),
              ),
              Text(
                hours,
                style: TextStyle(
                  fontSize: 13,
                  color: isOpen
                      ? AppColors.secondary600
                      : AppColors.secondary400,
                  fontWeight:
                      isOpen ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ── Services preview ─────────────────────────────────────────────────────────

class _ServicesPreview extends StatelessWidget {
  const _ServicesPreview({required this.services});
  final List<Map<String, dynamic>> services;

  @override
  Widget build(BuildContext context) {
    if (services.isEmpty) {
      return const Text(
        'Aucun service ajouté',
        style: TextStyle(color: AppColors.secondary400, fontSize: 13),
      );
    }
    final preview = services.take(4).toList();
    return Column(
      children: [
        ...preview.map((s) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.brand50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.content_cut_rounded,
                        color: AppColors.brand400, size: 15),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      s['name'] as String? ?? '',
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.brand950),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${(s['price'] as num?)?.toStringAsFixed(0) ?? '0'} MAD',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.brand700),
                  ),
                ],
              ),
            )),
        if (services.length > 4)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '+ ${services.length - 4} autres services',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.secondary400),
            ),
          ),
      ],
    );
  }
}

// ── Edit info sheet ───────────────────────────────────────────────────────────

class _EditInfoSheet extends StatefulWidget {
  const _EditInfoSheet({required this.salon, required this.onSaved});
  final SalonModel salon;
  final VoidCallback onSaved;

  @override
  State<_EditInfoSheet> createState() => _EditInfoSheetState();
}

class _EditInfoSheetState extends State<_EditInfoSheet> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _country;
  late final TextEditingController _street;
  late final TextEditingController _city;
  late final TextEditingController _postalCode;

  bool _loading = false;
  bool _isGettingLocation = false;
  double? _latitude;
  double? _longitude;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.salon.name);
    _description = TextEditingController(text: widget.salon.description);

    _latitude = widget.salon.latitude;
    _longitude = widget.salon.longitude;

    // Parse existing address into structured fields
    final parts = widget.salon.address.split(',').map((s) => s.trim()).toList();
    // Address format: "street, postalCode, city, country" or partial
    if (parts.length >= 4) {
      _street = TextEditingController(text: parts[0]);
      _postalCode = TextEditingController(text: parts[1]);
      _city = TextEditingController(text: parts[2]);
      _country = TextEditingController(text: parts[3]);
    } else if (parts.length == 3) {
      _street = TextEditingController(text: parts[0]);
      _postalCode = TextEditingController();
      _city = TextEditingController(text: parts[1]);
      _country = TextEditingController(text: parts[2]);
    } else if (parts.length == 2) {
      _street = TextEditingController(text: parts[0]);
      _postalCode = TextEditingController();
      _city = TextEditingController(text: parts[1]);
      _country = TextEditingController(text: 'Maroc');
    } else {
      _street = TextEditingController(text: widget.salon.address);
      _postalCode = TextEditingController();
      _city = TextEditingController(text: widget.salon.city);
      _country = TextEditingController(text: 'Maroc');
    }

    // Always sync city from salon model if available
    if (widget.salon.city.isNotEmpty) {
      _city.text = widget.salon.city;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _country.dispose();
    _street.dispose();
    _city.dispose();
    _postalCode.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isGettingLocation = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw 'Le service de localisation est désactivé.';

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw 'Permission de localisation refusée.';
        }
      }
      if (permission == LocationPermission.deniedForever) {
        throw 'Permission de localisation définitivement refusée. Activez-la dans les paramètres.';
      }

      final position = await Geolocator.getCurrentPosition();
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        setState(() {
          _latitude = position.latitude;
          _longitude = position.longitude;
          _street.text = (p.street ?? '').trim();
          _city.text = p.locality ?? p.administrativeArea ?? '';
          _postalCode.text = p.postalCode ?? '';
          _country.text =
              (p.country ?? '').isNotEmpty ? p.country! : 'Maroc';
          _isGettingLocation = false;
        });
      } else {
        setState(() {
          _latitude = position.latitude;
          _longitude = position.longitude;
          _isGettingLocation = false;
        });
      }
    } catch (e) {
      setState(() => _isGettingLocation = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur : ${e.toString()}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final city = _city.text.trim();

    if (name.isEmpty || city.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez remplir les champs obligatoires (nom et ville)'),
        ),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      // Build full address string
      final addressParts = [
        if (_street.text.trim().isNotEmpty) _street.text.trim(),
        if (_postalCode.text.trim().isNotEmpty) _postalCode.text.trim(),
        city,
        if (_country.text.trim().isNotEmpty) _country.text.trim(),
      ];
      final fullAddress = addressParts.join(', ');

      // Forward geocoding if GPS wasn't used or coords changed
      double? lat = _latitude;
      double? lng = _longitude;
      if (lat == null || lng == null) {
        try {
          final locations = await locationFromAddress(fullAddress);
          if (locations.isNotEmpty) {
            lat = locations.first.latitude;
            lng = locations.first.longitude;
          }
        } catch (_) {}
        if (lat == null || lng == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Impossible de localiser cette adresse. Veuillez utiliser le bouton GPS.',
              ),
              backgroundColor: Colors.redAccent,
              duration: Duration(seconds: 4),
            ),
          );
          setState(() => _loading = false);
          return;
        }
      }

      final updated = SalonModel(
        id: widget.salon.id,
        ownerId: widget.salon.ownerId,
        name: name,
        city: city,
        country: _country.text.trim().isNotEmpty ? _country.text.trim() : 'Maroc',
        address: fullAddress,
        description: _description.text.trim(),
        category: widget.salon.category,
        rating: widget.salon.rating,
        reviewCount: widget.salon.reviewCount,
        images: widget.salon.images,
        logoUrl: widget.salon.logoUrl,
        workingHours: widget.salon.workingHours,
        services: widget.salon.services,
        serviceCategories: widget.salon.serviceCategories,
        latitude: lat,
        longitude: lng,
        createdAt: widget.salon.createdAt,
        socialLinks: widget.salon.socialLinks,
      );
      await DatabaseService().saveSalon(updated);
      widget.onSaved();
      if (mounted) Navigator.pop(context);
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
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SheetHandle(),
            Text(
              'Modifier les informations',
              style: GoogleFonts.dmSans(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: AppColors.brand950),
            ),
            const SizedBox(height: 20),

            // Salon name
            _Field(controller: _name, label: 'Nom du salon'),
            const SizedBox(height: 16),

            // Address header + GPS button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Adresse',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.secondary700,
                  ),
                ),
                TextButton.icon(
                  onPressed:
                      _isGettingLocation ? null : _getCurrentLocation,
                  icon: _isGettingLocation
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.brand500,
                          ),
                        )
                      : Icon(
                          _latitude != null
                              ? Icons.check_circle
                              : Icons.my_location,
                          size: 14,
                          color: _latitude != null
                              ? Colors.green
                              : AppColors.brand600,
                        ),
                  label: Text(
                    _isGettingLocation
                        ? 'Localisation...'
                        : (_latitude != null
                            ? 'Position capturée'
                            : 'Utiliser ma position'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _latitude != null
                          ? Colors.green
                          : AppColors.brand600,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Country
            _Field(controller: _country, label: 'Pays'),
            const SizedBox(height: 10),

            // Street
            _Field(controller: _street, label: 'Adresse (rue et numéro)'),
            const SizedBox(height: 10),

            // City + Postal code side by side
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: _Field(controller: _city, label: 'Ville *'),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: _Field(
                    controller: _postalCode,
                    label: 'Code postal',
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Description
            _Field(
              controller: _description,
              label: 'Description',
              maxLines: 3,
            ),
            const SizedBox(height: 24),

            // Save button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _loading ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brand600,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Text('Enregistrer',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Edit hours sheet ─────────────────────────────────────────────────────────

class _EditHoursSheet extends StatefulWidget {
  const _EditHoursSheet({required this.salon, required this.onSaved});
  final SalonModel salon;
  final VoidCallback onSaved;

  @override
  State<_EditHoursSheet> createState() => _EditHoursSheetState();
}

class _EditHoursSheetState extends State<_EditHoursSheet> {
  static const _days = [
    ('lundi', 'Lundi'),
    ('mardi', 'Mardi'),
    ('mercredi', 'Mercredi'),
    ('jeudi', 'Jeudi'),
    ('vendredi', 'Vendredi'),
    ('samedi', 'Samedi'),
    ('dimanche', 'Dimanche'),
  ];

  late Map<String, Map<String, dynamic>> _hours;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _hours = {};
    for (final (key, _) in _days) {
      final data = widget.salon.workingHours[key] as Map<String, dynamic>?;
      _hours[key] = {
        'isOpen': data?['isOpen'] ?? false,
        'open': data?['open'] ?? '09:00',
        'close': data?['close'] ?? '18:00',
      };
    }
  }

  Future<void> _pickTime(String day, String field) async {
    final parts = (_hours[day]![field] as String).split(':');
    final initial = TimeOfDay(
        hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      setState(() {
        _hours[day]![field] =
            '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      });
    }
  }

  Future<void> _save() async {
    setState(() => _loading = true);
    try {
      final updated = SalonModel(
        id: widget.salon.id,
        ownerId: widget.salon.ownerId,
        name: widget.salon.name,
        city: widget.salon.city,
        country: widget.salon.country,
        address: widget.salon.address,
        description: widget.salon.description,
        category: widget.salon.category,
        rating: widget.salon.rating,
        reviewCount: widget.salon.reviewCount,
        images: widget.salon.images,
        logoUrl: widget.salon.logoUrl,
        workingHours: Map<String, dynamic>.from(_hours),
        services: widget.salon.services,
        serviceCategories: widget.salon.serviceCategories,
        latitude: widget.salon.latitude,
        longitude: widget.salon.longitude,
        createdAt: widget.salon.createdAt,
      );
      await DatabaseService().saveSalon(updated);
      widget.onSaved();
      if (mounted) Navigator.pop(context);
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
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, controller) => Column(
        children: [
          _SheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    "Horaires d'ouverture",
                    style: GoogleFonts.dmSans(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: AppColors.brand950),
                  ),
                ),
                TextButton(
                  onPressed: _loading ? null : _save,
                  child: _loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              color: AppColors.brand600, strokeWidth: 2))
                      : const Text('Enregistrer',
                          style: TextStyle(
                              color: AppColors.brand600,
                              fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              children: _days.map((entry) {
                final dayKey = entry.$1;
                final dayLabel = entry.$2;
                final data = _hours[dayKey]!;
                final isOpen = data['isOpen'] as bool;
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(dayLabel,
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.brand950)),
                        ),
                        Switch(
                          value: isOpen,
                          activeThumbColor: AppColors.brand600,
                          activeTrackColor: AppColors.brand100,
                          onChanged: (v) =>
                              setState(() => _hours[dayKey]!['isOpen'] = v),
                        ),
                      ],
                    ),
                    if (isOpen) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: _TimeButton(
                              label: 'Ouverture',
                              time: data['open'] as String,
                              onTap: () => _pickTime(dayKey, 'open'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _TimeButton(
                              label: 'Fermeture',
                              time: data['close'] as String,
                              onTap: () => _pickTime(dayKey, 'close'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    const Divider(height: 16),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeButton extends StatelessWidget {
  const _TimeButton(
      {required this.label, required this.time, required this.onTap});
  final String label;
  final String time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.secondary100,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.secondary500)),
            Text(time,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.brand700)),
          ],
        ),
      ),
    );
  }
}

// ── Services sheet ────────────────────────────────────────────────────────────

class _ServicesSheet extends ConsumerStatefulWidget {
  const _ServicesSheet({required this.salon, required this.onSaved});
  final SalonModel salon;
  final VoidCallback onSaved;

  @override
  ConsumerState<_ServicesSheet> createState() => _ServicesSheetState();
}

class _ServicesSheetState extends ConsumerState<_ServicesSheet> {
  late List<Map<String, dynamic>> _services;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _services = List<Map<String, dynamic>>.from(
        widget.salon.services.map((s) => Map<String, dynamic>.from(s)));
  }

  /// Build a map: serviceName → Set<memberName> from team members' assignedServiceNames
  Map<String, Set<String>> _buildServiceMemberMap(List<TeamMemberModel> members) {
    final map = <String, Set<String>>{};
    for (final m in members) {
      for (final sName in m.assignedServiceNames) {
        map.putIfAbsent(sName, () => {}).add(m.name);
      }
    }
    return map;
  }

  Future<void> _save() async {
    setState(() => _loading = true);
    try {
      final categories = _services
          .map((s) => s['category'] as String? ?? '')
          .where((c) => c.isNotEmpty)
          .toSet()
          .toList();

      final updated = SalonModel(
        id: widget.salon.id,
        ownerId: widget.salon.ownerId,
        name: widget.salon.name,
        city: widget.salon.city,
        country: widget.salon.country,
        address: widget.salon.address,
        description: widget.salon.description,
        category: widget.salon.category,
        rating: widget.salon.rating,
        reviewCount: widget.salon.reviewCount,
        images: widget.salon.images,
        logoUrl: widget.salon.logoUrl,
        workingHours: widget.salon.workingHours,
        services: _services,
        serviceCategories: categories,
        latitude: widget.salon.latitude,
        longitude: widget.salon.longitude,
        createdAt: widget.salon.createdAt,
      );
      await DatabaseService().saveSalon(updated);

      // Update each team member's assignedServiceNames
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
          widget.salon.id,
          member.id,
          {'assignedServiceNames': assignedServices},
        );
      }

      widget.onSaved();
      if (mounted) Navigator.pop(context);
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

  void _delete(int index) {
    setState(() => _services.removeAt(index));
  }

  void _showServiceDialog(int? index) {
    final teamMembers = ref.read(ownerTeamProvider).value ?? [];
    final serviceMemberMap = _buildServiceMemberMap(teamMembers);

    final isNew = index == null;
    final existing = isNew ? null : _services[index];

    // For existing services, get assigned members from the map or from the service data
    Set<String> currentAssigned = {};
    if (existing != null) {
      final fromData = existing['assignedMembers'];
      if (fromData != null) {
        currentAssigned = Set<String>.from(fromData);
      } else {
        currentAssigned = serviceMemberMap[existing['name']] ?? {};
      }
    }

    showDialog(
      context: context,
      builder: (_) => _SalonServiceFormDialog(
        existing: existing,
        assignedMembers: currentAssigned,
        teamMembers: teamMembers,
        onSave: (entry) {
          setState(() {
            if (isNew) {
              _services.add(entry);
            } else {
              _services[index] = entry;
            }
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final teamMembers = ref.watch(ownerTeamProvider).value ?? [];
    final serviceMemberMap = _buildServiceMemberMap(teamMembers);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, controller) => Column(
        children: [
          _SheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Services (${_services.length})',
                    style: GoogleFonts.dmSans(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: AppColors.brand950),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _showServiceDialog(null),
                  icon: const Icon(Icons.add, size: 16,
                      color: AppColors.brand600),
                  label: const Text('Ajouter',
                      style: TextStyle(
                          color: AppColors.brand600,
                          fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 4),
                TextButton(
                  onPressed: _loading ? null : _save,
                  child: _loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              color: AppColors.brand600, strokeWidth: 2))
                      : const Text('Enregistrer',
                          style: TextStyle(
                              color: AppColors.brand600,
                              fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _services.isEmpty
                ? const Center(
                    child: Text(
                      'Aucun service. Appuyez sur + pour en ajouter.',
                      style: TextStyle(
                          color: AppColors.secondary400, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.separated(
                    controller: controller,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _services.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 20),
                    itemBuilder: (_, i) {
                      final s = _services[i];
                      final category = s['category'] as String? ?? '';
                      final duration = s['duration'] as int? ?? 30;
                      final assignedFromData = s['assignedMembers'];
                      final assigned = assignedFromData != null
                          ? Set<String>.from(assignedFromData)
                          : (serviceMemberMap[s['name']] ?? <String>{});

                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        s['name'] as String? ?? '',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                          color: AppColors.brand950,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          if (category.isNotEmpty)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 2),
                                              decoration: BoxDecoration(
                                                color: AppColors.brand100,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                category,
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppColors.brand600,
                                                ),
                                              ),
                                            ),
                                          if (category.isNotEmpty)
                                            const SizedBox(width: 8),
                                          Text(
                                            '$duration min',
                                            style: const TextStyle(
                                              color: AppColors.secondary500,
                                              fontSize: 12,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            '${(s['price'] as num?)?.toStringAsFixed(0) ?? '0'} MAD',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                              color: AppColors.brand700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                InkWell(
                                  onTap: () => _showServiceDialog(i),
                                  borderRadius: BorderRadius.circular(6),
                                  child: const Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Icon(Icons.edit_outlined,
                                        size: 16,
                                        color: AppColors.secondary400),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                InkWell(
                                  onTap: () => _delete(i),
                                  borderRadius: BorderRadius.circular(6),
                                  child: const Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Icon(Icons.delete_outline_rounded,
                                        size: 16, color: Color(0xFFDC2626)),
                                  ),
                                ),
                              ],
                            ),
                            if (assigned.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: assigned.map((name) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppColors.brand50,
                                      border: Border.all(
                                          color: AppColors.brand200),
                                      borderRadius:
                                          BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.person_outline,
                                            size: 12,
                                            color: AppColors.brand600),
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
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Service form dialog (separate StatefulWidget to avoid _dependents error) ──

class _SalonServiceFormDialog extends StatefulWidget {
  const _SalonServiceFormDialog({
    this.existing,
    required this.assignedMembers,
    required this.teamMembers,
    required this.onSave,
  });

  final Map<String, dynamic>? existing;
  final Set<String> assignedMembers;
  final List<TeamMemberModel> teamMembers;
  final void Function(Map<String, dynamic> entry) onSave;

  @override
  State<_SalonServiceFormDialog> createState() =>
      _SalonServiceFormDialogState();
}

class _SalonServiceFormDialogState extends State<_SalonServiceFormDialog> {
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
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?['name'] as String? ?? '');
    _priceCtrl = TextEditingController(
      text: e != null && (e['price'] as num?) != null
          ? (e['price'] as num).toStringAsFixed(0)
          : '',
    );
    _descCtrl =
        TextEditingController(text: e?['description'] as String? ?? '');
    _category = e?['category'] as String? ?? AppConstants.categoryNames.first;
    // Ensure category is valid
    if (!AppConstants.categoryNames.contains(_category)) {
      _category = AppConstants.categoryNames.first;
    }
    _duration = e?['duration'] as int? ?? 30;
    _selectedMembers = Set<String>.from(widget.assignedMembers);
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
    if (_selectedMembers.isEmpty && widget.teamMembers.isNotEmpty) {
      setState(() => _memberError = 'Assignez au moins un employé');
      return;
    }
    final entry = <String, dynamic>{
      'name': _nameCtrl.text.trim(),
      'category': _category,
      'description': _descCtrl.text.trim(),
      'price': double.tryParse(_priceCtrl.text.trim()) ?? 0.0,
      'duration': _duration,
      'assignedMembers': _selectedMembers.toList(),
    };
    Navigator.pop(context);
    widget.onSave(entry);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AlertDialog(
      backgroundColor: Colors.white,
      title: Text(
        isEdit ? 'Modifier le service' : 'Nouveau service',
        style: GoogleFonts.dmSans(
          fontWeight: FontWeight.bold,
          color: AppColors.brand950,
          fontSize: 16,
        ),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Name
              _label('Nom du service *'),
              const SizedBox(height: 6),
              _field(_nameCtrl, 'ex. Coupe femme & Brushing'),
              const SizedBox(height: 14),

              // Category
              _label('Catégorie *'),
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
                        .map((e) =>
                            DropdownMenuItem(value: e, child: Text(e)))
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
                        _label('Durée *'),
                        const SizedBox(height: 6),
                        Container(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: AppColors.secondary300),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<int>(
                              isExpanded: true,
                              value: _duration,
                              items: const [15, 30, 45, 60, 90, 120]
                                  .map((d) => DropdownMenuItem(
                                      value: d,
                                      child: Text('$d min')))
                                  .toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _duration = val);
                                }
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
                        _label('Prix (MAD)'),
                        const SizedBox(height: 6),
                        _field(_priceCtrl, '0',
                            keyboardType: TextInputType.number),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Description
              _label('Description'),
              const SizedBox(height: 6),
              _field(_descCtrl, 'Description optionnelle…', maxLines: 2),
              const SizedBox(height: 14),

              // Member assignment
              if (widget.teamMembers.isNotEmpty) ...[
                _label('Réalisé par *'),
                const SizedBox(height: 2),
                const Text(
                  'Sélectionnez tous les employés capables de réaliser ce service',
                  style: TextStyle(fontSize: 11, color: AppColors.secondary400),
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
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler',
              style: TextStyle(color: AppColors.secondary400)),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.brand600,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(
                horizontal: 24, vertical: 12),
          ),
          child: Text(isEdit ? 'Enregistrer' : 'Ajouter'),
        ),
      ],
    );
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
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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

// ── Shared helpers ────────────────────────────────────────────────────────────

class _SheetHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 36,
          height: 4,
          margin: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.secondary200,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.maxLines = 1,
    this.keyboardType,
  });
  final TextEditingController controller;
  final String label;
  final int maxLines;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 14, color: AppColors.brand950),
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            const TextStyle(fontSize: 13, color: AppColors.secondary400),
        filled: true,
        fillColor: AppColors.secondary50,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.secondary200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.secondary200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              const BorderSide(color: AppColors.brand400, width: 1.5),
        ),
      ),
    );
  }
}

// ── Gallery section ─────────────────────────────────────────────────────────

class _GallerySection extends StatefulWidget {
  const _GallerySection({required this.salon});
  final SalonModel salon;

  @override
  State<_GallerySection> createState() => _GallerySectionState();
}

class _GallerySectionState extends State<_GallerySection> {
  late List<String> _images;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _images = List<String>.from(widget.salon.images);
  }

  @override
  void didUpdateWidget(covariant _GallerySection old) {
    super.didUpdateWidget(old);
    if (old.salon.images != widget.salon.images) {
      _images = List<String>.from(widget.salon.images);
    }
  }

  Future<void> _addImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      imageQuality: 80,
    );
    if (picked == null) return;

    setState(() => _uploading = true);
    try {
      final file = File(picked.path);
      final ref = FirebaseStorage.instance
          .ref()
          .child('salons/${widget.salon.id}/gallery_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await ref.putFile(file);
      final url = await ref.getDownloadURL();
      _images.add(url);
      await DatabaseService().updateSalonImages(widget.salon.id, _images);
      setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _deleteImage(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer cette photo ?'),
        content: const Text('Cette action est irréversible.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _uploading = true);
    try {
      final url = _images[index];
      // Delete from Storage
      try {
        await FirebaseStorage.instance.refFromURL(url).delete();
      } catch (_) {}
      _images.removeAt(index);
      await DatabaseService().updateSalonImages(widget.salon.id, _images);
      setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Galerie (${_images.length})',
                  style: GoogleFonts.dmSans(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.brand950,
                  ),
                ),
              ),
              if (_uploading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.brand600,
                  ),
                )
              else
                GestureDetector(
                  onTap: _addImage,
                  child: const Text(
                    '+ Ajouter',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.brand600,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (_images.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 28),
              decoration: BoxDecoration(
                color: AppColors.secondary50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.secondary200,
                  style: BorderStyle.solid,
                ),
              ),
              child: Column(
                children: [
                  const Icon(Icons.photo_library_outlined,
                      size: 32, color: AppColors.secondary300),
                  const SizedBox(height: 8),
                  Text(
                    'Aucune photo',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.secondary400,
                    ),
                  ),
                ],
              ),
            )
          else
            SizedBox(
              height: 100,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _images.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) => Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        _images[i],
                        width: 100,
                        height: 100,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 100,
                          height: 100,
                          color: AppColors.secondary100,
                          child: const Icon(Icons.broken_image_outlined,
                              color: AppColors.secondary300),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () => _deleteImage(i),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close,
                              size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Before / After section ──────────────────────────────────────────────────

class _BeforeAfterSection extends StatefulWidget {
  const _BeforeAfterSection({required this.salonId});
  final String salonId;

  @override
  State<_BeforeAfterSection> createState() => _BeforeAfterSectionState();
}

class _BeforeAfterSectionState extends State<_BeforeAfterSection> {
  bool _uploading = false;

  Future<void> _addBeforeAfter() async {
    try {
      final picker = ImagePicker();

      // Pick "before" image
      final beforePicked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        imageQuality: 80,
      );
      if (beforePicked == null || !mounted) return;

      // Pick "after" image
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sélectionnez maintenant la photo "Après"'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      final afterPicked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        imageQuality: 80,
      );
      if (afterPicked == null || !mounted) return;

      // Ask for a label
      final labelCtrl = TextEditingController();
      final label = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Nom du soin'),
          content: TextField(
            controller: labelCtrl,
            decoration: const InputDecoration(
              hintText: 'Ex: Coloration, Lissage…',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, labelCtrl.text.trim()),
              child: const Text('Valider'),
            ),
          ],
        ),
      );
      if (label == null || label.isEmpty || !mounted) return;

      setState(() => _uploading = true);

      final ts = DateTime.now().millisecondsSinceEpoch;
      final storageBase = 'salons/${widget.salonId}/before_after';

      // Upload before
      final beforeRef = FirebaseStorage.instance
          .ref()
          .child('$storageBase/before_$ts.jpg');
      await beforeRef.putFile(File(beforePicked.path));
      final beforeUrl = await beforeRef.getDownloadURL();

      // Upload after
      final afterRef = FirebaseStorage.instance
          .ref()
          .child('$storageBase/after_$ts.jpg');
      await afterRef.putFile(File(afterPicked.path));
      final afterUrl = await afterRef.getDownloadURL();

      await DatabaseService().addBeforeAfter(widget.salonId, {
        'beforeUrl': beforeUrl,
        'afterUrl': afterUrl,
        'label': label,
        'createdAt': DateTime.now(),
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _deleteItem(String docId, String beforeUrl, String afterUrl) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer cet avant/après ?'),
        content: const Text('Les deux photos seront supprimées.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      try { await FirebaseStorage.instance.refFromURL(beforeUrl).delete(); } catch (_) {}
      try { await FirebaseStorage.instance.refFromURL(afterUrl).delete(); } catch (_) {}
      await DatabaseService().deleteBeforeAfter(widget.salonId, docId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Avant / Après',
                  style: GoogleFonts.dmSans(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.brand950,
                  ),
                ),
              ),
              if (_uploading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.brand600,
                  ),
                )
              else
                GestureDetector(
                  onTap: _addBeforeAfter,
                  child: const Text(
                    '+ Ajouter',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.brand600,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: DatabaseService().getBeforeAfterStream(widget.salonId),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.brand600,
                    ),
                  ),
                );
              }
              final items = snap.data ?? [];
              if (items.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  decoration: BoxDecoration(
                    color: AppColors.secondary50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.secondary200),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.compare_outlined,
                          size: 32, color: AppColors.secondary300),
                      const SizedBox(height: 8),
                      Text(
                        'Aucun avant/après',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.secondary400,
                        ),
                      ),
                    ],
                  ),
                );
              }
              return SizedBox(
                height: 130,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, i) {
                    final item = items[i];
                    return Stack(
                      children: [
                        Container(
                          width: 200,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.secondary200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius: const BorderRadius.only(
                                          topLeft: Radius.circular(9),
                                        ),
                                        child: Image.network(
                                          item['beforeUrl'] ?? '',
                                          fit: BoxFit.cover,
                                          height: double.infinity,
                                          errorBuilder: (_, __, ___) =>
                                              Container(color: AppColors.secondary100),
                                        ),
                                      ),
                                    ),
                                    Container(
                                      width: 1,
                                      color: AppColors.secondary200,
                                    ),
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius: const BorderRadius.only(
                                          topRight: Radius.circular(9),
                                        ),
                                        child: Image.network(
                                          item['afterUrl'] ?? '',
                                          fit: BoxFit.cover,
                                          height: double.infinity,
                                          errorBuilder: (_, __, ___) =>
                                              Container(color: AppColors.secondary100),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 6),
                                decoration: const BoxDecoration(
                                  borderRadius: BorderRadius.only(
                                    bottomLeft: Radius.circular(9),
                                    bottomRight: Radius.circular(9),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Text('Avant',
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: AppColors.secondary400)),
                                    const Spacer(),
                                    Text(
                                      item['label'] ?? '',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.brand950,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const Spacer(),
                                    const Text('Après',
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: AppColors.secondary400)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () => _deleteItem(
                              item['id'] ?? '',
                              item['beforeUrl'] ?? '',
                              item['afterUrl'] ?? '',
                            ),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close,
                                  size: 14, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── Reward points toggle ────────────────────────────────────────────────────

class _RewardToggle extends StatefulWidget {
  const _RewardToggle({required this.salon, required this.onChanged});
  final SalonModel salon;
  final VoidCallback onChanged;

  @override
  State<_RewardToggle> createState() => _RewardToggleState();
}

class _RewardToggleState extends State<_RewardToggle> {
  late bool _enabled;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _enabled = widget.salon.rewardPointsEnabled;
  }

  Future<void> _toggle(bool value) async {
    setState(() {
      _enabled = value;
      _saving = true;
    });
    try {
      await DatabaseService().updateSalonField(
        widget.salon.id,
        'rewardPointsEnabled',
        value,
      );
      widget.onChanged();
    } catch (e) {
      if (mounted) {
        setState(() => _enabled = !value);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Paramètres',
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppColors.brand950,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.brand50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.stars_rounded,
                    size: 20, color: AppColors.brand600),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Points de fidélité',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.brand950,
                      ),
                    ),
                    Text(
                      _enabled
                          ? 'Les clients cumulent des points'
                          : 'Système désactivé',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.secondary400,
                      ),
                    ),
                  ],
                ),
              ),
              if (_saving)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.brand600,
                  ),
                )
              else
                Switch(
                  value: _enabled,
                  onChanged: _toggle,
                  activeTrackColor: AppColors.brand600,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── AI Auto-Promotions Toggle ────────────────────────────────────────────────

class _AiPromoToggle extends StatefulWidget {
  const _AiPromoToggle({required this.salon, required this.onChanged});
  final SalonModel salon;
  final VoidCallback onChanged;

  @override
  State<_AiPromoToggle> createState() => _AiPromoToggleState();
}

class _AiPromoToggleState extends State<_AiPromoToggle> {
  late bool _enabled;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _enabled = widget.salon.aiPromosEnabled;
  }

  Future<void> _toggle(bool value) async {
    // Show explanation popup when enabling
    if (value) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.brand50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.auto_awesome, size: 20, color: AppColors.brand600),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Promotions IA', style: TextStyle(fontSize: 17)),
              ),
            ],
          ),
          content: const Text(
            'L\'IA analysera vos clients chaque jour et créera des promotions ciblées :\n\n'
            '• Meilleur client du mois\n'
            '• Client absent depuis longtemps\n'
            '• Client fidèle\n\n'
            'Les promotions sont envoyées par notification push. '
            'Vous pouvez personnaliser les pourcentages depuis les paramètres.',
            style: TextStyle(fontSize: 13.5, height: 1.5, color: AppColors.secondary600),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brand600,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Activer', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() { _enabled = value; _saving = true; });
    try {
      await DatabaseService().updateSalonField(
        widget.salon.id,
        'aiPromosEnabled',
        value,
      );
      widget.onChanged();
    } catch (e) {
      if (mounted) {
        setState(() => _enabled = !value);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showConfigDialog() async {
    final config = Map<String, dynamic>.from(widget.salon.aiPromoConfig);
    int topPercent = config['topClientPercent'] ?? 30;
    int winBackPercent = config['winBackPercent'] ?? 20;
    int winBackWeeks = config['winBackWeeks'] ?? 3;
    int loyalPercent = config['loyalPercent'] ?? 15;
    int loyalMinVisits = config['loyalMinVisits'] ?? 10;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 16),
          contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.brand50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.tune_rounded, size: 20, color: AppColors.brand600),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Configurer les promos IA',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          content: SizedBox(
            width: MediaQuery.of(ctx).size.width,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
              children: [
                _configRow(
                  'Meilleur client',
                  'Réduction pour le top client du mois',
                  '$topPercent%',
                  topPercent,
                  5, 50,
                  (v) => setDialogState(() => topPercent = v),
                ),
                const Divider(height: 24),
                _configRow(
                  'Client absent',
                  'Réduction pour récupérer un client',
                  '$winBackPercent%',
                  winBackPercent,
                  5, 50,
                  (v) => setDialogState(() => winBackPercent = v),
                ),
                const SizedBox(height: 8),
                _configRow(
                  'Semaines d\'absence',
                  'Après combien de semaines ?',
                  '$winBackWeeks sem.',
                  winBackWeeks,
                  2, 8,
                  (v) => setDialogState(() => winBackWeeks = v),
                ),
                const Divider(height: 24),
                _configRow(
                  'Client fidèle',
                  'Réduction de remerciement',
                  '$loyalPercent%',
                  loyalPercent,
                  5, 50,
                  (v) => setDialogState(() => loyalPercent = v),
                ),
                const SizedBox(height: 8),
                _configRow(
                  'Visites minimum',
                  'Nombre de visites pour être fidèle',
                  '$loyalMinVisits',
                  loyalMinVisits,
                  5, 30,
                  (v) => setDialogState(() => loyalMinVisits = v),
                ),
              ],
            ),
          ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () {
                config['topClientPercent'] = topPercent;
                config['winBackPercent'] = winBackPercent;
                config['winBackWeeks'] = winBackWeeks;
                config['loyalPercent'] = loyalPercent;
                config['loyalMinVisits'] = loyalMinVisits;
                Navigator.pop(ctx, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brand600,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Enregistrer', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (saved == true) {
      try {
        await DatabaseService().updateSalonField(
          widget.salon.id,
          'aiPromoConfig',
          config,
        );
        widget.onChanged();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Configuration IA enregistrée'),
              backgroundColor: Color(0xFF16A34A),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur : $e')),
          );
        }
      }
    }
  }

  Widget _configRow(String title, String subtitle, String valueLabel,
      int value, int min, int max, ValueChanged<int> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.brand950)),
                  Text(subtitle,
                      style: const TextStyle(fontSize: 11, color: AppColors.secondary400)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.brand50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(valueLabel,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.brand600)),
            ),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: AppColors.brand600,
            inactiveTrackColor: AppColors.brand100,
            thumbColor: AppColors.brand600,
            overlayColor: AppColors.brand600.withValues(alpha: 0.1),
            trackHeight: 3,
          ),
          child: Slider(
            value: value.toDouble(),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: max - min,
            onChanged: (v) => onChanged(v.round()),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.brand50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.auto_awesome,
                    size: 20, color: AppColors.brand600),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Promotions IA',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.brand950,
                      ),
                    ),
                    Text(
                      _enabled
                          ? 'Promotions ciblées automatiques'
                          : 'Désactivé',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.secondary400,
                      ),
                    ),
                  ],
                ),
              ),
              if (_saving)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.brand600,
                  ),
                )
              else
                Switch(
                  value: _enabled,
                  onChanged: _toggle,
                  activeTrackColor: AppColors.brand600,
                ),
            ],
          ),
          if (_enabled) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _showConfigDialog,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                decoration: BoxDecoration(
                  color: AppColors.brand50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.brand100),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.tune_rounded, size: 16, color: AppColors.brand600),
                    SizedBox(width: 8),
                    Text(
                      'Configurer les pourcentages',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.brand600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
