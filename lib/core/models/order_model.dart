import 'package:cloud_firestore/cloud_firestore.dart';

class OrderItemModel {
  final String id;
  final String name;
  final double price;
  final int quantity;
  final double totalPrice;
  final String unit;
  final String imageUrl;

  OrderItemModel({
    required this.id,
    required this.name,
    required this.price,
    required this.quantity,
    required this.totalPrice,
    required this.unit,
    required this.imageUrl,
  });

  factory OrderItemModel.fromMap(Map<String, dynamic> map) {
    return OrderItemModel(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      price: (map['price'] ?? 0).toDouble(),
      quantity: (map['quantity'] ?? 1).toInt(),
      totalPrice: (map['totalPrice'] ?? 0).toDouble(),
      unit: map['unit']?.toString() ?? '',
      imageUrl: map['imageUrl']?.toString() ?? '',
    );
  }
}

class OrderModel {
  final String orderId;
  final String merchantId;
  final String storeName;
  final String deliveryAddress;
  final double deliveryFee;
  final double handlingFee;
  final double itemTotal;
  final double grandTotal;
  final String status;
  final String paymentMethod;
  final String paymentStatus;
  final String userId;
  final String userPhone;
  final String deliveryInstructions;
  final List<OrderItemModel> items;

  OrderModel({
    required this.orderId,
    required this.merchantId,
    required this.storeName,
    required this.deliveryAddress,
    required this.deliveryFee,
    required this.handlingFee,
    required this.itemTotal,
    required this.grandTotal,
    required this.status,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.userId,
    required this.userPhone,
    required this.deliveryInstructions,
    required this.items,
  });

  factory OrderModel.fromMap(Map<String, dynamic> map, String docId) {
    var rawItems = map['items'] as List<dynamic>? ?? [];
    List<OrderItemModel> parsedItems =
        rawItems.map((item) => OrderItemModel.fromMap(Map<String, dynamic>.from(item))).toList();

    return OrderModel(
      orderId: map['orderId']?.toString() ?? docId,
      merchantId: map['merchantId']?.toString() ?? '',
      storeName: map['storeName']?.toString() ?? 'Unknown Store',
      deliveryAddress: map['deliveryAddress']?.toString() ?? 'No Address Provided',
      deliveryFee: (map['deliveryFee'] ?? 0).toDouble(),
      handlingFee: (map['handlingFee'] ?? 0).toDouble(),
      itemTotal: (map['itemTotal'] ?? 0).toDouble(),
      grandTotal: (map['grandTotal'] ?? 0).toDouble(),
      status: map['status']?.toString() ?? map['orderStatus']?.toString() ?? 'Pending',
      paymentMethod: map['paymentMethod']?.toString() ?? 'COD',
      paymentStatus: map['paymentStatus']?.toString() ?? 'Pending',
      userId: map['userId']?.toString() ?? '',
      userPhone: map['userPhone']?.toString() ?? '',
      deliveryInstructions: map['deliveryInstructions']?.toString() ?? '',
      items: parsedItems,
    );
  }
}