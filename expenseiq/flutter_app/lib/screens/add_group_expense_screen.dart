import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:expenseiq/config/theme.dart';
import 'package:expenseiq/services/api_service.dart';
import 'package:expenseiq/models/split_group.dart';

class AddGroupExpenseScreen extends StatefulWidget {
  final SplitGroupModel group;
  const AddGroupExpenseScreen({super.key, required this.group});

  @override
  State<AddGroupExpenseScreen> createState() => _AddGroupExpenseScreenState();
}

class _AddGroupExpenseScreenState extends State<AddGroupExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();

  int? _paidById;
  int? _categoryId;
  DateTime _date = DateTime.now();
  List<dynamic> _categories = [];
  bool _isSaving = false;

  // Per-member: whether included in the split, and their share text field.
  final Map<int, bool> _included = {};
  final Map<int, TextEditingController> _shareCtrls = {};

  @override
  void initState() {
    super.initState();
    for (final m in widget.group.members) {
      _included[m.id] = true;
      _shareCtrls[m.id] = TextEditingController();
    }
    // Default payer = the owner member if present, else first.
    final owner = widget.group.members.where((m) => m.isOwner).toList();
    _paidById = owner.isNotEmpty ? owner.first.id : (widget.group.members.isNotEmpty ? widget.group.members.first.id : null);
    _amountCtrl.addListener(_splitEqually);
    _loadCategories();
  }

  @override
  void dispose() {
    _amountCtrl.removeListener(_splitEqually);
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    for (final c in _shareCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final cats = await ApiService().getCategories(kind: 'expense');
      if (mounted) setState(() => _categories = cats);
    } catch (_) {}
  }

  double get _totalAmount => double.tryParse(_amountCtrl.text.trim()) ?? 0;

  List<int> get _includedIds =>
      widget.group.members.where((m) => _included[m.id] == true).map((m) => m.id).toList();

  /// Distribute the total equally across included members (first absorbs the remainder cent).
  void _splitEqually() {
    final ids = _includedIds;
    final total = _totalAmount;
    if (ids.isEmpty || total <= 0) {
      for (final id in _shareCtrls.keys) {
        if (_included[id] != true) _shareCtrls[id]!.text = '';
      }
      return;
    }
    final cents = (total * 100).round();
    final base = cents ~/ ids.length;
    var remainder = cents - base * ids.length;
    for (final id in ids) {
      var share = base;
      if (remainder > 0) {
        share += 1;
        remainder -= 1;
      }
      _shareCtrls[id]!.text = (share / 100).toStringAsFixed(2);
    }
    // Clear excluded rows.
    for (final m in widget.group.members) {
      if (_included[m.id] != true) _shareCtrls[m.id]!.text = '';
    }
    setState(() {});
  }

  double get _shareSum {
    double sum = 0;
    for (final id in _includedIds) {
      sum += double.tryParse(_shareCtrls[id]!.text.trim()) ?? 0;
    }
    return sum;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final ids = _includedIds;
    if (ids.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Include at least one member in the split.')),
      );
      return;
    }
    final diff = (_shareSum - _totalAmount).abs();
    if (diff > 0.01 * ids.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Shares (₹${_shareSum.toStringAsFixed(2)}) must equal the total (₹${_totalAmount.toStringAsFixed(2)}).')),
      );
      return;
    }

    final shares = ids
        .map((id) => {'member': id, 'amount': (double.tryParse(_shareCtrls[id]!.text.trim()) ?? 0).toStringAsFixed(2)})
        .toList();

    setState(() => _isSaving = true);
    try {
      await ApiService().createGroupExpense({
        'group': widget.group.id,
        'name': _nameCtrl.text.trim(),
        'amount': _totalAmount.toStringAsFixed(2),
        'paid_by': _paidById,
        'category': _categoryId,
        'date': DateFormat('yyyy-MM-dd').format(_date),
        'shares': shares,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      String msg = 'Failed to save expense';
      if (e is DioException && e.response?.data is Map) {
        final data = e.response!.data as Map;
        final first = data.values.first;
        msg = first is List ? first.join(' ') : first.toString();
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final remaining = _totalAmount - _shareSum;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text('Expense · ${widget.group.name}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'What for?',
                  hintText: 'e.g. Groceries, Dinner',
                  prefixIcon: Icon(Icons.edit_outlined, color: AppColors.textMuted),
                ),
                validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Total amount',
                  prefixText: '₹ ',
                  prefixIcon: Icon(Icons.currency_rupee, color: AppColors.textMuted),
                ),
                validator: (v) {
                  final n = double.tryParse(v?.trim() ?? '');
                  if (n == null || n <= 0) return 'Enter a valid amount';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Paid by
              DropdownButtonFormField<int>(
                value: _paidById,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Paid by',
                  prefixIcon: Icon(Icons.account_balance_wallet_outlined, color: AppColors.textMuted),
                ),
                dropdownColor: colors.surface,
                items: widget.group.members
                    .map((m) => DropdownMenuItem(value: m.id, child: Text(m.name, overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: (v) => setState(() => _paidById = v),
                validator: (v) => v == null ? 'Required' : null,
              ),
              const SizedBox(height: 16),

              // Category (optional)
              DropdownButtonFormField<int?>(
                value: _categoryId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Category (optional)',
                  prefixIcon: Icon(Icons.category_outlined, color: AppColors.textMuted),
                ),
                dropdownColor: colors.surface,
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('None')),
                  ..._categories.map((c) => DropdownMenuItem<int?>(
                        value: c['id'] as int,
                        child: Text('${c['icon'] ?? ''} ${c['name']}', overflow: TextOverflow.ellipsis),
                      )),
                ],
                onChanged: (v) => setState(() => _categoryId = v),
              ),
              const SizedBox(height: 16),

              // Date
              GestureDetector(
                onTap: _pickDate,
                child: AbsorbPointer(
                  child: TextFormField(
                    decoration: const InputDecoration(
                      labelText: 'Date',
                      prefixIcon: Icon(Icons.calendar_today_outlined, color: AppColors.textMuted),
                    ),
                    controller: TextEditingController(text: DateFormat('dd MMM yyyy').format(_date)),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Split section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Split between',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: colors.textPrimary)),
                  TextButton.icon(
                    onPressed: _splitEqually,
                    icon: const Icon(Icons.balance, size: 18, color: AppColors.primary),
                    label: const Text('Split equally', style: TextStyle(color: AppColors.primary)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ...widget.group.members.map((m) => _buildShareRow(m, colors)),
              const SizedBox(height: 12),

              // Running total vs amount
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: remaining.abs() < 0.01 ? AppColors.income.withValues(alpha: 0.5) : AppColors.expense.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Assigned ₹${_shareSum.toStringAsFixed(2)} of ₹${_totalAmount.toStringAsFixed(2)}',
                        style: TextStyle(color: colors.textSecondary, fontSize: 13)),
                    Text(
                      remaining.abs() < 0.01 ? 'Balanced' : '₹${remaining.toStringAsFixed(2)} left',
                      style: TextStyle(
                        color: remaining.abs() < 0.01 ? AppColors.income : AppColors.expense,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              SizedBox(
                height: 54,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _isSaving
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Save Expense', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShareRow(GroupMemberModel m, dynamic colors) {
    final included = _included[m.id] == true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Checkbox(
            value: included,
            activeColor: AppColors.primary,
            onChanged: (v) {
              setState(() => _included[m.id] = v ?? false);
              _splitEqually();
            },
          ),
          Expanded(
            flex: 4,
            child: Text(
              m.name + (m.isOwner ? ' (you)' : ''),
              style: TextStyle(
                color: included ? colors.textPrimary : colors.textMuted,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: TextFormField(
              controller: _shareCtrls[m.id],
              enabled: included,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.right,
              decoration: const InputDecoration(prefixText: '₹', isDense: true),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
      ),
    );
  }
}
