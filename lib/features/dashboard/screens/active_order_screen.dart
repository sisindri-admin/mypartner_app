import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/order_model.dart';
import '../../../core/services/order_service.dart';

class ActiveOrderScreen extends StatefulWidget {
  final OrderModel order;

  const ActiveOrderScreen({super.key, required this.order});

  @override
  State<ActiveOrderScreen> createState() => _ActiveOrderScreenState();
}

class _ActiveOrderScreenState extends State<ActiveOrderScreen> {
  final OrderService _orderService = OrderService();
  final TextEditingController _otpController = TextEditingController();

  String _currentStatus = 'Accepted'; // Accepted -> Reached_Store -> Picked_Up -> Delivered
  bool _isLoading = false;

  // SAFE NULL-SAFE INITIALIZATION
  String _customerPhone = '';
  String _customerName = 'కస్టమర్';
  bool _isFetchingCustomer = true;

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.order.status.isEmpty ? 'Accepted' : widget.order.status;
    _fetchCustomerDetails();
  }

  // 1. FETCH CUSTOMER DETAILS FROM FIRESTORE 'customers' COLLECTION SAFELY
  Future<void> _fetchCustomerDetails() async {
    try {
      final String userId = widget.order.userId ?? '';
      
      if (userId.isNotEmpty) {
        final userDoc = await FirebaseFirestore.instance
            .collection('customers')
            .doc(userId)
            .get();

        if (userDoc.exists && mounted) {
          final data = userDoc.data();
          
          // INT OR STRING TO SAFE STRING CONVERSION
          final dynamic rawPhone = data?['phone'] ?? widget.order.userPhone ?? '';
          final dynamic rawName = data?['name'] ?? 'కస్టమర్';

          setState(() {
            _customerPhone = rawPhone.toString().trim();
            _customerName = rawName.toString().trim().isNotEmpty 
                ? rawName.toString().trim() 
                : 'కస్టమర్';
            _isFetchingCustomer = false;
          });
          return;
        }
      }

      if (mounted) {
        setState(() {
          _customerPhone = (widget.order.userPhone ?? '').toString().trim();
          _isFetchingCustomer = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _customerPhone = (widget.order.userPhone ?? '').toString().trim();
          _isFetchingCustomer = false;
        });
      }
    }
  }

  // 2. GOOGLE MAPS NAVIGATION FUNCTION
  Future<void> _openGoogleMaps(String destination) async {
    final String query = Uri.encodeComponent(destination ?? '');
    final Uri googleMapsUrl = Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');

    try {
      if (await canLaunchUrl(googleMapsUrl)) {
        await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Google Maps ఓపెన్ చేయడం కుదరలేదు')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ఎర్రర్: ${e.toString()}')),
        );
      }
    }
  }

  // 3. PHONE CALL FUNCTION
  Future<void> _makePhoneCall() async {
    final String phoneToCall = _customerPhone.trim();

    if (phoneToCall.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('కస్టమర్ ఫోన్ నంబర్ అందుబాటులో లేదు')),
      );
      return;
    }

    final Uri launchUri = Uri(
      scheme: 'tel',
      path: phoneToCall,
    );

    try {
      if (await canLaunchUrl(launchUri)) {
        await launchUrl(launchUri);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('కాల్ చేయడం కుదరలేదు: $phoneToCall')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ఎర్రర్: ${e.toString()}')),
        );
      }
    }
  }

  void _updateStatus(String nextStatus) async {
    setState(() => _isLoading = true);
    try {
      await _orderService.updateOrderStatus(widget.order.orderId, nextStatus);
      setState(() {
        _currentStatus = nextStatus;
        _isLoading = false;
      });

      if (nextStatus == 'Delivered' && mounted) {
        _showSuccessDialog();
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ఎర్రర్: ${e.toString()}')),
        );
      }
    }
  }

  void _verifyOtpAndDeliver() {
    final String otp = _otpController.text.trim();
    if (otp.length != 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('దయచేసి సరైన 4-Digit Delivery OTP ఎంటర్ చేయండి')),
      );
      return;
    }
    _updateStatus('Delivered');
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.green, size: 72),
            const SizedBox(height: 16),
            const Text(
              'డెలివరీ విజయవంతమైంది!',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'మీరు ₹${widget.order.deliveryFee.toStringAsFixed(0)} పేఅవుట్ పొందారు.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  Navigator.pop(context); // Dialog close
                  Navigator.pop(context); // Return to Dashboard
                },
                child: const Text('హోమ్‌కి వెళ్లండి', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: Text('ఆర్డర్ #${widget.order.orderId}'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. ORDER STATUS PROGRESS STEPPER
              _buildProgressTracker(),

              const SizedBox(height: 20),

              // 2. STORE OR CUSTOMER DETAILS CARD
              _buildLocationDetailsCard(),

              const SizedBox(height: 20),

              // 3. REAL ITEMS CHECKLIST FROM FIREBASE
              _buildItemsListCard(),

              const SizedBox(height: 24),

              // 4. DYNAMIC ACTION BUTTON BASED ON STATUS
              _buildActionButton(),
            ],
          ),
        ),
      ),
    );
  }

  // Progress Tracker
  Widget _buildProgressTracker() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStepItem('యాక్సెప్ట్', true),
          _buildStepLine(_currentStatus != 'Accepted'),
          _buildStepItem('స్టోర్ పిక్-అప్', _currentStatus == 'Reached_Store' || _currentStatus == 'Picked_Up' || _currentStatus == 'Delivered'),
          _buildStepLine(_currentStatus == 'Picked_Up' || _currentStatus == 'Delivered'),
          _buildStepItem('డెలివర్డ్', _currentStatus == 'Delivered'),
        ],
      ),
    );
  }

  Widget _buildStepItem(String title, bool isCompleted) {
    return Column(
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: isCompleted ? AppColors.primary : Colors.grey.shade300,
          child: Icon(
            isCompleted ? Icons.check : Icons.circle,
            size: 14,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isCompleted ? FontWeight.bold : FontWeight.normal,
            color: isCompleted ? AppColors.primary : Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildStepLine(bool isCompleted) {
    return Expanded(
      child: Container(
        height: 2,
        color: isCompleted ? AppColors.primary : Colors.grey.shade300,
      ),
    );
  }

  // Location Card
  Widget _buildLocationDetailsCard() {
    final bool isPickupPhase = _currentStatus == 'Accepted' || _currentStatus == 'Reached_Store';
    final String targetAddress = isPickupPhase 
        ? (widget.order.storeName ?? '') 
        : (widget.order.deliveryAddress ?? '');
        
    final bool hasValidPhone = _customerPhone.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isPickupPhase ? Icons.store : Icons.person_pin_circle,
                color: AppColors.primary,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isPickupPhase ? 'పిక్-అప్ స్టోర్ (Pickup)' : 'డెలివరీ అడ్రస్ (Drop)',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    Text(
                      isPickupPhase ? (widget.order.storeName ?? 'స్టోర్') : _customerName,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          Text(
            targetAddress,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => _openGoogleMaps(targetAddress),
                  icon: const Icon(Icons.navigation, size: 18),
                  label: const Text('MAP NAVIGATE'),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _isFetchingCustomer ? null : _makePhoneCall,
                icon: const Icon(Icons.call, color: AppColors.primary, size: 18),
                label: Text(
                  _isFetchingCustomer
                      ? '...'
                      : (hasValidPhone ? 'CALL' : 'NO NUMBER'),
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Real Items List from Firestore
  Widget _buildItemsListCard() {
    final items = widget.order.items ?? [];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'ఐటమ్స్ జాబితా (Order Items)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${items.length} Items',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 20),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                'ఐటమ్స్ వివరాలు అందుబాటులో లేవు.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          '${index + 1}. ${item.name} (${item.unit}) x ${item.quantity}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Text(
                        '₹${item.totalPrice.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'మొత్తం బిల్లు (Grand Total)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              Text(
                '₹${widget.order.grandTotal.toStringAsFixed(0)} (${widget.order.paymentMethod})',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: Colors.green,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Action Buttons
  Widget _buildActionButton() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

    if (_currentStatus == 'Accepted') {
      return SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: () => _updateStatus('Reached_Store'),
          child: const Text('స్టోర్‌కి చేరుకున్నాను (REACHED STORE)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        ),
      );
    } else if (_currentStatus == 'Reached_Store') {
      return SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange.shade800,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: () => _updateStatus('Picked_Up'),
          child: const Text('ఐటమ్స్ పిక్ చేసుకున్నాను (CONFIRM PICKUP)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        ),
      );
    } else if (_currentStatus == 'Picked_Up') {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            TextField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              maxLength: 4,
              decoration: InputDecoration(
                hintText: '4-Digit Delivery OTP ఎంటర్ చేయండి',
                counterText: '',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _verifyOtpAndDeliver,
                child: const Text('డెలివరీ పూర్తి చేయండి (COMPLETE DELIVERY)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }
}