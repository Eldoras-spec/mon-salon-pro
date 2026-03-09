import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/salon_model.dart';
import '../models/appointment_model.dart';
import '../models/inventory_model.dart';
import '../models/promotion_model.dart';
import '../models/team_member_model.dart';
import '../models/product_model.dart';
import '../models/order_model.dart';
import '../services/database_service.dart';
import 'auth_providers.dart';

final _db = DatabaseService();

/// Live stream of the owner's salon document.
final ownerSalonProvider = StreamProvider<SalonModel?>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(null);
  return _db.getOwnerSalon(user.uid);
});

/// Live stream of all appointments booked at the owner's salon.
/// Returns an empty list until the salon document is loaded.
final ownerAppointmentsProvider = StreamProvider<List<AppointmentModel>>((ref) {
  final salon = ref.watch(ownerSalonProvider).value;
  if (salon == null) return Stream.value([]);
  return _db.getSalonAppointments(salon.id);
});

/// Live stream of inventory items for the owner's salon.
final ownerInventoryProvider = StreamProvider<List<InventoryModel>>((ref) {
  final salon = ref.watch(ownerSalonProvider).value;
  if (salon == null) return Stream.value([]);
  return _db.getInventory(salon.id);
});

/// Live stream of all promotions for the owner's salon.
final ownerPromotionsProvider = StreamProvider<List<PromotionModel>>((ref) {
  final salon = ref.watch(ownerSalonProvider).value;
  if (salon == null) return Stream.value([]);
  return _db.getPromotions(salon.id);
});

/// Live stream of all team members for the owner's salon.
final ownerTeamProvider = StreamProvider<List<TeamMemberModel>>((ref) {
  final salon = ref.watch(ownerSalonProvider).value;
  if (salon == null) return Stream.value([]);
  return _db.getTeamMembers(salon.id);
});

/// Live stream of all products for the owner's salon.
final ownerProductsProvider = StreamProvider<List<ProductModel>>((ref) {
  final salon = ref.watch(ownerSalonProvider).value;
  if (salon == null) return Stream.value([]);
  return _db.getProducts(salon.id);
});

/// Live stream of all orders for the owner's salon.
final ownerOrdersProvider = StreamProvider<List<OrderModel>>((ref) {
  final salon = ref.watch(ownerSalonProvider).value;
  if (salon == null) return Stream.value([]);
  return _db.getSalonOrders(salon.id);
});
