import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

import '../models/salon_model.dart';
import '../services/app_localizations.dart';
import '../theme/app_colors.dart';
import '../widgets/custom_button.dart';

/// Dedicated, focused screen to set the salon's location AFTER onboarding.
/// Surfaced by the Home "set location" setup card. The owner is encouraged
/// to use the GPS button **while physically at the salon** for an exact
/// position; typing the address is the fallback (forward-geocoded on save).
class OwnerSetLocationScreen extends StatefulWidget {
  const OwnerSetLocationScreen({super.key, this.salon});

  /// The current salon — used to pre-fill any address already entered.
  final SalonModel? salon;

  @override
  State<OwnerSetLocationScreen> createState() => _OwnerSetLocationScreenState();
}

class _OwnerSetLocationScreenState extends State<OwnerSetLocationScreen> {
  final _countryController = TextEditingController();
  final _streetController = TextEditingController();
  final _cityController = TextEditingController();
  final _postalCodeController = TextEditingController();

  double? _latitude;
  double? _longitude;
  bool _isGettingLocation = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final s = widget.salon;
    if (s != null) {
      _cityController.text = s.city;
      _latitude = s.latitude;
      _longitude = s.longitude;
      // The salon stores a single joined `address` string; we keep it in the
      // street field as a best-effort prefill (the owner can tidy it).
      if (s.address.trim().isNotEmpty) _streetController.text = s.address;
    }
  }

  @override
  void dispose() {
    _countryController.dispose();
    _streetController.dispose();
    _cityController.dispose();
    _postalCodeController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isGettingLocation = true);
    final l = AppLocalizations.of(context);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw l?.tr('salon_edit_info_location_disabled') ??
            'Le service de localisation est désactivé.';
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw l?.tr('salon_edit_info_location_denied') ??
              'Permission de localisation refusée.';
        }
      }
      if (permission == LocationPermission.deniedForever) {
        throw l?.tr('salon_edit_info_location_denied_forever') ??
            'Permission de localisation définitivement refusée. Activez-la dans les paramètres.';
      }

      final position = await Geolocator.getCurrentPosition();
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (!mounted) return;
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          if ((p.street ?? '').trim().isNotEmpty) {
            _streetController.text = p.street!.trim();
          }
          final city = p.locality ?? p.administrativeArea ?? '';
          if (city.isNotEmpty) _cityController.text = city;
          if ((p.postalCode ?? '').isNotEmpty) {
            _postalCodeController.text = p.postalCode!;
          }
          if ((p.country ?? '').isNotEmpty) _countryController.text = p.country!;
        }
        _isGettingLocation = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isGettingLocation = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$e'),
        backgroundColor: Colors.redAccent,
      ));
    }
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final addressParts = [
      if (_streetController.text.trim().isNotEmpty) _streetController.text.trim(),
      if (_postalCodeController.text.trim().isNotEmpty)
        _postalCodeController.text.trim(),
      if (_cityController.text.trim().isNotEmpty) _cityController.text.trim(),
      if (_countryController.text.trim().isNotEmpty)
        _countryController.text.trim(),
    ];
    final fullAddress = addressParts.join(', ');

    setState(() => _saving = true);

    double? lat = _latitude;
    double? lng = _longitude;
    // Forward-geocode the typed address when GPS wasn't used.
    if ((lat == null || lng == null) && fullAddress.isNotEmpty) {
      try {
        final locations = await locationFromAddress(fullAddress);
        if (locations.isNotEmpty) {
          lat = locations.first.latitude;
          lng = locations.first.longitude;
        }
      } catch (_) {}
    }

    if (lat == null || lng == null) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l?.tr('salon_edit_info_geocode_error') ??
            'Impossible de localiser cette adresse. Utilisez le bouton « Ma position » une fois au salon.'),
        backgroundColor: Colors.redAccent,
        duration: const Duration(seconds: 4),
      ));
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('salons').doc(uid).update({
        'address': fullAddress,
        'city': _cityController.text.trim(),
        'country': _countryController.text.trim(),
        'latitude': lat,
        'longitude': lng,
      });
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${l?.tr('common_error_short') ?? 'Erreur'} : $e'),
        backgroundColor: Colors.redAccent,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final hasCoords = _latitude != null && _longitude != null;
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
          l?.tr('set_location_title') ?? 'Localisation du salon',
          style: GoogleFonts.dmSans(
            fontWeight: FontWeight.bold,
            color: AppColors.brand950,
            fontSize: 18,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // GPS recommendation banner.
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.brand50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.brand100),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.tips_and_updates_outlined,
                            size: 20, color: AppColors.brand600),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            l?.tr('set_location_gps_tip') ??
                                'Pour une position exacte, utilisez le bouton « Ma position » une fois sur place, au salon. La saisie manuelle de l\'adresse est moins précise.',
                            style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.brand900,
                                height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // GPS button.
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed:
                          _isGettingLocation ? null : _getCurrentLocation,
                      icon: _isGettingLocation
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppColors.brand500),
                            )
                          : Icon(
                              hasCoords
                                  ? Icons.check_circle
                                  : Icons.my_location,
                              size: 18,
                              color: hasCoords
                                  ? Colors.green
                                  : AppColors.brand600),
                      label: Text(
                        _isGettingLocation
                            ? (l?.tr('salon_edit_info_gps_loading') ??
                                'Localisation...')
                            : (hasCoords
                                ? (l?.tr('salon_edit_info_gps_captured') ??
                                    'Position capturée')
                                : (l?.tr('salon_edit_info_gps_use') ??
                                    'Utiliser ma position')),
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color:
                                hasCoords ? Colors.green : AppColors.brand600),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(
                            color: hasCoords
                                ? Colors.green
                                : AppColors.brand300),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Map preview when coords are known.
                  if (hasCoords) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        height: 150,
                        child: IgnorePointer(
                          child: FlutterMap(
                            options: MapOptions(
                              initialCenter: LatLng(_latitude!, _longitude!),
                              initialZoom: 15,
                              interactionOptions: const InteractionOptions(
                                  flags: InteractiveFlag.none),
                            ),
                            children: [
                              TileLayer(
                                urlTemplate:
                                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'com.blagence.monsalon',
                              ),
                              MarkerLayer(markers: [
                                Marker(
                                  point: LatLng(_latitude!, _longitude!),
                                  width: 32,
                                  height: 32,
                                  child: const Icon(Icons.location_on,
                                      color: AppColors.brand600, size: 32),
                                ),
                              ]),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  _field(_countryController,
                      l?.tr('salon_edit_info_country') ?? 'Pays',
                      icon: Icons.public_outlined),
                  const SizedBox(height: 14),
                  _field(_streetController,
                      l?.tr('salon_edit_info_street') ?? 'Adresse (rue et numéro)',
                      icon: Icons.signpost_outlined),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: _field(_cityController,
                            l?.tr('salon_edit_info_city') ?? 'Ville',
                            icon: Icons.location_city_outlined),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: _field(_postalCodeController,
                            l?.tr('salon_edit_info_postal') ?? 'Code postal',
                            icon: Icons.markunread_mailbox_outlined,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ]),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(
                20, 12, 20, 12 + MediaQuery.of(context).padding.bottom),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: AppColors.secondary200)),
            ),
            child: CustomButton(
              text: l?.tr('common_save') ?? 'Enregistrer',
              onPressed: _save,
              isLoading: _saving,
              icon: Icons.check,
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String label,
      {required IconData icon,
      TextInputType keyboardType = TextInputType.text,
      List<TextInputFormatter>? inputFormatters}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.secondary700)),
        const SizedBox(height: 6),
        TextField(
          controller: c,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          style: const TextStyle(fontSize: 14, color: AppColors.secondary800),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, size: 18, color: AppColors.secondary400),
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
              borderSide: const BorderSide(color: AppColors.brand400, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}
