import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/app_colors.dart';

class PartnerLoginScreen extends StatefulWidget {
  const PartnerLoginScreen({super.key});

  @override
  State<PartnerLoginScreen> createState() => _PartnerLoginScreenState();
}

class _PartnerLoginScreenState extends State<PartnerLoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _vehicleCtrl = TextEditingController();

  bool _isRegister = false;
  bool _loading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _vehicleCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text.trim();
    if (email.isEmpty || pass.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter valid email & password (min 6 chars).')),
      );
      return;
    }

    setState(() => _loading = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      if (_isRegister) {
        final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: pass);
        final uid = cred.user!.uid;
        await FirebaseFirestore.instance.collection('delivery_partners').doc(uid).set({
          'uid': uid,
          'email': email,
          'name': _nameCtrl.text.trim().isEmpty ? 'Delivery Partner' : _nameCtrl.text.trim(),
          'phone': _phoneCtrl.text.trim(),
          'vehicleNumber': _vehicleCtrl.text.trim().toUpperCase(),
          'status': 'pending',
          'isApproved': false,
          'isOnline': false,
          'codSettledAmount': 0.0,
          'currentLocation': const GeoPoint(14.4426, 79.9865),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: pass);
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Auth Error: $e'), backgroundColor: AppColors.accentRed));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: [AppColors.primaryDark, Color(0xFF1E293B)]),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.delivery_dining_rounded, size: 46, color: AppColors.primaryEmerald),
                ),
                const SizedBox(height: 14),
                const Text('Flash2Mart Partner', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22)),
                const Text('Nellore Quick-Commerce Fleet App', style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.borderSubtle),
                  ),
                  child: Column(
                    children: [
                      if (_isRegister) ...[
                        _field(_nameCtrl, 'Full Name', Icons.person_outline),
                        _field(_phoneCtrl, 'Phone Number', Icons.phone_outlined, type: TextInputType.phone),
                        _field(_vehicleCtrl, 'Bike / Vehicle Number (e.g. AP26AB1234)', Icons.two_wheeler_rounded),
                      ],
                      _field(_emailCtrl, 'Email Address', Icons.email_outlined, type: TextInputType.emailAddress),
                      _field(_passCtrl, 'Password', Icons.lock_outline, obscure: true),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryEmerald,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _loading ? null : _submit,
                          child: _loading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : Text(
                                  _isRegister ? 'REGISTER AS PARTNER' : 'SIGN IN',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: () => setState(() => _isRegister = !_isRegister),
                        child: Text(
                          _isRegister ? 'Already registered? Sign In' : 'New Delivery Partner? Register Here',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryEmerald),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon,
      {TextInputType type = TextInputType.text, bool obscure = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: ctrl,
        keyboardType: type,
        obscureText: obscure,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
    );
  }
}
