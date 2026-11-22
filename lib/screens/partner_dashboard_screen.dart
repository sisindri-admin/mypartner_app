import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../constants/app_colors.dart';
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

  void _triggerNewOrderAlert({
    required String docId,
    required String displayOrderId,
    required String storeName,
    required String address,
    required bool isPoolOrder,
    required Map<String, dynamic> partnerData,
  }) {
    if (_alertDialogOpen || !mounted) return;
    _alertDialogOpen = true;
    OrderSoundService.startLoopingAlert();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(
            children: [
              const Icon(Icons.notifications_active_rounded, color: AppColors.primaryEmerald, size: 28),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isPoolOrder ? 'New Order Available!' : 'New Delivery Assigned!',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Order #$displayOrderId',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppColors.primaryDark),
              ),
              const SizedBox(height: 6),
              Text('🏪 Store: $storeName', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
              if (address.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('📍 Drop: $address', style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
              ],
              const SizedBox(height: 10),
              const Text(
                '🔔 Ringing until you Accept or Reject',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.accentOrange),
              ),
            ],
          ),
          actions: [
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accentRed,
                side: const BorderSide(color: AppColors.accentRed),
              ),
              onPressed: () async {
                await OrderSoundService.stopAlert();
                _dismissedOrderIds.add(docId);
                _alertDialogOpen = false;
                if (ctx.mounted) Navigator.pop(ctx);

                final user = FirebaseAuth.instance.currentUser;
                if (user != null) {
                  final pName = (partnerData['name'] ?? 'Partner').toString();
                  final updateData = <String, dynamic>{
                    'rejectedByRiders': FieldValue.arrayUnion([user.uid]),
                    'updatedAt': FieldValue.serverTimestamp(),
                  };
                  if (!isPoolOrder) {
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
              },
              child: const Text('REJECT', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryEmerald, foregroundColor: Colors.white),
              onPressed: () async {
                await OrderSoundService.stopAlert();
                _knownAssignedIds.add(docId);
                _knownPoolIds.add(docId);
                _alertDialogOpen = false;
                if (ctx.mounted) Navigator.pop(ctx);

                final user = FirebaseAuth.instance.currentUser;
                if (isPoolOrder && user != null) {
                  final pName = (partnerData['name'] ?? 'Delivery Partner').toString();
                  final pPhone = (partnerData['phone'] ?? '').toString();
                  final vNo = (partnerData['vehicleNumber'] ?? '').toString();
                  await FirebaseFirestore.instance.collection('orders').doc(docId).update({
                    'deliveryPartnerId': user.uid,
                    'deliveryPartnerName': pName,
                    'deliveryPartnerPhone': pPhone,
                    if (vNo.isNotEmpty) 'vehicleNumber': vNo,
                    if (partnerData['currentLocation'] != null) 'deliveryPartnerLocation': partnerData['currentLocation'],
                    'orderStatus': 'Accepted',
                    'status': 'Accepted',
                    'currentStatus': 'Accepted',
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
                  String? alertDocId;
                  String alertDisplayId = '';
                  String alertStore = 'Store';
                  String alertAddress = '';
                  bool alertIsPool = false;

                  for (final d in orderSnap.data!.docs) {
                    final od = d.data() as Map<String, dynamic>;
                    final pid = (od['deliveryPartnerId'] ?? od['driverId'] ?? '').toString().trim();
                    final s = (od['orderStatus'] ?? od['status'] ?? '').toString().toLowerCase();
                    if (s == 'delivered' || s == 'completed' || s == 'cancelled' || s == 'rejected') continue;

                    final List rejectedList = (od['rejectedByRiders'] is List) ? od['rejectedByRiders'] as List : const [];
                    final bool alreadyRejected = _dismissedOrderIds.contains(d.id) || rejectedList.contains(user.uid);

                    if (pid == user.uid) {
                      myNewCount++;
                      if (_initialLoadDone && !_knownAssignedIds.contains(d.id) && !alreadyRejected && alertDocId == null && isOnline) {
                        alertDocId = d.id;
                        alertDisplayId = (od['orderId'] ?? d.id).toString();
                        alertStore = (od['storeName'] ?? 'Store').toString();
                        alertAddress = (od['deliveryAddress'] ?? od['address'] ?? '').toString();
                        alertIsPool = false;
                      }
                      _knownAssignedIds.add(d.id);
                    } else if (pid.isEmpty) {
                      poolCount++;
                      if (_initialLoadDone && !_knownPoolIds.contains(d.id) && !alreadyRejected && alertDocId == null && isOnline && myNewCount < 2) {
                        alertDocId = d.id;
                        alertDisplayId = (od['orderId'] ?? d.id).toString();
                        alertStore = (od['storeName'] ?? 'Store').toString();
                        alertAddress = (od['deliveryAddress'] ?? od['address'] ?? '').toString();
                        alertIsPool = true;
                      }
                      _knownPoolIds.add(d.id);
                    }
                  }
                  _initialLoadDone = true;

                  if (alertDocId != null) {
                    final docId = alertDocId;
                    final dispId = alertDisplayId;
                    final store = alertStore;
                    final addr = alertAddress;
                    final isPool = alertIsPool;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _triggerNewOrderAlert(
                        docId: docId,
                        displayOrderId: dispId,
                        storeName: store,
                        address: addr,
                        isPoolOrder: isPool,
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
