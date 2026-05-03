import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'owner_providers.dart';

enum SetupTaskKey {
  googleReview,
  firstPromo,
  firstProduct,
  salonImages,
  team,
  loyalty,
  smartPromotions,
  classifyEmployees,
  beforeAfter,
}

class SetupTask {
  const SetupTask({
    required this.key,
    required this.priority,
  });

  final SetupTaskKey key;
  final int priority;
}

final _db = FirebaseFirestore.instance;

/// List of setup tasks NOT yet done AND not dismissed by the owner.
final setupTasksProvider = Provider<List<SetupTask>>((ref) {
  final salon = ref.watch(ownerSalonProvider).value;
  if (salon == null) return [];

  final promos = ref.watch(ownerPromotionsProvider).value ?? [];
  final products = ref.watch(ownerProductsProvider).value ?? [];
  final team = ref.watch(ownerTeamProvider).value ?? [];
  final beforeAfter = ref.watch(ownerBeforeAfterProvider).value ?? [];

  final dismissed = salon.dismissedSetupTasks;
  final grr = salon.googleReviewReward;

  // Classification suggestion:
  //  - relevant: at least one service has 2+ eligible members
  //  - AND the owner hasn't classified any service yet (no memberPriority set
  //    anywhere). Once they classify a single service, the task auto-hides —
  //    they don't have to rank every service to dismiss the nudge.
  final hasMultiMemberService = salon.services.any((svc) {
    final name = (svc['name'] ?? svc['title']) as String?;
    if (name == null || name.isEmpty) return false;
    final count = team
        .where((m) => m.isActive && m.assignedServiceNames.contains(name))
        .length;
    return count >= 2;
  });
  final anyPrioritySet = salon.services.any(
      (svc) => (svc['memberPriority'] as List?)?.isNotEmpty == true);
  final needsClassification = hasMultiMemberService && !anyPrioritySet;

  final all = <SetupTask>[
    if (!(grr['enabled'] == true))
      const SetupTask(key: SetupTaskKey.googleReview, priority: 1),
    if (promos.isEmpty)
      const SetupTask(key: SetupTaskKey.firstPromo, priority: 2),
    if (products.isEmpty)
      const SetupTask(key: SetupTaskKey.firstProduct, priority: 3),
    if (salon.images.length < 3)
      const SetupTask(key: SetupTaskKey.salonImages, priority: 4),
    if (team.isEmpty)
      const SetupTask(key: SetupTaskKey.team, priority: 5),
    if (needsClassification)
      const SetupTask(key: SetupTaskKey.classifyEmployees, priority: 6),
    if (beforeAfter.isEmpty)
      const SetupTask(key: SetupTaskKey.beforeAfter, priority: 7),
    if (!salon.rewardPointsEnabled)
      const SetupTask(key: SetupTaskKey.loyalty, priority: 8),
    if (!salon.aiPromosEnabled)
      const SetupTask(key: SetupTaskKey.smartPromotions, priority: 9),
  ];

  return all.where((t) => !dismissed.contains(t.key.name)).toList()
    ..sort((a, b) => a.priority.compareTo(b.priority));
});

/// Mark a setup task as dismissed (stores the key in
/// `salons/{id}.dismissedSetupTasks` array).
Future<void> dismissSetupTask(String salonId, SetupTaskKey key) {
  return _db.collection('salons').doc(salonId).update({
    'dismissedSetupTasks': FieldValue.arrayUnion([key.name]),
  });
}

/// Re-show all previously dismissed tasks.
Future<void> clearDismissedSetupTasks(String salonId) {
  return _db.collection('salons').doc(salonId).update({
    'dismissedSetupTasks': <String>[],
  });
}

