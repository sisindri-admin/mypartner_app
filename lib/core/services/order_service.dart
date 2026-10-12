import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/order_model.dart';

class OrderService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // 1. డెలివరీ పార్ట్‌నర్‌కు అందుబాటులో ఉన్న ఆర్డర్లు
  Stream<List<OrderModel>> getAvailableOrders() {
    return _db
        .collection('order_accept_merchant')
        .where('status', whereIn: ['Ready_For_Pickup', 'Preparing', 'Ready'])
        .snapshots()
        .map((QuerySnapshot snapshot) {
      return snapshot.docs.map((DocumentSnapshot doc) {
        final data = doc.data() as Map<String, dynamic>? ?? {};
        return OrderModel.fromMap(data, doc.id);
      }).toList();
    });
  }

  // 2. ఆర్డర్ యాక్సెప్ట్ చేయడం
  Future<void> acceptOrder(String orderId, String partnerId) async {
    await _db.collection('order_accept_merchant').doc(orderId).update({
      'deliveryPartnerId': partnerId,
      'status': 'Accepted',
      'orderStatus': 'Accepted',
      'acceptedAt': FieldValue.serverTimestamp(),
    });
  }

  // 3. ఆర్డర్ స్టేటస్ అప్‌డేట్ చేయడం (Reached_Store, Picked_Up, Delivered)
  Future<void> updateOrderStatus(String orderId, String newStatus) async {
    await _db.collection('order_accept_merchant').doc(orderId).update({
      'status': newStatus,
      'orderStatus': newStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}