import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:expenseiq/config/theme.dart';
import 'package:expenseiq/models/transaction.dart';
import 'package:expenseiq/services/api_service.dart';

/// Monthly spending caps — one optional overall cap plus any number of
/// per-category ones. Progress is computed server-side against real spending.
class BudgetsScreen extends StatefulWidget {
  const BudgetsScreen({super.key});

  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends State<BudgetsScreen> {
  DateTime _anchor = DateTime.now();
  List<BudgetModel> _budgets = [];
  List<CategoryModel> _categories = [];
  bool _isLoading = true;

  final _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        ApiService().getBudgetStatus(month: _anchor.month, year: _anchor.year),
        ApiService().getCategories(kind: 'expense'),
      ]);
      if (!mounted) return;
      setState(() {
        _budgets = (results[0]).map((e) => BudgetModel.fromJson(e)).toList();
        _categories = (results[1]).map((e) => CategoryModel.fromJson(e)).toList();
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _shiftMonth(int delta) {
    setState(() => _anchor = DateTime(_anchor.year, _anchor.month + delta));
    _load();
  }

  Future<void> _openEditor({BudgetModel? existing}) async {
    // Categories that already have a budget this month can't be doubled up,
    // and neither can a second overall budget.
    final taken = _budgets
        .where((b) => b.id != existing?.id)
        .map((b) => b.categoryId)
        .toSet();

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BudgetEditorSheet(
        existing: existing,
        categories: _categories.where((c) => !taken.contains(c.id)).toList(),
        allowOverall: !taken.contains(null),
        month: _anchor.month,
        year: _anchor.year,
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _delete(BudgetModel budget) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete budget?'),
        content: Text('Remove the budget for ${budget.label}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.expense)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiService().deleteBudget(budget.id);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Could not delete budget')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(title: const Text('Budgets')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Set Budget'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.primary,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
          children: [
            _buildMonthHeader(),
            const SizedBox(height: 16),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 80),
                child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
              )
            else if (_budgets.isEmpty)
              _buildEmpty()
            else ...[
              for (final budget in _budgets) ...[
                _buildBudgetCard(budget),
                const SizedBox(height: 12),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMonthHeader() {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border, width: 0.5),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => _shiftMonth(-1),
            icon: Icon(Icons.chevron_left_rounded, color: colors.textSecondary),
          ),
          Expanded(
            child: Text(
              DateFormat('MMMM yyyy').format(_anchor),
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: colors.textPrimary, fontWeight: FontWeight.w700, fontSize: 16),
            ),
          ),
          IconButton(
            onPressed: () => _shiftMonth(1),
            icon: Icon(Icons.chevron_right_rounded, color: colors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: [
          Icon(Icons.savings_outlined, size: 52, color: colors.textMuted),
          const SizedBox(height: 14),
          Text('No budgets for this month',
              style: TextStyle(color: colors.textSecondary, fontSize: 15)),
          const SizedBox(height: 6),
          Text('Set a cap and track how much is left as you spend.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textMuted, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildBudgetCard(BudgetModel budget) {
    final colors = AppColors.of(context);
    final pct = budget.pct;
    final color = budget.isExceeded
        ? AppColors.expense
        : budget.isNearLimit
            ? const Color(0xFFFFA726)
            : AppColors.income;

    return GestureDetector(
      onTap: () => _openEditor(existing: budget),
      onLongPress: () => _delete(budget),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: budget.isExceeded ? AppColors.expense.withValues(alpha: 0.5) : colors.border,
            width: budget.isExceeded ? 1 : 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    budget.label,
                    style: TextStyle(
                        color: colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 15),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('${pct.toStringAsFixed(0)}%',
                      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (pct / 100).clamp(0.0, 1.0),
                minHeight: 7,
                backgroundColor: colors.border.withValues(alpha: 0.5),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${_inr.format(budget.spent)} of ${_inr.format(budget.amount)}',
                    style: TextStyle(color: colors.textMuted, fontSize: 12)),
                Text(
                  budget.remaining >= 0
                      ? '${_inr.format(budget.remaining)} left'
                      : '${_inr.format(budget.remaining.abs())} over',
                  style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Create/edit sheet for a single budget.
class _BudgetEditorSheet extends StatefulWidget {
  final BudgetModel? existing;
  final List<CategoryModel> categories;
  final bool allowOverall;
  final int month;
  final int year;

  const _BudgetEditorSheet({
    this.existing,
    required this.categories,
    required this.allowOverall,
    required this.month,
    required this.year,
  });

  @override
  State<_BudgetEditorSheet> createState() => _BudgetEditorSheetState();
}

class _BudgetEditorSheetState extends State<_BudgetEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  int? _categoryId;
  bool _isSaving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _amountCtrl.text = existing.amount.toStringAsFixed(0);
      _categoryId = existing.categoryId;
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final data = {
      'amount': _amountCtrl.text.trim(),
      'category': _categoryId,
      'month': widget.month,
      'year': widget.year,
    };

    try {
      if (_isEditing) {
        await ApiService().updateBudget(widget.existing!.id, data);
      } else {
        await ApiService().createBudget(data);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save budget. It may already exist.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    // An existing budget keeps its own category in the list even though the
    // "taken" filter excluded it.
    final options = [...widget.categories];
    final existing = widget.existing;
    if (existing?.categoryId != null && !options.any((c) => c.id == existing!.categoryId)) {
      options.insert(
        0,
        CategoryModel(
          id: existing!.categoryId!,
          name: existing.categoryName ?? '',
          icon: existing.categoryIcon ?? '📦',
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                        color: colors.textMuted,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    _isEditing ? 'Edit Budget' : 'Set a Budget',
                    style: TextStyle(
                        color: colors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('MMMM yyyy').format(DateTime(widget.year, widget.month)),
                    style: TextStyle(color: colors.textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<int?>(
                    value: _categoryId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Scope',
                      prefixIcon: Icon(Icons.category_outlined, color: colors.textMuted),
                    ),
                    dropdownColor: colors.surface,
                    items: [
                      if (widget.allowOverall || existing?.categoryId == null)
                        const DropdownMenuItem(value: null, child: Text('🎯 Overall (all expenses)')),
                      ...options.map((c) => DropdownMenuItem(
                            value: c.id,
                            child: Text('${c.icon} ${c.name}'),
                          )),
                    ],
                    onChanged: (v) => setState(() => _categoryId = v),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    autofocus: !_isEditing,
                    decoration: InputDecoration(
                      labelText: 'Monthly limit',
                      prefixText: '₹ ',
                      prefixIcon: Icon(Icons.account_balance_wallet_outlined, color: colors.textMuted),
                    ),
                    validator: (v) {
                      final n = double.tryParse(v?.trim() ?? '');
                      if (n == null || n <= 0) return 'Enter a valid amount';
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(_isEditing ? 'Update Budget' : 'Save Budget',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
