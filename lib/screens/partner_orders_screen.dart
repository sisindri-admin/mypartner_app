import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/app_colors.dart';
import '../utils/parse_utils.dart';

class PartnerOrdersScreen extends StatefulWidget {
  final bool showAvailablePool;
  final Map<String, dynamic> partnerData;
  final Future<void> Function() onRefreshSync;
  final void Function(String docId)? onOrderAccepted;

  const PartnerOrdersScreen({
    super.key,
    required this.showAvailablePool,
    required this.partnerData,
    required this.onRefreshSync,
    this.onOrderAccepted,
  });

  @override
  State<PartnerOrdersScreen> createState() => _PartnerOrdersScreenState();
}

class _PartnerOrdersScreenState extends State<PartnerOrdersScreen> {
  late final Stream<QuerySnapshot> _ordersStream;

  @override
  void initState() {
    super.initState();
    _ordersStream = FirebaseFirestore.instance.collection('orders').snapshots();
  }

  LatLng _extractPoint(dynamic val, LatLng fallback) {
    if (val is GeoPoint && val.latitude != 0 && val.longitude != 0) {
      return LatLng(val.latitude, val.longitude);
    }
    if (val is Map) {
      final lat = ParseUtils.toDouble(val['latitude'] ?? val['lat']);
      final lng = ParseUtils.toDouble(val['longitude'] ?? val['lng']);
      if (lat != 0 && lng != 0) return LatLng(lat, lng);
    }
    return fallback;
  }

  double _haversineKm(LatLng a, LatLng b) {
    const double r = 6371.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180.0;
    final dLon = (b.longitude - a.longitude) * math.pi / 180.0;
    final lat1 = a.latitude * math.pi / 180.0;
    final lat2 = b.latitude * math.pi / 180.0;
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) * math.cos(lat2) * math.sin(dLon / 2) * math.sin(dLon / 2);
    return 2 * r * math.asin(math.sqrt(h));
  }

  Future<void> _callPhone(String phone) async {
    if (phone.trim().isEmpty) return;
    final uri = Uri(scheme: 'tel', path: phone.trim());
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _callMerchant(BuildContext context, Map<String, dynamic> data) async {
    final direct = (data['storePhone'] ?? data['merchantPhone'] ?? '').toString().trim();
    if (direct.isNotEmpty) {
      await _callPhone(direct);
      return;
    }
    final merchantId = (data['merchantId'] ?? '').toString().trim();
    if (merchantId.isNotEmpty) {
      final doc = await FirebaseFirestore.instance.collection('merchants').doc(merchantId).get();
      final phone = (doc.data()?['phone'] ?? doc.data()?['phoneNumber'] ?? '').toString().trim();
      if (phone.isNotEmpty) {
        await _callPhone(phone);
        return;
      }
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Store phone number not available.')),
      );
    }
  }

  Future<void> _openMaps(LatLng dest, {String label = ''}) async {
    final cleanLabel = label.trim().isNotEmpty
        ? label.trim()
        : '${dest.latitude.toStringAsFixed(5)}, ${dest.longitude.toStringAsFixed(5)}';
    final geoUri = Uri.parse(
      'geo:${dest.latitude},${dest.longitude}?q=${dest.latitude},${dest.longitude}(${Uri.encodeComponent(cleanLabel)})',
    );
    try {
      if (await launchUrl(geoUri, mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (_) {}

    final webUri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${dest.latitude},${dest.longitude}&travelmode=driving',
    );
    await launchUrl(webUri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openSmartOrderMap(
    Map<String, dynamic> data,
    bool isOutForDeliveryOrLater,
    LatLng fallbackStore,
    LatLng fallbackCustomer,
  ) async {
    if (isOutForDeliveryOrLater) {
      final custAddr = (data['deliveryAddress'] ?? data['address'] ?? 'Customer Location').toString().trim();
      await _openMaps(fallbackCustomer, label: 'Customer • $custAddr');
      return;
    }

    LatLng storeDest = fallbackStore;
    String storeName = (data['storeName'] ?? 'Flash2Mart Store').toString().trim();
    String storeAddr = (data['storeAddress'] ?? data['merchantLocationAddress'] ?? '').toString().trim();

    final hasDirectStore = data['storeLocation'] != null ||
        data['merchantLocation'] != null ||
        (data['storeLat'] is num && data['storeLng'] is num);
    if (!hasDirectStore || storeAddr.isEmpty) {
      final mid = (data['merchantId'] ?? '').toString().trim();
      if (mid.isNotEmpty) {
        try {
          final mDoc = await FirebaseFirestore.instance.collection('merchants').doc(mid).get();
          if (mDoc.exists) {
            final md = mDoc.data() ?? {};
            if (storeAddr.isEmpty) {
              storeAddr = (md['address'] ?? md['fullAddress'] ?? md['locationAddress'] ?? '').toString().trim();
            }
            if ((md['storeName'] ?? '').toString().trim().isNotEmpty) {
              storeName = md['storeName'].toString().trim();
            }
            if (!hasDirectStore) {
              final pt = _extractPoint(md['storeLocation'] ?? md['location'], const LatLng(0, 0));
              if (pt.latitude != 0 && pt.longitude != 0) {
                storeDest = pt;
              } else if (md['storeLat'] is num && md['storeLng'] is num) {
                storeDest = LatLng((md['storeLat'] as num).toDouble(), (md['storeLng'] as num).toDouble());
              } else if (md['latitude'] is num && md['longitude'] is num) {
                storeDest = LatLng((md['latitude'] as num).toDouble(), (md['longitude'] as num).toDouble());
              }
            }
          }
        } catch (_) {}
      }
    }

    final storeLabel = storeAddr.isNotEmpty ? '$storeName • $storeAddr' : storeName;
    await _openMaps(storeDest, label: storeLabel);
  }

  void _showReportIssueDialog(BuildContext context, String docId) {
    final reasons = [
      'Customer Not Answering Phone',
      'Wrong / Incomplete Address',
      'Store Item Out of Stock',
      'Vehicle / Traffic Delay',
    ];
    String selected = reasons.first;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Report Delivery Issue'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: reasons.map((r) {
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  selected == r ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: selected == r ? AppColors.accentRed : AppColors.textMuted,
                ),
                title: Text(r, style: const TextStyle(fontSize: 13)),
                onTap: () => setDialogState(() => selected = r),
              );
            }).toList(),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.accentRed, foregroundColor: Colors.white),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(ctx);
                widget.onOrderAccepted?.call(docId);
    await FirebaseFirestore.instance.collection('orders').doc(docId).update({
                  'riderIssue': selected,
                  'riderIssueAt': FieldValue.serverTimestamp(),
                  'trackingHistory': FieldValue.arrayUnion([
                    {
                      'status': 'Issue Reported',
                      'title': 'Rider Issue: $selected',
                      'timestamp': DateTime.now().toIso8601String(),
                      'updatedBy': 'DeliveryPartner',
                    }
                  ]),
                });
                messenger.showSnackBar(
                  SnackBar(content: Text('⚠️ Issue reported to Admin: $selected'), backgroundColor: AppColors.accentOrange),
                );
              },
              child: const Text('SEND ALERT'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _acceptPoolOrder(
    BuildContext context,
    String docId,
    Map<String, dynamic> data,
    int currentActiveCount,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    if (currentActiveCount >= 2) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Max 2 active orders allowed at a time!'), backgroundColor: AppColors.accentOrange),
      );
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final pName = (widget.partnerData['name'] ?? 'Delivery Partner').toString();
    final pPhone = (widget.partnerData['phone'] ?? '').toString();
    final vNo = (widget.partnerData['vehicleNumber'] ?? '').toString();

    int newSeq = 1;
    if (currentActiveCount >= 1) {
      final activeSnap = await FirebaseFirestore.instance
          .collection('orders')
          .where('deliveryPartnerId', isEqualTo: user.uid)
          .get();
      final newStore = _extractPoint(data['storeLocation'] ?? data['merchantLocation'], const LatLng(14.4485, 79.9890));
      final newCust = _extractPoint(data['customerLocation'] ?? data['deliveryLocation'], const LatLng(14.4328, 79.9772));
      final distNew = _haversineKm(newStore, newCust);
      for (final ed in activeSnap.docs) {
        if (ed.id == docId) continue;
        final edData = ed.data();
        final es = (edData['orderStatus'] ?? edData['status'] ?? '').toString().toLowerCase();
        if (es == 'delivered' || es == 'completed' || es == 'cancelled' || es == 'rejected') continue;
        final exStore = _extractPoint(edData['storeLocation'] ?? edData['merchantLocation'], const LatLng(14.4485, 79.9890));
        final exCust = _extractPoint(edData['customerLocation'] ?? edData['deliveryLocation'], const LatLng(14.4328, 79.9772));
        final distEx = _haversineKm(exStore, exCust);
        if (distNew < distEx) {
          newSeq = 1;
          await ed.reference.update({'isBatchedOrder': true, 'batchSequence': 2, 'batchedWithOrderId': docId});
        } else {
          newSeq = 2;
          await ed.reference.update({'isBatchedOrder': true, 'batchSequence': 1, 'batchedWithOrderId': docId});
        }
        break;
      }
    }

    await FirebaseFirestore.instance.collection('orders').doc(docId).update({
      'deliveryPartnerId': user.uid,
      'deliveryPartnerName': pName,
      'deliveryPartnerPhone': pPhone,
      if (vNo.isNotEmpty) 'vehicleNumber': vNo,
      if (widget.partnerData['currentLocation'] != null) 'deliveryPartnerLocation': widget.partnerData['currentLocation'],
      'orderStatus': 'Accepted',
      'status': 'Accepted',
      'currentStatus': 'Accepted',
      'isBatchedOrder': currentActiveCount >= 1,
      'batchSequence': newSeq,
      'updatedAt': FieldValue.serverTimestamp(),
      'trackingHistory': FieldValue.arrayUnion([
        {
          'status': 'Accepted',
          'title': 'Accepted by $pName',
          'timestamp': DateTime.now().toIso8601String(),
          'updatedBy': 'DeliveryPartner',
        }
      ]),
    });

    messenger.showSnackBar(
      SnackBar(content: Text('✅ Order #$docId accepted!'), backgroundColor: AppColors.primaryEmerald),
    );
  }


  Future<double> _getLiveDistanceMeters(LatLng target, LatLng fallbackRider) async {
    LatLng current = fallbackRider;
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.always || perm == LocationPermission.whileInUse) {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
        ).timeout(const Duration(seconds: 4));
        current = LatLng(pos.latitude, pos.longitude);
      }
    } catch (_) {}
    return _haversineKm(current, target) * 1000.0;
  }

  Future<void> _handleReachedPickupLocation(
    BuildContext context,
    String docId,
    String storeName,
    LatLng storeLatLng,
    LatLng riderLatLng,
  ) async {
    final distMeters = await _getLiveDistanceMeters(storeLatLng, riderLatLng);
    if (!context.mounted) return;
    if (distMeters > 100.0) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Row(
            children: [
              Icon(Icons.location_off_rounded, color: AppColors.accentRed),
              SizedBox(width: 8),
              Expanded(child: Text('Outside 100m Store Zone', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
            ],
          ),
          content: Text(
            'You are currently ${distMeters.round()}m away from $storeName.\n\nPlease move within 100m of the pickup location to confirm arrival.',
            style: const TextStyle(fontSize: 13.5),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryEmerald, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    await _advanceStatus(context, docId, 'Reached Store', 'Delivery Partner reached $storeName');
  }

  Future<void> _confirmPickupCompleted(
    BuildContext context,
    String docId,
    String storeName,
    LatLng storeLatLng,
    LatLng riderLatLng,
    int itemCount,
    bool isCod,
    double grandTotal,
  ) async {
    final distMeters = await _getLiveDistanceMeters(storeLatLng, riderLatLng);
    if (!context.mounted) return;
    if (distMeters > 100.0) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Row(
            children: [
              Icon(Icons.location_off_rounded, color: AppColors.accentRed),
              SizedBox(width: 8),
              Expanded(child: Text('Outside 100m Store Zone', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
            ],
          ),
          content: Text(
            'You are currently ${distMeters.round()}m away from $storeName.\n\nYou must be within 100m of the store to mark Pickup Completed.',
            style: const TextStyle(fontSize: 13.5),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryEmerald, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Confirm Pickup Completed?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Have you collected all $itemCount item(s) from $storeName?',
              style: const TextStyle(fontSize: 13.5, color: AppColors.textDark),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isCod ? AppColors.accentOrangeLight : AppColors.primaryLight,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: (isCod ? AppColors.accentRed : AppColors.primaryEmerald).withAlpha(120)),
              ),
              child: Text(
                isCod
                    ? '💵 COD ORDER: Collect ₹${grandTotal.toStringAsFixed(0)} cash from customer at delivery!'
                    : '✅ PAID ONLINE: Do not collect cash (₹0) from customer.',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 12.5,
                  color: isCod ? AppColors.accentRed : AppColors.primaryEmerald,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryEmerald, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('CONFIRM PICKUP'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await _advanceStatus(context, docId, 'Out for Delivery', 'Order picked up from $storeName');
    }
  }

  Future<void> _handleReachedCustomerLocation(
    BuildContext context,
    String docId,
    LatLng customerLatLng,
    LatLng riderLatLng,
  ) async {
    final distMeters = await _getLiveDistanceMeters(customerLatLng, riderLatLng);
    if (!context.mounted) return;
    if (distMeters <= 100.0) {
      await _advanceStatus(context, docId, 'Customer Location Reached', 'Partner arrived at customer doorstep');
      return;
    }

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(
          children: [
            Icon(Icons.wrong_location_rounded, color: AppColors.accentOrange),
            SizedBox(width: 8),
            Expanded(child: Text('Customer Different Location?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
          ],
        ),
        content: Text(
          'You are ${distMeters.round()}m away from the pinned customer location (> 100m).\n\nIs the customer at a different/nearby location? Tap OK to confirm arrival.',
          style: const TextStyle(fontSize: 13.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryEmerald, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('OK, ARRIVED'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await _advanceStatus(
        context,
        docId,
        'Customer Location Reached',
        'Partner arrived at customer location (~${distMeters.round()}m from pin - different location)',
        extraFields: {
          'arrivedDifferentLocation': true,
          'arrivalDistanceMeters': distMeters.round(),
        },
      );
    }
  }

  Future<void> _advanceStatus(BuildContext context, String docId, String nextStatus, String title, {Map<String, dynamic>? extraFields}) async {
    final messenger = ScaffoldMessenger.of(context);
    final Map<String, dynamic> payload = {
      'orderStatus': nextStatus,
      'status': nextStatus,
      'currentStatus': nextStatus,
      'updatedAt': FieldValue.serverTimestamp(),
      'trackingHistory': FieldValue.arrayUnion([
        {
          'status': nextStatus,
          'title': title,
          'timestamp': DateTime.now().toIso8601String(),
          'updatedBy': 'DeliveryPartner',
        }
      ]),
    };

    if (extraFields != null) {
      payload.addAll(extraFields);
    }
    if (nextStatus == 'Delivered') {
      payload['paymentStatus'] = 'Paid';
      payload['deliveredAt'] = FieldValue.serverTimestamp();
    }

    await FirebaseFirestore.instance.collection('orders').doc(docId).update(payload);
    messenger.showSnackBar(
      SnackBar(content: Text('✅ Order #$docId → $nextStatus'), backgroundColor: AppColors.primaryEmerald),
    );
  }

  void _showOtpVerifyDialog(
    BuildContext context,
    String docId,
    String expectedOtp,
    bool isCod,
    double grandTotal,
  ) {
    final otpCtrl = TextEditingController();
    final cashCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    bool cashConfirmed = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Verify Customer Delivery OTP'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: isCod ? AppColors.accentOrangeLight : AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: isCod ? AppColors.accentOrange : AppColors.primaryEmerald),
                  ),
                  child: Text(
                    isCod
                        ? '💵 COLLECT ₹${grandTotal.toStringAsFixed(0)} CASH FROM CUSTOMER'
                        : '✅ ALREADY PAID ONLINE — Collect ₹0',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12.5,
                      color: isCod ? AppColors.accentRed : AppColors.primaryEmerald,
                    ),
                  ),
                ),
                const Text(
                  'Ask the customer for the 4-digit Delivery OTP shown in their Flash2Mart Customer App.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: otpCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 8),
                  decoration: const InputDecoration(hintText: '••••', border: OutlineInputBorder()),
                ),
                if (isCod) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: cashCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Enter Collected Cash (₹${grandTotal.toStringAsFixed(0)})',
                      hintText: grandTotal.toStringAsFixed(0),
                      prefixText: '₹ ',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    activeColor: AppColors.primaryEmerald,
                    value: cashConfirmed,
                    onChanged: (v) => setDialogState(() => cashConfirmed = v ?? false),
                    title: Text(
                      'Confirm Cash ₹${grandTotal.toStringAsFixed(0)} Collected',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Doorstep Note (Optional)',
                    hintText: 'e.g. Handed to customer / Left at gate',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryEmerald, foregroundColor: Colors.white),
              onPressed: () async {
                final entered = otpCtrl.text.trim();
                if (expectedOtp.isNotEmpty && entered != expectedOtp) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('❌ Incorrect OTP! Please check with customer.'), backgroundColor: AppColors.accentRed),
                  );
                  return;
                }

                double collectedAmt = 0;
                if (isCod) {
                  collectedAmt = ParseUtils.toDouble(cashCtrl.text.trim());
                  if (collectedAmt < grandTotal.roundToDouble()) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: Text('❌ Please enter full collected cash amount ₹${grandTotal.toStringAsFixed(0)}'),
                        backgroundColor: AppColors.accentRed,
                      ),
                    );
                    return;
                  }
                  if (!cashConfirmed) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                        content: Text('❌ Please check "Confirm Cash Collected" first.'),
                        backgroundColor: AppColors.accentRed,
                      ),
                    );
                    return;
                  }
                }

                final bool? finalOk = await showDialog<bool>(
                  context: ctx,
                  builder: (confirmCtx) => AlertDialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    title: const Text('Confirm Delivery Completed?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    content: Text(
                      isCod
                          ? 'Order #$docId\n\n💵 Cash Collected: ₹${collectedAmt.toStringAsFixed(0)}\n\nTap OK to complete delivery.'
                          : 'Order #$docId\n\nTap OK to complete delivery.',
                      style: const TextStyle(fontSize: 13.5),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(confirmCtx, false), child: const Text('CANCEL')),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryEmerald, foregroundColor: Colors.white),
                        onPressed: () => Navigator.pop(confirmCtx, true),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                );

                if (finalOk != true) return;
                if (ctx.mounted) Navigator.pop(ctx);
                if (!context.mounted) return;
                final note = noteCtrl.text.trim();
                final titleMsg = note.isNotEmpty
                    ? 'Delivered ($note)'
                    : 'Order Delivered & Verified with OTP';
                await _advanceStatus(
                  context,
                  docId,
                  'Delivered',
                  titleMsg,
                  extraFields: isCod
                      ? {
                          'collectedCashAmount': collectedAmt,
                          'cashCollectedConfirmed': true,
                        }
                      : null,
                );
              },
              child: const Text('DELIVERY COMPLETED'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final riderLatLng = _extractPoint(widget.partnerData['currentLocation'], const LatLng(14.4426, 79.9865));

    return StreamBuilder<QuerySnapshot>(
      stream: _ordersStream,
      builder: (context, snap) {
        if (!snap.hasData && snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppColors.primaryEmerald));
        }
        final allDocs = snap.hasData ? snap.data!.docs : <QueryDocumentSnapshot>[];

        final myActiveOrders = allDocs.where((d) {
          final data = d.data() as Map<String, dynamic>;
          final pid = (data['deliveryPartnerId'] ?? data['driverId'] ?? '').toString().trim();
          final s = (data['orderStatus'] ?? data['status'] ?? '').toString().toLowerCase();
          return pid == uid && s != 'delivered' && s != 'completed' && s != 'cancelled' && s != 'rejected';
        }).toList();

        if (myActiveOrders.length > 1) {
          myActiveOrders.sort((a, b) {
            final da = a.data() as Map<String, dynamic>;
            final db = b.data() as Map<String, dynamic>;
            final seqA = ParseUtils.toInt(da['batchSequence'], 99);
            final seqB = ParseUtils.toInt(db['batchSequence'], 99);
            if (seqA != seqB) return seqA.compareTo(seqB);
            final ca = _extractPoint(da['customerLocation'] ?? da['deliveryLocation'], const LatLng(14.4328, 79.9772));
            final cb = _extractPoint(db['customerLocation'] ?? db['deliveryLocation'], const LatLng(14.4328, 79.9772));
            return _haversineKm(riderLatLng, ca).compareTo(_haversineKm(riderLatLng, cb));
          });
        }

        final availableOrders = allDocs.where((d) {
          final data = d.data() as Map<String, dynamic>;
          final pid = (data['deliveryPartnerId'] ?? data['driverId'] ?? '').toString().trim();
          final s = (data['orderStatus'] ?? data['status'] ?? '').toString().toLowerCase();
          return pid.isEmpty && s != 'delivered' && s != 'completed' && s != 'cancelled' && s != 'rejected';
        }).toList();

        final list = widget.showAvailablePool ? availableOrders : myActiveOrders;

        if (list.isEmpty) {
          return RefreshIndicator(
            color: AppColors.primaryEmerald,
            onRefresh: widget.onRefreshSync,
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            widget.showAvailablePool ? Icons.explore_off_rounded : Icons.delivery_dining_rounded,
                            size: 56,
                            color: AppColors.textMuted.withAlpha(110),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            widget.showAvailablePool ? 'No unassigned orders in pool right now.' : 'No active trips assigned right now.',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textDark),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            widget.showAvailablePool
                                ? 'Swipe down anytime to sync fresh orders from Nellore stores.'
                                : 'Swipe down anytime to sync latest trips & live GPS.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return RefreshIndicator(
          color: AppColors.primaryEmerald,
          onRefresh: widget.onRefreshSync,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(14),
            itemCount: list.length,
            itemBuilder: (context, idx) {
              final doc = list[idx];
              final data = doc.data() as Map<String, dynamic>;
              final orderId = (data['orderId'] ?? doc.id).toString();
              final rawStatus = (data['orderStatus'] ?? data['status'] ?? 'Placed').toString();
              final storeName = (data['storeName'] ?? 'Flash2Mart Store').toString();
              final address = (data['deliveryAddress'] ?? 'Nellore, AP').toString();
              final phone = (data['userPhone'] ?? data['customerPhone'] ?? '').toString();
              final paymentMethod = (data['paymentMethod'] ?? 'COD').toString();
              final paymentStatus = (data['paymentStatus'] ?? '').toString().toLowerCase();
              final bool isCod = !paymentMethod.toUpperCase().contains('ONLINE') &&
                  !paymentMethod.toUpperCase().contains('UPI') &&
                  paymentStatus != 'paid';
              final grandTotal = ParseUtils.toDouble(data['grandTotal'] ?? data['totalAmount'] ?? data['itemTotal']);
              final otp = (data['deliveryOtp'] ?? '').toString();
              final bool isBatched = data['isBatchedOrder'] == true || (!widget.showAvailablePool && myActiveOrders.length > 1);
              final List items = (data['items'] is List) ? data['items'] as List : [];

              LatLng storeLatLng = _extractPoint(
                data['storeLocation'] ?? data['merchantLocation'],
                const LatLng(0, 0),
              );
              if (storeLatLng.latitude == 0) {
                final sLat = ParseUtils.toDouble(data['storeLat'] ?? data['merchantLat']);
                final sLng = ParseUtils.toDouble(data['storeLng'] ?? data['merchantLng']);
                storeLatLng = (sLat != 0 && sLng != 0) ? LatLng(sLat, sLng) : const LatLng(14.4485, 79.9890);
              }
              LatLng customerLatLng = _extractPoint(
                data['customerLocation'] ?? data['deliveryLocation'],
                const LatLng(0, 0),
              );
              if (customerLatLng.latitude == 0) {
                final cLat = ParseUtils.toDouble(data['customerLat'] ?? data['latitude']);
                final cLng = ParseUtils.toDouble(data['customerLng'] ?? data['longitude']);
                customerLatLng = (cLat != 0 && cLng != 0) ? LatLng(cLat, cLng) : const LatLng(14.4328, 79.9772);
              }

              final sLower = rawStatus.toLowerCase().replaceAll(' ', '_');
              final bool isStoreReachedOrLater = sLower == 'reached_store' ||
                  sLower == 'picked_up' ||
                  sLower == 'out_for_delivery' ||
                  sLower == 'customer_location_reached';
              final bool isOutForDeliveryOrLater = sLower == 'picked_up' ||
                  sLower == 'out_for_delivery' ||
                  sLower == 'customer_location_reached';

              String btnLabel = 'REACHED PICKUP LOCATION';
              String nextStatus = 'REACHED_PICKUP';

              if (sLower == 'reached_store') {
                btnLabel = 'PICKUP COMPLETED';
                nextStatus = 'PICKUP_COMPLETED';
              } else if (sLower == 'picked_up' || sLower == 'out_for_delivery') {
                btnLabel = 'REACHED CUSTOMER LOCATION';
                nextStatus = 'REACHED_CUSTOMER';
              } else if (sLower == 'customer_location_reached') {
                btnLabel = 'VERIFY OTP & COMPLETE';
                nextStatus = 'OTP';
              }

              if (!widget.showAvailablePool && idx > 0) {
                final custName = (data['customerName'] ?? data['userName'] ?? 'Customer').toString();
                return Card(
                  margin: const EdgeInsets.only(bottom: 14),
                  color: const Color(0xFFF8FAFC),
                  elevation: 0.5,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: AppColors.borderSubtle, width: 1.2),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Text('#$orderId', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5)),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(color: AppColors.accentIndigo, borderRadius: BorderRadius.circular(6)),
                                  child: Text(
                                    'STOP ${idx + 1} OF ${myActiveOrders.length} • QUEUED',
                                    style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                            const Icon(Icons.lock_outline_rounded, size: 18, color: AppColors.textMuted),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('👤 Customer: $custName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 3),
                        Text('🏪 Store: $storeName', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEEF2FF),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            '🔒 Location & delivery controls will unlock automatically after Stop 1 is delivered.',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.accentIndigo),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return Card(
                margin: const EdgeInsets.only(bottom: 14),
                color: Colors.white,
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: isBatched ? AppColors.accentIndigo : AppColors.borderSubtle, width: isBatched ? 1.4 : 1),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Text('#$orderId', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                              if (!widget.showAvailablePool && myActiveOrders.length > 1) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: AppColors.accentIndigo, borderRadius: BorderRadius.circular(6)),
                                  child: Text(
                                    'STOP ${idx + 1} OF ${myActiveOrders.length}${idx == 0 ? ' • ACTIVE' : ' • QUEUED'}',
                                    style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: Colors.white),
                                  ),
                                ),
                              ] else if (isBatched) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: AppColors.accentIndigoLight, borderRadius: BorderRadius.circular(6)),
                                  child: const Text('BATCHED', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: AppColors.accentIndigo)),
                                ),
                              ],
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(8)),
                            child: Text(rawStatus.toUpperCase(),
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.primaryEmerald)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      if (!widget.showAvailablePool && isOutForDeliveryOrLater)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: isCod ? AppColors.accentOrangeLight : AppColors.primaryLight,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: (isCod ? AppColors.accentOrange : AppColors.primaryEmerald).withAlpha(110),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isCod ? Icons.currency_rupee_rounded : Icons.verified_rounded,
                                size: 16,
                                color: isCod ? AppColors.accentRed : AppColors.primaryEmerald,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  isCod
                                      ? 'COLLECT ₹${grandTotal.toStringAsFixed(0)} CASH (COD)'
                                      : 'PAID ONLINE ($paymentMethod) • Collect ₹0',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 11.5,
                                    color: isCod ? AppColors.accentRed : AppColors.primaryEmerald,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (!widget.showAvailablePool) ...[
                        Builder(builder: (_) {
                          final targetPt = isOutForDeliveryOrLater ? customerLatLng : storeLatLng;
                          final distM = (_haversineKm(riderLatLng, targetPt) * 1000).round();
                          final within100 = distM <= 100;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: within100 ? AppColors.primaryLight : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.near_me_rounded,
                                  size: 14,
                                  color: within100 ? AppColors.primaryEmerald : AppColors.textMuted,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  '${distM}m from ${isOutForDeliveryOrLater ? 'Customer' : 'Store'}${within100 ? ' (Within 100m ✓)' : ''}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: within100 ? AppColors.primaryEmerald : AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],

                      if (!widget.showAvailablePool) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            height: 145,
                            child: FlutterMap(
                              key: ValueKey('order_map_${doc.id}'),
                              options: MapOptions(initialCenter: storeLatLng, initialZoom: 13.2),
                              children: [
                                TileLayer(
                                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                  userAgentPackageName: 'com.flash2mart.delivery',
                                ),
                                PolylineLayer(
                                  polylines: [
                                    Polyline(points: [riderLatLng, storeLatLng, customerLatLng], strokeWidth: 3.5, color: AppColors.primaryEmerald),
                                  ],
                                ),
                                MarkerLayer(
                                  markers: [
                                    Marker(point: riderLatLng, width: 32, height: 32, child: _pin(Icons.delivery_dining_rounded, AppColors.primaryEmerald)),
                                    Marker(point: storeLatLng, width: 32, height: 32, child: _pin(Icons.storefront_rounded, AppColors.accentIndigo)),
                                    Marker(point: customerLatLng, width: 32, height: 32, child: _pin(Icons.location_on_rounded, AppColors.accentRed)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],

                      Text('🏪 Pickup: $storeName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text('📍 Drop: $address', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),

                      if (items.isNotEmpty && !widget.showAvailablePool && isStoreReachedOrLater) ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: AppColors.bgLight,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.borderSubtle),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('📦 Order Details (${items.length} items)',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: AppColors.textDark)),
                              const SizedBox(height: 4),
                              ...items.map((item) {
                                final m = (item is Map) ? item : <String, dynamic>{};
                                final name = (m['name'] ?? m['title'] ?? 'Item').toString();
                                final qty = ParseUtils.toInt(m['qty'] ?? m['quantity'], 1);
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 1.5),
                                  child: Text('• $qty x $name', style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                                );
                              }),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              minimumSize: Size.zero,
                            ),
                            onPressed: () => _callMerchant(context, data),
                            icon: const Icon(Icons.store_rounded, size: 16, color: AppColors.accentIndigo),
                            label: const Text('Store', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.accentIndigo)),
                          ),
                          if (phone.isNotEmpty)
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                minimumSize: Size.zero,
                              ),
                              onPressed: () => _callPhone(phone),
                              icon: const Icon(Icons.call_rounded, color: AppColors.primaryEmerald, size: 16),
                              label: const Text('Customer', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.primaryEmerald)),
                            ),
                          if (!widget.showAvailablePool)
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                minimumSize: Size.zero,
                              ),
                              onPressed: () => _showReportIssueDialog(context, doc.id),
                              icon: const Icon(Icons.report_problem_outlined, color: AppColors.accentRed, size: 16),
                              label: const Text('Issue', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.accentRed)),
                            ),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              minimumSize: Size.zero,
                            ),
                            onPressed: () => _openSmartOrderMap(
                              data,
                              isOutForDeliveryOrLater,
                              storeLatLng,
                              customerLatLng,
                            ),
                            icon: const Icon(Icons.directions_rounded, color: AppColors.accentBlue, size: 18),
                            label: Text(
                              isOutForDeliveryOrLater ? 'Customer Map' : 'Store Map',
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.accentBlue),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: widget.showAvailablePool ? AppColors.accentIndigo : AppColors.primaryEmerald,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () {
                            if (widget.showAvailablePool) {
                              _acceptPoolOrder(context, doc.id, data, myActiveOrders.length);
                            } else if (nextStatus == 'REACHED_PICKUP') {
                              _handleReachedPickupLocation(context, doc.id, storeName, storeLatLng, riderLatLng);
                            } else if (nextStatus == 'PICKUP_COMPLETED') {
                              _confirmPickupCompleted(context, doc.id, storeName, storeLatLng, riderLatLng, items.length, isCod, grandTotal);
                            } else if (nextStatus == 'REACHED_CUSTOMER') {
                              _handleReachedCustomerLocation(context, doc.id, customerLatLng, riderLatLng);
                            } else if (nextStatus == 'OTP') {
                              _showOtpVerifyDialog(context, doc.id, otp, isCod, grandTotal);
                            }
                          },
                          child: Text(
                            widget.showAvailablePool ? 'ACCEPT ORDER' : btnLabel,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _pin(IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Icon(icon, color: Colors.white, size: 17),
    );
  }
}
