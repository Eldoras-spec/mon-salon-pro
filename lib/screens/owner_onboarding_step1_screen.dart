import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:latlong2/latlong.dart';

import '../theme/app_colors.dart';
import '../services/auth_service.dart';
import '../widgets/custom_button.dart';
import '../services/app_localizations.dart';
import 'owner_onboarding_step2_screen.dart';

class OwnerOnboardingStep1Screen extends StatefulWidget {
  const OwnerOnboardingStep1Screen({super.key});

  @override
  State<OwnerOnboardingStep1Screen> createState() =>
      _OwnerOnboardingStep1ScreenState();
}

class _OwnerOnboardingStep1ScreenState
    extends State<OwnerOnboardingStep1Screen> {
  final _salonNameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _instagramController = TextEditingController();
  final _facebookController = TextEditingController();
  final _tiktokController = TextEditingController();
  final _whatsappController = TextEditingController();

  // Structured address fields
  final _countryController = TextEditingController(text: 'Maroc');
  final _streetController = TextEditingController();
  final _cityController = TextEditingController();
  final _postalCodeController = TextEditingController();

  int _charCount = 0;
  final int _maxChars = 500;
  double? _latitude;
  double? _longitude;
  bool _isGettingLocation = false;

  @override
  void initState() {
    super.initState();
    _descriptionController.addListener(() {
      setState(() {
        _charCount = _descriptionController.text.length;
      });
    });
  }

  @override
  void dispose() {
    _salonNameController.dispose();
    _descriptionController.dispose();
    _instagramController.dispose();
    _facebookController.dispose();
    _tiktokController.dispose();
    _whatsappController.dispose();
    _countryController.dispose();
    _streetController.dispose();
    _cityController.dispose();
    _postalCodeController.dispose();
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

        final street = (p.street ?? '').trim();
        final city = p.locality ?? p.administrativeArea ?? '';
        final postal = p.postalCode ?? '';
        final country = p.country ?? 'Maroc';

        setState(() {
          _latitude = position.latitude;
          _longitude = position.longitude;
          _streetController.text = street;
          _cityController.text = city;
          _postalCodeController.text = postal;
          _countryController.text = country.isNotEmpty ? country : 'Maroc';
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

  Future<void> _handleNext() async {
    final name = _salonNameController.text.trim();
    final city = _cityController.text.trim();

    final l = AppLocalizations.of(context);
    if (name.isEmpty || city.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l?.tr('salon_edit_info_required') ?? 'Veuillez remplir les champs obligatoires (nom et ville)'),
        ),
      );
      return;
    }

    // Build full address string
    final addressParts = [
      if (_streetController.text.trim().isNotEmpty) _streetController.text.trim(),
      if (_postalCodeController.text.trim().isNotEmpty) _postalCodeController.text.trim(),
      city,
      if (_countryController.text.trim().isNotEmpty) _countryController.text.trim(),
    ];
    final fullAddress = addressParts.join(', ');

    // Forward geocoding: convert address to coordinates if GPS wasn't used
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
      // If still no coordinates, require GPS
      if (lat == null || lng == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l?.tr('salon_edit_info_geocode_error') ?? 'Impossible de localiser cette adresse. Veuillez utiliser le bouton GPS.',
            ),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }
    }

    final String ownerId = AuthService().currentUserId ?? '';

    final salonData = {
      'ownerId': ownerId,
      'name': name,
      'address': fullAddress,
      'description': _descriptionController.text.trim(),
      'city': city,
      'country': _countryController.text.trim().isNotEmpty
          ? _countryController.text.trim()
          : 'Maroc',
      'category': 'Beauté',
      'latitude': lat,
      'longitude': lng,
      'socialLinks': {
        'instagram': _instagramController.text.trim().replaceAll('@', ''),
        'facebook': _facebookController.text.trim().replaceAll('@', ''),
        'tiktok': _tiktokController.text.trim().replaceAll('@', ''),
        'whatsapp': _whatsappController.text.trim(),
      },
    };

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OwnerOnboardingStep2Screen(salonData: salonData),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: _buildFormSection(),
      ),
    );
  }

  Widget _buildMapPlaceholder({required bool hasLocation}) {
    return Container(
      color: AppColors.secondary100,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              hasLocation ? Icons.map_outlined : Icons.add_location_alt_outlined,
              size: 32,
              color: AppColors.secondary400,
            ),
            const SizedBox(height: 8),
            Text(
              hasLocation
                  ? 'Aperçu carte indisponible'
                  : 'Utilisez votre position ou remplissez l\'adresse',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.secondary400,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddressField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool required = false,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    int? maxLength,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.secondary700,
              ),
            ),
            if (required) ...[
              const SizedBox(width: 4),
              const Text(
                '*',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.brand600,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            maxLength: maxLength,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.secondary800,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(
                color: AppColors.secondary400,
                fontSize: 13,
              ),
              prefixIcon: Icon(icon, size: 18, color: AppColors.secondary400),
              counterText: '',
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: AppColors.secondary200),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: AppColors.secondary200),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                    color: AppColors.brand400, width: 2),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFormSection() {
    final l = AppLocalizations.of(context);
    return Container(
      color: Colors.white,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Nav Row
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.secondary50,
                          border: Border.all(color: AppColors.secondary100),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.arrow_back,
                          size: 12,
                          color: AppColors.secondary500,
                        ),
                      ),
                      label: Text(
                        l?.tr('onboarding_back') ?? 'Retour',
                        style: const TextStyle(
                          color: AppColors.secondary500,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Progress
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      l?.tr('onboarding_step1_title') ?? 'Détails du salon',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.brand900,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.brand50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        l?.tr('onboarding_step1_step') ?? 'Étape 2 sur 6',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.brand600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AppColors.brand500,
                          borderRadius: BorderRadius.horizontal(
                            left: Radius.circular(3),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                        child: Container(
                            height: 6, color: AppColors.secondary100)),
                    const SizedBox(width: 2),
                    Expanded(
                        child: Container(
                            height: 6, color: AppColors.secondary100)),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Container(
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AppColors.secondary100,
                          borderRadius: BorderRadius.horizontal(
                            right: Radius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // Header
                Text(
                  l?.tr('onboarding_step1_subtitle') ?? 'Parlez-nous de votre salon',
                  style: GoogleFonts.dmSans(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: AppColors.brand950,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Commencez par ajouter le nom de votre salon, sa localisation et une courte description. C\'est ce que vos clients verront en premier.',
                  style:
                      TextStyle(color: AppColors.secondary500, height: 1.5),
                ),
                const SizedBox(height: 32),

                // ── Salon Name ───────────────────────────────────────────────
                _buildAddressField(
                  controller: _salonNameController,
                  label: l?.tr('onboarding_step1_name') ?? 'Nom du salon',
                  hint: 'ex. Luxe Beauty Lounge',
                  icon: Icons.store_mall_directory_outlined,
                  required: true,
                ),
                const SizedBox(height: 28),

                // ── Address section ──────────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      l?.tr('onboarding_step1_address') ?? 'Adresse',
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
                const SizedBox(height: 14),

                // Country
                _buildAddressField(
                  controller: _countryController,
                  label: l?.tr('salon_edit_info_country') ?? 'Pays',
                  hint: 'Maroc',
                  icon: Icons.public_outlined,
                ),
                const SizedBox(height: 14),

                // Street
                _buildAddressField(
                  controller: _streetController,
                  label: l?.tr('salon_edit_info_street') ?? 'Adresse (rue et numéro)',
                  hint: 'ex. 12 Rue Mohammed V',
                  icon: Icons.signpost_outlined,
                ),
                const SizedBox(height: 14),

                // City + Postal code side by side
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: _buildAddressField(
                        controller: _cityController,
                        label: l?.tr('salon_edit_info_city') ?? 'Ville *',
                        hint: 'ex. Casablanca',
                        icon: Icons.location_city_outlined,
                        required: true,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: _buildAddressField(
                        controller: _postalCodeController,
                        label: l?.tr('salon_edit_info_postal') ?? 'Code postal',
                        hint: 'ex. 20000',
                        icon: Icons.markunread_mailbox_outlined,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        maxLength: 10,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Map preview (shown when GPS coords are available)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    height: 130,
                    child: _latitude != null && _longitude != null
                        ? IgnorePointer(
                            child: FlutterMap(
                              options: MapOptions(
                                initialCenter: LatLng(_latitude!, _longitude!),
                                initialZoom: 15,
                                interactionOptions: const InteractionOptions(
                                  flags: InteractiveFlag.none,
                                ),
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate:
                                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                  userAgentPackageName: 'com.blagence.monsalon',
                                ),
                                MarkerLayer(
                                  markers: [
                                    Marker(
                                      point: LatLng(_latitude!, _longitude!),
                                      width: 32,
                                      height: 32,
                                      child: const Icon(
                                        Icons.location_on,
                                        color: AppColors.brand600,
                                        size: 32,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          )
                        : _buildMapPlaceholder(hasLocation: false),
                  ),
                ),
                const SizedBox(height: 28),

                // ── Description ──────────────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      l?.tr('onboarding_step1_description') ?? 'Description',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.secondary700,
                      ),
                    ),
                    Text(
                      '$_charCount/$_maxChars',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: _charCount > _maxChars
                            ? Colors.red
                            : AppColors.secondary400,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _descriptionController,
                    maxLines: 4,
                    maxLength: _maxChars,
                    decoration: InputDecoration(
                      hintText:
                          'Décrivez ce qui rend votre salon unique...',
                      filled: true,
                      fillColor: Colors.white,
                      counterText: '',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: AppColors.secondary200,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: AppColors.secondary200,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: AppColors.brand400,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // ── Social media ─────────────────────────────────────────────
                Row(
                  children: [
                    Text(
                      l?.tr('onboarding_step1_social') ?? 'Réseaux sociaux',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.secondary700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.secondary100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        l?.tr('onboarding_step1_optional') ?? 'Optionnel',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.secondary500),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  l?.tr('onboarding_step1_social_hint') ?? 'Permet aux clients de vous retrouver facilement.',
                  style:
                      TextStyle(fontSize: 12, color: AppColors.secondary400),
                ),
                const SizedBox(height: 16),
                _buildSocialField(
                  controller: _instagramController,
                  hint: 'votre_salon',
                  prefix: 'instagram.com/',
                  icon: FontAwesomeIcons.instagram,
                  color: const Color(0xFFE1306C),
                ),
                const SizedBox(height: 12),
                _buildSocialField(
                  controller: _facebookController,
                  hint: 'votre_salon',
                  prefix: 'facebook.com/',
                  icon: FontAwesomeIcons.facebookF,
                  color: const Color(0xFF1877F2),
                ),
                const SizedBox(height: 12),
                _buildSocialField(
                  controller: _tiktokController,
                  hint: 'votre_salon',
                  prefix: 'tiktok.com/@',
                  icon: FontAwesomeIcons.tiktok,
                  color: Colors.black87,
                ),
                const SizedBox(height: 12),
                _buildSocialField(
                  controller: _whatsappController,
                  hint: '212661234567',
                  prefix: 'wa.me/',
                  icon: FontAwesomeIcons.whatsapp,
                  color: const Color(0xFF25D366),
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                ),
                const SizedBox(height: 32),

                // Actions
                CustomButton(
                  text: l?.tr('onboarding_step1_next') ?? 'Étape suivante',
                  onPressed: _handleNext,
                  icon: Icons.arrow_forward,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSocialField({
    required TextEditingController controller,
    required String hint,
    required String prefix,
    required IconData icon,
    required Color color,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: const TextStyle(fontSize: 13, color: AppColors.secondary800),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
            const TextStyle(color: AppColors.secondary400, fontSize: 13),
        prefixIcon: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FaIcon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Text(
                prefix,
                style: TextStyle(
                    fontSize: 12,
                    color: AppColors.secondary400,
                    fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
        prefixIconConstraints:
            const BoxConstraints(minWidth: 0, minHeight: 0),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.secondary200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.secondary200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: AppColors.brand400, width: 2),
        ),
      ),
    );
  }
}
