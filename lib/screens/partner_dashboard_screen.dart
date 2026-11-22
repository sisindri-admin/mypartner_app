import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../constants/app_colors.dart';
import '../utils/parse_utils.dart';
import '../services/order_sound_service.dart';
import 'partner_orders_screen.dart';
import 'partner_earnings_screen.dart';
import 'partner_profile_screen.dart';

class PartnerDashboardScreen extends StatefulWidget {
  const PartnerDashboardScreen({super.key});

  @override
  State<PartnerDashboardScreen> createState() => _PartnerDashboardScreenState();
}

class _PartnerDashboardScreenState extends State<PartnerDashboardScreen> {
  int _currentIndex = 0;
  int _syncEpoch = 0;
  Timer? _gpsTimer;
  final Set<String> _knownAssignedIds = {};
  final Set<String> _knownPoolIds = {};
  final Set<String> _dismissedOrderIds = {};
  bool _initialLoadDone = false;
  bool _alertDialogOpen = false;
  Stream<DocumentSnapshot>? _partnerStream;
  Stream<QuerySnapshot>? _ordersStream;
  String? _streamUid;

  @override
  void initState() {
    super.initState();
    _initStreams();
    _startGpsHeartbeat();
  }

  void _initStreams() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid != _streamUid) {
      _streamUid = uid;
      _partnerStream = FirebaseFirestore.instance.collection('delivery_partners').doc(uid).snapshots();
      _ordersStream = FirebaseFirestore.instance.collection('orders').snapshots();
    }
  }

  @override
  void dispose() {
    _gpsTimer?.cancel();
    OrderSoundService.stopAlert();
    super.dispose();
  }

  void _startGpsHeartbeat() {
    _pushCurrentLocation();
    _gpsTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _pushCurrentLocation();
    });
  }

  Future<void> _pushCurrentLocation() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final partnerDoc = await FirebaseFirestore.instance.collection('delivery_partners').doc(user.uid).get();
      if (!partnerDoc.exists || partnerDoc.data()?['isOnline'] != true) return;

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final geo = GeoPoint(pos.latitude, pos.longitude);

      await FirebaseFirestore.instance.collection('delivery_partners').doc(user.uid).set({
        'currentLocation': geo,
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'heading': pos.heading,
        'lastLocationUpdate': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final activeOrders = await FirebaseFirestore.instance
          .collection('orders')
          .where('deliveryPartnerId', isEqualTo: user.uid)
          .get();

      for (final oDoc in activeOrders.docs) {
        final s = (oDoc.data()['orderStatus'] ?? oDoc.data()['status'] ?? '').toString().toLowerCase();
        if (s == 'delivered' || s == 'completed' || s == 'cancelled' || s == 'rejected') continue;
        await oDoc.reference.update({
          'deliveryPartnerLocation': geo,
          'deliveryPartnerLat': pos.latitude,
          'deliveryPartnerLng': pos.longitude,
          'heading': pos.heading,
          'lastLocationUpdate': FieldValue.serverTimestamp(),
        });
      }
    } catch (_) {}
  }

  Future<void> _handlePullRefresh() async {
    HapticFeedback.lightImpact();
    await _pushCurrentLocation();
    if (!mounted) return;
    setState(() {
      _syncEpoch++;
      _streamUid = null;
      _initStreams();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ Data & Live GPS Synchronized!'),
        duration: Duration(seconds: 1),
        backgroundColor: AppColors.primaryEmerald,
      ),
    );
  }

  Future<void> _toggleOnline(bool newVal) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance.collection('delivery_partners').doc(user.uid).set({
      'isOnline': newVal,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (newVal) _pushCurrentLocation();
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

  LatLng _resolveStorePt(Map<String, dynamic> data) {
    var pt = _extractPoint(data['storeLocation'] ?? data['merchantLocation'], const LatLng(0, 0));
    if (pt.latitude == 0) {
      final lat = ParseUtils.toDouble(data['storeLat'] ?? data['merchantLat']);
      final lng = ParseUtils.toDouble(data['storeLng'] ?? data['merchantLng']);
      pt = (lat != 0 && lng != 0) ? LatLng(lat, lng) : const LatLng(14.4485, 79.9890);
    }
    return pt;
  }

  LatLng _resolveCustPt(Map<String, dynamic> data) {
    var pt = _extractPoint(data['customerLocation'] ?? data['deliveryLocation'], const LatLng(0, 0));
    if (pt.latitude == 0) {
      final lat = ParseUtils.toDouble(data['customerLat'] ?? data['latitude']);
      final lng = ParseUtils.toDouble(data['customerLng'] ?? data['longitude']);
      pt = (lat != 0 && lng != 0) ? LatLng(lat, lng) : const LatLng(14.4328, 79.9772);
    }
    return pt;
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

  void _triggerNewOrderAlert({
    required List<Map<String, dynamic>> alertOrders,
    required bool isPoolOrder,
    required Map<String, dynamic> partnerData,
  }) {
    if (_alertDialogOpen || !mounted || alertOrders.isEmpty) return;
    _alertDialogOpen = true;
    OrderSoundService.startLoopingAlert();

    final riderPt = _extractPoint(partnerData['currentLocation'], const LatLng(14.4426, 79.9865));
    double totalDistKm = 0;
    double totalBasePay = 0;
    double totalSurgePay = 0;
    LatLng cursor = riderPt;

    for (final item in alertOrders) {
      final od = item['data'] as Map<String, dynamic>;
      final sPt = _resolveStorePt(od);
      final cPt = _resolveCustPt(od);
      totalDistKm += _haversineKm(cursor, sPt) + _haversineKm(sPt, cPt);
      cursor = cPt;

      final double base = ParseUtils.toDouble(od['riderPayout'] ?? od['deliveryFee'], 25.0);
      final double surge = ParseUtils.toDouble(od['surgeFee'] ?? od['surgeBonus'], 0.0);
      totalBasePay += base;
      totalSurgePay += surge;
    }

    final double totalPayout = totalBasePay + totalSurgePay;
    final int etaMins = (totalDistKm * 3.0 + (alertOrders.length * 4)).round().clamp(5, 90);
    final bool isMulti = alertOrders.length >= 2;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(
            children: [
              const Icon(Icons.notifications_active_rounded, color: AppColors.primaryEmerald, size: 26),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isMulti
                      ? '${alertOrders.length} New Orders Available'
                      : (isPoolOrder ? 'New Order Available!' : 'New Delivery Assigned!'),
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16.5),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (int i = 0; i < alertOrders.length; i++) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: AppColors.primaryEmerald,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w900),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (alertOrders[i]['storeName'] ?? 'Store').toString(),
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.primaryDark),
                          ),
                          Text(
                            'Order #${alertOrders[i]['displayOrderId']}',
                            style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (i < alertOrders.length - 1)
                  Padding(
                    padding: const EdgeInsets.only(left: 10, top: 3, bottom: 3),
                    child: Column(
                      children: List.generate(
                        3,
                        (_) => Container(
                          width: 3,
                          height: 3,
                          margin: const EdgeInsets.symmetric(vertical: 2),
                          decoration: const BoxDecoration(color: AppColors.textMuted, shape: BoxShape.circle),
                        ),
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 16),
              Center(
                child: Column(
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '(₹${totalBasePay.toStringAsFixed(0)} + ',
                          style: const TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w500),
                        ),
                        const Icon(Icons.bolt_rounded, size: 14, color: AppColors.textMuted),
                        Text(
                          ' ₹${totalSurgePay.toStringAsFixed(0)})',
                          style: const TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.payments_rounded, size: 22, color: AppColors.primaryEmerald),
                        const SizedBox(width: 6),
                        Text(
                          '₹${totalPayout.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: AppColors.primaryEmerald,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '📍 ${totalDistKm.toStringAsFixed(1)} km  •  ⏱️ ~$etaMins mins',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.spaceEvenly,
          actions: [
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accentRed,
                side: const BorderSide(color: AppColors.accentRed),
              ),
              onPressed: () async {
                await OrderSoundService.stopAlert();
                for (final item in alertOrders) {
                  _dismissedOrderIds.add(item['docId'].toString());
                }
                _alertDialogOpen = false;
                if (ctx.mounted) Navigator.pop(ctx);

                final user = FirebaseAuth.instance.currentUser;
                if (user != null) {
                  final pName = (partnerData['name'] ?? 'Partner').toString();
                  for (final item in alertOrders) {
                    final docId = item['docId'].toString();
                    final itemIsPool = item['isPool'] == true;
                    final updateData = <String, dynamic>{
                      'rejectedByRiders': FieldValue.arrayUnion([user.uid]),
                      'updatedAt': FieldValue.serverTimestamp(),
                    };
                    if (!itemIsPool) {
                      updateData['deliveryPartnerId'] = '';
                      updateData['orderStatus'] = 'Ready for Pickup';
                      updateData['status'] = 'Ready for Pickup';
                      updateData['currentStatus'] = 'Ready for Pickup';
                      updateData['trackingHistory'] = FieldValue.arrayUnion([
                        {
                          'status': 'Ready for Pickup',
                          'title': 'Rejected by $pName — Re-broadcasting to riders',
                          'timestamp': DateTime.now().toIso8601String(),
                          'updatedBy': 'DeliveryPartner',
                        }
                      ]);
                    }
                    await FirebaseFirestore.instance.collection('orders').doc(docId).update(updateData);
                  }
                }
              },
              child: const Text('REJECT', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryEmerald, foregroundColor: Colors.white),
              onPressed: () async {
                await OrderSoundService.stopAlert();
                for (final item in alertOrders) {
                  final docId = item['docId'].toString();
                  _knownAssignedIds.add(docId);
                  _knownPoolIds.add(docId);
                }
                _alertDialogOpen = false;
                if (ctx.mounted) Navigator.pop(ctx);

                final user = FirebaseAuth.instance.currentUser;
                if (user != null) {
                  final pName = (partnerData['name'] ?? 'Delivery Partner').toString();
                  final pPhone = (partnerData['phone'] ?? '').toString();
                  final vNo = (partnerData['vehicleNumber'] ?? '').toString();
                  for (int i = 0; i < alertOrders.length; i++) {
                    final item = alertOrders[i];
                    final docId = item['docId'].toString();
                    final itemIsPool = item['isPool'] == true;
                    if (itemIsPool) {
                      await FirebaseFirestore.instance.collection('orders').doc(docId).update({
                        'deliveryPartnerId': user.uid,
                        'deliveryPartnerName': pName,
                        'deliveryPartnerPhone': pPhone,
                        if (vNo.isNotEmpty) 'vehicleNumber': vNo,
                        if (partnerData['currentLocation'] != null) 'deliveryPartnerLocation': partnerData['currentLocation'],
                        'orderStatus': 'Accepted',
                        'status': 'Accepted',
                        'currentStatus': 'Accepted',
                        if (isMulti) 'isBatchedOrder': true,
                        if (isMulti) 'batchSequence': i + 1,
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
                    }
                  }
                }
                if (mounted) setState(() => _currentIndex = 0);
              },
              child: const Text('ACCEPT', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    _initStreams();
    return StreamBuilder<DocumentSnapshot>(
      key: ValueKey('partner_stream_$_syncEpoch'),
      stream: _partnerStream,
      builder: (context, snap) {
        final pData = (snap.hasData && snap.data!.exists)
            ? (snap.data!.data() as Map<String, dynamic>? ?? {})
            : <String, dynamic>{};
        final bool isOnline = pData['isOnline'] == true;
        final String partnerName = (pData['name'] ?? 'Partner').toString();

        final pages = [
          PartnerOrdersScreen(
            key: PageStorageKey('active_orders_$_syncEpoch'),
            showAvailablePool: false,
            partnerData: pData,
            onRefreshSync: _handlePullRefresh,
            onOrderAccepted: (id) => _knownAssignedIds.add(id),
          ),
          PartnerOrdersScreen(
            key: PageStorageKey('pool_orders_$_syncEpoch'),
            showAvailablePool: true,
            partnerData: pData,
            onRefreshSync: _handlePullRefresh,
            onOrderAccepted: (id) => _knownAssignedIds.add(id),
          ),
          PartnerEarningsScreen(
            key: PageStorageKey('earnings_$_syncEpoch'),
            partnerData: pData,
            onRefreshSync: _handlePullRefresh,
          ),
        ];

        return Scaffold(
          appBar: AppBar(
            backgroundColor: AppColors.primaryDark,
            foregroundColor: Colors.white,
            elevation: 0,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(partnerName, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                Text(
                  isOnline ? '🟢 Online • Live GPS Syncing' : '⚫ Offline • Tap switch to go Online',
                  style: TextStyle(
                    fontSize: 11,
                    color: isOnline ? const Color(0xFF34D399) : Colors.white60,
                  ),
                ),
              ],
            ),
            actions: [
              Switch(
                value: isOnline,
                activeThumbColor: const Color(0xFF34D399),
                onChanged: _toggleOnline,
              ),
              IconButton(
                tooltip: 'Profile & Withdraw',
                icon: const Icon(Icons.person_outline_rounded, size: 22),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => PartnerProfileScreen(partnerData: pData)),
                ),
              ),
              IconButton(
                tooltip: 'Sign Out',
                icon: const Icon(Icons.logout_rounded, size: 20),
                onPressed: () => FirebaseAuth.instance.signOut(),
              ),
            ],
          ),
          body: Column(
            children: [
              StreamBuilder<QuerySnapshot>(
                stream: _ordersStream,
                builder: (context, orderSnap) {
                  if (!orderSnap.hasData) return const SizedBox.shrink();
                  int myNewCount = 0;
                  int poolCount = 0;
                  final List<Map<String, dynamic>> pendingAlerts = [];
                  final List<Map<String, dynamic>> activeAssignedList = [];

                  for (final d in orderSnap.data!.docs) {
                    final od = d.data() as Map<String, dynamic>;
                    final pid = (od['deliveryPartnerId'] ?? od['driverId'] ?? '').toString().trim();
                    final s = (od['orderStatus'] ?? od['status'] ?? '').toString().toLowerCase();
                    if (s == 'delivered' || s == 'completed' || s == 'cancelled' || s == 'rejected') continue;

                    final List rejectedList = (od['rejectedByRiders'] is List) ? od['rejectedByRiders'] as List : const [];
                    final bool alreadyRejected = _dismissedOrderIds.contains(d.id) || rejectedList.contains(user.uid);

                    if (pid == user.uid) {
                      myNewCount++;
                      activeAssignedList.add({
                        'docId': d.id,
                        'displayOrderId': (od['orderId'] ?? d.id).toString(),
                        'storeName': (od['storeName'] ?? 'Store').toString(),
                        'isPool': false,
                        'data': od,
                      });
                      if (_initialLoadDone && !_knownAssignedIds.contains(d.id) && !alreadyRejected && isOnline && pendingAlerts.length < 2) {
                        pendingAlerts.add({
                          'docId': d.id,
                          'displayOrderId': (od['orderId'] ?? d.id).toString(),
                          'storeName': (od['storeName'] ?? 'Store').toString(),
                          'isPool': false,
                          'data': od,
                        });
                      }
                      _knownAssignedIds.add(d.id);
                    } else if (pid.isEmpty) {
                      poolCount++;
                      if (_initialLoadDone && !_knownPoolIds.contains(d.id) && !alreadyRejected && isOnline && myNewCount < 2 && pendingAlerts.length < 2) {
                        pendingAlerts.add({
                          'docId': d.id,
                          'displayOrderId': (od['orderId'] ?? d.id).toString(),
                          'storeName': (od['storeName'] ?? 'Store').toString(),
                          'isPool': true,
                          'data': od,
                        });
                      }
                      _knownPoolIds.add(d.id);
                    }
                  }
                  _initialLoadDone = true;

                  if (pendingAlerts.isNotEmpty) {
                    // If partner already has 1 active order and 1 new order arrives, show both (1 + 2) in the 2-order popup
                    final List<Map<String, dynamic>> alertOrders = [...pendingAlerts];
                    if (alertOrders.length == 1 && activeAssignedList.length == 1) {
                      final ex = activeAssignedList.first;
                      if (ex['docId'] != alertOrders.first['docId']) {
                        alertOrders.insert(0, ex);
                      }
                    }
                    final bool hasPool = alertOrders.any((e) => e['isPool'] == true);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _triggerNewOrderAlert(
                        alertOrders: alertOrders,
                        isPoolOrder: hasPool,
                        partnerData: pData,
                      );
                    });
                  }

                  if (myNewCount == 0 && poolCount == 0) return const SizedBox.shrink();

                  final bool showAssignedAlert = myNewCount > 0 && _currentIndex != 0;
                  final bool showPoolAlert = poolCount > 0 && _currentIndex != 1;
                  if (!showAssignedAlert && !showPoolAlert) return const SizedBox.shrink();

                  return InkWell(
                    onTap: () => setState(() => _currentIndex = showAssignedAlert ? 0 : 1),
                    child: Container(
                      width: double.infinity,
                      color: showAssignedAlert ? AppColors.primaryEmerald : AppColors.accentIndigo,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.notifications_active_rounded, color: Colors.white, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              showAssignedAlert
                                  ? '🛵 You have $myNewCount Active Trip(s) • Tap to open'
                                  : '🔔 $poolCount New Order(s) in Pool • Tap to accept',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 13),
                        ],
                      ),
                    ),
                  );
                },
              ),
              Expanded(child: IndexedStack(index: _currentIndex, children: pages)),
            ],
          ),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (i) => setState(() => _currentIndex = i),
            selectedItemColor: AppColors.primaryEmerald,
            unselectedItemColor: AppColors.textMuted,
            backgroundColor: Colors.white,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.delivery_dining_rounded),
                label: 'Active Trips',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.explore_rounded),
                label: 'Order Pool',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.account_balance_wallet_rounded),
                label: 'Earnings & COD',
              ),
            ],
          ),
        );
      },
    );
  }
}
