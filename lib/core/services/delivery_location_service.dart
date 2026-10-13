import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

class DeliveryLocationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription<Position>? _positionStreamSubscription;

  // Background/Foreground lo location capture chesi Firestore 'orders' doc update chestundi
  void startTrackingOrder(String orderId) async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // Frame 10 meters maragane trigger autundi
    );

    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) {
      _firestore.collection('orders').doc(orderId).update({
        'deliveryPartnerLocation': GeoPoint(position.latitude, position.longitude),
        'heading': position.heading, // Vehicle rotation angle
        'lastLocationUpdate': FieldValue.serverTimestamp(),
      });
    });
  }

  void stopTrackingOrder() {
    _positionStreamSubscription?.cancel();
  }
}