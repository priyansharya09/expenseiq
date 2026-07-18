import 'package:flutter/material.dart';
import 'package:expenseiq/config/theme.dart';
import 'package:expenseiq/services/api_service.dart';
import 'package:expenseiq/models/contact.dart';
import 'package:expenseiq/screens/add_debt_screen.dart';
import 'package:expenseiq/screens/contact_details_screen.dart';

class SplitsScreen extends StatefulWidget {
  final VoidCallback? onRefresh;
  const SplitsScreen({super.key, this.onRefresh});

  @override
  State<SplitsScreen> createState() => _SplitsScreenState();
}

class _SplitsScreenState extends State<SplitsScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _summary;
  List<ContactModel> _contacts = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final summaryData = await ApiService().getDebtSummary();
      final contactsResponse = await ApiService().getContacts();
      
      setState(() {
        _summary = summaryData.data;
        _contacts = (contactsResponse.data['results'] as List).map((e) => ContactModel.fromJson(e)).toList();
      });
    } catch (e) {
      setState(() => _error = 'Failed to load splits data');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Splits', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: colors.textPrimary)),
                  GestureDetector(
                    onTap: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AddDebtScreen()),
                      );
                      if (result == true) {
                        _loadData();
                        widget.onRefresh?.call();
                      }
                    },
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: colors.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colors.border, width: 0.5),
                      ),
                      child: const Icon(Icons.add, color: AppColors.primary, size: 24),
                    ),
                  ),
                ],
              ),
            ),

            if (_isLoading)
              const Expanded(child: Center(child: CircularProgressIndicator(color: AppColors.primary)))
            else if (_error != null)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!, style: TextStyle(color: colors.textSecondary)),
                      const SizedBox(height: 12),
                      ElevatedButton(onPressed: _loadData, child: const Text('Retry')),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    await _loadData();
                    widget.onRefresh?.call();
                  },
                  color: AppColors.primary,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      _buildSummaryCards(),
                      const SizedBox(height: 24),
                      Text('Contacts', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: colors.textPrimary)),
                      const SizedBox(height: 12),
                      if (_contacts.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(Icons.people_outline, size: 64, color: colors.textMuted),
                                const SizedBox(height: 16),
                                Text('No split records yet', style: TextStyle(color: colors.textSecondary, fontSize: 16)),
                              ],
                            ),
                          ),
                        )
                      else
                        ..._contacts.map((c) => _buildContactCard(c)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards() {
    final colors = AppColors.of(context);
    final lent = double.tryParse(_summary?['total_lent']?.toString() ?? '0') ?? 0;
    final borrowed = double.tryParse(_summary?['total_borrowed']?.toString() ?? '0') ?? 0;

    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.5), width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.arrow_upward, color: AppColors.primary, size: 16),
                    const SizedBox(width: 6),
                    Text('You are owed', style: TextStyle(color: colors.textSecondary, fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 8),
                Text('₹${lent.toStringAsFixed(0)}', style: const TextStyle(color: AppColors.primary, fontSize: 22, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.secondary.withValues(alpha: 0.5), width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.arrow_downward, color: AppColors.secondary, size: 16),
                    const SizedBox(width: 6),
                    Text('You owe', style: TextStyle(color: colors.textSecondary, fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 8),
                Text('₹${borrowed.toStringAsFixed(0)}', style: const TextStyle(color: AppColors.secondary, fontSize: 22, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContactCard(ContactModel contact) {
    final colors = AppColors.of(context);
    Color amountColor = colors.textSecondary;
    String amountText = 'Settled up';
    
    if (contact.netBalance > 0) {
      amountColor = AppColors.primary;
      amountText = 'Owes you ₹${contact.netBalance.toStringAsFixed(0)}';
    } else if (contact.netBalance < 0) {
      amountColor = AppColors.secondary;
      amountText = 'You owe ₹${contact.netBalance.abs().toStringAsFixed(0)}';
    }

    return GestureDetector(
      onTap: () async {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ContactDetailsScreen(contactId: contact.id)),
        );
        if (result == true) {
          _loadData();
          widget.onRefresh?.call();
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.border, width: 0.5),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: AppColors.primary.withValues(alpha: 0.1),
              child: Text(contact.name.substring(0, 1).toUpperCase(), style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(contact.name, style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
                  if (contact.phone.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(contact.phone, style: TextStyle(color: colors.textMuted, fontSize: 12)),
                  ],
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(amountText, style: TextStyle(color: amountColor, fontSize: 14, fontWeight: FontWeight.w600)),
                if (contact.unsettledCount > 0) ...[
                  const SizedBox(height: 2),
                  Text('${contact.unsettledCount} active debts', style: TextStyle(color: colors.textMuted, fontSize: 11)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
