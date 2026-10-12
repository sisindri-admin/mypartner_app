import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'core/constants/app_colors.dart';
import 'features/auth/screens/splash_screen.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/auth/screens/onboarding_profile_screen.dart';
import 'features/dashboard/screens/home_screen.dart';
import 'features/dashboard/screens/dashboard_screen.dart';
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const Flash2MartDeliveryApp());
}

class Flash2MartDeliveryApp extends StatelessWidget {
  const Flash2MartDeliveryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flash2Mart Delivery',
      theme: ThemeData(
        scaffoldBackgroundColor: AppColors.background,
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  Future<Widget> _checkUserStatus(User? user) async {
    if (user == null) {
      return const LoginScreen();
    }

    final doc = await FirebaseFirestore.instance
        .collection('delivery_partners')
        .doc(user.uid)
        .get();

    if (doc.exists) {
      bool isOnboarded = doc.data()?['isOnboarded'] ?? false;
      if (isOnboarded) {
        return const DashboardScreen();
      } else {
        return const OnboardingProfileScreen();
      }
    } else {
      return const LoginScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SplashScreen();
        }

        return FutureBuilder<Widget>(
          future: _checkUserStatus(snapshot.data),
          builder: (context, futureSnapshot) {
            if (futureSnapshot.connectionState == ConnectionState.waiting) {
              return const SplashScreen();
            }
            return futureSnapshot.data ?? const LoginScreen();
          },
        );
      },
    );
  }
}