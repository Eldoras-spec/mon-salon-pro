import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../theme/app_colors.dart';
import '../models/salon_model.dart';
import '../providers/owner_providers.dart';
import '../services/app_localizations.dart';
import '../services/database_service.dart';
import '../utils/media_compressor.dart';
import 'owner_onboarding_step1_screen.dart';
import '../utils/currency_helper.dart';
import '../utils/timezone_helper.dart';

// ── Screen ───────────────────────────────────────────────────────────────────

class OwnerSalonScreen extends ConsumerWidget {
  const OwnerSalonScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final salonAsync = ref.watch(ownerSalonProvider);

    return Scaffold(
      backgroundColor: AppColors.secondary50,
      body: salonAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.brand600),
        ),
        error: (e, _) => Center(child: Text('${l?.tr('common_error_short') ?? 'Erreur'} : $e')),
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
                    l?.tr('salon_not_configured') ?? 'Salon non configuré',
                    style: GoogleFonts.dmSans(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.brand950,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l?.tr('salon_configure_hint') ?? 'Complétez la configuration de votre salon.',
                    style: const TextStyle(
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
                    label: Text(l?.tr('salon_configure_button') ?? 'Configurer mon salon'),
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

  void _invalidate() {
    try {
      ref.invalidate(ownerSalonProvider);
    } catch (_) {
      // Widget rebuilt during async save — the Firestore StreamProvider
      // will pick up the change on its own.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
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
            l?.tr('salon_title') ?? 'Mon Salon',
            style: GoogleFonts.dmSans(
              fontWeight: FontWeight.bold,
              color: Colors.white,
              fontSize: 20,
            ),
          ),
          flexibleSpace: FlexibleSpaceBar(
            background: Stack(
              fit: StackFit.expand,
              children: [
                salon.images.isNotEmpty
                    ? Image.network(
                        salon.images.first,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _coverPlaceholder(),
                      )
                    : _coverPlaceholder(),
                Positioned(
                  bottom: 12,
                  right: 12,
                  child: Material(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => _pickCoverPhoto(context),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.camera_alt_outlined,
                                size: 16, color: Colors.white),
                            const SizedBox(width: 6),
                            Text(
                              salon.images.isNotEmpty
                                  ? (l?.tr('salon_edit_cover') ?? 'Modifier')
                                  : (l?.tr('salon_add_cover') ?? 'Ajouter une photo'),
                              style: GoogleFonts.dmSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
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
                title: l?.tr('salon_section_info') ?? 'Informations',
                actionLabel: l?.tr('salon_edit') ?? 'Modifier',
                onAction: () => _showEditInfoSheet(context, salon),
                child: _InfoRows(salon: salon),
              ),

              const SizedBox(height: 8),

              // ── Horaires ──────────────────────────────────────────────────
              _SectionCard(
                title: l?.tr('salon_section_hours') ?? "Horaires d'ouverture",
                actionLabel: l?.tr('salon_edit') ?? 'Modifier',
                onAction: () => _showEditHoursSheet(context, salon),
                child: _HoursRows(workingHours: salon.workingHours),
              ),

              const SizedBox(height: 8),

              // ── Galerie ───────────────────────────────────────────────────
              _GallerySection(salon: salon),

              const SizedBox(height: 8),

              // ── Avant / Après ──────────────────────────────────────────
              _BeforeAfterSection(salonId: salon.id),

              // Services & Packs are managed exclusively from the dedicated
              // "Services & Packs" screen (OwnerServicesScreen) — the inline
              // sections here were a non-synced duplicate, removed to avoid
              // confusion.

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

  Future<void> _pickCoverPhoto(BuildContext context) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    // Compress image
    if (!context.mounted) return;
    final compressOverlay = MediaCompressor.showCompressionOverlay(context, isVideo: false);
    final result = await MediaCompressor.compressImage(File(picked.path));
    compressOverlay.remove();
    if (!context.mounted) return;
    if (result == null) {
      await MediaCompressor.showSizeErrorDialog(context, isVideo: false, afterCompression: false);
      return;
    }
    if (result.compressedSize > MediaCompressor.maxImageSizeBytes) {
      await MediaCompressor.showSizeErrorDialog(context, isVideo: false, afterCompression: true);
      return;
    }

    // Show loading
    if (context.mounted) {
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l?.tr('salon_uploading') ?? 'Upload en cours…')),
      );
    }

    try {
      final file = result.file;
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('salons/${salon.id}/cover_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await storageRef.putFile(
        file,
        SettableMetadata(cacheControl: 'public, max-age=604800'),
      );
      final url = await storageRef.getDownloadURL();

      // Put new cover as first image, keep existing gallery images
      final updatedImages = List<String>.from(salon.images);
      if (updatedImages.isNotEmpty) {
        updatedImages[0] = url;
      } else {
        updatedImages.insert(0, url);
      }
      await DatabaseService().updateSalonImages(salon.id, updatedImages);
      _invalidate();

      if (context.mounted) {
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l?.tr('salon_cover_updated') ?? 'Photo de couverture mise à jour !')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l?.tr('common_error_short') ?? 'Erreur'} : $e')),
        );
      }
    }
  }

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
    final l = AppLocalizations.of(context);
    return Column(
      children: [
        _InfoRow(icon: Icons.storefront_outlined, label: l?.tr('salon_info_name') ?? 'Nom', value: salon.name),
        _InfoRow(icon: Icons.location_city_outlined, label: l?.tr('salon_info_city') ?? 'Ville', value: salon.city),
        _InfoRow(icon: Icons.map_outlined, label: l?.tr('salon_info_address') ?? 'Adresse', value: salon.address),
        _InfoRow(
          icon: Icons.attach_money,
          label: l?.tr('salon_info_currency') ?? 'Devise',
          value: CurrencyHelper.allCurrencies
              .firstWhere((c) => c.code == salon.currency,
                  orElse: () => const CurrencyOption('MAD', 'MAD — Dirham marocain'))
              .label,
        ),
        _InfoRow(
          icon: Icons.description_outlined,
          label: l?.tr('salon_info_description') ?? 'Description',
          value: salon.description.isNotEmpty ? salon.description : '—',
        ),
        if (salon.phone.isNotEmpty)
          _InfoRow(
            icon: Icons.phone_outlined,
            label: l?.tr('salon_info_phone') ?? 'Téléphone',
            value: salon.phone,
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

  static const _dayKeys = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
  static const _dayTrKeys = [
    'day_monday', 'day_tuesday', 'day_wednesday', 'day_thursday',
    'day_friday', 'day_saturday', 'day_sunday',
  ];
  static const _dayFallbacks = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'];

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      children: List.generate(_dayKeys.length, (i) {
        final dayKey = _dayKeys[i];
        final dayLabel = l?.tr(_dayTrKeys[i]) ?? _dayFallbacks[i];
        final data =
            workingHours[dayKey] as Map<String, dynamic>?;
        final isOpen = data?['isOpen'] == true;
        final hours = isOpen
            ? '${data!['open']} – ${data['close']}'
            : (l?.tr('salon_hours_closed') ?? 'Fermé');
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
      }),
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
      final l = AppLocalizations.of(context);
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw l?.tr('salon_edit_info_location_disabled') ?? 'Le service de localisation est désactivé.';

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw l?.tr('salon_edit_info_location_denied') ?? 'Permission de localisation refusée.';
        }
      }
      if (permission == LocationPermission.deniedForever) {
        throw l?.tr('salon_edit_info_location_denied_forever') ?? 'Permission de localisation définitivement refusée. Activez-la dans les paramètres.';
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
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l?.tr('salon_edit_info_required') ?? 'Veuillez remplir les champs obligatoires (nom et ville)'),
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
          final l = AppLocalizations.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                l?.tr('salon_edit_info_geocode_error') ?? 'Impossible de localiser cette adresse. Veuillez utiliser le bouton GPS.',
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
        currency: widget.salon.currency,
        rating: widget.salon.rating,
        reviewCount: widget.salon.reviewCount,
        images: widget.salon.images,
        logoUrl: widget.salon.logoUrl,
        phone: widget.salon.phone,
        workingHours: widget.salon.workingHours,
        services: widget.salon.services,
        serviceCategories: widget.salon.serviceCategories,
        servicePacks: widget.salon.servicePacks,
        latitude: lat,
        longitude: lng,
        closedDates: widget.salon.closedDates,
        createdAt: widget.salon.createdAt,
        socialLinks: widget.salon.socialLinks,
        rewardPointsEnabled: widget.salon.rewardPointsEnabled,
        aiPromosEnabled: widget.salon.aiPromosEnabled,
        aiPromoConfig: widget.salon.aiPromoConfig,
        googleReviewReward: widget.salon.googleReviewReward,
        slug: widget.salon.slug,
        isPremium: widget.salon.isPremium,
        galleryStorageUsed: widget.salon.galleryStorageUsed,
        salonType: widget.salon.salonType,
        timezone: widget.salon.timezone,
      );
      await DatabaseService().saveSalon(updated);
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppLocalizations.of(context)?.tr('common_error_short') ?? 'Erreur'} : $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
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
              l?.tr('salon_edit_info_title') ?? 'Modifier les informations',
              style: GoogleFonts.dmSans(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: AppColors.brand950),
            ),
            const SizedBox(height: 20),

            // Salon name
            _Field(controller: _name, label: l?.tr('salon_edit_info_name') ?? 'Nom du salon'),
            const SizedBox(height: 16),

            // Address header + GPS button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l?.tr('salon_edit_info_address_title') ?? 'Adresse',
                  style: const TextStyle(
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
                        ? (l?.tr('salon_edit_info_gps_loading') ?? 'Localisation...')
                        : (_latitude != null
                            ? (l?.tr('salon_edit_info_gps_captured') ?? 'Position capturée')
                            : (l?.tr('salon_edit_info_gps_use') ?? 'Utiliser ma position')),
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
            _Field(controller: _country, label: l?.tr('salon_edit_info_country') ?? 'Pays'),
            const SizedBox(height: 10),

            // Street
            _Field(controller: _street, label: l?.tr('salon_edit_info_street') ?? 'Adresse (rue et numéro)'),
            const SizedBox(height: 10),

            // City + Postal code side by side
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: _Field(controller: _city, label: l?.tr('salon_edit_info_city') ?? 'Ville *'),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: _Field(
                    controller: _postalCode,
                    label: l?.tr('salon_edit_info_postal') ?? 'Code postal',
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Description
            _Field(
              controller: _description,
              label: l?.tr('salon_edit_info_description') ?? 'Description',
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
                    : Text(l?.tr('common_save') ?? 'Enregistrer',
                        style: const TextStyle(
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
  static const _dayKeys = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
  static const _dayTrKeys = [
    'day_monday', 'day_tuesday', 'day_wednesday', 'day_thursday',
    'day_friday', 'day_saturday', 'day_sunday',
  ];
  static const _dayFallbacks = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'];

  late Map<String, Map<String, dynamic>> _hours;
  late String _timezone;
  late Set<String> _closedDates; // ISO "YYYY-MM-DD" salon-wide closures
  String? _closedDateError; // inline error (e.g. day has booked appointments)
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _hours = {};
    for (final key in _dayKeys) {
      final data = widget.salon.workingHours[key] as Map<String, dynamic>?;
      _hours[key] = {
        'isOpen': data?['isOpen'] ?? false,
        'open': data?['open'] ?? '09:00',
        'close': data?['close'] ?? '18:00',
      };
    }
    // Pre-fill with the salon's stored timezone — fall back to default if
    // the stored value isn't in the curated list (defensive: keeps the
    // dropdown happy even for unusual TZs typed in by hand).
    final stored = widget.salon.timezone;
    final isCurated = TimezoneHelper.commonTimezones
        .any((t) => t.iana == stored);
    _timezone = isCurated ? stored : TimezoneHelper.defaultTimezone;
    // Drop past closures (salon TZ) — once a day passes it's auto-removed here
    // (and persisted on the next save).
    final tzNow = TimezoneHelper.salonNow(_timezone);
    final todayIso = '${tzNow.year}-${tzNow.month.toString().padLeft(2, '0')}'
        '-${tzNow.day.toString().padLeft(2, '0')}';
    _closedDates = Set<String>.from(
        widget.salon.closedDates.where((d) => d.compareTo(todayIso) >= 0));
  }

  Future<void> _addClosedDate() async {
    final now = TimezoneHelper.salonNow(_timezone);
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: today,
      firstDate: today,
      lastDate: DateTime(today.year + 2, 12, 31),
    );
    if (picked == null || !mounted) return;
    final iso =
        '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    if (_closedDates.contains(iso)) return;
    // Refuse to mark a day closed when it already has booked appointments —
    // the owner must cancel/move them first.
    final appts = await DatabaseService()
        .getSalonAppointmentsForDate(widget.salon.id, picked);
    if (!mounted) return;
    if (appts.isNotEmpty) {
      final l = AppLocalizations.of(context);
      setState(() {
        _closedDateError = (l?.tr('salon_closed_days_has_appts') ??
                'Des rendez-vous sont déjà programmés le {date}. Annulez-les avant de fermer ce jour.')
            .replaceAll('{date}', _formatClosedDate(iso));
      });
      return;
    }
    setState(() {
      _closedDateError = null;
      _closedDates.add(iso);
    });
  }

  String _formatClosedDate(String iso) {
    final parts = iso.split('-');
    if (parts.length != 3) return iso;
    return '${parts[2]}/${parts[1]}/${parts[0]}';
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
        phone: widget.salon.phone,
        workingHours: Map<String, dynamic>.from(_hours),
        services: widget.salon.services,
        serviceCategories: widget.salon.serviceCategories,
        servicePacks: widget.salon.servicePacks,
        latitude: widget.salon.latitude,
        longitude: widget.salon.longitude,
        createdAt: widget.salon.createdAt,
        socialLinks: widget.salon.socialLinks,
        currency: widget.salon.currency,
        rewardPointsEnabled: widget.salon.rewardPointsEnabled,
        aiPromosEnabled: widget.salon.aiPromosEnabled,
        aiPromoConfig: widget.salon.aiPromoConfig,
        googleReviewReward: widget.salon.googleReviewReward,
        slug: widget.salon.slug,
        isPremium: widget.salon.isPremium,
        galleryStorageUsed: widget.salon.galleryStorageUsed,
        salonType: widget.salon.salonType,
        timezone: _timezone,
        closedDates: _closedDates.toList(),
      );
      await DatabaseService().saveSalon(updated);
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppLocalizations.of(context)?.tr('common_error_short') ?? 'Erreur'} : $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _buildClosedDatesSection(AppLocalizations? l) {
    final sorted = _closedDates.toList()..sort();
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l?.tr('salon_closed_days_title') ?? 'Jours de fermeture',
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.brand950),
          ),
          const SizedBox(height: 4),
          Text(
            l?.tr('salon_closed_days_hint') ??
                'Jours fériés ou fermetures exceptionnelles. Le salon sera fermé ces jours-là, en plus des horaires hebdomadaires.',
            style: const TextStyle(
                fontSize: 11, color: AppColors.secondary400),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _addClosedDate,
            icon: const Icon(Icons.event_busy_outlined, size: 18),
            label: Text(l?.tr('salon_closed_days_add') ?? 'Ajouter un jour'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.brand600,
              side: const BorderSide(color: AppColors.brand200),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          if (_closedDateError != null) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline,
                    size: 15, color: Color(0xFFDC2626)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(_closedDateError!,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFFDC2626))),
                ),
              ],
            ),
          ],
          if (sorted.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: sorted
                  .map((iso) => Chip(
                        label: Text(_formatClosedDate(iso),
                            style: const TextStyle(fontSize: 12)),
                        backgroundColor: AppColors.brand50,
                        side: const BorderSide(color: AppColors.brand200),
                        deleteIcon: const Icon(Icons.close, size: 15),
                        onDeleted: () =>
                            setState(() => _closedDates.remove(iso)),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, controller) {
        final l = AppLocalizations.of(context);
        return Column(
        children: [
          _SheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l?.tr('salon_edit_hours_title') ?? "Horaires d'ouverture",
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
                      : Text(l?.tr('common_save') ?? 'Enregistrer',
                          style: const TextStyle(
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
              children: [
                // ── Closure days (holidays / exceptional) ──
                _buildClosedDatesSection(l),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 8),
                // Timezone picker — drives how working hours are interpreted
                // by Zayna's availability and the reminders. Same field is
                // captured at onboarding step1; this is the in-app override.
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l?.tr('salon_edit_hours_timezone') ?? 'Fuseau horaire',
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.brand950),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l?.tr('salon_edit_hours_timezone_hint') ??
                            'Vos horaires ci-dessous sont enregistrés dans ce fuseau.',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.secondary400),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _timezone,
                        isExpanded: true,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.public,
                              size: 18, color: AppColors.secondary400),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                                color: AppColors.secondary200),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                                color: AppColors.secondary200),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                                color: AppColors.brand400, width: 2),
                          ),
                        ),
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.secondary800),
                        dropdownColor: Colors.white,
                        items: TimezoneHelper.commonTimezones
                            .map((t) => DropdownMenuItem<String>(
                                  value: t.iana,
                                  child: Text(
                                    t.label,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _timezone = val);
                        },
                      ),
                      const SizedBox(height: 4),
                    ],
                  ),
                ),
                const Divider(height: 16),
                ...List.generate(_dayKeys.length, (i) {
                final dayKey = _dayKeys[i];
                final dayLabel = l?.tr(_dayTrKeys[i]) ?? _dayFallbacks[i];
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
                              label: l?.tr('salon_edit_hours_opening') ?? 'Ouverture',
                              time: data['open'] as String,
                              onTap: () => _pickTime(dayKey, 'open'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _TimeButton(
                              label: l?.tr('salon_edit_hours_closing') ?? 'Fermeture',
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
              }),
              ],
            ),
          ),
        ],
      );
      },
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

// Service form dialog moved to widgets/service_form_dialog.dart (ServiceFormDialog)


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
  double _uploadProgress = 0;
  int get _maxStorageBytes => widget.salon.isPremium
      ?  5 * 1024 * 1024 * 1024   //  5 GB premium (images + videos)
      :  3 * 1024 * 1024 * 1024;  //  3 GB standard (images only)

  bool get _isPremium => widget.salon.isPremium;

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

  bool _isVideo(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.mp4') || lower.contains('.mov') || lower.contains('.avi') || lower.contains('.webm') || lower.contains('video%2F');
  }

  Future<void> _addMedia({bool video = false}) async {
    final l = AppLocalizations.of(context);

    if (video && !_isPremium) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l?.tr('gallery_premium_required') ?? 'Les vidéos sont disponibles avec le plan Business')),
      );
      return;
    }

    // Check storage limit
    final currentUsage = widget.salon.galleryStorageUsed;
    if (currentUsage >= _maxStorageBytes) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.cloud_off_rounded, color: Colors.orange, size: 48),
            title: const Text('Stockage plein'),
            content: Text('Vous avez atteint la limite de ${widget.salon.isPremium ? "5" : "3"} GB. Supprimez des fichiers pour en ajouter.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
            ],
          ),
        );
      }
      return;
    }

    File? file;
    String ext;

    final picker = ImagePicker();
    XFile? picked;
    if (video) {
      picked = await picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(seconds: 60),
      );
    } else {
      picked = await picker.pickImage(source: ImageSource.gallery);
    }
    if (picked == null) return;

    // Compress media
    if (!mounted) return;
    final compressOverlay = MediaCompressor.showCompressionOverlay(context, isVideo: video);
    final result = video
        ? await MediaCompressor.compressVideo(File(picked.path))
        : await MediaCompressor.compressImage(File(picked.path));
    compressOverlay.remove();
    if (!mounted) return;
    if (result == null) {
      await MediaCompressor.showSizeErrorDialog(context, isVideo: video, afterCompression: false);
      return;
    }
    final maxSize = video ? MediaCompressor.maxVideoSizeBytes : MediaCompressor.maxImageSizeBytes;
    if (result.compressedSize > maxSize) {
      await MediaCompressor.showSizeErrorDialog(context, isVideo: video, afterCompression: true);
      return;
    }

    file = result.file;
    ext = video ? file.path.split('.').last : 'jpg';

    setState(() { _uploading = true; _uploadProgress = 0; });
    try {
      final fileSize = await file.length();
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('salons/${widget.salon.id}/gallery_${DateTime.now().millisecondsSinceEpoch}.$ext');

      // Cache-Control: 7 days — clients revisiting the gallery reuse local cache
      // instead of re-downloading the same videos/images (main egress saver).
      final uploadTask = storageRef.putFile(
        file,
        SettableMetadata(cacheControl: 'public, max-age=604800'),
      );
      uploadTask.snapshotEvents.listen((snap) {
        if (mounted) {
          setState(() => _uploadProgress = snap.bytesTransferred / snap.totalBytes);
        }
      });

      await uploadTask;
      final url = await storageRef.getDownloadURL();
      _images.add(url);
      await DatabaseService().updateSalonImages(widget.salon.id, _images);

      // Update storage usage
      final newUsage = currentUsage + fileSize;
      await DatabaseService().updateSalonField(widget.salon.id, 'galleryStorageUsed', newUsage);

      setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l?.tr('common_error_short') ?? 'Erreur'} : $e')),
        );
      }
    } finally {
      if (mounted) setState(() { _uploading = false; _uploadProgress = 0; });
    }
  }

  Future<void> _deleteImage(int index) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l?.tr('salon_gallery_delete_title') ?? 'Supprimer cette photo ?'),
        content: Text(l?.tr('salon_gallery_delete_message') ?? 'Cette action est irréversible.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l?.tr('common_cancel') ?? 'Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l?.tr('common_delete') ?? 'Supprimer',
                style: const TextStyle(color: Colors.red)),
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
          SnackBar(content: Text('${AppLocalizations.of(context)?.tr('common_error_short') ?? 'Erreur'} : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
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
                  (l?.tr('salon_gallery_title') ?? 'Galerie ({count})').replaceAll('{count}', '${_images.length}'),
                  style: GoogleFonts.dmSans(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.brand950,
                  ),
                ),
              ),
              if (_uploading)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_uploadProgress > 0)
                      Text('${(_uploadProgress * 100).toInt()}%',
                          style: const TextStyle(fontSize: 11, color: AppColors.brand600, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 6),
                    const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brand600),
                    ),
                  ],
                )
              else
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'image') _addMedia(video: false);
                    if (value == 'video') _addMedia(video: true);
                  },
                  icon: const Icon(Icons.add_circle_outline, color: AppColors.brand600, size: 22),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'image',
                      child: Row(
                        children: [
                          const Icon(Icons.photo_outlined, size: 18, color: AppColors.brand600),
                          const SizedBox(width: 10),
                          Text(l?.tr('gallery_add_photo') ?? 'Photo'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'video',
                      enabled: _isPremium,
                      child: Row(
                        children: [
                          Icon(Icons.videocam_outlined, size: 18,
                              color: _isPremium ? AppColors.brand600 : AppColors.secondary300),
                          const SizedBox(width: 10),
                          Text(
                            l?.tr('gallery_add_video') ?? 'Vidéo',
                            style: TextStyle(color: _isPremium ? null : AppColors.secondary300),
                          ),
                          if (!_isPremium) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(4)),
                              child: const Text('Business', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFFD97706))),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
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
                    l?.tr('salon_gallery_empty') ?? 'Aucune photo',
                    style: const TextStyle(
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
                itemBuilder: (_, i) {
                  final isVid = _isVideo(_images[i]);
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: isVid
                            ? Container(
                                width: 100, height: 100,
                                color: AppColors.brand950,
                                child: const Center(
                                  child: Icon(Icons.play_circle_outline, size: 36, color: Colors.white70),
                                ),
                              )
                            : Image.network(
                                _images[i],
                                width: 100, height: 100,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 100, height: 100,
                                  color: AppColors.secondary100,
                                  child: const Icon(Icons.broken_image_outlined, color: AppColors.secondary300),
                                ),
                              ),
                      ),
                      if (isVid)
                        Positioned(
                          bottom: 4, left: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                            child: const Text('VIDEO', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white)),
                          ),
                        ),
                      Positioned(
                        top: 4, right: 4,
                        child: GestureDetector(
                          onTap: () => _deleteImage(i),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                            child: const Icon(Icons.close, size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  );
                },
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
      final beforePicked = await picker.pickImage(source: ImageSource.gallery);
      if (beforePicked == null || !mounted) return;

      // Pick "after" image
      if (mounted) {
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l?.tr('salon_before_after_select_after') ?? 'Sélectionnez maintenant la photo "Après"'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      final afterPicked = await picker.pickImage(source: ImageSource.gallery);
      if (afterPicked == null || !mounted) return;

      // Compress both images
      if (!mounted) return;
      final compressOverlay = MediaCompressor.showCompressionOverlay(context, isVideo: false);
      final beforeResult = await MediaCompressor.compressImage(File(beforePicked.path));
      final afterResult = await MediaCompressor.compressImage(File(afterPicked.path));
      compressOverlay.remove();
      if (!mounted) return;
      if (beforeResult == null || afterResult == null) {
        await MediaCompressor.showSizeErrorDialog(context, isVideo: false, afterCompression: false);
        return;
      }
      if (beforeResult.compressedSize > MediaCompressor.maxImageSizeBytes ||
          afterResult.compressedSize > MediaCompressor.maxImageSizeBytes) {
        await MediaCompressor.showSizeErrorDialog(context, isVideo: false, afterCompression: true);
        return;
      }

      // Ask for a label
      final labelCtrl = TextEditingController();
      final l2 = AppLocalizations.of(context);
      final label = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(l2?.tr('salon_before_after_label_title') ?? 'Nom du soin'),
          content: TextField(
            controller: labelCtrl,
            decoration: InputDecoration(
              hintText: l2?.tr('salon_before_after_label_hint') ?? 'Ex: Coloration, Lissage…',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l2?.tr('common_cancel') ?? 'Annuler'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, labelCtrl.text.trim()),
              child: Text(l2?.tr('salon_before_after_validate') ?? 'Valider'),
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
      await beforeRef.putFile(
        beforeResult.file,
        SettableMetadata(cacheControl: 'public, max-age=604800'),
      );
      final beforeUrl = await beforeRef.getDownloadURL();

      // Upload after
      final afterRef = FirebaseStorage.instance
          .ref()
          .child('$storageBase/after_$ts.jpg');
      await afterRef.putFile(
        afterResult.file,
        SettableMetadata(cacheControl: 'public, max-age=604800'),
      );
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
          SnackBar(content: Text('${AppLocalizations.of(context)?.tr('common_error_short') ?? 'Erreur'} : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _deleteItem(String docId, String beforeUrl, String afterUrl) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l?.tr('salon_before_after_delete_title') ?? 'Supprimer cet avant/après ?'),
        content: Text(l?.tr('salon_before_after_delete_message') ?? 'Les deux photos seront supprimées.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l?.tr('common_cancel') ?? 'Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l?.tr('common_delete') ?? 'Supprimer',
                style: const TextStyle(color: Colors.red)),
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
          SnackBar(content: Text('${AppLocalizations.of(context)?.tr('common_error_short') ?? 'Erreur'} : $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
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
                  l?.tr('salon_before_after_title') ?? 'Avant / Après',
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
                  child: Text(
                    l?.tr('salon_gallery_add') ?? '+ Ajouter',
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
                        l?.tr('salon_before_after_empty') ?? 'Aucun avant/après',
                        style: const TextStyle(
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
                          clipBehavior: Clip.hardEdge,
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
                                    Text(l?.tr('salon_before_after_before') ?? 'Avant',
                                        style: const TextStyle(
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
                                    Text(l?.tr('salon_before_after_after') ?? 'Après',
                                        style: const TextStyle(
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

