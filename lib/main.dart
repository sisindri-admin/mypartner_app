import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'constants/app_colors.dart';
import 'screens/partner_login_screen.dart';
import 'screens/partner_dashboard_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const Flash2MartDeliveryApp());
}

class Flash2MartDeliveryApp extends StatelessWidget {
  const Flash2MartDeliveryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flash2Mart Delivery Partner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primaryEmerald),
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.bgLight,
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, authSnap) {
          if (authSnap.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator(color: AppColors.primaryEmerald)),
            );
          }
          final user = authSnap.data;
          if (user == null) {
            return const PartnerLoginScreen();
          }

          return StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('delivery_partners').doc(user.uid).snapshots(),
            builder: (context, partnerSnap) {
              if (partnerSnap.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator(color: AppColors.primaryEmerald)),
                );
              }
              final data = (partnerSnap.hasData && partnerSnap.data!.exists)
                  ? (partnerSnap.data!.data() as Map<String, dynamic>? ?? {})
                  : <String, dynamic>{};
              final status = (data['status'] ?? 'pending').toString().toLowerCase();
              final bool isApproved = data['isApproved'] == true || status == 'approved';

              if (!isApproved) {
                return _PendingVerificationScreen(status: status);
              }
              return const PartnerDashboardScreen();
            },
          );
        },
      ),
    );
  }
}

class _PendingVerificationScreen extends StatelessWidget {
  final String status;
  const _PendingVerificationScreen({required this.status});

  @override
  Widget build(BuildContext context) {
    final bool isBlocked = status == 'blocked';
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.borderSubtle),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: isBlocked ? AppColors.accentRedLight : AppColors.accentOrangeLight,
                  child: Icon(
                    isBlocked ? Icons.block_rounded : Icons.hourglass_top_rounded,
                    size: 36,
                    color: isBlocked ? AppColors.accentRed : AppColors.accentOrange,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  isBlocked ? 'Account Suspended' : 'Pending Admin Verification',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.textDark),
                ),
                const SizedBox(height: 8),
                Text(
                  isBlocked
                      ? 'Your delivery partner account has been paused by Admin. Please contact Flash2Mart Nellore hub.'
                      : 'Your profile is registered! Once Flash2Mart Admin approves your ID in the Admin App, your dashboard unlocks automatically.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: () => FirebaseAuth.instance.signOut(),
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('SIGN OUT'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
