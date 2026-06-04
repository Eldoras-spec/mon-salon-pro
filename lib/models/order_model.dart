import 'package:cloud_firestore/cloud_firestore.dart';

class OrderItem {
  final String productId;
  final String name;
  final double price;
  final int quantity;
  final String? imageUrl;

  const OrderItem({
    required this.productId,
    required this.name,
    required this.price,
    required this.quantity,
    this.imageUrl,
  });

  double get total => price * quantity;

  factory OrderItem.fromMap(Map<String, dynamic> d) => OrderItem(
        productId: d['productId'] ?? '',
        name: d['name'] ?? '',
        price: (d['price'] as num?)?.toDouble() ?? 0,
        quantity: (d['quantity'] as num?)?.toInt() ?? 1,
        imageUrl: d['imageUrl'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'name': name,
        'price': price,
        'quantity': quantity,
        if (imageUrl != null) 'imageUrl': imageUrl,
      };
}

class OrderModel {
  final String id;
  final String salonId;
  final String clientId; // userId or 'walk-in' for website
  final String clientName;
  final String clientPhone;
  final String? clientAddress;
  final List<OrderItem> items;
  final double totalPrice;
  final double deliveryFee;
  final String deliveryMethod; // 'pickup' or 'delivery'
  // 'card' = paid online via Stripe; 'cod' = pay on delivery / at salon.
  final String paymentMethod;
  final String? paymentStatus;
  final double? paymentAmount;
  final String? paymentIntentId;
  final String status; // 'pending', 'confirmed', 'delivered', 'cancelled'
  final DateTime createdAt;

  const OrderModel({
    required this.id,
    required this.salonId,
    required this.clientId,
    required this.clientName,
    required this.clientPhone,
    this.clientAddress,
    required this.items,
    required this.totalPrice,
    this.deliveryFee = 0,
    required this.deliveryMethod,
    this.paymentMethod = 'cod',
    this.paymentStatus,
    this.paymentAmount,
    this.paymentIntentId,
    this.status = 'pending',
    required this.createdAt,
  });

  double get grandTotal => totalPrice + deliveryFee;

  String get statusLabel {
    switch (status) {
      case 'pending':
        return 'En attente';
      case 'confirmed':
        return 'Confirmée';
      case 'delivered':
        return 'Livrée';
      case 'cancelled':
        return 'Annulée';
      default:
        return status;
    }
  }

  String get deliveryLabel =>
      deliveryMethod == 'pickup' ? 'Retrait au salon' : 'Livraison';

  factory OrderModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return OrderModel(
      id: doc.id,
      salonId: d['salonId'] ?? '',
      clientId: d['clientId'] ?? '',
      clientName: d['clientName'] ?? '',
      clientPhone: d['clientPhone'] ?? '',
      clientAddress: d['clientAddress'] as String?,
      items: d['items'] != null
          ? (d['items'] as List)
              .map((e) => OrderItem.fromMap(e as Map<String, dynamic>))
              .toList()
          : [],
      totalPrice: (d['totalPrice'] as num?)?.toDouble() ?? 0,
      deliveryFee: (d['deliveryFee'] as num?)?.toDouble() ?? 0,
      deliveryMethod: d['deliveryMethod'] ?? 'pickup',
      paymentMethod: (d['paymentMethod'] as String?) ?? 'cod',
      paymentStatus: d['paymentStatus'] as String?,
      paymentAmount: (d['paymentAmount'] as num?)?.toDouble(),
      paymentIntentId: d['paymentIntentId'] as String?,
      status: d['status'] ?? 'pending',
      createdAt: d['createdAt'] != null
          ? (d['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'salonId': salonId,
        'clientId': clientId,
        'clientName': clientName,
        'clientPhone': clientPhone,
        if (clientAddress != null) 'clientAddress': clientAddress,
        'items': items.map((e) => e.toMap()).toList(),
        'totalPrice': totalPrice,
        'price': totalPrice,
        'deliveryFee': deliveryFee,
        'deliveryMethod': deliveryMethod,
        'paymentMethod': paymentMethod,
        if (paymentStatus != null) 'paymentStatus': paymentStatus,
        if (paymentAmount != null) 'paymentAmount': paymentAmount,
        if (paymentIntentId != null) 'paymentIntentId': paymentIntentId,
        'status': status,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  OrderModel copyWith({String? status}) => OrderModel(
        id: id,
        salonId: salonId,
        clientId: clientId,
        clientName: clientName,
        clientPhone: clientPhone,
        clientAddress: clientAddress,
        items: items,
        totalPrice: totalPrice,
        deliveryFee: deliveryFee,
        deliveryMethod: deliveryMethod,
        paymentMethod: paymentMethod,
        paymentStatus: paymentStatus,
        paymentAmount: paymentAmount,
        paymentIntentId: paymentIntentId,
        status: status ?? this.status,
        createdAt: createdAt,
      );
}
