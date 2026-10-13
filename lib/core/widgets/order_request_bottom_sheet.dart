import 'package:flutter/material.dart';
import '../constants/app_colors.dart'; // Corrected import path
import '../models/order_model.dart';   // Corrected import path

class OrderRequestBottomSheet extends StatefulWidget {
  final OrderModel order;
  final Function(String orderId) onAccept;
  final Function(String orderId, String reason) onReject;

  const OrderRequestBottomSheet({
    super.key,
    required this.order,
    required this.onAccept,
    required this.onReject,
  });

  @override
  State<OrderRequestBottomSheet> createState() => _OrderRequestBottomSheetState();
}

class _OrderRequestBottomSheetState extends State<OrderRequestBottomSheet> {
  // Rejection Reasons List
  final List<String> _rejectionReasons = [
    'బైక్ పాడైంది/రిపేర్ (Bike Issue)',
    'మొబైల్ ఫోన్ చార్జింగ్ లేదా నెట్‌వర్క్ సమస్య (Mobile Issue)',
    'డిస్టెన్స్ చాలా దూరం ఉంది (Order Distance Too Long)',
    'ట్రాఫిక్/వర్షం సమస్య (Heavy Traffic / Bad Weather)',
    'అత్యవసర వ్యక్తిగత పని (Personal Emergency)',
    'ఇతర సమస్య (Other)',
  ];

  String? _selectedReason;
  final TextEditingController _otherReasonController = TextEditingController();

  // Reject Reason Selection Dialog using StatefulBuilder
  void _showRejectReasonDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text(
              'ఆర్డర్ రిజెక్ట్ చేయడానికి కారణం ఎంచుకోండి',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ..._rejectionReasons.map((reason) {
                    return RadioListTile<String>(
                      title: Text(reason, style: const TextStyle(fontSize: 14)),
                      value: reason,
                      groupValue: _selectedReason,
                      activeColor: Colors.red,
                      onChanged: (value) {
                        setDialogState(() {
                          _selectedReason = value;
                        });
                      },
                    );
                  }),
                  if (_selectedReason == 'ఇతర సమస్య (Other)') ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: _otherReasonController,
                      decoration: InputDecoration(
                        hintText: 'సమస్యను టైప్ చేయండి...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('క్యాన్సిల్'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _selectedReason == null
                    ? null
                    : () {
                        String finalReason = _selectedReason == 'ఇతర సమస్య (Other)'
                            ? _otherReasonController.text.trim()
                            : _selectedReason!;
                        if (finalReason.isEmpty) finalReason = 'No reason specified';

                        Navigator.pop(context); // Dialog close
                        widget.onReject(widget.order.orderId, finalReason);
                      },
                child: const Text('రిజెక్ట్ కన్ఫర్మ్', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'కొత్త ఆర్డర్ అభ్యర్థన #${widget.order.orderId}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Text(
                '₹${widget.order.deliveryFee.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          Row(
            children: [
              Icon(Icons.store, color: AppColors.primary), // Removed unnecessary const
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.order.storeName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.location_on, color: Colors.redAccent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.order.deliveryAddress,
                  style: const TextStyle(color: Colors.black87),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 1. SWIPE TO REJECT
          Dismissible(
            key: Key('reject_${widget.order.orderId}'),
            direction: DismissDirection.startToEnd,
            confirmDismiss: (direction) async {
              _showRejectReasonDialog();
              return false;
            },
            background: Container(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: 20),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.close, color: Colors.white, size: 24),
                  SizedBox(width: 8),
                  Text(
                    'REJECTING...',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                border: Border.all(color: Colors.red.shade300),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.arrow_forward, color: Colors.red, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'SWIPE TO REJECT',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // 2. CLICK TO ACCEPT BUTTON
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              onPressed: () => widget.onAccept(widget.order.orderId),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline, color: Colors.white),
                  SizedBox(width: 8),
                  Text(
                    'ACCEPT ORDER',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}