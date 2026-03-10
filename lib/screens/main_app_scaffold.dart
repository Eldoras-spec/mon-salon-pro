import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_colors.dart';
import '../models/user_model.dart';
import '../providers/team_providers.dart';
import '../utils/page_transitions.dart';
import 'client_profile_screen.dart';
import 'conversations_screen.dart';
import 'gerant_conges_screen.dart';
import 'owner_appointments_screen.dart';
import 'owner_finances_screen.dart';
import 'owner_home_screen.dart';
import 'owner_inventory_screen.dart';
import 'owner_promotions_screen.dart';
import 'owner_boutique_screen.dart';
import 'owner_salon_screen.dart';
import 'owner_agenda_screen.dart';
import 'owner_clients_screen.dart';
import 'owner_statistics_screen.dart';
import 'owner_team_screen.dart';

class MainAppScaffold extends ConsumerStatefulWidget {
  final UserModel userModel;
  const MainAppScaffold({super.key, required this.userModel});

  @override
  ConsumerState<MainAppScaffold> createState() => _MainAppScaffoldState();
}

class _MainAppScaffoldState extends ConsumerState<MainAppScaffold> {
  int _currentIndex = 0;

  static const List<Widget> _ownerScreens = [
    OwnerHomeScreen(),
    OwnerAppointmentsScreen(),
    OwnerSalonScreen(),
    ClientProfileScreen(),
  ];

  static const List<Widget> _gerantScreens = [
    OwnerHomeScreen(),
    OwnerAppointmentsScreen(),
    GerantCongesScreen(),
    ClientProfileScreen(),
  ];

  void _onTabTapped(int index) {
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final activeMember = ref.watch(activeTeamMemberProvider);
    final isGerant = activeMember?.role == 'gerant';

    final screens = isGerant ? _gerantScreens : _ownerScreens;

    if (_currentIndex >= screens.length) _currentIndex = 0;

    return Scaffold(
      backgroundColor: AppColors.secondary50,
      body: screens[_currentIndex],
      bottomNavigationBar: _buildBottomNav(isGerant),
      floatingActionButton: _buildOwnerFAB(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  Widget _buildOwnerFAB() {
    return FloatingActionButton(
      onPressed: _showOwnerMenu,
      backgroundColor: AppColors.brand900,
      shape: const CircleBorder(
        side: BorderSide(color: Colors.white, width: 4),
      ),
      child: const Icon(Icons.add, color: Colors.white),
    );
  }

  void _showOwnerMenu() {
    final activeMember = ref.read(activeTeamMemberProvider);
    final isGerant = activeMember?.role == 'gerant';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.secondary200,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Actions rapides',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.brand950,
                      fontFamily: 'DmSans',
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),

              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: EdgeInsets.zero,
                  children: [
            _buildMenuTile(
              icon: Icons.calendar_view_day_outlined,
              iconBg: AppColors.brand50,
              iconColor: AppColors.brand600,
              label: 'Agenda',
              sub: 'Planning de l\'équipe',
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).pushSlide(
                  OwnerAgendaScreen(salonId: widget.userModel.id),
                );
              },
            ),
            _buildMenuTile(
              icon: Icons.calendar_month_outlined,
              iconBg: const Color(0xFFEFF6FF),
              iconColor: const Color(0xFF2563EB),
              label: 'Rendez-vous du jour',
              sub: 'Voir les réservations d\'aujourd\'hui',
              onTap: () {
                Navigator.pop(context);
                setState(() => _currentIndex = 1);
              },
            ),
            if (!isGerant)
              _buildMenuTile(
                icon: Icons.content_cut_outlined,
                iconBg: const Color(0xFFF0FDF4),
                iconColor: const Color(0xFF16A34A),
                label: 'Gérer les services',
                sub: 'Ajouter ou modifier vos services',
                onTap: () {
                  Navigator.pop(context);
                  setState(() => _currentIndex = 2);
                },
              ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Divider(height: 1, color: AppColors.secondary100),
            ),

            _buildMenuTile(
              icon: Icons.chat_outlined,
              iconBg: const Color(0xFFFDF2F8),
              iconColor: const Color(0xFFDB2777),
              label: 'Messages',
              sub: 'Conversations avec les clients',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ConversationsScreen(
                      currentUserId: widget.userModel.id,
                      isClient: false,
                    ),
                  ),
                );
              },
            ),
            _buildMenuTile(
              icon: Icons.inventory_2_outlined,
              iconBg: const Color(0xFFFFF7ED),
              iconColor: const Color(0xFFEA580C),
              label: 'Stock & Produits',
              sub: 'Gérez vos produits et consommables',
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).pushSlide(const OwnerInventoryScreen());
              },
            ),
            _buildMenuTile(
              icon: Icons.account_balance_wallet_outlined,
              iconBg: const Color(0xFFF0FDF4),
              iconColor: const Color(0xFF059669),
              label: 'Finances',
              sub: 'Charges, revenus et bénéfice net',
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).pushSlide(const OwnerFinancesScreen());
              },
            ),
            if (!isGerant)
              _buildMenuTile(
                icon: Icons.local_offer_outlined,
                iconBg: const Color(0xFFFDF4FF),
                iconColor: const Color(0xFF9333EA),
                label: 'Offres & Promotions',
                sub: 'Réductions, codes promo et offres spéciales',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).pushSlide(const OwnerPromotionsScreen());
                },
              ),
            _buildMenuTile(
              icon: Icons.storefront_outlined,
              iconBg: const Color(0xFFFFF7ED),
              iconColor: const Color(0xFFEA580C),
              label: 'Boutique',
              sub: 'Produits, commandes et livraisons',
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).pushSlide(const OwnerBoutiqueScreen());
              },
            ),
            if (!isGerant)
              _buildMenuTile(
                icon: Icons.groups_outlined,
                iconBg: const Color(0xFFEFF6FF),
                iconColor: const Color(0xFF2563EB),
                label: 'Mon Équipe',
                sub: 'Membres, rôles et disponibilités',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).pushSlide(const OwnerTeamScreen());
                },
              ),
            _buildMenuTile(
              icon: Icons.people_outline,
              iconBg: const Color(0xFFFFF1F2),
              iconColor: const Color(0xFFE11D48),
              label: 'Mes clients',
              sub: 'Historique, contacts et fidélité',
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).pushSlide(const OwnerClientsScreen());
              },
            ),
            _buildMenuTile(
              icon: Icons.bar_chart_rounded,
              iconBg: const Color(0xFFF0F9FF),
              iconColor: const Color(0xFF0284C7),
              label: 'Statistiques',
              sub: 'Analyses détaillées et performances',
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).pushSlide(const OwnerStatisticsScreen());
              },
            ),
            const SizedBox(height: 8),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuTile({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String label,
    required String sub,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: iconBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
          color: AppColors.brand950,
        ),
      ),
      subtitle: Text(
        sub,
        style: const TextStyle(
          fontSize: 12,
          color: AppColors.secondary400,
        ),
      ),
      trailing: const Icon(Icons.chevron_right_rounded,
          color: AppColors.secondary300, size: 20),
    );
  }

  Widget _buildBottomNav(bool isGerant) {
    return BottomAppBar(
      color: Colors.white,
      elevation: 20,
      shadowColor: Colors.black12,
      shape: const CircularNotchedRectangle(),
      notchMargin: 8.0,
      child: SizedBox(
        height: 60,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(Icons.grid_view_rounded, 'Accueil', 0),
            _buildNavItem(Icons.calendar_month_rounded, 'RDV', 1),
            const SizedBox(width: 48),
            isGerant
                ? _buildNavItem(Icons.event_busy_rounded, 'Indispo', 2)
                : _buildNavItem(Icons.store_rounded, 'Salon', 2),
            _buildNavItem(Icons.person_rounded, 'Profil', 3),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index) {
    final isSelected = _currentIndex == index;
    final color = isSelected ? AppColors.brand600 : AppColors.secondary400;

    return InkWell(
      onTap: () => _onTabTapped(index),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.brand50 : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
