import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
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
  bool _hasActiveTrip = false;
  DateTime? _lastGpsSyncAt;
  final ValueNotifier<List<Map<String, dynamic>>> _alertOrdersNotifier = ValueNotifier([]);
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
      _ordersStream = FirebaseFirestore.instance
          .collection('orders')
          .where('orderStatus', whereNotIn: const [
            'Delivered',
            'Completed',
            'Cancelled',
            'Rejected',
            'delivered',
            'completed',
            'cancelled',
            'rejected',
          ])
          .snapshots();
    }
  }

  @override
  void dispose() {
    _gpsTimer?.cancel();
    _alertOrdersNotifier.dispose();
    OrderSoundService.stopAlert();
    super.dispose();
  }

  void _startGpsHeartbeat() {
    _pushCurrentLocation();
    _gpsTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _pushCurrentLocation();
    });
  }

  Future<void> _pushCurrentLocation({bool forceHighAccuracy = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (!forceHighAccuracy && !_hasActiveTrip && _lastGpsSyncAt != null) {
      if (DateTime.now().difference(_lastGpsSyncAt!).inSeconds < 45) return;
    }
    try {
      final partnerDoc = await FirebaseFirestore.instance.collection('delivery_partners').doc(user.uid).get();
      if (!partnerDoc.exists || partnerDoc.data()?['isOnline'] != true) return;

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: (_hasActiveTrip || forceHighAccuracy) ? LocationAccuracy.high : LocationAccuracy.medium,
        ),
      );
      _lastGpsSyncAt = DateTime.now();
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
    await _pushCurrentLocation(forceHighAccuracy: true);
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

  Widget _mapPin(IconData icon, Color color, {String badge = ''}) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: [BoxShadow(color: Colors.black.withAlpha(65), blurRadius: 6, offset: const Offset(0, 2))],
          ),
          child: Icon(icon, color: Colors.white, size: 17),
        ),
        if (badge.isNotEmpty)
          Positioned(
            top: -5,
            right: -5,
            child: Container(
              width: 17,
              height: 17,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primaryDark,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Text(badge, style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w900)),
            ),
          ),
      ],
    );
  }

  Future<void> _showRejectReasonDialog(
    BuildContext overlayCtx,
    Map<String, dynamic> partnerData,
  ) async {
    final reasons = [
      "I don't want to do this order",
      'Bike / Vehicle issue',
      'Mobile / Battery / Network issue',
      'Pickup / Drop too far',
      'Other reason',
    ];
    String selected = reasons.first;
    final otherCtrl = TextEditingController();

    await showDialog(
      context: overlayCtx,
      builder: (rCtx) => StatefulBuilder(
        builder: (rCtx, setRState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Row(
            children: [
              Icon(Icons.cancel_outlined, color: AppColors.accentRed),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Select Reject Reason',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16.5),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...reasons.map((r) {
                  return InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => setRState(() => selected = r),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                      child: Row(
                        children: [
                          Icon(
                            selected == r ? Icons.radio_button_checked : Icons.radio_button_off,
                            color: selected == r ? AppColors.accentRed : AppColors.textMuted,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Text(r, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600))),
                        ],
                      ),
                    ),
                  );
                }),
                if (selected == 'Other reason') ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: otherCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Enter your reason...',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(rCtx),
              child: const Text('CANCEL', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.accentRed, foregroundColor: Colors.white),
              onPressed: () async {
                final String finalReason = (selected == 'Other reason' && otherCtrl.text.trim().isNotEmpty)
                    ? otherCtrl.text.trim()
                    : selected;
                Navigator.pop(rCtx);

                await OrderSoundService.stopAlert();
                final currentAlerts = List<Map<String, dynamic>>.from(_alertOrdersNotifier.value);
                for (final item in currentAlerts) {
                  _dismissedOrderIds.add(item['docId'].toString());
                }
                _alertOrdersNotifier.value = [];
                _alertDialogOpen = false;
                if (overlayCtx.mounted) Navigator.pop(overlayCtx);

                final user = FirebaseAuth.instance.currentUser;
                if (user != null) {
                  final pName = (partnerData['name'] ?? 'Partner').toString();
                  for (final item in currentAlerts) {
                    final docId = item['docId'].toString();
                    final itemIsPool = item['isPool'] == true;
                    final updateData = <String, dynamic>{
                      'rejectedByRiders': FieldValue.arrayUnion([user.uid]),
                      'lastRejectReason': finalReason,
                      'updatedAt': FieldValue.serverTimestamp(),
                      'trackingHistory': FieldValue.arrayUnion([
                        {
                          'status': itemIsPool ? 'Rejected in Pool' : 'Ready for Pickup',
                          'title': 'Rejected by $pName ($finalReason)',
                          'timestamp': DateTime.now().toIso8601String(),
                          'updatedBy': 'DeliveryPartner',
                        }
                      ]),
                    };
                    if (!itemIsPool) {
                      updateData['deliveryPartnerId'] = '';
                      updateData['orderStatus'] = 'Ready for Pickup';
                      updateData['status'] = 'Ready for Pickup';
                      updateData['currentStatus'] = 'Ready for Pickup';
                    }
                    await FirebaseFirestore.instance.collection('orders').doc(docId).update(updateData);
                  }
                }
              },
              child: const Text('CONFIRM REJECT', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _triggerNewOrderAlert({
    required Map<String, dynamic> partnerData,
  }) {
    if (_alertDialogOpen || !mounted || _alertOrdersNotifier.value.isEmpty) return;
    _alertDialogOpen = true;
    OrderSoundService.startLoopingAlert();

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      pageBuilder: (ctx, _, _) => PopScope(
        canPop: false,
        child: Scaffold(
          backgroundColor: AppColors.bgLight,
          body: ValueListenableBuilder<List<Map<String, dynamic>>>(
            valueListenable: _alertOrdersNotifier,
            builder: (ctx, alertOrders, _) {
              final riderPt = _extractPoint(partnerData['currentLocation'], const LatLng(14.4426, 79.9865));
              double totalDistKm = 0;
              double totalBasePay = 0;
              double totalSurgePay = 0;

              final List<LatLng> routePoints = [riderPt];
              final List<Marker> markers = [
                Marker(
                  point: riderPt,
                  width: 36,
                  height: 36,
                  child: _mapPin(Icons.two_wheeler_rounded, AppColors.primaryEmerald),
                ),
              ];

              // Route: Partner -> Store(s) -> Customer 1 -> Customer 2
              final List<LatLng> storePts = [];
              final List<LatLng> custPts = [];
              for (int i = 0; i < alertOrders.length; i++) {
                final od = alertOrders[i]['data'] as Map<String, dynamic>;
                final sPt = _resolveStorePt(od);
                final cPt = _resolveCustPt(od);
                storePts.add(sPt);
                custPts.add(cPt);

                final double base = ParseUtils.toDouble(od['riderPayout'] ?? od['deliveryFee'], 25.0);
                final double surge = ParseUtils.toDouble(od['surgeFee'] ?? od['surgeBonus'], 0.0);
                totalBasePay += base;
                totalSurgePay += surge;
              }

              for (int i = 0; i < storePts.length; i++) {
                final sPt = storePts[i];
                if (i == 0 || _haversineKm(storePts[i - 1], sPt) > 0.05) {
                  routePoints.add(sPt);
                }
                markers.add(
                  Marker(
                    point: sPt,
                    width: 36,
                    height: 36,
                    child: _mapPin(Icons.storefront_rounded, AppColors.accentIndigo, badge: storePts.length > 1 ? '${i + 1}' : ''),
                  ),
                );
              }
              for (int i = 0; i < custPts.length; i++) {
                final cPt = custPts[i];
                routePoints.add(cPt);
                markers.add(
                  Marker(
                    point: cPt,
                    width: 36,
                    height: 36,
                    child: _mapPin(Icons.location_on_rounded, AppColors.accentRed, badge: custPts.length > 1 ? '${i + 1}' : ''),
                  ),
                );
              }

              for (int i = 1; i < routePoints.length; i++) {
                totalDistKm += _haversineKm(routePoints[i - 1], routePoints[i]);
              }

              final double totalPayout = totalBasePay + totalSurgePay;
              final int etaMins = (totalDistKm * 3.0 + (alertOrders.length * 4)).round().clamp(5, 90);
              final bool isMulti = alertOrders.length >= 2;
              final bool isPoolOrder = alertOrders.any((e) => e['isPool'] == true);

              final bounds = LatLngBounds.fromPoints(routePoints);
              final bool hasSpread = (bounds.north - bounds.south).abs() > 0.0005 || (bounds.east - bounds.west).abs() > 0.0005;

              return Column(
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        FlutterMap(
                          key: ValueKey('alert_map_${alertOrders.length}_${totalDistKm.toStringAsFixed(2)}'),
                          options: MapOptions(
                            initialCenter: riderPt,
                            initialZoom: 14.0,
                            initialCameraFit: hasSpread
                                ? CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.fromLTRB(48, 84, 48, 40))
                                : null,
                          ),
                          children: [
                            TileLayer(
                              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.flash2mart.delivery',
                            ),
                            PolylineLayer(
                              polylines: [
                                Polyline(
                                  points: routePoints,
                                  strokeWidth: 4.5,
                                  color: AppColors.primaryEmerald,
                                  pattern: StrokePattern.dotted(spacingFactor: 2.2),
                                ),
                              ],
                            ),
                            MarkerLayer(markers: markers),
                          ],
                        ),
                        SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 14, top: 10),
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: AppColors.accentRed,
                                elevation: 4,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  side: const BorderSide(color: AppColors.accentRed, width: 1.2),
                                ),
                              ),
                              onPressed: () => _showRejectReasonDialog(ctx, partnerData),
                              icon: const Icon(Icons.close_rounded, size: 18),
                              label: const Text('REJECT', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(35),
                          blurRadius: 18,
                          offset: const Offset(0, -4),
                        ),
                      ],
                    ),
                    child: SafeArea(
                      top: false,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Container(
                              width: 40,
                              height: 4,
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: AppColors.borderSubtle,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              const Icon(Icons.notifications_active_rounded, color: AppColors.primaryEmerald, size: 24),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  isMulti
                                      ? '${alertOrders.length} New Orders Available'
                                      : (isPoolOrder ? 'New Order Available!' : 'New Delivery Assigned!'),
                                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: AppColors.primaryDark),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
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
                                        '${i + 1} Order (${(alertOrders[i]['storeName'] ?? 'Store').toString()})',
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
                          const SizedBox(height: 14),
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
                                const SizedBox(height: 3),
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
                                const SizedBox(height: 6),
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
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryEmerald,
                                foregroundColor: Colors.white,
                                elevation: 2,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              onPressed: () async {
                                await OrderSoundService.stopAlert();
                                final currentAlerts = List<Map<String, dynamic>>.from(_alertOrdersNotifier.value);
                                for (final item in currentAlerts) {
                                  final docId = item['docId'].toString();
                                  _knownAssignedIds.add(docId);
                                  _knownPoolIds.add(docId);
                                }
                                _alertOrdersNotifier.value = [];
                                _alertDialogOpen = false;
                                if (ctx.mounted) Navigator.pop(ctx);

                                final user = FirebaseAuth.instance.currentUser;
                                if (user != null) {
                                  final pName = (partnerData['name'] ?? 'Delivery Partner').toString();
                                  final pPhone = (partnerData['phone'] ?? '').toString();
                                  final vNo = (partnerData['vehicleNumber'] ?? '').toString();
                                  final bool multiNow = currentAlerts.length >= 2;
                                  for (int i = 0; i < currentAlerts.length; i++) {
                                    final item = currentAlerts[i];
                                    final docId = item['docId'].toString();
                                    final itemIsPool = item['isPool'] == true;
                                    if (itemIsPool) {
                                      await FirebaseFirestore.instance.collection('orders').doc(docId).update({
                                        'deliveryPartnerId': user.uid,
                                        'deliveryPartnerName': pName,
                                        'deliveryPartnerPhone': pPhone,
                                        if (vNo.isNotEmpty) 'vehicleNumber': vNo,
                                        if (partnerData['currentLocation'] != null)
                                          'deliveryPartnerLocation': partnerData['currentLocation'],
                                        'orderStatus': 'Accepted',
                                        'status': 'Accepted',
                                        'currentStatus': 'Accepted',
                                        if (multiNow) 'isBatchedOrder': true,
                                        if (multiNow) 'batchSequence': i + 1,
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
                              child: const Text(
                                'ACCEPT ORDER',
                                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5, letterSpacing: 0.6),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
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

        final String initial = partnerName.trim().isNotEmpty ? partnerName.trim()[0].toUpperCase() : 'P';

        return Scaffold(
          backgroundColor: AppColors.bgLight,
          appBar: AppBar(
            backgroundColor: AppColors.primaryDark,
            foregroundColor: Colors.white,
            elevation: 0,
            toolbarHeight: 64,
            titleSpacing: 14,
            title: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isOnline
                          ? [AppColors.primaryEmerald, const Color(0xFF34D399)]
                          : [Colors.white24, Colors.white12],
                    ),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text(
                    initial,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        partnerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, letterSpacing: 0.1),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: isOnline ? const Color(0xFF34D399) : Colors.white54,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            isOnline ? 'Online • Live GPS' : 'Offline • Duty Off',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isOnline ? const Color(0xFF34D399) : Colors.white60,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              GestureDetector(
                onTap: () => _toggleOnline(!isOnline),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(vertical: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isOnline ? AppColors.primaryEmerald.withAlpha(55) : Colors.white12,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isOnline ? const Color(0xFF34D399) : Colors.white30,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isOnline ? Icons.power_settings_new_rounded : Icons.bedtime_outlined,
                        size: 14,
                        color: isOnline ? const Color(0xFF34D399) : Colors.white70,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isOnline ? 'ON' : 'OFF',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: isOnline ? const Color(0xFF34D399) : Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
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
              Expanded(child: IndexedStack(index: _currentIndex, children: pages)),
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
                  _hasActiveTrip = myNewCount > 0;

                  if (pendingAlerts.isNotEmpty) {
                    final List<Map<String, dynamic>> alertOrders = [...pendingAlerts];
                    if (alertOrders.length == 1 && activeAssignedList.length == 1) {
                      final ex = activeAssignedList.first;
                      if (ex['docId'] != alertOrders.first['docId']) {
                        alertOrders.insert(0, ex);
                      }
                    }
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      if (_alertDialogOpen) {
                        final current = List<Map<String, dynamic>>.from(_alertOrdersNotifier.value);
                        bool added = false;
                        for (final item in alertOrders) {
                          if (current.length >= 2) break;
                          if (!current.any((e) => e['docId'] == item['docId'])) {
                            current.add(item);
                            added = true;
                          }
                        }
                        if (added) {
                          _alertOrdersNotifier.value = current;
                          OrderSoundService.ensureLoopingAlert();
                        }
                      } else {
                        _alertOrdersNotifier.value = alertOrders;
                        _triggerNewOrderAlert(partnerData: pData);
                      }
                    });
                  }

                  if (myNewCount == 0 && poolCount == 0) return const SizedBox.shrink();

                  final bool showAssignedAlert = myNewCount > 0 && _currentIndex != 0;
                  final bool showPoolAlert = poolCount > 0 && _currentIndex != 1;
                  if (!showAssignedAlert && !showPoolAlert) return const SizedBox.shrink();

                  final String primaryStore = activeAssignedList.isNotEmpty
                      ? (activeAssignedList.first['storeName'] ?? 'Store').toString()
                      : '';
                  final String primaryStatus = activeAssignedList.isNotEmpty
                      ? (((activeAssignedList.first['data'] as Map<String, dynamic>?)?['orderStatus'] ??
                              (activeAssignedList.first['data'] as Map<String, dynamic>?)?['status'] ??
                              'Processing')
                          .toString())
                      : 'Processing';
                  final Color barStart = showAssignedAlert ? const Color(0xFFEA580C) : const Color(0xFF312E81);
                  final Color barEnd = showAssignedAlert ? const Color(0xFFF59E0B) : AppColors.accentIndigo;

                  return Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                    child: Material(
                      color: Colors.transparent,
                      elevation: 6,
                      shadowColor: barStart.withAlpha(110),
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => setState(() => _currentIndex = showAssignedAlert ? 0 : 1),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [barStart, barEnd],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withAlpha(70), width: 1),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: Colors.white.withAlpha(45),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  showAssignedAlert ? Icons.local_shipping_rounded : Icons.explore_rounded,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withAlpha(55),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Container(
                                                width: 6,
                                                height: 6,
                                                decoration: const BoxDecoration(
                                                  color: Colors.white,
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                showAssignedAlert ? 'ORDER PROCESSING' : 'NEW POOL',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.w900,
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (showAssignedAlert) ...[
                                          const SizedBox(width: 6),
                                          Flexible(
                                            child: Text(
                                              primaryStatus.toUpperCase(),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      showAssignedAlert
                                          ? '$myNewCount Active ${myNewCount == 1 ? 'Order' : 'Orders'} in Progress'
                                          : '$poolCount New ${poolCount == 1 ? 'Order' : 'Orders'} Available',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 15,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      showAssignedAlert
                                          ? (primaryStore.isNotEmpty ? 'Store: $primaryStore • Tap to continue' : 'Tap to continue active delivery')
                                          : 'Tap to open Order Pool & accept',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(22),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      showAssignedAlert ? 'OPEN' : 'VIEW',
                                      style: TextStyle(
                                        color: barStart,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(width: 3),
                                    Icon(Icons.arrow_forward_rounded, color: barStart, size: 15),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          bottomNavigationBar: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: AppColors.borderSubtle, width: 1)),
            ),
            child: BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: (i) => setState(() => _currentIndex = i),
              selectedItemColor: AppColors.primaryEmerald,
              unselectedItemColor: AppColors.textMuted,
              selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
              backgroundColor: Colors.white,
              elevation: 0,
              type: BottomNavigationBarType.fixed,
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.two_wheeler_rounded),
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
          ),
        );
      },
    );
  }
}
