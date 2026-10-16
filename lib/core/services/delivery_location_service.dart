import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class DeliveryLocationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription<Position>? _positionStreamSubscription;

  void startTrackingOrder(String orderId) async {
    // 1. GPS On ఉందో లేదో చెక్ చేయడం
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    // 2. Location Permissions చెక్ చేయడం
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    if (permission == LocationPermission.deniedForever) return;

    // 3. Platform Specific Location Settings (High Accuracy & 10m Filter)
    late LocationSettings locationSettings;

    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // ప్రతీ 10 మీటర్ల మూవ్‌మెంట్‌కి Firestore అప్‌డేట్ అవుతుంది
        forceLocationManager: true,
        intervalDuration: const Duration(seconds: 5), // ప్రతీ 5 సెకన్లకు ఒకసారి
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.fitness,
        distanceFilter: 10,
        pauseLocationUpdatesAutomatically: false,
        // బ్యాక్‌గ్రౌండ్ లోకేషన్ కోసం
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      );
    }

    // 4. Listen to Position Stream
    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) {
      _firestore.collection('orders').doc(orderId).update({
        'deliveryPartnerLocation': GeoPoint(position.latitude, position.longitude),
        'heading': position.heading, // బైక్ రోటేషన్ డిగ్రీ (0 - 360)
        'lastLocationUpdate': FieldValue.serverTimestamp(),
      });
    });
  }

  void stopTrackingOrder() {
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
  }
}