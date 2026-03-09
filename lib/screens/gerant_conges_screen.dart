import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/owner_providers.dart';
import '../providers/team_providers.dart';
import '../theme/app_colors.dart';
import 'member_home_screen.dart';

class GerantCongesScreen extends ConsumerWidget {
  const GerantCongesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final member = ref.watch(activeTeamMemberProvider);
    final salonAsync = ref.watch(ownerSalonProvider);

    if (member == null) return const SizedBox.shrink();

    return Scaffold(
      backgroundColor: AppColors.secondary50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Mes Indisponibilités',
          style: TextStyle(
            fontFamily: 'DmSans',
            fontWeight: FontWeight.bold,
            fontSize: 20,
            color: AppColors.brand950,
          ),
        ),
      ),
      body: salonAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.brand500),
        ),
        error: (e, _) => Center(child: Text('Erreur: $e')),
        data: (salon) {
          if (salon == null) {
            return const Center(
              child: Text(
                'Salon introuvable',
                style: TextStyle(color: AppColors.secondary400),
              ),
            );
          }
          return UnavailabilityTab(salonId: salon.id, member: member);
        },
      ),
    );
  }
}
