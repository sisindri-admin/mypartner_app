import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/app_colors.dart';
import '../services/order_sound_service.dart';
import '../utils/parse_utils.dart';

class PartnerProfileScreen extends StatefulWidget {
  final Map<String, dynamic> partnerData;
  const PartnerProfileScreen({super.key, required this.partnerData});

  @override
  State<PartnerProfileScreen> createState() => _PartnerProfileScreenState();
}

class _PartnerProfileScreenState extends State<PartnerProfileScreen> {
  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _vehicleCtrl;
  late TextEditingController _upiCtrl;
  final _withdrawAmtCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: (widget.partnerData['name'] ?? '').toString());
    _phoneCtrl = TextEditingController(text: (widget.partnerData['phone'] ?? '').toString());
    _vehicleCtrl = TextEditingController(text: (widget.partnerData['vehicleNumber'] ?? '').toString());
    _upiCtrl = TextEditingController(text: (widget.partnerData['upiId'] ?? '').toString());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _vehicleCtrl.dispose();
    _upiCtrl.dispose();
    _withdrawAmtCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final snap = await FirebaseFirestore.instance.collection('delivery_partners').doc(user.uid).get();
    if (!mounted) return;
    if (snap.exists) {
      final d = snap.data() ?? {};
      setState(() {
        _nameCtrl.text = (d['name'] ?? '').toString();
        _phoneCtrl.text = (d['phone'] ?? '').toString();
        _vehicleCtrl.text = (d['vehicleNumber'] ?? '').toString();
        _upiCtrl.text = (d['upiId'] ?? '').toString();
      });
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ Profile Synced!'),
        duration: Duration(seconds: 1),
        backgroundColor: AppColors.primaryEmerald,
      ),
    );
  }

  Future<void> _saveProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await FirebaseFirestore.instance.collection('delivery_partners').doc(user.uid).set({
        'name': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'vehicleNumber': _vehicleCtrl.text.trim().toUpperCase(),
        'upiId': _upiCtrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      messenger.showSnackBar(
        const SnackBar(content: Text('✅ Profile & UPI saved!'), backgroundColor: AppColors.primaryEmerald),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.accentRed));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _requestPayout() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final amt = ParseUtils.toDouble(_withdrawAmtCtrl.text);
    final upi = _upiCtrl.text.trim();
    final messenger = ScaffoldMessenger.of(context);

    if (amt <= 0) {
      messenger.showSnackBar(const SnackBar(content: Text('Enter a valid withdrawal amount.')));
      return;
    }
    if (upi.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Please save your UPI ID first.')));
      return;
    }

    await FirebaseFirestore.instance.collection('payout_requests').add({
      'partnerId': user.uid,
      'merchantId': user.uid,
      'merchantName': '${_nameCtrl.text.trim()} (Rider)',
      'shopName': 'Delivery Partner • ${_vehicleCtrl.text.trim().toUpperCase()}',
      'role': 'delivery_partner',
      'amount': amt,
      'upiId': upi,
      'phone': _phoneCtrl.text.trim(),
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });

    _withdrawAmtCtrl.clear();
    messenger.showSnackBar(
      SnackBar(
        content: Text('✅ Payout request for ₹${amt.toStringAsFixed(0)} sent to Admin!'),
        backgroundColor: AppColors.primaryEmerald,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        title: const Text('Partner Profile & Payouts', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textDark,
        elevation: 0.5,
      ),
      body: RefreshIndicator(
        color: AppColors.primaryEmerald,
        onRefresh: _refreshProfile,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.borderSubtle),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Rider Details & UPI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      TextButton.icon(
                        onPressed: () => OrderSoundService.testRingtone(context),
                        icon: const Icon(Icons.volume_up_rounded, size: 17, color: AppColors.primaryEmerald),
                        label: const Text('Test Ringtone', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primaryEmerald)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _field(_nameCtrl, 'Full Name'),
                  _field(_phoneCtrl, 'Phone Number', type: TextInputType.phone),
                  _field(_vehicleCtrl, 'Vehicle Number'),
                  _field(_upiCtrl, 'UPI ID for Payouts (e.g. name@ybl)'),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryEmerald,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _saving ? null : _saveProfile,
                      child: _saving
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('SAVE PROFILE', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.borderSubtle),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Request Earnings Payout', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 6),
                  const Text('Send a withdrawal request to Flash2Mart Admin via your saved UPI ID.',
                      style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  const SizedBox(height: 12),
                  _field(_withdrawAmtCtrl, 'Withdrawal Amount (₹)', type: TextInputType.number),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accentIndigo,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _requestPayout,
                      icon: const Icon(Icons.payments_rounded, size: 18),
                      label: const Text('REQUEST PAYOUT', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, {TextInputType type = TextInputType.text}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: ctrl,
        keyboardType: type,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
    );
  }
}
