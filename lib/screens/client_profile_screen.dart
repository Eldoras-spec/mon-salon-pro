import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../theme/app_colors.dart';
import '../models/user_model.dart';
import '../providers/auth_providers.dart';
import '../providers/owner_providers.dart';
import '../services/auth_service.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

String _hashPin(String pin) {
  final bytes = utf8.encode(pin);
  return sha256.convert(bytes).toString();
}

// ── Screen ───────────────────────────────────────────────────────────────────

class ClientProfileScreen extends ConsumerStatefulWidget {
  const ClientProfileScreen({super.key});

  @override
  ConsumerState<ClientProfileScreen> createState() =>
      _ClientProfileScreenState();
}

class _ClientProfileScreenState extends ConsumerState<ClientProfileScreen> {
  bool _uploadingPhoto = false;

  Future<void> _pickPhoto(UserModel user) async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );
    if (picked == null || !mounted) return;

    setState(() => _uploadingPhoto = true);
    try {
      final url = await AuthService()
          .uploadProfilePicture(user.id, File(picked.path));
      await AuthService().updateProfileImageUrl(user.id, url);
      // userStreamProvider auto-updates — no invalidation needed
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Erreur : $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _signOut() async {
    await ref.read(authServiceProvider).signOut();
    ref.invalidate(authStateProvider);
    ref.invalidate(userModelProvider);
    if (mounted) {
      Navigator.of(context, rootNavigator: true)
          .popUntil((route) => route.isFirst);
    }
  }

  Future<void> _deleteAccount() async {
    final confirm1 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Supprimer votre compte ?'),
        content: const Text(
          'Cette action est irréversible. Toutes vos données, '
          'réservations et conversations seront définitivement supprimées.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirm1 != true || !mounted) return;

    final confirm2 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Êtes-vous vraiment sûr ?'),
        content: const Text(
          'Votre compte et toutes vos données seront supprimés de façon permanente. '
          'Cette action ne peut pas être annulée.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Non, garder mon compte'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Oui, supprimer définitivement',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirm2 != true || !mounted) return;

    try {
      await AuthService().deleteAccount();
      if (mounted) {
        ref.invalidate(authStateProvider);
        ref.invalidate(userModelProvider);
        Navigator.of(context, rootNavigator: true)
            .popUntil((route) => route.isFirst);
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      String msg = 'Erreur lors de la suppression.';
      if (e.code == 'requires-recent-login') {
        msg = 'Veuillez vous reconnecter puis réessayer la suppression.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(userStreamProvider);

    return Scaffold(
      backgroundColor: AppColors.secondary50,
      body: userAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.brand600)),
        error: (e, _) => Center(child: Text('Erreur : $e')),
        data: (user) {
          if (user == null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Profil introuvable'),
                  TextButton(
                    onPressed: () => ref.invalidate(userStreamProvider),
                    child: const Text('Réessayer'),
                  ),
                ],
              ),
            );
          }
          final isOwner = user.userType == UserType.owner;
          return CustomScrollView(
            slivers: [
              _appBar(),
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    // ── Avatar + identity ──────────────────────────────────
                    _AvatarSection(
                      user: user,
                      uploading: _uploadingPhoto,
                      onPickPhoto: () => _pickPhoto(user),
                    ),

                    const SizedBox(height: 20),

                    // ── Mon compte ─────────────────────────────────────────
                    _AccountCard(user: user, onSaved: () {}),

                    const SizedBox(height: 8),

                    // ── Section spécifique au type ─────────────────────────
                    if (isOwner) ...[
                      _OwnerSalonCard(),
                      const SizedBox(height: 8),
                      const _SocialLinksCard(),
                    ] else
                      _ClientStatsCard(user: user),

                    const SizedBox(height: 8),

                    // ── Paramètres ─────────────────────────────────────────
                    _SettingsCard(
                      user: user,
                    ),

                    const SizedBox(height: 24),

                    // ── Déconnexion ────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: OutlinedButton.icon(
                          onPressed: _signOut,
                          icon: const Icon(Icons.logout_rounded, size: 18),
                          label: const Text('Se déconnecter'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFDC2626),
                            side: const BorderSide(
                                color: Color(0xFFFEE2E2), width: 1.5),
                            backgroundColor: const Color(0xFFFFF5F5),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            textStyle: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // ── Supprimer le compte ──────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: OutlinedButton.icon(
                          onPressed: _deleteAccount,
                          icon: const Icon(Icons.delete_forever_rounded, size: 18),
                          label: const Text('Supprimer mon compte'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFDC2626),
                            side: const BorderSide(
                                color: Color(0xFFFEE2E2), width: 1.5),
                            backgroundColor: const Color(0xFFFFF5F5),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            textStyle: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),
                    Text(
                      'Mon Salon v1.1.2',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.secondary300),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  SliverAppBar _appBar() => SliverAppBar(
        pinned: true,
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        title: Text(
          'Profil',
          style: GoogleFonts.dmSans(
            fontWeight: FontWeight.bold,
            color: AppColors.brand950,
            fontSize: 20,
          ),
        ),
      );
}

// ── Avatar section ───────────────────────────────────────────────────────────

class _AvatarSection extends StatelessWidget {
  const _AvatarSection({
    required this.user,
    required this.uploading,
    required this.onPickPhoto,
  });
  final UserModel user;
  final bool uploading;
  final VoidCallback onPickPhoto;

  @override
  Widget build(BuildContext context) {
    final isOwner = user.userType == UserType.owner;
    final memberYear = DateFormat('yyyy').format(user.createdAt);

    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Column(
        children: [
          // Avatar
          Stack(
            children: [
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.brand100, width: 3),
                ),
                child: ClipOval(
                  child: uploading
                      ? Container(
                          color: AppColors.brand50,
                          child: const Center(
                            child: CircularProgressIndicator(
                                color: AppColors.brand600, strokeWidth: 2),
                          ),
                        )
                      : user.profileImageUrl != null
                          ? Image.network(user.profileImageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  _avatarFallback(user.fullName))
                          : _avatarFallback(user.fullName),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: GestureDetector(
                  onTap: uploading ? null : onPickPhoto,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppColors.brand600,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(Icons.camera_alt_rounded,
                        color: Colors.white, size: 13),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          Text(
            user.fullName,
            style: GoogleFonts.dmSans(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.brand950,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            user.email,
            style: const TextStyle(
                fontSize: 13, color: AppColors.secondary500),
          ),

          const SizedBox(height: 12),

          // Badges
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Badge(
                icon: isOwner
                    ? Icons.storefront_outlined
                    : Icons.person_outline_rounded,
                label: isOwner ? 'Propriétaire' : 'Client',
                color: AppColors.brand600,
                bg: AppColors.brand50,
              ),
              const SizedBox(width: 8),
              _Badge(
                icon: Icons.calendar_today_outlined,
                label: 'Membre depuis $memberYear',
                color: AppColors.secondary500,
                bg: AppColors.secondary100,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _avatarFallback(String name) {
    final initials = name.trim().isNotEmpty
        ? name.trim().split(' ').map((w) => w[0]).take(2).join().toUpperCase()
        : '?';
    return Container(
      color: AppColors.brand50,
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: AppColors.brand400,
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(
      {required this.icon,
      required this.label,
      required this.color,
      required this.bg});
  final IconData icon;
  final String label;
  final Color color;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color)),
        ],
      ),
    );
  }
}

// ── Account card (editable) ───────────────────────────────────────────────────

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.user, required this.onSaved});
  final UserModel user;
  final VoidCallback onSaved;

  void _openEdit(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _EditProfileSheet(user: user, onSaved: onSaved),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Mon compte',
      trailing: GestureDetector(
        onTap: () => _openEdit(context),
        child: const Text('Modifier',
            style: TextStyle(
                fontSize: 13,
                color: AppColors.brand600,
                fontWeight: FontWeight.w600)),
      ),
      child: Column(
        children: [
          _ProfileRow(
              icon: Icons.person_outline_rounded,
              label: 'Nom complet',
              value: user.fullName),
          _ProfileRow(
              icon: Icons.email_outlined,
              label: 'Email',
              value: user.email),
          _ProfileRow(
              icon: Icons.phone_outlined,
              label: 'Téléphone',
              value: user.phone.isNotEmpty ? user.phone : '—'),
          _ProfileRow(
              icon: Icons.location_city_outlined,
              label: 'Ville',
              value: user.city.isNotEmpty ? user.city : '—',
              last: true),
        ],
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.icon,
    required this.label,
    required this.value,
    this.last = false,
  });
  final IconData icon;
  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.secondary100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: AppColors.secondary500),
              ),
              const SizedBox(width: 12),
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
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppColors.brand950)),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (!last)
          const Divider(height: 1, indent: 46),
      ],
    );
  }
}

// ── Client stats card ────────────────────────────────────────────────────────

class _ClientStatsCard extends StatelessWidget {
  const _ClientStatsCard({required this.user});
  final UserModel user;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Mon activité',
      child: Row(
        children: [
          Expanded(
            child: _StatTile(
              icon: Icons.favorite_border_rounded,
              color: const Color(0xFFDB2777),
              bg: const Color(0xFFFDF2F8),
              value: '${user.favorites.length}',
              label: 'Favoris',
            ),
          ),
          Container(width: 1, height: 50, color: AppColors.secondary100),
          Expanded(
            child: _StatTile(
              icon: Icons.calendar_today_outlined,
              color: const Color(0xFF2563EB),
              bg: const Color(0xFFEFF6FF),
              value: '—',
              label: 'Réservations',
            ),
          ),
          Container(width: 1, height: 50, color: AppColors.secondary100),
          Expanded(
            child: _StatTile(
              icon: Icons.star_outline_rounded,
              color: const Color(0xFFD97706),
              bg: const Color(0xFFFEF3C7),
              value: '—',
              label: 'Avis',
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.color,
    required this.bg,
    required this.value,
    required this.label,
  });
  final IconData icon;
  final Color color;
  final Color bg;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration:
              BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(height: 6),
        Text(value,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.brand950)),
        Text(label,
            style: const TextStyle(
                fontSize: 10, color: AppColors.secondary400)),
      ],
    );
  }
}

// ── Owner salon card ─────────────────────────────────────────────────────────

class _OwnerSalonCard extends ConsumerWidget {
  const _OwnerSalonCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salonAsync = ref.watch(ownerSalonProvider);
    final salon = salonAsync.value;

    return _Card(
      title: 'Mon Salon',
      child: salon == null
          ? const Text(
              'Aucun salon configuré',
              style:
                  TextStyle(color: AppColors.secondary400, fontSize: 13),
            )
          : Column(
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: salon.logoUrl != null
                          ? Image.network(salon.logoUrl!,
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  _logoFallback())
                          : _logoFallback(),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(salon.name,
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.brand950)),
                          const SizedBox(height: 2),
                          Text('${salon.city} · ${salon.category}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.secondary500)),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 13, color: Color(0xFFD97706)),
                        const SizedBox(width: 3),
                        Text(salon.rating.toStringAsFixed(1),
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFD97706))),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _SalonStat(
                        value: '${salon.services.length}',
                        label: 'Services'),
                    Container(
                        width: 1,
                        height: 28,
                        color: AppColors.secondary100,
                        margin:
                            const EdgeInsets.symmetric(horizontal: 16)),
                    _SalonStat(
                        value: '${salon.reviewCount}',
                        label: 'Avis'),
                    Container(
                        width: 1,
                        height: 28,
                        color: AppColors.secondary100,
                        margin:
                            const EdgeInsets.symmetric(horizontal: 16)),
                    _SalonStat(
                        value: salon.rating.toStringAsFixed(1),
                        label: 'Note'),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _logoFallback() => Container(
        width: 48,
        height: 48,
        color: AppColors.brand50,
        child: const Icon(Icons.storefront_outlined,
            color: AppColors.brand300, size: 22),
      );
}

// ── Social links card ────────────────────────────────────────────────────────

class _SocialLinksCard extends ConsumerStatefulWidget {
  const _SocialLinksCard();

  @override
  ConsumerState<_SocialLinksCard> createState() => _SocialLinksCardState();
}

class _SocialLinksCardState extends ConsumerState<_SocialLinksCard> {
  bool _editing = false;
  bool _saving = false;

  late final TextEditingController _instagramCtrl;
  late final TextEditingController _facebookCtrl;
  late final TextEditingController _tiktokCtrl;
  late final TextEditingController _whatsappCtrl;
  bool _initialized = false;

  void _initControllers(Map<String, String> links) {
    if (_initialized) return;
    _instagramCtrl = TextEditingController(text: links['instagram'] ?? '');
    _facebookCtrl = TextEditingController(text: links['facebook'] ?? '');
    _tiktokCtrl = TextEditingController(text: links['tiktok'] ?? '');
    _whatsappCtrl = TextEditingController(text: links['whatsapp'] ?? '');
    _initialized = true;
  }

  @override
  void dispose() {
    if (_initialized) {
      _instagramCtrl.dispose();
      _facebookCtrl.dispose();
      _tiktokCtrl.dispose();
      _whatsappCtrl.dispose();
    }
    super.dispose();
  }

  Future<void> _save(String salonId) async {
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.collection('salons').doc(salonId).update({
        'socialLinks': {
          'instagram': _instagramCtrl.text.trim().replaceAll('@', ''),
          'facebook': _facebookCtrl.text.trim().replaceAll('@', ''),
          'tiktok': _tiktokCtrl.text.trim().replaceAll('@', ''),
          'whatsapp': _whatsappCtrl.text.trim(),
        },
      });
      ref.invalidate(ownerSalonProvider);
      if (mounted) {
        setState(() {
          _editing = false;
          _saving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Réseaux sociaux mis à jour'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final salonAsync = ref.watch(ownerSalonProvider);
    final salon = salonAsync.value;
    if (salon == null) return const SizedBox.shrink();

    _initControllers(salon.socialLinks);

    return _Card(
      title: 'Réseaux sociaux',
      trailing: _saving
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.brand600),
            )
          : GestureDetector(
              onTap: () {
                if (_editing) {
                  _save(salon.id);
                } else {
                  setState(() => _editing = true);
                }
              },
              child: Text(
                _editing ? 'Enregistrer' : 'Modifier',
                style: const TextStyle(
                  color: AppColors.brand600,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
      child: Column(
        children: [
          _socialRow(
            icon: FontAwesomeIcons.instagram,
            color: const Color(0xFFE1306C),
            label: 'Instagram',
            controller: _instagramCtrl,
            hint: 'nom_utilisateur',
          ),
          _socialRow(
            icon: FontAwesomeIcons.facebook,
            color: const Color(0xFF1877F2),
            label: 'Facebook',
            controller: _facebookCtrl,
            hint: 'nom_utilisateur',
          ),
          _socialRow(
            icon: FontAwesomeIcons.tiktok,
            color: Colors.black87,
            label: 'TikTok',
            controller: _tiktokCtrl,
            hint: 'nom_utilisateur',
          ),
          _socialRow(
            icon: FontAwesomeIcons.whatsapp,
            color: const Color(0xFF25D366),
            label: 'WhatsApp',
            controller: _whatsappCtrl,
            hint: '+212...',
          ),
        ],
      ),
    );
  }

  Widget _socialRow({
    required IconData icon,
    required Color color,
    required String label,
    required TextEditingController controller,
    required String hint,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          FaIcon(icon, color: color, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: _editing
                ? TextField(
                    controller: controller,
                    style: const TextStyle(fontSize: 14, color: AppColors.brand950),
                    decoration: InputDecoration(
                      hintText: hint,
                      hintStyle: const TextStyle(
                          color: AppColors.secondary300, fontSize: 13),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 10),
                      filled: true,
                      fillColor: AppColors.secondary50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.secondary400)),
                      const SizedBox(height: 2),
                      Text(
                        controller.text.isEmpty ? 'Non renseigné' : controller.text,
                        style: TextStyle(
                          fontSize: 14,
                          color: controller.text.isEmpty
                              ? AppColors.secondary300
                              : AppColors.brand950,
                          fontStyle: controller.text.isEmpty
                              ? FontStyle.italic
                              : FontStyle.normal,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _SalonStat extends StatelessWidget {
  const _SalonStat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.brand950)),
          Text(label,
              style: const TextStyle(
                  fontSize: 10, color: AppColors.secondary400)),
        ],
      );
}

// ── Settings card ─────────────────────────────────────────────────────────────

class _SettingsCard extends StatefulWidget {
  const _SettingsCard({required this.user});
  final UserModel user;

  @override
  State<_SettingsCard> createState() => _SettingsCardState();
}

class _SettingsCardState extends State<_SettingsCard> {
  late bool _notifs;

  @override
  void initState() {
    super.initState();
    _notifs = widget.user.notificationsEnabled;
  }

  Future<void> _toggleNotifs(bool value) async {
    setState(() => _notifs = value);
    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.user.id)
        .update({'notificationsEnabled': value});
  }

  void _openSecurity() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _SecuritySheet(
        userEmail: widget.user.email,
      ),
    );
  }

  void _openChangePin() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ChangePinSheet(user: widget.user),
    );
  }

  void _openSupport() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _SupportSheet(user: widget.user),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Paramètres',
      child: Column(
        children: [
          // ── Notifications (inline toggle) ──────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.notifications_none_rounded,
                      size: 16, color: Color(0xFF2563EB)),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('Notifications',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppColors.brand950)),
                ),
                Switch(
                  value: _notifs,
                  onChanged: _toggleNotifs,
                  thumbColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return Colors.white;
                    }
                    return null;
                  }),
                  trackColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return AppColors.brand600;
                    }
                    return null;
                  }),
                ),
              ],
            ),
          ),
          const Divider(height: 1, indent: 46),

          // ── Sécurité ──────────────────────────────────────────────────
          _SettingsRow(
            icon: Icons.lock_outline_rounded,
            iconColor: const Color(0xFF059669),
            iconBg: const Color(0xFFDCFCE7),
            label: 'Sécurité',
            onTap: _openSecurity,
          ),
          const Divider(height: 1, indent: 46),

          // ── PIN de profil (propriétaire uniquement) ───────────────────
          if (widget.user.userType == UserType.owner) ...[
            _SettingsRow(
              icon: Icons.pin_outlined,
              iconColor: const Color(0xFF7C3AED),
              iconBg: const Color(0xFFF5F3FF),
              label: widget.user.pinHash != null
                  ? 'Changer le PIN de profil'
                  : 'Définir un PIN de profil',
              onTap: _openChangePin,
            ),
            const Divider(height: 1, indent: 46),
          ],

          // ── Aide & Support ────────────────────────────────────────────
          _SettingsRow(
            icon: Icons.help_outline_rounded,
            iconColor: const Color(0xFFD97706),
            iconBg: const Color(0xFFFEF3C7),
            label: 'Aide & Support',
            onTap: _openSupport,
          ),
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.label,
    this.onTap,
  });
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                  color: iconBg, borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, size: 16, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.brand950)),
            ),
            const Icon(Icons.chevron_right_rounded,
                size: 18, color: AppColors.secondary300),
          ],
        ),
      ),
    );
  }
}

// ── Security sheet ────────────────────────────────────────────────────────────

class _SecuritySheet extends StatefulWidget {
  const _SecuritySheet({required this.userEmail});
  final String userEmail;

  @override
  State<_SecuritySheet> createState() => _SecuritySheetState();
}

class _SecuritySheetState extends State<_SecuritySheet> {
  bool _loading = false;
  bool _sent = false;

  Future<void> _resetPassword() async {
    setState(() => _loading = true);
    try {
      await FirebaseAuth.instance
          .sendPasswordResetEmail(email: widget.userEmail);
      if (mounted) setState(() { _sent = true; _loading = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                  color: AppColors.secondary200,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Text('Sécurité',
              style: GoogleFonts.dmSans(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: AppColors.brand950)),
          const SizedBox(height: 20),
          if (_sent) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline_rounded,
                      color: Color(0xFF16A34A), size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Un email de réinitialisation a été envoyé à ${widget.userEmail}',
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF166534)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brand600,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Fermer',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: AppColors.secondary50,
                  borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline_rounded,
                      color: AppColors.secondary500, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Un lien de réinitialisation sera envoyé à\n${widget.userEmail}',
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.secondary600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _loading ? null : _resetPassword,
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
                    : const Text('Réinitialiser le mot de passe',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15)),
              ),
            ),
          ],

        ],
      ),
    );
  }
}

// ── Support sheet ─────────────────────────────────────────────────────────────

class _SupportSheet extends StatefulWidget {
  const _SupportSheet({required this.user});
  final UserModel user;

  @override
  State<_SupportSheet> createState() => _SupportSheetState();
}

class _SupportSheetState extends State<_SupportSheet> {
  String _category = 'Bug';
  final _messageController = TextEditingController();
  bool _loading = false;
  bool _sent = false;

  static const _categories = ['Bug', 'Suggestion', 'Question'];

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final msg = _messageController.text.trim();
    if (msg.isEmpty) return;
    setState(() => _loading = true);
    try {
      await FirebaseFirestore.instance.collection('reports').add({
        'userId': widget.user.id,
        'userEmail': widget.user.email,
        'userName': widget.user.fullName,
        'userType':
            widget.user.userType == UserType.owner ? 'owner' : 'client',
        'category': _category,
        'message': msg,
        'status': 'open',
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted) setState(() { _sent = true; _loading = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                  color: AppColors.secondary200,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Text('Aide & Support',
              style: GoogleFonts.dmSans(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: AppColors.brand950)),
          const SizedBox(height: 4),
          const Text('Décrivez votre problème ou suggestion',
              style:
                  TextStyle(fontSize: 13, color: AppColors.secondary400)),
          const SizedBox(height: 20),
          if (_sent) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(12)),
              child: const Column(
                children: [
                  Icon(Icons.check_circle_outline_rounded,
                      color: Color(0xFF16A34A), size: 36),
                  SizedBox(height: 10),
                  Text('Rapport envoyé !',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF166534))),
                  SizedBox(height: 6),
                  Text(
                    'Merci pour votre retour. Nous traiterons votre demande dans les meilleurs délais.',
                    style: TextStyle(
                        fontSize: 13, color: Color(0xFF16A34A)),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brand600,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Fermer',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
              ),
            ),
          ] else ...[
            // Category chips
            Row(
              children: _categories.map((cat) {
                final selected = cat == _category;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _category = cat),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.brand600
                            : AppColors.secondary100,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        cat,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? Colors.white
                              : AppColors.secondary500,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _messageController,
              maxLines: 5,
              style: const TextStyle(
                  fontSize: 14, color: AppColors.brand950),
              decoration: InputDecoration(
                hintText: _category == 'Bug'
                    ? 'Décrivez le problème rencontré...'
                    : _category == 'Suggestion'
                        ? 'Décrivez votre suggestion...'
                        : 'Posez votre question...',
                hintStyle: const TextStyle(
                    fontSize: 13, color: AppColors.secondary300),
                filled: true,
                fillColor: AppColors.secondary50,
                contentPadding: const EdgeInsets.all(14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      const BorderSide(color: AppColors.secondary200),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      const BorderSide(color: AppColors.secondary200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                      color: AppColors.brand400, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
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
                    : const Text('Envoyer',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Change PIN sheet ──────────────────────────────────────────────────────────

class _ChangePinSheet extends StatefulWidget {
  const _ChangePinSheet({required this.user});
  final UserModel user;

  @override
  State<_ChangePinSheet> createState() => _ChangePinSheetState();
}

class _ChangePinSheetState extends State<_ChangePinSheet> {
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  bool _success = false;
  bool _showNew = false;

  bool get _hasPinSet => widget.user.pinHash != null;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final newPin = _newCtrl.text.trim();
    final confirmPin = _confirmCtrl.text.trim();

    if (newPin.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Le PIN doit contenir exactement 6 chiffres'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating),
      );
      return;
    }
    if (newPin != confirmPin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Les PINs ne correspondent pas'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating),
      );
      return;
    }

    // Si un PIN existe déjà, vérifier l'ancien PIN
    if (_hasPinSet) {
      final currentHash = _hashPin(_currentCtrl.text.trim());
      if (currentHash != widget.user.pinHash) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('PIN actuel incorrect'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating),
        );
        return;
      }
    }

    setState(() => _loading = true);
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.id)
          .update({'pinHash': _hashPin(newPin)});
      if (mounted) setState(() { _success = true; _loading = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                  color: AppColors.secondary200,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Text(
            _hasPinSet ? 'Changer le PIN de profil' : 'Définir un PIN de profil',
            style: GoogleFonts.dmSans(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: AppColors.brand950),
          ),
          const SizedBox(height: 6),
          Text(
            'Ce PIN sera demandé lors de la sélection de votre profil.',
            style: const TextStyle(fontSize: 13, color: AppColors.secondary400),
          ),
          const SizedBox(height: 20),
          if (_success) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline_rounded,
                      color: Color(0xFF16A34A), size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _hasPinSet
                          ? 'PIN modifié avec succès !'
                          : 'PIN défini avec succès !',
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF166534)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brand600,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Fermer',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
              ),
            ),
          ] else ...[
            // Ancien PIN (si déjà défini)
            if (_hasPinSet) ...[
              _PinInputField(
                controller: _currentCtrl,
                label: 'PIN actuel',
                showPin: false,
              ),
              const SizedBox(height: 14),
            ],
            // Nouveau PIN
            _PinInputField(
              controller: _newCtrl,
              label: 'Nouveau PIN (6 chiffres)',
              showPin: _showNew,
              suffixIcon: IconButton(
                icon: Icon(_showNew
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                    size: 18, color: AppColors.secondary400),
                onPressed: () => setState(() => _showNew = !_showNew),
              ),
            ),
            const SizedBox(height: 14),
            // Confirmer PIN
            _PinInputField(
              controller: _confirmCtrl,
              label: 'Confirmer le PIN',
              showPin: false,
            ),
            const SizedBox(height: 24),
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
                    : Text(
                        _hasPinSet ? 'Modifier le PIN' : 'Définir le PIN',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PinInputField extends StatelessWidget {
  const _PinInputField({
    required this.controller,
    required this.label,
    required this.showPin,
    this.suffixIcon,
  });
  final TextEditingController controller;
  final String label;
  final bool showPin;
  final Widget? suffixIcon;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: !showPin,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(6),
      ],
      style: const TextStyle(
          fontSize: 22, letterSpacing: 12, color: AppColors.brand950),
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            const TextStyle(fontSize: 13, color: AppColors.secondary400),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: AppColors.secondary50,
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
              const BorderSide(color: AppColors.brand500, width: 1.5),
        ),
      ),
    );
  }
}

// ── Edit profile sheet ────────────────────────────────────────────────────────

class _EditProfileSheet extends StatefulWidget {
  const _EditProfileSheet({required this.user, required this.onSaved});
  final UserModel user;
  final VoidCallback onSaved;

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _city;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.user.fullName);
    _phone = TextEditingController(text: widget.user.phone);
    _city = TextEditingController(text: widget.user.city);
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _city.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.id)
          .update({
        'fullName': _name.text.trim(),
        'phone': _phone.text.trim(),
        'city': _city.text.trim(),
      });
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
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.secondary200,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            'Modifier mon profil',
            style: GoogleFonts.dmSans(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: AppColors.brand950),
          ),
          const SizedBox(height: 20),
          _InputField(controller: _name, label: 'Nom complet'),
          const SizedBox(height: 12),
          _InputField(
              controller: _phone,
              label: 'Téléphone',
              keyboardType: TextInputType.phone),
          const SizedBox(height: 12),
          _InputField(controller: _city, label: 'Ville'),
          const SizedBox(height: 24),
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
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child, this.trailing});
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
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
              ?trailing,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _InputField extends StatelessWidget {
  const _InputField(
      {required this.controller,
      required this.label,
      this.keyboardType});
  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
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
