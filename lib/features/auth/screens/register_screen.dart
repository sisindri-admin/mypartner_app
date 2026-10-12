import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/custom_button.dart';
import '../../../core/widgets/custom_text_field.dart';
import '../../dashboard/screens/home_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  
  String _vehicleType = 'Bike';
  bool _isLoading = false;

  void _registerPartner() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final city = _cityController.text.trim();

    if (name.isEmpty || phone.isEmpty || email.isEmpty || password.isEmpty || city.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('దయచేసి అన్ని వివరాలు నమోదు చేయండి')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. Firebase Auth లో User క్రియేట్ చేయడం
      UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final String uid = userCredential.user!.uid;

      // 2. new `delivery_partners` Firestore collection లోకి డేటా పుష్ చేయడం
      await FirebaseFirestore.instance.collection('delivery_partners').doc(uid).set({
        'uid': uid,
        'fullName': name,
        'phone': '+91$phone',
        'email': email,
        'city': city,
        'vehicleType': _vehicleType,
        'isOnline': false,
        'isOnboarded': false,
        'kycStatus': 'Approved', // డెమో కోసం నేరుగా Approved అని ఇస్తున్నాం
        'createdAt': FieldValue.serverTimestamp(),
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
    } on FirebaseAuthException catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('రిజిస్ట్రేషన్ విఫలమైంది: ${e.message}')),
      );
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ఎర్రర్: ${e.toString()}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('పార్ట్‌నర్ రిజిస్ట్రేషన్'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'కొత్త ఖాతా సృష్టించండి',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              CustomTextField(controller: _nameController, hintText: 'పూర్తి పేరు (Full Name)'),
              const SizedBox(height: 12),
              CustomTextField(
                controller: _phoneController,
                hintText: 'ఫోన్ నంబర్ (10 అంకెలు)',
                keyboardType: TextInputType.phone,
                maxLength: 10,
              ),
              const SizedBox(height: 12),
              CustomTextField(
                controller: _emailController,
                hintText: 'ఈమెయిల్ (Email)',
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              CustomTextField(
                controller: _passwordController,
                hintText: 'పాస్‌వర్డ్ (Password)',
                keyboardType: TextInputType.visiblePassword,
              ),
              const SizedBox(height: 12),
              CustomTextField(controller: _cityController, hintText: 'నగరం (City)'),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _vehicleType,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                items: ['Bike', 'EV Scooter', 'Bicycle'].map((type) {
                  return DropdownMenuItem(value: type, child: Text(type));
                }).toList(),
                onChanged: (val) => setState(() => _vehicleType = val!),
              ),
              const SizedBox(height: 32),
              CustomButton(
                text: 'రిజిస్టర్ అవ్వండి (REGISTER)',
                isLoading: _isLoading,
                onPressed: _registerPartner,
              ),
            ],
          ),
        ),
      ),
    );
  }
}