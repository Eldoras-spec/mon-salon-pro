import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import '../providers/auth_providers.dart';
import '../models/salon_model.dart';
import '../models/user_model.dart';
import '../models/appointment_model.dart';
import '../models/promotion_model.dart';
import 'client_salon_profile_screen.dart';
import 'client_search_screen.dart';
import 'client_all_recommended_screen.dart';
import 'notifications_screen.dart';
import '../theme/app_constants.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math' show cos, sqrt, asin, pi;

class ClientHomeScreen extends ConsumerStatefulWidget {
  const ClientHomeScreen({super.key});

  @override
  ConsumerState<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends ConsumerState<ClientHomeScreen> {
  final _databaseService = DatabaseService();
  UserModel? _user;
  String? _selectedCategory;
  String _selectedSort = 'Recommandé';
  Position? _currentUserPosition;
  final TextEditingController _searchController = TextEditingController();

  bool _isSalonOpen(Map<String, dynamic> workingHours) {
    if (workingHours.isEmpty) return false;

    final now = DateTime.now();
    // Keys stored in Firestore use French day names (set by owner onboarding step 3)
    const dayNames = [
      'lundi', 'mardi', 'mercredi', 'jeudi',
      'vendredi', 'samedi', 'dimanche',
    ];
    final dayConfig = workingHours[dayNames[now.weekday - 1]];
    if (dayConfig == null || dayConfig['isOpen'] != true) return false;

    try {
      final op = (dayConfig['open'] as String).split(':');
      final cl = (dayConfig['close'] as String).split(':');
      final nowMin = now.hour * 60 + now.minute;
      final openMin = int.parse(op[0]) * 60 + int.parse(op[1]);
      final closeMin = int.parse(cl[0]) * 60 + int.parse(cl[1]);
      return nowMin >= openMin && nowMin < closeMin;
    } catch (_) {
      return false;
    }
  }

  final _authService = AuthService();
  String _userName = 'Sarah Johnson'; // Default
  final List<Map<String, dynamic>> _categories = AppConstants.categories;
  List<AppointmentModel> _pastAppointments = [];
  late final Future<List<({SalonModel salon, PromotionModel promo})>>
      _dealsFuture;

  @override
  void initState() {
    super.initState();
    _dealsFuture = _databaseService.getDealsWithSalons();
    _loadUserData();
    _checkLocationPermission();
    _loadPastAppointments();
  }

  void _showLogoutSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.secondary300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.logout_rounded, color: Colors.red),
                title: Text(
                  'Se déconnecter',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w600,
                    color: Colors.red,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  await ref.read(authServiceProvider).signOut();
                  ref.invalidate(authStateProvider);
                  ref.invalidate(userModelProvider);
                  if (mounted) {
                    Navigator.of(context, rootNavigator: true)
                        .popUntil((route) => route.isFirst);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadPastAppointments() async {
    final uid = _authService.currentUserId;
    if (uid == null) return;
    try {
      final appointments = await _databaseService.getCompletedAppointmentsOnce(uid);
      if (mounted) {
        setState(() {
          _pastAppointments = appointments;
        });
      }
    } catch (_) {
      // Recommendations still work without history
    }
  }

  Future<void> _checkLocationPermission() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse) {
        final position = await Geolocator.getCurrentPosition();
        if (mounted) {
          setState(() {
            _currentUserPosition = position;
          });
        }
      }
    } catch (e) {
      debugPrint('Error getting location: $e');
    }
  }

  double _calculateDistance(double lat2, double lon2) {
    if (_currentUserPosition == null) return 0.0;

    // Using Haversine formula
    const p = pi / 180;
    final a =
        0.5 -
        cos((lat2 - _currentUserPosition!.latitude) * p) / 2 +
        cos(_currentUserPosition!.latitude * p) *
            cos(lat2 * p) *
            (1 - cos((lon2 - _currentUserPosition!.longitude) * p)) /
            2;
    return 12742 * asin(sqrt(a)); // 2 * R; R = 6371 km
  }

  // Recommendation score: combinedScore + boost spécifique au service
  double _recommendationScore(SalonModel salon, Map<String, dynamic> service) {
    double score = _combinedScore(salon);

    // Boost service-specific: le service correspond à l'historique du client (+0.15)
    if (_pastAppointments.isNotEmpty) {
      final pastKeywords = _pastAppointments
          .map((a) => a.serviceName.toLowerCase())
          .expand((name) => name.split(' ').where((w) => w.length > 3))
          .toSet();

      final serviceTitle =
          (service['title'] ?? service['name'] ?? '').toLowerCase();
      final serviceCategory = (service['category'] ?? '').toLowerCase();

      for (final keyword in pastKeywords) {
        if (serviceTitle.contains(keyword) || serviceCategory.contains(keyword)) {
          score += 0.15;
          break;
        }
      }
    }

    return score;
  }

  // Combined score: 60% rating + 40% proximity (higher = better)
  double _combinedScore(SalonModel salon) {
    // Bayesian weighted rating: avoids inflated scores from few reviews
    // k=10 (confidence threshold), C=3.0 (neutral prior)
    const double k = 10.0;
    const double C = 3.0;
    final n = salon.reviewCount.toDouble();
    final weightedRating = (n / (n + k)) * salon.rating + (k / (n + k)) * C;
    final ratingScore = weightedRating / 5.0;

    double score;
    if (_currentUserPosition == null ||
        salon.latitude == null ||
        salon.longitude == null) {
      score = ratingScore;
    } else {
      const double maxDistanceKm = 50.0;
      final distKm = _calculateDistance(salon.latitude!, salon.longitude!);
      final proximityScore = (1 - (distKm / maxDistanceKm)).clamp(0.0, 1.0);
      score = 0.6 * ratingScore + 0.4 * proximityScore;
    }

    // Boost favoris (+0.15)
    if (_user?.favorites.contains(salon.id) ?? false) {
      score += 0.15;
    }

    // Boost historique: salon déjà visité (+0.25)
    final visitedSalonIds = _pastAppointments.map((a) => a.salonId).toSet();
    if (visitedSalonIds.contains(salon.id)) {
      score += 0.25;
    }

    // Boost catégorie: services similaires à l'historique (+0.15)
    if (_pastAppointments.isNotEmpty) {
      final pastKeywords = _pastAppointments
          .map((a) => a.serviceName.toLowerCase())
          .expand((name) => name.split(' ').where((w) => w.length > 3))
          .toSet();
      final salonKeywords = salon.services
          .expand((s) => [
                (s['title'] ?? s['name'] ?? '').toString().toLowerCase(),
                (s['category'] ?? '').toString().toLowerCase(),
              ])
          .toSet();
      for (final keyword in pastKeywords) {
        if (salonKeywords.any((sk) => sk.contains(keyword))) {
          score += 0.15;
          break;
        }
      }
    }

    return score;
  }

  Future<void> _loadUserData() async {
    final uid = _authService.currentUserId;
    if (uid != null) {
      final user = await _authService.getUserModel(uid);
      if (user != null && mounted) {
        setState(() {
          _user = user;
          _userName = user.fullName;
        });
      }
    }
  }

  Future<void> _claimOffer() async {
    if (_user == null || _user!.hasClaimedOffer) return;

    try {
      await _databaseService.claimFirstBookingOffer(_user!.id);

      // Update local state
      setState(() {
        _user = UserModel(
          id: _user!.id,
          email: _user!.email,
          fullName: _user!.fullName,
          phone: _user!.phone,
          city: _user!.city,
          userType: _user!.userType,
          profileImageUrl: _user!.profileImageUrl,
          favorites: _user!.favorites,
          fcmToken: _user!.fcmToken,
          hasClaimedOffer: true,
          createdAt: _user!.createdAt,
        );
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Offre de 10% activée ! Utilisez le code ELITE10 au paiement.',
            ),
            backgroundColor: AppColors.brand600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de l\'activation: $e')),
        );
      }
    }
  }

  void _showFilterModal() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Filtres',
                    style: GoogleFonts.dmSans(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Trier par',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Recommandé'),
                        selected: _selectedSort == 'Recommandé',
                        selectedColor: AppColors.brand100,
                        onSelected: (v) {
                          if (v) {
                            setModalState(() => _selectedSort = 'Recommandé');
                            setState(() {});
                          }
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Proximité'),
                        selected: _selectedSort == 'Proximité',
                        selectedColor: AppColors.brand100,
                        onSelected: (v) {
                          if (v) {
                            setModalState(() => _selectedSort = 'Proximité');
                            setState(() {});
                          }
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Prix'),
                        selected: _selectedSort == 'Prix',
                        selectedColor: AppColors.brand100,
                        onSelected: (v) {
                          if (v) {
                            setModalState(() => _selectedSort = 'Prix');
                            setState(() {});
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brand600,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'Appliquer',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showAllCategoriesModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.6,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Toutes les catégories',
                    style: GoogleFonts.dmSans(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: AppColors.secondary900,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.close,
                      color: AppColors.secondary400,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 24,
                    childAspectRatio: 0.8,
                  ),
                  itemCount: _categories.length,
                  itemBuilder: (context, index) {
                    final c = _categories[index];
                    final categoryName = c['name'] as String;
                    final isSelected = _selectedCategory == categoryName;

                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          if (_selectedCategory == categoryName) {
                            _selectedCategory = null;
                          } else {
                            _selectedCategory = categoryName;
                          }
                        });
                        Navigator.pop(context);
                      },
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.brand50
                                  : AppColors.secondary50,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.brand200
                                    : Colors.transparent,
                              ),
                            ),
                            child: Icon(
                              c['icon'] as IconData,
                              color: isSelected
                                  ? AppColors.brand600
                                  : AppColors.secondary500,
                              size: 30,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            categoryName,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              color: isSelected
                                  ? AppColors.brand600
                                  : AppColors.secondary700,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        _buildMobileSliverAppBar(),
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              _buildCategories(isDesktop: false),
              _buildFeaturedSalons(isDesktop: false),
              _buildPromoBanner(isDesktop: false),
              _buildRecommendedServices(isDesktop: false),
              _buildWeeklyDeals(),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ],
    );
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Bonjour,';
    if (hour < 18) return 'Bon après-midi,';
    return 'Bonsoir,';
  }

  Widget _buildMobileSliverAppBar() {
    final statusBarHeight = MediaQuery.of(context).padding.top;
    const contentHeight = 155.0;
    final totalHeight = statusBarHeight + contentHeight;

    return SliverPersistentHeader(
      pinned: true,
      delegate: _FixedHeaderDelegate(
        height: totalHeight,
        child: Material(
          color: Colors.white,
          elevation: 3,
          shadowColor: Colors.black.withValues(alpha: 0.08),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(28),
              bottomRight: Radius.circular(28),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: statusBarHeight),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _greeting,
                          style: GoogleFonts.plusJakartaSans(
                            color: AppColors.secondary500,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _userName,
                          style: GoogleFonts.dmSans(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppColors.secondary900,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        StreamBuilder<int>(
                          stream: _user != null
                              ? _databaseService.getUnreadNotificationCount(_user!.id)
                              : const Stream.empty(),
                          builder: (context, snapshot) {
                            final unread = snapshot.data ?? 0;
                            return GestureDetector(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const NotificationsScreen(),
                                ),
                              ),
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white,
                                      border: Border.all(color: AppColors.secondary100),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.05),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.notifications_none_rounded,
                                      color: AppColors.secondary600,
                                      size: 20,
                                    ),
                                  ),
                                  if (unread > 0)
                                    Positioned(
                                      top: -2,
                                      right: -2,
                                      child: Container(
                                        width: 16,
                                        height: 16,
                                        decoration: const BoxDecoration(
                                          color: AppColors.brand500,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Center(
                                          child: Text(
                                            unread > 9 ? '9+' : '$unread',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: () => _showLogoutSheet(),
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.secondary100, width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.06),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: CircleAvatar(
                              radius: 19,
                              backgroundColor: AppColors.secondary100,
                              backgroundImage: _user?.profileImageUrl != null
                                  ? NetworkImage(_user!.profileImageUrl!)
                                  : null,
                              child: _user?.profileImageUrl == null
                                  ? const Icon(Icons.person, size: 20, color: AppColors.secondary400)
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.secondary50,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _searchController,
                    readOnly: true,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ClientSearchScreen(),
                      ),
                    ),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      color: AppColors.secondary900,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Rechercher salon, service ou lieu...',
                      hintStyle: GoogleFonts.plusJakartaSans(
                        color: AppColors.secondary400,
                        fontSize: 13,
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: AppColors.secondary400,
                        size: 20,
                      ),
                      suffixIcon: Container(
                        margin: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.tune_rounded, color: AppColors.secondary600, size: 18),
                          onPressed: _showFilterModal,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                        ),
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategories({required bool isDesktop}) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 0 : 24.0,
        vertical: 16,
      ),
      child: Column(
        children: [
          _buildSectionHeader(
            label: 'PARCOURIR',
            title: 'Catégories',
            actionLabel: 'Voir tout',
            onAction: _showAllCategoriesModal,
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              children: _categories.map((c) {
                final categoryName = c['name'] as String;
                final isSelected = _selectedCategory == categoryName;
                return Padding(
                  padding: const EdgeInsets.only(right: 16.0),
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        if (_selectedCategory == categoryName) {
                          _selectedCategory = null;
                        } else {
                          _selectedCategory = categoryName;
                        }
                      });
                    },
                    child: Column(
                      children: [
                        Container(
                          width: isDesktop ? 80 : 64,
                          height: isDesktop ? 80 : 64,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.brand50
                                : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.brand200
                                  : AppColors.secondary100,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black12,
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Icon(
                            c['icon'] as IconData,
                            color: isSelected
                                ? AppColors.brand600
                                : AppColors.secondary400,
                            size: 24,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          categoryName,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.w500,
                            color: isSelected
                                ? AppColors.brand600
                                : AppColors.secondary600,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturedSalons({required bool isDesktop}) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 0 : 24.0,
        vertical: 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildSectionHeader(
                label: 'EN VEDETTE',
                title: 'Salons',
                subtitle: 'Les meilleurs salons près de chez vous',
              ),
              if (isDesktop)
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.secondary200),
                      ),
                      child: const Icon(
                        Icons.chevron_left,
                        size: 16,
                        color: AppColors.secondary400,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.secondary200),
                      ),
                      child: const Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: AppColors.secondary400,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 16),
          StreamBuilder<List<SalonModel>>(
            stream: _databaseService.salons,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              var salons = snapshot.data ?? [];

              // Filter by selected category (client-side)
              if (_selectedCategory != null) {
                salons = salons
                    .where((s) => s.serviceCategories.contains(_selectedCategory))
                    .toList();
              }

              // Apply Sorting
              if (_selectedSort == 'Recommandé') {
                salons.sort((a, b) => _combinedScore(b).compareTo(_combinedScore(a)));
              } else if (_selectedSort == 'Prix') {
                salons.sort((a, b) {
                  final priceA = a.services.isEmpty
                      ? 0.0
                      : a.services
                            .map((s) => (s['price'] ?? 0.0).toDouble())
                            .reduce((curr, next) => curr < next ? curr : next);
                  final priceB = b.services.isEmpty
                      ? 0.0
                      : b.services
                            .map((s) => (s['price'] ?? 0.0).toDouble())
                            .reduce((curr, next) => curr < next ? curr : next);
                  return priceA.compareTo(priceB);
                });
              } else if (_selectedSort == 'Proximité') {
                if (_currentUserPosition != null) {
                  salons.sort((a, b) {
                    if (a.latitude == null || a.longitude == null) return 1;
                    if (b.latitude == null || b.longitude == null) return -1;
                    final distA = _calculateDistance(a.latitude!, a.longitude!);
                    final distB = _calculateDistance(b.latitude!, b.longitude!);
                    return distA.compareTo(distB);
                  });
                } else {
                  salons.shuffle(); // Fallback if location not available
                }
              }

              if (salons.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.secondary50,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Center(
                    child: Text(
                      'Aucun salon disponible pour le moment.',
                      style: TextStyle(color: AppColors.secondary500),
                    ),
                  ),
                );
              }

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: salons.map((salon) {
                    return _buildFeaturedSalonCard(
                      salon: salon,
                      imageUrl: salon.images.isNotEmpty
                          ? salon.images[0]
                          : 'https://images.unsplash.com/photo-1560066984-138dadb4c035?ixlib=rb-4.0.3&auto=format&fit=crop&w=1000&q=80',
                      name: salon.name,
                      distance: salon.address,
                      isOpen: _isSalonOpen(salon.workingHours),
                      tags: [salon.category],
                      rating: salon.reviewCount > 0 ? salon.rating.toStringAsFixed(1) : null,
                      isDesktop: isDesktop,
                      isFavorite: _user?.favorites.contains(salon.id) ?? false,
                      onFavoriteTap: () async {
                        final uid = _authService.currentUserId;
                        if (uid == null) return;
                        final isFav = _user?.favorites.contains(salon.id) ?? false;
                        await DatabaseService().toggleFavorite(uid, salon.id, !isFav);
                        _loadUserData();
                      },
                    );
                  }).toList(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturedSalonCard({
    required SalonModel salon,
    required String imageUrl,
    required String name,
    required String distance,
    required bool isOpen,
    required List<String> tags,
    String? rating,
    required bool isDesktop,
    bool isFavorite = false,
    VoidCallback? onFavoriteTap,
  }) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ClientSalonProfileScreen(salon: salon),
          ),
        );
      },
      child: Container(
        width: isDesktop ? 340 : 280,
        margin: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.secondary100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: isDesktop ? 190 : 160,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                image: DecorationImage(
                  image: NetworkImage(imageUrl),
                  fit: BoxFit.cover,
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    top: 12,
                    left: 12,
                    child: GestureDetector(
                      onTap: onFavoriteTap,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isFavorite
                              ? AppColors.brand600.withValues(alpha: 0.85)
                              : Colors.black26,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isFavorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: rating != null
                          ? Row(
                              children: [
                                const Icon(Icons.star, color: Colors.amber, size: 12),
                                const SizedBox(width: 4),
                                Text(
                                  rating,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            )
                          : const Text(
                              'Nouveau',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppColors.brand600,
                              ),
                            ),
                    ),
                  ),
                  Positioned(
                    bottom: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isOpen
                            ? const Color(0xFF22C55E)
                            : const Color(0xFFEF4444),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        isOpen ? 'OPEN' : 'CLOSED',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.dmSans(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.secondary900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isOpen
                              ? Colors.green.withValues(alpha: 0.1)
                              : Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isOpen ? 'OPEN' : 'CLOSED',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isOpen ? Colors.green : Colors.red,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on,
                        color: AppColors.brand400,
                        size: 12,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          distance.length > 35
                              ? '${distance.substring(0, 35)}...'
                              : distance,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.secondary500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: tags
                        .map(
                          (t) => Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.secondary50,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppColors.secondary100),
                            ),
                            child: Text(
                              t,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.secondary500,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required String label,
    required String title,
    String? subtitle,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 18, height: 1.5, color: AppColors.brand500),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.5,
                    color: AppColors.brand500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: GoogleFonts.dmSans(
                fontSize: 28,
                fontWeight: FontWeight.w600,
                fontStyle: FontStyle.italic,
                color: AppColors.secondary900,
                height: 1.1,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppColors.secondary500,
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
        if (actionLabel != null)
          GestureDetector(
            onTap: onAction,
            child: Row(
              children: [
                Text(
                  actionLabel,
                  style: const TextStyle(
                    color: AppColors.brand600,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 3),
                const Icon(Icons.arrow_forward, size: 13, color: AppColors.brand600),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildPromoBanner({required bool isDesktop}) {
    final promoUsed = _user?.promoCodeUsed ?? false;
    final claimed = _user?.hasClaimedOffer ?? false;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 0 : 24.0,
        vertical: 16,
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        child: promoUsed
            ? _buildUsedBanner(isDesktop: isDesktop)
            : claimed
                ? _buildClaimedBanner(isDesktop: isDesktop)
                : _buildUnclaimedBanner(isDesktop: isDesktop),
      ),
    );
  }

  Widget _buildUnclaimedBanner({required bool isDesktop}) {
    return Container(
      key: const ValueKey('unclaimed'),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.brand900,
        borderRadius: BorderRadius.circular(16),
        image: const DecorationImage(
          image: NetworkImage(
            'https://images.unsplash.com/photo-1562322140-8baeececf3df?ixlib=rb-4.0.3&auto=format&fit=crop&w=1000&q=80',
          ),
          fit: BoxFit.cover,
          opacity: 0.2,
        ),
      ),
      child: isDesktop
          ? Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildUnclaimedText(fontSize: 26),
                ElevatedButton(
                  onPressed: _claimOffer,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.brand900,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Profiter maintenant',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            )
          : Column(
              children: [
                _buildUnclaimedText(fontSize: 24),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _claimOffer,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.brand900,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Profiter maintenant',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildUnclaimedText({required double fontSize}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'OFFRE SPÉCIALE',
          style: TextStyle(
            color: AppColors.brand200,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '-10% sur votre 1ère réservation',
          style: GoogleFonts.dmSans(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text(
              'Code : ',
              style: TextStyle(color: AppColors.brand100, fontSize: 14),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'ELITE10',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const Text(
              ' à la réservation.',
              style: TextStyle(color: AppColors.brand100, fontSize: 14),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildUsedBanner({required bool isDesktop}) {
    return Container(
      key: const ValueKey('used'),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: const Color(0xFF374151),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          // Badge utilisé
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_outline, color: Colors.white54, size: 16),
                SizedBox(width: 6),
                Text(
                  'OFFRE UTILISÉE',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Code déjà utilisé',
            style: GoogleFonts.dmSans(
              fontSize: isDesktop ? 28 : 22,
              fontWeight: FontWeight.bold,
              color: Colors.white54,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Vous avez déjà bénéficié de cette offre de bienvenue',
            style: TextStyle(color: Colors.white38, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          // Coupon barré
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF4B5563),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12, width: 1.5),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.local_offer, color: Colors.white24, size: 20),
                const SizedBox(width: 10),
                Stack(
                  alignment: Alignment.center,
                  children: [
                    const Text(
                      'ELITE10',
                      style: TextStyle(
                        color: Colors.white24,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                        letterSpacing: 4,
                      ),
                    ),
                    Container(
                      height: 2,
                      width: 130,
                      color: Colors.white38,
                    ),
                  ],
                ),
                const SizedBox(width: 10),
                const Text(
                  '— 10%',
                  style: TextStyle(
                    color: Colors.white24,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClaimedBanner({required bool isDesktop}) {
    return Container(
      key: const ValueKey('claimed'),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1B4332), Color(0xFF2D6A4F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          // Badge succès
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, color: Colors.greenAccent, size: 16),
                SizedBox(width: 6),
                Text(
                  'OFFRE ACTIVÉE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Votre réduction est prête !',
            style: GoogleFonts.dmSans(
              fontSize: isDesktop ? 28 : 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Utilisez ce code lors de votre prochain paiement',
            style: TextStyle(color: Colors.white70, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          // Coupon ticket
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.greenAccent.withValues(alpha: 0.5),
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.local_offer, color: Color(0xFF2D6A4F), size: 20),
                const SizedBox(width: 10),
                const Text(
                  'ELITE10',
                  style: TextStyle(
                    color: Color(0xFF1B4332),
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  '— 10%',
                  style: TextStyle(
                    color: Color(0xFF2D6A4F),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Bouton copier
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(const ClipboardData(text: 'ELITE10'));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Code ELITE10 copié !'),
                    backgroundColor: const Color(0xFF2D6A4F),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              icon: const Icon(Icons.copy, size: 16, color: Colors.white),
              label: const Text(
                'Copier le code',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: Colors.white54),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendedServices({required bool isDesktop}) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 0 : 24.0,
        vertical: 24,
      ),
      child: Column(
        children: [
          _buildSectionHeader(
            label: 'RECOMMANDÉS',
            title: 'Pour Vous',
            actionLabel: 'Voir tout',
            onAction: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ClientAllRecommendedScreen(
                  user: _user,
                  pastAppointments: _pastAppointments,
                  userPosition: _currentUserPosition,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          StreamBuilder<List<SalonModel>>(
            stream: _databaseService.salons,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final salons = snapshot.data ?? [];
              if (salons.isEmpty) {
                return const Center(
                  child: Text('Aucune recommandation disponible pour le moment.'),
                );
              }

              // Logic for recommendations:
              // 1. Flatten all services from all salons
              // 2. Pair each service with its salon info
              // 3. Filter by salon rating if applicable
              // 4. Shuffle and pick 4
              final List<Map<String, dynamic>> allServicesWithSalon = [];
              outer:
              for (var salon in salons) {
                for (var service in salon.services) {
                  allServicesWithSalon.add({
                    'salon': salon,
                    'service': service,
                  });
                  if (allServicesWithSalon.length >= 20) break outer;
                }
              }

              allServicesWithSalon.sort((a, b) {
                final scoreA = _recommendationScore(a['salon'], a['service']);
                final scoreB = _recommendationScore(b['salon'], b['service']);
                return scoreB.compareTo(scoreA);
              });
              final displayServices = allServicesWithSalon.take(4).toList();

              if (isDesktop) {
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 3.2,
                  ),
                  itemCount: displayServices.length,
                  itemBuilder: (context, index) {
                    final SalonModel salon = displayServices[index]['salon'];
                    final Map<String, dynamic> service = displayServices[index]['service'];
                    return _buildServiceCard(salon: salon, service: service, isDesktop: true);
                  },
                );
              }
              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: displayServices.length,
                separatorBuilder: (context, index) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final SalonModel salon = displayServices[index]['salon'];
                  final Map<String, dynamic> service = displayServices[index]['service'];
                  return _buildServiceCard(salon: salon, service: service, isDesktop: false);
                },
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Weekly Deals ────────────────────────────────────────────────────────────

  Widget _buildWeeklyDeals() {
    return FutureBuilder<List<({SalonModel salon, PromotionModel promo})>>(
      future: _dealsFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }
        final raw = snap.data ?? [];
        if (raw.isEmpty) return const SizedBox.shrink();

        // Filter by distance (≤ 100 km) when position is available, then sort
        // by combined score (60 % rating + 40 % proximity) — same formula as
        // the featured-salons section.
        final deals = raw
            .where((d) {
              if (_currentUserPosition != null &&
                  d.salon.latitude != null &&
                  d.salon.longitude != null) {
                final dist = _calculateDistance(
                    d.salon.latitude!, d.salon.longitude!);
                return dist <= 100.0;
              }
              return true; // no position yet → keep all
            })
            .toList()
          ..sort((a, b) =>
              _combinedScore(b.salon).compareTo(_combinedScore(a.salon)));

        if (deals.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Section header
              Row(
                children: [
                  Container(
                    width: 20,
                    height: 2,
                    color: const Color(0xFFEA580C),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'DEALS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFFEA580C),
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Offres de la Semaine',
                style: GoogleFonts.dmSans(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.brand950,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 210,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  itemCount: deals.length,
                  separatorBuilder: (_, i) => const SizedBox(width: 14),
                  itemBuilder: (context, i) => _DealCard(
                    salon: deals[i].salon,
                    promo: deals[i].promo,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            ClientSalonProfileScreen(salon: deals[i].salon),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildServiceCard({
    required SalonModel salon,
    required Map<String, dynamic> service,
    required bool isDesktop,
  }) {
    final name = service['name'] ?? 'Service';
    final price = '\$${service['price'] ?? 0}';
    final details = '${salon.name} • ${service['duration'] ?? 0} mins';
    final reviews = '${salon.rating} (${salon.reviewCount} reviews)';
    final imageUrl = salon.images.isNotEmpty
        ? salon.images[0]
        : 'https://images.unsplash.com/photo-1560066984-138dadb4c035?ixlib=rb-4.0.3&auto=format&fit=crop&w=300&q=80';

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ClientSalonProfileScreen(salon: salon),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.secondary100),
        ),
        child: Row(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                image: DecorationImage(
                  image: NetworkImage(imageUrl),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: AppColors.secondary900,
                          ),
                        ),
                      ),
                      Text(
                        price,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: AppColors.brand600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    details,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.secondary500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.star, color: Colors.amber, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            reviews,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: AppColors.secondary700,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.secondary50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Book',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: AppColors.secondary900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Deal Card ─────────────────────────────────────────────────────────────────

class _DealCard extends StatelessWidget {
  const _DealCard({
    required this.salon,
    required this.promo,
    required this.onTap,
  });
  final SalonModel salon;
  final PromotionModel promo;
  final VoidCallback onTap;

  static const _typeBg = {
    'percent': Color(0xFFEFF6FF),
    'special': Color(0xFFFDF4FF),
    'code': Color(0xFFFFF7ED),
  };
  static const _typeColor = {
    'percent': Color(0xFF2563EB),
    'special': Color(0xFF9333EA),
    'code': Color(0xFFEA580C),
  };
  static const _typeIcon = {
    'percent': Icons.percent_rounded,
    'special': Icons.redeem_outlined,
    'code': Icons.confirmation_number_outlined,
  };
  static const _typeLabel = {
    'percent': '% Réduction',
    'special': 'Offre spéciale',
    'code': 'Code promo',
  };

  @override
  Widget build(BuildContext context) {
    final bg = _typeBg[promo.type] ?? AppColors.brand50;
    final color = _typeColor[promo.type] ?? AppColors.brand600;
    final icon = _typeIcon[promo.type] ?? Icons.local_offer_outlined;
    final typeLabel = _typeLabel[promo.type] ?? 'Promo';
    final imageUrl =
        salon.images.isNotEmpty ? salon.images[0] : null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 220,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.secondary100),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(18)),
                  child: imageUrl != null
                      ? Image.network(
                          imageUrl,
                          height: 110,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, e, s) => _imagePlaceholder(),
                        )
                      : _imagePlaceholder(),
                ),
                // Promo type badge
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 12, color: color),
                        const SizedBox(width: 4),
                        Text(
                          promo.discountPercent != null
                              ? '-${promo.discountPercent!.toStringAsFixed(0)}%'
                              : typeLabel,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // Content
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Salon name + rating
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          salon.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: AppColors.brand950,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(Icons.star_rounded,
                          size: 12, color: Colors.amber),
                      const SizedBox(width: 2),
                      Text(
                        salon.rating.toStringAsFixed(1),
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.secondary600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Promo title
                  Text(
                    promo.title,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.secondary600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  // CTA
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        salon.city,
                        style: const TextStyle(
                            fontSize: 10, color: AppColors.secondary400),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.brand700,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Voir →',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imagePlaceholder() => Container(
        height: 110,
        color: AppColors.secondary100,
        alignment: Alignment.center,
        child: const Icon(Icons.store_outlined,
            size: 36, color: AppColors.secondary300),
      );
}

// ── Fixed-height SliverPersistentHeader delegate ─────────────────────────────
class _FixedHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final Widget child;

  const _FixedHeaderDelegate({required this.height, required this.child});

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox.expand(child: child);
  }

  @override
  bool shouldRebuild(_FixedHeaderDelegate old) =>
      old.height != height || old.child != child;
}
