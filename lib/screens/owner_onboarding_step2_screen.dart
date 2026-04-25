import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../theme/app_colors.dart';
import '../services/auth_service.dart';
import '../services/plan_config.dart';
import '../utils/media_compressor.dart';
import '../widgets/custom_button.dart';
import '../services/app_localizations.dart';
import 'owner_onboarding_step3_screen.dart';

class OwnerOnboardingStep2Screen extends StatefulWidget {
  final Map<String, dynamic> salonData;
  const OwnerOnboardingStep2Screen({super.key, required this.salonData});

  @override
  State<OwnerOnboardingStep2Screen> createState() =>
      _OwnerOnboardingStep2ScreenState();
}

class _OwnerOnboardingStep2ScreenState
    extends State<OwnerOnboardingStep2Screen> {
  final _picker = ImagePicker();

  // Cover photo
  File? _coverPhotoFile;
  String? _coverPhotoUrl;
  bool _isUploadingCover = false;

  // Gallery: each item holds the local file, the remote URL and its upload state
  final List<Map<String, dynamic>> _galleryItems = [];
  // each map: {'file': File, 'url': String?, 'uploading': bool}

  bool get _hasCoverPhoto => _coverPhotoFile != null;
  bool get _isAnyUploading =>
      _isUploadingCover ||
      _galleryItems.any((g) => g['uploading'] == true);

  // Video uploads are gated on Business plan. During onboarding the salon
  // doc doesn't exist yet, so we read the in-progress salonData.
  bool get _isBusinessPlan =>
      widget.salonData['plan'] == PlanConfig.planBusiness;

  // ── Upload helper ────────────────────────────────────────────────────────────

  Future<String?> _uploadToStorage(File file, String storagePath) async {
    final ref = FirebaseStorage.instance.ref().child(storagePath);
    await ref.putFile(
      file,
      SettableMetadata(cacheControl: 'public, max-age=604800'),
    );
    return await ref.getDownloadURL();
  }

  // ── Cover photo ──────────────────────────────────────────────────────────────

  Future<void> _pickCoverPhoto() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    // Compress
    if (!mounted) return;
    final compressOverlay = MediaCompressor.showCompressionOverlay(context, isVideo: false);
    final result = await MediaCompressor.compressImage(File(picked.path));
    compressOverlay.remove();
    if (!mounted) return;
    if (result == null) {
      await MediaCompressor.showSizeErrorDialog(context, isVideo: false, afterCompression: false);
      return;
    }
    if (result.compressedSize > MediaCompressor.maxImageSizeBytes) {
      await MediaCompressor.showSizeErrorDialog(context, isVideo: false, afterCompression: true);
      return;
    }

    final file = result.file;
    setState(() {
      _coverPhotoFile = file;
      _coverPhotoUrl = null;
      _isUploadingCover = true;
    });

    try {
      final uid = AuthService().currentUserId;
      if (uid == null) {
        throw StateError('Not authenticated');
      }
      final path =
          'salon_images/$uid/cover_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final url = await _uploadToStorage(file, path);
      if (mounted) {
        setState(() {
          _coverPhotoUrl = url;
          _isUploadingCover = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _coverPhotoFile = null;
          _isUploadingCover = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur upload photo de couverture : $e'),
          backgroundColor: Colors.redAccent,
        ));
      }
    }
  }

  void _removeCoverPhoto() => setState(() {
        _coverPhotoFile = null;
        _coverPhotoUrl = null;
      });

  // ── Gallery ──────────────────────────────────────────────────────────────────

  Future<void> _pickGalleryPhoto() async {
    if (_galleryItems.length >= 10) return;

    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    // Compress
    if (!mounted) return;
    final compressOverlay = MediaCompressor.showCompressionOverlay(context, isVideo: false);
    final result = await MediaCompressor.compressImage(File(picked.path));
    compressOverlay.remove();
    if (!mounted) return;
    if (result == null) {
      await MediaCompressor.showSizeErrorDialog(context, isVideo: false, afterCompression: false);
      return;
    }
    if (result.compressedSize > MediaCompressor.maxImageSizeBytes) {
      await MediaCompressor.showSizeErrorDialog(context, isVideo: false, afterCompression: true);
      return;
    }

    final file = result.file;
    final index = _galleryItems.length;

    setState(() {
      _galleryItems.add({
        'file': file,
        'url': null,
        'uploading': true,
        'isVideo': false,
      });
    });

    try {
      final uid = AuthService().currentUserId;
      if (uid == null) {
        throw StateError('Not authenticated');
      }
      final path =
          'salon_images/$uid/gallery_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final url = await _uploadToStorage(file, path);
      if (mounted) {
        setState(() {
          _galleryItems[index]['url'] = url;
          _galleryItems[index]['uploading'] = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _galleryItems.removeAt(index));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur upload image galerie : $e'),
          backgroundColor: Colors.redAccent,
        ));
      }
    }
  }

  Future<void> _pickGalleryVideo() async {
    if (_galleryItems.length >= 10) return;

    final picked = await _picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(seconds: 60),
    );
    if (picked == null) return;

    if (!mounted) return;
    final compressOverlay =
        MediaCompressor.showCompressionOverlay(context, isVideo: true);
    final result = await MediaCompressor.compressVideo(File(picked.path));
    compressOverlay.remove();
    if (!mounted) return;
    if (result == null) {
      await MediaCompressor.showSizeErrorDialog(context,
          isVideo: true, afterCompression: false);
      return;
    }
    if (result.compressedSize > MediaCompressor.maxVideoSizeBytes) {
      await MediaCompressor.showSizeErrorDialog(context,
          isVideo: true, afterCompression: true);
      return;
    }

    final file = result.file;
    final ext = file.path.split('.').last;
    final index = _galleryItems.length;

    setState(() {
      _galleryItems.add({
        'file': file,
        'url': null,
        'uploading': true,
        'isVideo': true,
      });
    });

    try {
      final uid = AuthService().currentUserId;
      if (uid == null) {
        throw StateError('Not authenticated');
      }
      final path =
          'salon_images/$uid/gallery_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final url = await _uploadToStorage(file, path);
      if (mounted) {
        setState(() {
          _galleryItems[index]['url'] = url;
          _galleryItems[index]['uploading'] = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _galleryItems.removeAt(index));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur upload vidéo galerie : $e'),
          backgroundColor: Colors.redAccent,
        ));
      }
    }
  }

  void _removeGalleryImage(int index) =>
      setState(() => _galleryItems.removeAt(index));

  // Video tile is unlocked only if the owner picked the Business plan
  // at step 1. Otherwise we keep the lock + upsell dialog.
  void _showPickerSheet() {
    if (_galleryItems.length >= 10) return;
    final l = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.secondary200,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.brand50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.add_photo_alternate_outlined,
                      color: AppColors.brand600, size: 20),
                ),
                title: Text(l?.tr('gallery_add_photo') ?? 'Photo',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _pickGalleryPhoto();
                },
              ),
              if (_isBusinessPlan)
                ListTile(
                  leading: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.brand50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.videocam_outlined,
                        color: AppColors.brand600, size: 20),
                  ),
                  title: Text(l?.tr('gallery_add_video') ?? 'Vidéo',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _pickGalleryVideo();
                  },
                )
              else
                ListTile(
                  leading: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: Colors.purple.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.lock_outline,
                        color: Colors.purple, size: 20),
                  ),
                  title: Row(
                    children: [
                      Text(l?.tr('gallery_add_video') ?? 'Vidéo',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.purple.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('Business',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.purple,
                            )),
                      ),
                    ],
                  ),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _showVideoPremiumDialog();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showVideoPremiumDialog() {
    final l = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            color: Colors.purple.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.workspace_premium_rounded,
              color: Colors.purple, size: 28),
        ),
        title: Text(
          l?.tr('video_premium_dialog_title') ?? 'Fonctionnalité Business',
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        ),
        content: Text(
          l?.tr('gallery_premium_required') ??
              'Les vidéos sont disponibles avec le plan Business',
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

  // ── Navigation ───────────────────────────────────────────────────────────────

  void _handleNext() {
    if (_isAnyUploading) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Veuillez attendre la fin des uploads…'),
      ));
      return;
    }

    final updatedData = Map<String, dynamic>.from(widget.salonData);
    final galleryUrls = _galleryItems
        .where((g) => g['url'] != null)
        .map((g) => g['url'] as String)
        .toList();
    // Cover photo goes first in images array
    final allImages = <String>[
      if (_coverPhotoUrl != null) _coverPhotoUrl!,
      ...galleryUrls,
    ];
    updatedData['images'] = allImages;
    updatedData['logoUrl'] = _coverPhotoUrl;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OwnerOnboardingStep3Screen(salonData: updatedData),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(child: _buildFormSection()),
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
            constraints: const BoxConstraints(maxWidth: 600),
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
                        child: const Icon(Icons.arrow_back,
                            size: 12, color: AppColors.secondary500),
                      ),
                      label: Text(l?.tr('onboarding_back') ?? 'Retour',
                          style: const TextStyle(
                              color: AppColors.secondary500,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Progress bar
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(l?.tr('onboarding_step2_title') ?? 'Portfolio visuel',
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.brand900)),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                          color: AppColors.brand50,
                          borderRadius: BorderRadius.circular(6)),
                      child: Text(l?.tr('onboarding_step2_step') ?? 'Étape 3 sur 6',
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.brand600)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: Container(
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppColors.brand300,
                        borderRadius:
                            BorderRadius.horizontal(left: Radius.circular(3)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Expanded(child: Container(height: 6, color: AppColors.brand500)),
                  const SizedBox(width: 2),
                  Expanded(
                      child: Container(height: 6, color: AppColors.secondary100)),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Container(
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppColors.secondary100,
                        borderRadius:
                            BorderRadius.horizontal(right: Radius.circular(3)),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 32),

                // Header
                Text(
                  l?.tr('onboarding_step2_subtitle') ?? 'Ajoutez vos photos de salon',
                  style: GoogleFonts.dmSans(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: AppColors.brand950),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Choisissez une belle photo de couverture et des photos de votre espace. Ce sont les premières images que les clients verront.',
                  style: TextStyle(color: AppColors.secondary500, height: 1.5),
                ),
                const SizedBox(height: 32),

                // ── Cover Photo ─────────────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(l?.tr('onboarding_step2_cover') ?? 'Photo de couverture *',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.secondary800)),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color: AppColors.secondary50,
                          borderRadius: BorderRadius.circular(6)),
                      child: Text(l?.tr('onboarding_step2_cover_format') ?? 'Format 16:9 recommandé',
                          style: TextStyle(
                              fontSize: 10, color: AppColors.secondary400)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                GestureDetector(
                  onTap: _isUploadingCover ? null : _pickCoverPhoto,
                  child: Container(
                    height: 200,
                    decoration: BoxDecoration(
                      color: _hasCoverPhoto
                          ? Colors.black
                          : AppColors.secondary50.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _hasCoverPhoto
                            ? Colors.transparent
                            : AppColors.secondary300,
                        width: 2,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: _hasCoverPhoto
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.file(_coverPhotoFile!, fit: BoxFit.cover),
                                Container(
                                    color:
                                        Colors.black.withValues(alpha: 0.3)),
                                if (_isUploadingCover)
                                  const Center(
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2),
                                  )
                                else ...[
                                  Positioned(
                                    bottom: 12,
                                    left: 12,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                          color: Colors.white
                                              .withValues(alpha: 0.9),
                                          borderRadius:
                                              BorderRadius.circular(6)),
                                      child: Row(children: [
                                        const Icon(Icons.star,
                                            size: 12,
                                            color: AppColors.brand700),
                                        const SizedBox(width: 4),
                                        Text(l?.tr('onboarding_step2_cover_label') ?? 'Couverture',
                                            style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.brand700)),
                                      ]),
                                    ),
                                  ),
                                  Center(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          onPressed: _pickCoverPhoto,
                                          style: IconButton.styleFrom(
                                              backgroundColor: Colors.white
                                                  .withValues(alpha: 0.2)),
                                          icon: const Icon(Icons.edit,
                                              color: Colors.white),
                                        ),
                                        const SizedBox(width: 16),
                                        IconButton(
                                          onPressed: _removeCoverPhoto,
                                          style: IconButton.styleFrom(
                                              backgroundColor: Colors.white
                                                  .withValues(alpha: 0.2)),
                                          icon: const Icon(Icons.delete,
                                              color: Colors.white),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                          color: Colors.black12,
                                          blurRadius: 8,
                                          offset: Offset(0, 4))
                                    ],
                                  ),
                                  child: const Icon(Icons.image_outlined,
                                      color: AppColors.brand400, size: 24),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  l?.tr('onboarding_step2_cover_tap') ?? 'Appuyer pour choisir une photo',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.secondary700),
                                ),
                                const SizedBox(height: 8),
                                Text(l?.tr('onboarding_step2_cover_formats') ?? 'JPG, PNG ou WEBP (Max 5 Mo)',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: AppColors.secondary400)),
                              ],
                            ),
                    ),
                  ),
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Divider(color: AppColors.secondary100, height: 1),
                ),

                // ── Gallery ─────────────────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l?.tr('onboarding_step2_gallery') ?? 'Images de galerie',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppColors.secondary800)),
                        SizedBox(height: 4),
                        Text(
                          'Intérieur, équipements,\nclients satisfaits…',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppColors.secondary500,
                              height: 1.5),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.secondary50,
                        border: Border.all(color: AppColors.secondary100),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('${_galleryItems.length}/10 ajoutées',
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.secondary400)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    // Add button
                    if (_galleryItems.length < 10)
                      GestureDetector(
                        onTap: _showPickerSheet,
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            color: AppColors.secondary50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: AppColors.secondary200, width: 1),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: const BoxDecoration(
                                    color: AppColors.secondary100,
                                    shape: BoxShape.circle),
                                child: const Icon(Icons.add,
                                    color: AppColors.secondary400, size: 16),
                              ),
                              const SizedBox(height: 8),
                              Text(l?.tr('onboarding_step2_add') ?? 'Ajouter',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.secondary500)),
                            ],
                          ),
                        ),
                      ),

                    // Gallery thumbnails
                    ...List.generate(_galleryItems.length, (index) {
                      final item = _galleryItems[index];
                      final file = item['file'] as File;
                      final uploading = item['uploading'] as bool;
                      final isVideo = item['isVideo'] == true;
                      return SizedBox(
                        width: 100,
                        height: 100,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (isVideo)
                                Container(
                                  color: Colors.black87,
                                  alignment: Alignment.center,
                                  child: const Icon(
                                    Icons.play_circle_fill_rounded,
                                    color: Colors.white,
                                    size: 36,
                                  ),
                                )
                              else
                                Image.file(file, fit: BoxFit.cover),
                              if (uploading)
                                Container(
                                  color: Colors.black.withValues(alpha: 0.45),
                                  child: const Center(
                                    child: SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                          color: Colors.white, strokeWidth: 2),
                                    ),
                                  ),
                                )
                              else
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: GestureDetector(
                                    onTap: () => _removeGalleryImage(index),
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.white
                                            .withValues(alpha: 0.9),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.close,
                                          size: 12,
                                          color: AppColors.secondary600),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
                const SizedBox(height: 24),

                // Guidelines
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue[50]?.withValues(alpha: 0.5),
                    border: Border.all(color: Colors.blue[100]!),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline,
                          color: Colors.blueAccent, size: 16),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Conseils photos',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue)),
                            const SizedBox(height: 4),
                            Text(
                              '• Taille recommandée : 1920×1080px (min 800×600px)\n• Taille max : 5 Mo par image\n• Formats acceptés : JPG, PNG, WEBP',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.secondary500,
                                  height: 1.5),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),
                const Divider(color: AppColors.secondary100, height: 1),
                const SizedBox(height: 24),

                // Actions
                CustomButton(
                  text: l?.tr('onboarding_step2_continue') ?? 'Continuer',
                  onPressed: _handleNext,
                  isLoading: _isAnyUploading,
                  icon: Icons.arrow_forward,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      side: const BorderSide(color: AppColors.secondary200),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.arrow_back,
                            size: 14, color: AppColors.secondary700),
                        const SizedBox(width: 8),
                        Text(l?.tr('onboarding_back') ?? 'Retour',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.secondary700)),
                      ],
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
}
