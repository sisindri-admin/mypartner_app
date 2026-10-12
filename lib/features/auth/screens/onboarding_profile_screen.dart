import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/custom_button.dart';
import '../../../core/widgets/custom_text_field.dart';
import '../../dashboard/screens/home_screen.dart';

class OnboardingProfileScreen extends StatefulWidget {
  const OnboardingProfileScreen({super.key});

  @override
  State<OnboardingProfileScreen> createState() => _OnboardingProfileScreenState();
}

class _OnboardingProfileScreenState extends State<OnboardingProfileScreen> {
  final TextEditingController _aadhaarController = TextEditingController();
  final TextEditingController _dlController = TextEditingController();
  final TextEditingController _vehicleNoController = TextEditingController();
  final TextEditingController _emergencyContactController = TextEditingController();
  final TextEditingController _bankAccountController = TextEditingController();
  final TextEditingController _ifscController = TextEditingController();

  bool _isLoading = false;

  void _completeOnboarding() async {
    final aadhaar = _aadhaarController.text.trim();
    final dl = _dlController.text.trim();
    final vehicleNo = _vehicleNoController.text.trim();
    final emergencyPhone = _emergencyContactController.text.trim();
    final bankAccount = _bankAccountController.text.trim();
    final ifsc = _ifscController.text.trim();

    if (aadhaar.isEmpty || dl.isEmpty || vehicleNo.isEmpty || emergencyPhone.isEmpty || bankAccount.isEmpty || ifsc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('దయచేసి అన్ని ఆన్‌బోర్డింగ్ వివరాలు పూర్తి చేయండి')),
      );
      return;
    }

    setState(() => _isLoading = true);
    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      await FirebaseFirestore.instance.collection('delivery_partners').doc(user.uid).update({
        'aadhaarNumber': aadhaar,
        'drivingLicense': dl,
        'vehicleNumber': vehicleNo,
        'emergencyContact': emergencyPhone,
        'bankDetails': {
          'accountNumber': bankAccount,
          'ifscCode': ifsc,
        },
        'isOnboarded': true, // ఆన్‌బోర్డింగ్ పూర్తయింది
        'kycStatus': 'Approved',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        setState(() => _isLoading = false);
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('పార్ట్‌నర్ ఆన్‌బోర్డింగ్'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false, // Back button లేకుండా
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'డాక్యుమెంట్లు & బ్యాంక్ వివరాలు',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'డెలివరీ సర్వీస్ ప్రారంభించడానికి ఈ వివరాలు తప్పనిసరి',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 20),

              // 1. Identity Documents
              const Text('1. గుర్తింపు వివరాలు', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
              const SizedBox(height: 10),
              CustomTextField(
                controller: _aadhaarController,
                hintText: 'ఆధార్ కార్డ్ నంబర్ (12 అంకెలు)',
                keyboardType: TextInputType.number,
                maxLength: 12,
              ),
              const SizedBox(height: 12),
              CustomTextField(
                controller: _dlController,
                hintText: 'డ్రైవింగ్ లైసెన్స్ నంబర్ (Driving License)',
              ),
              const SizedBox(height: 12),
              CustomTextField(
                controller: _vehicleNoController,
                hintText: 'వాహనం నంబర్ (ఉదా: AP26XX1234)',
              ),

              const SizedBox(height: 20),

              // 2. Emergency Contact
              const Text('2. అత్యవసర కాంటాక్ట్ (Emergency)', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
              const SizedBox(height: 10),
              CustomTextField(
                controller: _emergencyContactController,
                hintText: 'ఎమర్జెన్సీ ఫోన్ నంబర్',
                keyboardType: TextInputType.phone,
                maxLength: 10,
              ),

              const SizedBox(height: 20),

              // 3. Bank Account Details
              const Text('3. బ్యాంక్ ఖాతా వివరాలు (Payouts)', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
              const SizedBox(height: 10),
              CustomTextField(
                controller: _bankAccountController,
                hintText: 'బ్యాంక్ అకౌంట్ నంబర్',
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              CustomTextField(
                controller: _ifscController,
                hintText: 'IFSC కోడ్ (ఉదా: SBIN0001234)',
              ),

              const SizedBox(height: 32),

              CustomButton(
                text: 'ఆన్‌బోర్డింగ్ పూర్తి చేయండి',
                isLoading: _isLoading,
                onPressed: _completeOnboarding,
              ),
            ],
          ),
        ),
      ),
    );
  }
}