import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/app_colors.dart';
import '../utils/parse_utils.dart';

class PartnerEarningsScreen extends StatelessWidget {
  final Map<String, dynamic> partnerData;
  final Future<void> Function() onRefreshSync;

  const PartnerEarningsScreen({
    super.key,
    required this.partnerData,
    required this.onRefreshSync,
  });

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final double settledCod = ParseUtils.toDouble(partnerData['codSettledAmount']);

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('orders').where('deliveryPartnerId', isEqualTo: uid).snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppColors.primaryEmerald));
        }

        final docs = snap.hasData ? snap.data!.docs : <QueryDocumentSnapshot>[];
        final now = DateTime.now();
        final todayMidnight = DateTime(now.year, now.month, now.day);
        final sevenDaysAgo = todayMidnight.subtract(const Duration(days: 6));

        int todayCount = 0;
        int weeklyCount = 0;
        int totalCount = 0;
        double totalCodCollected = 0;
        double todayEarnings = 0;
        double weeklyEarnings = 0;

        final List<QueryDocumentSnapshot> deliveredDocs = [];

        for (final doc in docs) {
          final d = doc.data() as Map<String, dynamic>;
          final s = (d['orderStatus'] ?? d['status'] ?? '').toString().toLowerCase();
          if (s != 'delivered' && s != 'completed') continue;

          deliveredDocs.add(doc);
          totalCount++;

          final double payout = ParseUtils.toDouble(d['riderPayout'], 35.0);
          final payment = (d['paymentMethod'] ?? 'COD').toString().toUpperCase();
          final bool isCod = !payment.contains('ONLINE') && !payment.contains('UPI');
          final double grandTotal = ParseUtils.toDouble(d['grandTotal'] ?? d['totalAmount']);
          if (isCod) totalCodCollected += grandTotal;

          DateTime? dt;
          final dynamic ts = d['deliveredAt'] ?? d['updatedAt'] ?? d['createdAt'];
          if (ts is Timestamp) dt = ts.toDate();

          if (dt != null) {
            if (!dt.isBefore(todayMidnight)) {
              todayCount++;
              todayEarnings += payout;
            }
            if (!dt.isBefore(sevenDaysAgo)) {
              weeklyCount++;
              weeklyEarnings += payout;
            }
          }
        }

        final double pendingCod = (totalCodCollected - settledCod).clamp(0.0, double.infinity);

        return RefreshIndicator(
          color: AppColors.primaryEmerald,
          onRefresh: onRefreshSync,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AppColors.primaryDark, Color(0xFF1E293B)]),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Your Earnings & COD Summary', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _heroStat('TODAY', '₹${todayEarnings.toStringAsFixed(0)}', '$todayCount deliveries', const Color(0xFF34D399)),
                        _heroStat('THIS WEEK', '₹${weeklyEarnings.toStringAsFixed(0)}', '$weeklyCount deliveries', const Color(0xFF38BDF8)),
                        _heroStat('ALL TIME', '$totalCount', 'Completed', Colors.amber),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: pendingCod > 0 ? AppColors.accentRedLight : AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: (pendingCod > 0 ? AppColors.accentRed : AppColors.primaryEmerald).withAlpha(80)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.payments_rounded,
                      color: pendingCod > 0 ? AppColors.accentRed : AppColors.primaryEmerald,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Pending COD Cash to Deposit', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Text(
                            'Collected: ₹${totalCodCollected.toStringAsFixed(0)} • Settled: ₹${settledCod.toStringAsFixed(0)}',
                            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '₹${pendingCod.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        color: pendingCod > 0 ? AppColors.accentRed : AppColors.primaryEmerald,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              const Text('Completed Deliveries', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 8),
              if (deliveredDocs.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child: Center(child: Text('No completed deliveries yet.', style: TextStyle(color: AppColors.textMuted))),
                )
              else
                ...deliveredDocs.map((doc) {
                  final d = doc.data() as Map<String, dynamic>;
                  final orderId = (d['orderId'] ?? doc.id).toString();
                  final store = (d['storeName'] ?? 'Store').toString();
                  final payment = (d['paymentMethod'] ?? 'COD').toString();
                  final total = ParseUtils.toDouble(d['grandTotal'] ?? d['totalAmount']);
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    color: Colors.white,
                    elevation: 0.4,
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: AppColors.primaryLight,
                        child: Icon(Icons.check_circle_rounded, color: AppColors.primaryEmerald),
                      ),
                      title: Text('#$orderId • $store', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      subtitle: Text('$payment • Order ₹${total.toStringAsFixed(0)}', style: const TextStyle(fontSize: 11.5)),
                      trailing: const Text('+₹35', style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.primaryEmerald)),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  Widget _heroStat(String label, String value, String sub, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w900)),
          Text(sub, style: const TextStyle(color: Colors.white70, fontSize: 10.5)),
        ],
      ),
    );
  }
}
