import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/order_model.dart';

class OrderService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // 1. Merchant / Admin ద్వారా తయారైన Available Orders List
  Stream<List<OrderModel>> getAvailableOrders() {
    return _db
        .collection('orders')
        .where('status', whereIn: ['Ready_For_Pickup', 'Preparing', 'Ready'])
        .snapshots()
        .map((QuerySnapshot snapshot) {
      return snapshot.docs.map((DocumentSnapshot doc) {
        final data = doc.data() as Map<String, dynamic>? ?? {};
        return OrderModel.fromMap(data, doc.id);
      }).toList();
    });
  }

  // 2. Order Accept చేయడం (Tracking Initialized)
  Future<void> acceptOrder(String orderId, String partnerId) async {
    await _db.collection('orders').doc(orderId).update({
      'deliveryPartnerId': partnerId,
      'status': 'Accepted',
      'acceptedAt': FieldValue.serverTimestamp(),
    });
  }

  // 3. Complete Delivery Life Cycle Updates (Stepper Tracker)
  // Status Steps: 'Reached_Store' -> 'Picked_Up' -> 'Customer_Location_Reached' -> 'Delivered'
  Future<void> updateOrderStatus(String orderId, String newStatus) async {
    Map<String, dynamic> updateData = {
      'status': newStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (newStatus == 'Reached_Store') {
      updateData['reachedStoreAt'] = FieldValue.serverTimestamp();
    } else if (newStatus == 'Picked_Up') {
      updateData['pickedUpAt'] = FieldValue.serverTimestamp();
    } else if (newStatus == 'Customer_Location_Reached') {
      updateData['reachedCustomerAt'] = FieldValue.serverTimestamp();
    } else if (newStatus == 'Delivered') {
      updateData['deliveredAt'] = FieldValue.serverTimestamp();
    }

    await _db.collection('orders').doc(orderId).update(updateData);
  }

  // 4. Order Reject చేయడం (With Reason & Audit Log)
  Future<void> rejectOrder(String orderId, String partnerId, String reason) async {
    // Orders collection లో అప్‌డేట్
    await _db.collection('orders').doc(orderId).update({
      'status': 'Rejected',
      'rejectedBy': partnerId,
      'lastRejectedBy': partnerId,
      'rejectionReason': reason,
      'rejectedAt': FieldValue.serverTimestamp(),
    });

    // Rejection Analytics & Audit Log Entry
    await _db.collection('delivery_order_rejections').add({
      'orderId': orderId,
      'deliveryPartnerId': partnerId,
      'reason': reason,
      'rejectedAt': FieldValue.serverTimestamp(),
    });
  }

  // 5. Delivery Partner Metrics (Accepted orders, Earnings, Completed)
  Stream<Map<String, dynamic>> getPartnerDashboardStats(String partnerId) {
    return _db
        .collection('orders')
        .where('deliveryPartnerId', isEqualTo: partnerId)
        .snapshots()
        .map((snapshot) {
      int acceptedCount = 0;
      int completedCount = 0;
      double totalEarnings = 0.0;

      for (var doc in snapshot.docs) {
        var data = doc.data();
        String status = data['status'] ?? '';
        
        if (status != 'Rejected') {
          acceptedCount++;
        }

        if (status == 'Delivered') {
          completedCount++;
          double fee = (data['deliveryFee'] ?? 0.0).toDouble();
          totalEarnings += fee;
        }
      }

      return {
        'totalAccepted': acceptedCount,
        'totalCompleted': completedCount,
        'totalEarnings': totalEarnings,
      };
    });
  }

  // 6. Delivery Partner ఎన్ని ఆర్డర్లు రిజెక్ట్ చేశాడో కౌంట్ చేసే క్వెరీ
  Stream<int> getPartnerRejectionCount(String partnerId) {
    return _db
        .collection('delivery_order_rejections')
        .where('deliveryPartnerId', isEqualTo: partnerId)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }
}