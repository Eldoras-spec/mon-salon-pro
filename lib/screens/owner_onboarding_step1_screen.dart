import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:latlong2/latlong.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../theme/app_colors.dart';
import '../services/auth_service.dart';
import '../widgets/custom_button.dart';
import '../widgets/country_phone_field.dart';
import '../widgets/whatsapp_otp_dialog.dart';
import '../services/app_localizations.dart';
import '../services/plan_config.dart';
import '../utils/currency_helper.dart';
import '../utils/timezone_helper.dart';
import '../services/onboarding_progress.dart';
import 'owner_onboarding_plan_screen.dart';

class OwnerOnboardingStep1Screen extends StatefulWidget {
  const OwnerOnboardingStep1Screen({super.key, this.initialData});

  /// Saved step-1 raw fields to re-fill the form when resuming onboarding.
  final Map<String, dynamic>? initialData;

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
  String? _whatsappE164;
  String? _verifiedWhatsappE164; // last WA number successfully verified this session
  bool _isProcessingNext = false; // guards _handleNext against re-entry
  Timer? _autosaveTimer; // debounces draft autosave on field edits

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
  String _selectedCurrency = 'MAD';
  String _selectedSalonType = 'femme';
  String _selectedTimezone = TimezoneHelper.defaultTimezone;

  @override
  void initState() {
    super.initState();
    // Restore a saved draft (resume) FIRST — before wiring listeners — so
    // setting controller text doesn't fire the charCount setState during
    // initState, and so auto-detect doesn't override the saved currency/TZ.
    final saved = widget.initialData;
    if (saved != null) _restoreFromDraft(saved);

    _descriptionController.addListener(() {
      setState(() {
        _charCount = _descriptionController.text.length;
      });
    });
    // Auto-detect currency via GeoJS (IP geolocation) only when not restored.
    if (saved == null || saved['currency'] == null) {
      _autoDetectCurrency();
    }
    // Prime with device TZ then refine via GeoJS — unless restored.
    if (saved == null || saved['timezone'] == null) {
      _selectedTimezone = TimezoneHelper.detectDeviceTimezone();
      _autoDetectTimezone();
    }
    // Autosave the form (debounced) so a reboot mid-step doesn't lose data.
    for (final c in [
      _salonNameController,
      _descriptionController,
      _instagramController,
      _facebookController,
      _tiktokController,
      _countryController,
      _streetController,
      _cityController,
      _postalCodeController,
    ]) {
      c.addListener(_scheduleAutosave);
    }
  }

  void _restoreFromDraft(Map<String, dynamic> d) {
    String s(String k) => (d[k] as String?) ?? '';
    _salonNameController.text = s('name');
    if (d['country'] is String && (d['country'] as String).isNotEmpty) {
      _countryController.text = d['country'] as String;
    }
    _streetController.text = s('street');
    _cityController.text = s('city');
    _postalCodeController.text = s('postal');
    _descriptionController.text = s('description');
    _instagramController.text = s('instagram');
    _facebookController.text = s('facebook');
    _tiktokController.text = s('tiktok');
    if (d['currency'] is String) _selectedCurrency = d['currency'] as String;
    if (d['salonType'] is String) _selectedSalonType = d['salonType'] as String;
    if (d['timezone'] is String) _selectedTimezone = d['timezone'] as String;
    if (d['whatsapp'] is String && (d['whatsapp'] as String).isNotEmpty) {
      _whatsappE164 = d['whatsapp'] as String;
    }
    if (d['latitude'] is num) _latitude = (d['latitude'] as num).toDouble();
    if (d['longitude'] is num) _longitude = (d['longitude'] as num).toDouble();
    _charCount = _descriptionController.text.length;
  }

  Map<String, dynamic> _buildStep1Raw() => {
        'name': _salonNameController.text.trim(),
        'country': _countryController.text.trim(),
        'street': _streetController.text.trim(),
        'city': _cityController.text.trim(),
        'postal': _postalCodeController.text.trim(),
        'description': _descriptionController.text.trim(),
        'instagram': _instagramController.text.trim(),
        'facebook': _facebookController.text.trim(),
        'tiktok': _tiktokController.text.trim(),
        'currency': _selectedCurrency,
        'salonType': _selectedSalonType,
        'timezone': _selectedTimezone,
        if (_whatsappE164 != null) 'whatsapp': _whatsappE164,
        if (_latitude != null) 'latitude': _latitude,
        if (_longitude != null) 'longitude': _longitude,
      };

  void _scheduleAutosave() {
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(milliseconds: 1500), () {
      OnboardingProgress.save(
        step: 1,
        stepName: 'details',
        step1Raw: _buildStep1Raw(),
      );
    });
  }

  Future<void> _autoDetectCurrency() async {
    try {
      final detected = await PlanConfig.detectCurrencyByIp();
      if (!mounted) return;
      // Only overwrite if the user hasn't already interacted with the picker.
      if (_selectedCurrency == 'MAD') {
        setState(() => _selectedCurrency = detected);
      }
    } catch (_) { /* best effort, fallback to MAD */ }
  }

  Future<void> _autoDetectTimezone() async {
    try {
      final deviceTz = TimezoneHelper.detectDeviceTimezone();
      final ipTz = await TimezoneHelper.detectTimezoneByIp();
      if (!mounted) return;
      // Only overwrite if the user hasn't picked manually since init —
      // we compare against the device-detection value (the priming default).
      if (_selectedTimezone == deviceTz && ipTz != deviceTz) {
        setState(() => _selectedTimezone = ipTz);
      }
    } catch (_) { /* best effort, keep device fallback */ }
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _salonNameController.dispose();
    _descriptionController.dispose();
    _instagramController.dispose();
    _facebookController.dispose();
    _tiktokController.dispose();
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

  /// Pre-checks WA availability for an owner account, then shows the
  /// WhatsApp OTP dialog. On success, persists the WhatsApp number on
  /// the user doc with `whatsappVerified: true`. Returns true on success,
  /// false on cancel / availability conflict / OTP failure.
  Future<bool> _verifyWhatsapp() async {
    final whatsapp = _whatsappE164;
    if (whatsapp == null) return false;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    // Pre-check: same WhatsApp + same userType already exists?
    bool needsClaim = false;
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('checkWhatsappAvailable')
          .call({'whatsapp': whatsapp, 'userType': 'owner'});
      final available = (res.data is Map) && res.data['available'] == true;
      if (!available) {
        if (!mounted) return false;
        // Number is already linked to another pro account — offer the
        // claim flow: send an OTP, on success the CF transfers the WA
        // from the old user doc to the current one atomically.
        final l = AppLocalizations.of(context);
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l?.tr('onboarding_whatsapp_claim_title') ??
                'Numéro déjà utilisé'),
            content: Text(l?.tr('onboarding_whatsapp_claim_message') ??
                'Ce numéro WhatsApp est associé à un autre compte pro. Si vous en êtes le propriétaire, nous vous enverrons un code pour le rattacher à votre compte. L\'autre compte perdra l\'accès à ce numéro.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l?.tr('common_cancel') ?? 'Annuler'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l?.tr('onboarding_whatsapp_claim_cta') ??
                    'Recevoir le code'),
              ),
            ],
          ),
        );
        if (confirmed != true) return false;
        if (!mounted) return false;
        needsClaim = true;
      }
    } catch (_) { /* non-fatal — proceed to OTP */ }

    if (needsClaim) {
      // Claim flow: CF claimWhatsappOwnership atomically verifies the
      // OTP, releases the WA from the previous user doc, and writes it
      // on the current auth user's doc — no separate write needed.
      final result = await WhatsappOtpDialog.showForClaim(context, whatsapp);
      if (result == null) return false;
      _verifiedWhatsappE164 = whatsapp;
      return true;
    }

    final result = await WhatsappOtpDialog.show(context, whatsapp);
    if (result == null) return false; // user cancelled or OTP failed

    // Mark verified IMMEDIATELY before any further awaits to prevent a
    // concurrent _handleNext from re-entering the OTP flow.
    _verifiedWhatsappE164 = whatsapp;

    // Persist the WhatsApp number on the user doc.
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({'whatsapp': whatsapp, 'whatsappVerified': true});
    } catch (_) { /* non-fatal */ }

    return true;
  }

  Future<void> _handleNext() async {
    if (_isProcessingNext) return;
    _isProcessingNext = true;
    try {
      await _handleNextInner();
    } finally {
      _isProcessingNext = false;
    }
  }

  Future<void> _handleNextInner() async {
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

    if (_whatsappE164 == null || _whatsappE164!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l?.tr('onboarding_whatsapp_required') ?? 'Le numéro WhatsApp est obligatoire'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    // Verify the WhatsApp number via WA OTP if not already verified this session.
    if (_verifiedWhatsappE164 != _whatsappE164) {
      final verified = await _verifyWhatsapp();
      if (!verified) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l?.tr('onboarding_whatsapp_verify_required') ??
                'La vérification WhatsApp est obligatoire. Complétez-la pour continuer.'),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }
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
      'currency': _selectedCurrency,
      'salonType': _selectedSalonType,
      'timezone': _selectedTimezone,
      'latitude': lat,
      'longitude': lng,
      'socialLinks': {
        'instagram': _instagramController.text.trim().replaceAll('@', ''),
        'facebook': _facebookController.text.trim().replaceAll('@', ''),
        'tiktok': _tiktokController.text.trim().replaceAll('@', ''),
        'whatsapp': _whatsappE164 ?? '',
      },
    };

    // Checkpoint: step-1 done → resume point is the Plan screen.
    await OnboardingProgress.save(
      step: 2,
      stepName: 'plan',
      data: salonData,
      step1Raw: _buildStep1Raw(),
    );

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OwnerOnboardingPlanScreen(salonData: salonData),
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
                // Nav Row — "Retour" at this stage means cancelling the
                // signup: the user only has a Firebase Auth account, no
                // salon yet, and the previous screens were pushed with
                // pushReplacement so a plain Navigator.pop lands on a
                // black screen. Trigger the same flow as the explicit
                // "Annuler mon inscription" button (delete user + go home).
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: _handleCancelSignup,
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

                // Salon Type
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l?.tr('onboarding_salon_type') ?? 'Type de salon',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.secondary700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _SalonTypeChip(
                          label: l?.tr('salon_type_femme') ?? 'Femme',
                          icon: Icons.female,
                          selected: _selectedSalonType == 'femme',
                          onTap: () {
                            setState(() => _selectedSalonType = 'femme');
                            _scheduleAutosave();
                          },
                        ),
                        const SizedBox(width: 8),
                        _SalonTypeChip(
                          label: l?.tr('salon_type_homme') ?? 'Homme',
                          icon: Icons.male,
                          selected: _selectedSalonType == 'homme',
                          onTap: () {
                            setState(() => _selectedSalonType = 'homme');
                            _scheduleAutosave();
                          },
                        ),
                        const SizedBox(width: 8),
                        _SalonTypeChip(
                          label: l?.tr('salon_type_mixte') ?? 'Mixte',
                          icon: Icons.people,
                          selected: _selectedSalonType == 'mixte',
                          onTap: () {
                            setState(() => _selectedSalonType = 'mixte');
                            _scheduleAutosave();
                          },
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Currency
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l?.tr('onboarding_currency') ?? 'Devise',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.secondary700,
                      ),
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
                      child: DropdownButtonFormField<String>(
                        value: _selectedCurrency,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.attach_money,
                              size: 18, color: AppColors.secondary400),
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
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.secondary800,
                        ),
                        dropdownColor: Colors.white,
                        icon: const Icon(Icons.keyboard_arrow_down,
                            color: AppColors.secondary400),
                        items: CurrencyHelper.allCurrencies
                            .map((c) => DropdownMenuItem<String>(
                                  value: c.code,
                                  child: Text(
                                    c.label,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: c.code == _selectedCurrency
                                          ? AppColors.brand600
                                          : AppColors.secondary800,
                                      fontWeight: c.code == _selectedCurrency
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedCurrency = val);
                            _scheduleAutosave();
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Timezone — auto-detected from device, owner can override
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l?.tr('onboarding_timezone') ?? 'Fuseau horaire',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.secondary700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l?.tr('onboarding_timezone_hint') ??
                          'Utilisé pour vos horaires d\'ouverture et les rappels.',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.secondary400,
                      ),
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
                      child: DropdownButtonFormField<String>(
                        value: _selectedTimezone,
                        isExpanded: true,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.schedule,
                              size: 18, color: AppColors.secondary400),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                                color: AppColors.secondary200),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                                color: AppColors.secondary200),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                                color: AppColors.brand400, width: 2),
                          ),
                        ),
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.secondary800,
                        ),
                        dropdownColor: Colors.white,
                        icon: const Icon(Icons.keyboard_arrow_down,
                            color: AppColors.secondary400),
                        items: TimezoneHelper.commonTimezones
                            .map((t) => DropdownMenuItem<String>(
                                  value: t.iana,
                                  child: Text(
                                    t.label,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: t.iana == _selectedTimezone
                                          ? AppColors.brand600
                                          : AppColors.secondary800,
                                      fontWeight: t.iana == _selectedTimezone
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedTimezone = val);
                            _scheduleAutosave();
                          }
                        },
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

                // ── WhatsApp (required, WA OTP-verified) ─────────────
                Row(
                  children: [
                    Text(
                      l?.tr('onboarding_step1_whatsapp') ?? 'Numéro WhatsApp',
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
                        color: const Color(0xFFFFE4E6),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        l?.tr('onboarding_step1_required') ?? 'Obligatoire',
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFFBE123C)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  l?.tr('onboarding_step1_whatsapp_hint') ??
                      'Vérifié par WhatsApp. Utilisé pour recevoir les notifications de réservation et sécuriser votre compte.',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.secondary400),
                ),
                const SizedBox(height: 16),
                CountryPhoneField(
                  initialE164: _whatsappE164,
                  onChanged: (e164) {
                    _whatsappE164 = e164;
                    // Changing the WA number invalidates the previous verification.
                    if (_verifiedWhatsappE164 != e164) _verifiedWhatsappE164 = null;
                    _scheduleAutosave();
                  },
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
                const SizedBox(height: 32),

                // Actions
                CustomButton(
                  text: l?.tr('onboarding_step1_next') ?? 'Étape suivante',
                  onPressed: _handleNext,
                  icon: Icons.arrow_forward,
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _handleCancelSignup,
                  child: Text(
                    l?.tr('onboarding_cancel_signup') ?? 'Annuler mon inscription',
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Deletes the in-progress Firebase Auth user and returns to the login
  /// screen. Used when the owner abandons the onboarding before OTP
  /// validation so their orphan account doesn't persist.
  Future<void> _handleCancelSignup() async {
    final l = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l?.tr('onboarding_cancel_title') ?? 'Annuler l\'inscription ?'),
        content: Text(l?.tr('onboarding_cancel_message')
            ?? 'Votre compte en cours sera supprimé définitivement. Cette action ne peut pas être annulée.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l?.tr('common_cancel') ?? 'Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              l?.tr('onboarding_cancel_confirm') ?? 'Oui, supprimer',
              style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final user = FirebaseAuth.instance.currentUser;
    bool deleted = false;
    try {
      await user?.delete();
      deleted = true;
    } catch (_) {
      try {
        await FirebaseFunctions.instance.httpsCallable('forceDeleteSelf').call();
        deleted = true;
      } catch (_) { /* swallowed — fall through to signOut so the auth
                        state still clears and the user lands on the login
                        screen instead of being stuck on the orphan
                        onboarding step. */ }
    }

    // Force-clear the local auth session even when the server-side delete
    // failed. Without this, currentUser stays alive, the auth listener
    // re-routes to OwnerOnboardingStep1Screen (labelled "Étape 2 sur 6")
    // and the owner is stuck. signOut() triggers authStateChanges() so
    // main.dart's StreamProvider rebuilds → LoginScreen.
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) { /* non-fatal */ }

    if (!mounted) return;
    if (!deleted) {
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l?.tr('profile_delete_error') ??
              'La suppression a partiellement échoué — veuillez vous reconnecter pour réessayer.'),
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 5),
        ),
      );
    }
    Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
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

class _SalonTypeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _SalonTypeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? AppColors.brand50 : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.brand600 : AppColors.secondary200,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, size: 22, color: selected ? AppColors.brand600 : AppColors.secondary400),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  color: selected ? AppColors.brand600 : AppColors.secondary500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
