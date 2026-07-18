import 'package:flutter/material.dart';
import 'package:expenseiq/config/theme.dart';
import 'package:expenseiq/services/api_service.dart';
import 'package:expenseiq/services/share_service.dart';
import 'package:expenseiq/models/contact.dart';
import 'package:expenseiq/models/debt_record.dart';
import 'package:expenseiq/screens/add_debt_screen.dart';

class ContactDetailsScreen extends StatefulWidget {
  final int contactId;
  const ContactDetailsScreen({super.key, required this.contactId});

  @override
  State<ContactDetailsScreen> createState() => _ContactDetailsScreenState();
}

class _ContactDetailsScreenState extends State<ContactDetailsScreen> {
  bool _isLoading = true;
  ContactModel? _contact;
  List<DebtRecordModel> _records = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final response = await ApiService().getContactBalance(widget.contactId);
      final data = response.data;
      
      setState(() {
        _contact = ContactModel.fromJson(data['contact']);
        _records = (data['records'] as List).map((e) => DebtRecordModel.fromJson(e)).toList();
      });
    } catch (e) {
      setState(() => _error = 'Failed to load details');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _settleRecord(int id) async {
    try {
      await ApiService().settleDebt(id);
      _loadData();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Marked as settled')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to settle')));
    }
  }

  Future<void> _settleAll() async {
    try {
      await ApiService().settleAllDebts(widget.contactId);
      _loadData();
      
      // Prompt to share confirmation
      if (mounted && _contact!.phone.isNotEmpty) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Send Confirmation?'),
            content: const Text('Do you want to send a WhatsApp message confirming the settlement?'),
            backgroundColor: AppColors.surface,
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('No')),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  ShareService.shareViaWhatsApp(
                    _contact!.phone,
                    ShareService.generateSettlementMessage(_contact!.name, _contact!.netBalance.abs()),
                  );
                },
                child: const Text('Yes, Share'),
              ),
            ],
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All records settled')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to settle all')));
    }
  }

  Future<void> _sendReminder() async {
    if (_contact == null || _contact!.phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No phone number saved for this contact')));
      return;
    }

    final message = ShareService.generateDebtReminder(
      contactName: _contact!.name,
      totalAmount: _contact!.netBalance,
      pendingItems: _records.map((r) => {
        'description': r.description,
        'amount': r.amount.toStringAsFixed(0),
        'date': r.date.toString().substring(0, 10),
      }).toList(),
    );

    // Bottom sheet to choose method
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.message, color: Colors.green),
              title: const Text('WhatsApp'),
              onTap: () {
                Navigator.pop(context);
                ShareService.shareViaWhatsApp(_contact!.phone, message);
              },
            ),
            ListTile(
              leading: const Icon(Icons.sms, color: Colors.blue),
              title: const Text('SMS'),
              onTap: () {
                Navigator.pop(context);
                ShareService.shareViaSMS(_contact!.phone, message);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share, color: Colors.orange),
              title: const Text('Other'),
              onTap: () {
                Navigator.pop(context);
                ShareService.shareGeneral(message);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(backgroundColor: AppColors.background, body: Center(child: CircularProgressIndicator()));
    if (_error != null || _contact == null) return Scaffold(backgroundColor: AppColors.background, body: Center(child: Text(_error ?? 'Error', style: const TextStyle(color: Colors.white))));

    Color balanceColor = AppColors.textSecondary;
    String balanceText = 'Settled up';
    if (_contact!.netBalance > 0) {
      balanceColor = AppColors.primary;
      balanceText = 'Owes you ₹${_contact!.netBalance.toStringAsFixed(0)}';
    } else if (_contact!.netBalance < 0) {
      balanceColor = AppColors.secondary;
      balanceText = 'You owe ₹${_contact!.netBalance.abs().toStringAsFixed(0)}';
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_contact!.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: _sendReminder,
          ),
        ],
      ),
      body: Column(
        children: [
          // Header summary
          Container(
            padding: const EdgeInsets.all(24),
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: const Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
            ),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                  child: Text(_contact!.name.substring(0, 1).toUpperCase(), style: const TextStyle(fontSize: 24, color: AppColors.primary, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 16),
                Text(balanceText, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: balanceColor)),
                if (_contact!.phone.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(_contact!.phone, style: const TextStyle(color: AppColors.textMuted)),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => AddDebtScreen(preselectedContactId: _contact!.id)));
                          if (result == true) _loadData();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('Add Record'),
                      ),
                    ),
                    if (_records.isNotEmpty) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _settleAll,
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.primary),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text('Settle All', style: TextStyle(color: AppColors.primary)),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          
          // Records List
          Expanded(
            child: _records.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_outline, size: 64, color: AppColors.textMuted),
                        SizedBox(height: 16),
                        Text('All settled up!', style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: _records.length,
                    itemBuilder: (context, index) {
                      final record = _records[index];
                      final isLend = record.isLend;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.border, width: 0.5),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44, height: 44,
                              decoration: BoxDecoration(
                                color: (isLend ? AppColors.primary : AppColors.secondary).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(isLend ? Icons.arrow_upward : Icons.arrow_downward, color: isLend ? AppColors.primary : AppColors.secondary, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(record.description, style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 2),
                                  Text(record.date.toString().substring(0, 10), style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('₹${record.amount.toStringAsFixed(0)}', style: TextStyle(color: isLend ? AppColors.primary : AppColors.secondary, fontSize: 16, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 6),
                                GestureDetector(
                                  onTap: () => _settleRecord(record.id),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppColors.surface,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: AppColors.primary),
                                    ),
                                    child: const Text('Settle', style: TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
