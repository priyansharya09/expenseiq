import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:expenseiq/config/theme.dart';
import 'package:expenseiq/models/transaction.dart';
import 'package:expenseiq/services/api_service.dart';

/// Rules that post a transaction automatically on a schedule — rent, salary,
/// subscriptions. Due rules are materialized by the backend on app open.
class RecurringScreen extends StatefulWidget {
  const RecurringScreen({super.key});

  @override
  State<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends State<RecurringScreen> {
  List<RecurringModel> _rules = [];
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
        ApiService().getRecurring(),
        ApiService().getCategories(),
      ]);
      if (!mounted) return;
      setState(() {
        _rules = (results[0]).map((e) => RecurringModel.fromJson(e)).toList();
        _categories = (results[1]).map((e) => CategoryModel.fromJson(e)).toList();
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openEditor({RecurringModel? existing}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RecurringEditorSheet(existing: existing, categories: _categories),
    );
    if (saved == true) _load();
  }

  Future<void> _toggleActive(RecurringModel rule) async {
    try {
      await ApiService().updateRecurring(rule.id, {'active': !rule.active});
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Could not update rule')));
      }
    }
  }

  Future<void> _delete(RecurringModel rule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete rule?'),
        content: Text('"${rule.name}" will stop posting automatically. '
            'Transactions it already created are kept.'),
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
      await ApiService().deleteRecurring(rule.id);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Could not delete rule')));
      }
    }
  }

  Future<void> _runDue() async {
    final posted = await ApiService().runDueRecurring();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(posted == 0
            ? 'Nothing due right now'
            : 'Posted $posted transaction${posted == 1 ? '' : 's'}'),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('Recurring'),
        actions: [
          IconButton(
            tooltip: 'Post anything due now',
            onPressed: _runDue,
            icon: const Icon(Icons.play_circle_outline_rounded, size: 22),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Rule'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.primary,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : _rules.isEmpty
                ? _buildEmpty()
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                    itemCount: _rules.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) => _buildRuleCard(_rules[i]),
                  ),
      ),
    );
  }

  Widget _buildEmpty() {
    final colors = AppColors.of(context);
    return ListView(
      children: [
        const SizedBox(height: 100),
        Icon(Icons.autorenew_rounded, size: 52, color: colors.textMuted),
        const SizedBox(height: 14),
        Text('No recurring rules',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textSecondary, fontSize: 15)),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            'Add rent, salary or subscriptions once and let them post themselves.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textMuted, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildRuleCard(RecurringModel rule) {
    final colors = AppColors.of(context);
    final accent = rule.isIncome ? AppColors.income : AppColors.expense;
    final next = rule.nextRunDate;
    final isOverdue = next != null && next.isBefore(DateTime.now());

    return GestureDetector(
      onTap: () => _openEditor(existing: rule),
      onLongPress: () => _delete(rule),
      child: Opacity(
        opacity: rule.active ? 1 : 0.55,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.border, width: 0.5),
          ),
          child: Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(rule.categoryIcon ?? '🔁', style: const TextStyle(fontSize: 20)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(rule.name,
                        style: TextStyle(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 15),
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text(
                          rule.frequency == 'weekly' ? 'Weekly' : 'Monthly',
                          style: TextStyle(color: colors.textMuted, fontSize: 11),
                        ),
                        Text(' · ', style: TextStyle(color: colors.textMuted, fontSize: 11)),
                        Text(
                          next == null
                              ? '—'
                              : isOverdue
                                  ? 'Due now'
                                  : 'Next ${DateFormat('d MMM').format(next)}',
                          style: TextStyle(
                            color: isOverdue && rule.active ? AppColors.expense : colors.textMuted,
                            fontSize: 11,
                            fontWeight: isOverdue ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${rule.isIncome ? '+' : '-'}${_inr.format(rule.amount)}',
                    style: TextStyle(color: accent, fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  SizedBox(
                    height: 26,
                    child: Switch(
                      value: rule.active,
                      activeThumbColor: AppColors.primary,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onChanged: (_) => _toggleActive(rule),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecurringEditorSheet extends StatefulWidget {
  final RecurringModel? existing;
  final List<CategoryModel> categories;

  const _RecurringEditorSheet({this.existing, required this.categories});

  @override
  State<_RecurringEditorSheet> createState() => _RecurringEditorSheetState();
}

class _RecurringEditorSheetState extends State<_RecurringEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();

  String _type = 'expense';
  String _frequency = 'monthly';
  int? _categoryId;
  DateTime _nextRun = DateTime.now();
  bool _isSaving = false;

  bool get _isEditing => widget.existing != null;

  List<CategoryModel> get _visibleCategories =>
      widget.categories.where((c) => c.matches(_type)).toList();

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _nameCtrl.text = existing.name;
      _amountCtrl.text = existing.amount.toStringAsFixed(0);
      _type = existing.type;
      _frequency = existing.frequency;
      _categoryId = existing.categoryId;
      _nextRun = existing.nextRunDate ?? DateTime.now();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickNextRun() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _nextRun,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked != null) setState(() => _nextRun = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final data = {
      'name': _nameCtrl.text.trim(),
      'amount': _amountCtrl.text.trim(),
      'type': _type,
      'category': _categoryId,
      'frequency': _frequency,
      'next_run': DateFormat('yyyy-MM-dd').format(_nextRun),
    };

    try {
      if (_isEditing) {
        await ApiService().updateRecurring(widget.existing!.id, data);
      } else {
        await ApiService().createRecurring(data);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Could not save rule')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
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
                    _isEditing ? 'Edit Rule' : 'New Recurring Rule',
                    style: TextStyle(
                        color: colors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 20),

                  // Type toggle
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: colors.card,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: colors.border, width: 0.5),
                    ),
                    child: Row(
                      children: [
                        _typeButton('Expense', 'expense', AppColors.expense),
                        const SizedBox(width: 4),
                        _typeButton('Income', 'income', AppColors.income),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _nameCtrl,
                    decoration: InputDecoration(
                      labelText: 'Name',
                      hintText: 'e.g. Rent, Netflix, Salary',
                      prefixIcon: Icon(Icons.edit_outlined, color: colors.textMuted),
                    ),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Name is required' : null,
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Amount',
                      prefixText: '₹ ',
                      prefixIcon: Icon(Icons.currency_rupee_rounded, color: colors.textMuted),
                    ),
                    validator: (v) {
                      final n = double.tryParse(v?.trim() ?? '');
                      if (n == null || n <= 0) return 'Enter a valid amount';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  DropdownButtonFormField<int>(
                    value: _visibleCategories.any((c) => c.id == _categoryId) ? _categoryId : null,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Category',
                      prefixIcon: Icon(Icons.category_outlined, color: colors.textMuted),
                    ),
                    dropdownColor: colors.surface,
                    items: _visibleCategories
                        .map((c) => DropdownMenuItem(
                              value: c.id,
                              child: Text('${c.icon} ${c.name}'),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _categoryId = v),
                    validator: (v) => v == null ? 'Select a category' : null,
                  ),
                  const SizedBox(height: 16),

                  DropdownButtonFormField<String>(
                    value: _frequency,
                    decoration: InputDecoration(
                      labelText: 'Repeats',
                      prefixIcon: Icon(Icons.repeat_rounded, color: colors.textMuted),
                    ),
                    dropdownColor: colors.surface,
                    items: const [
                      DropdownMenuItem(value: 'monthly', child: Text('Every month')),
                      DropdownMenuItem(value: 'weekly', child: Text('Every week')),
                    ],
                    onChanged: (v) => setState(() => _frequency = v ?? 'monthly'),
                  ),
                  const SizedBox(height: 16),

                  GestureDetector(
                    onTap: _pickNextRun,
                    child: AbsorbPointer(
                      child: TextFormField(
                        key: ValueKey(_nextRun),
                        initialValue: DateFormat('dd MMM yyyy').format(_nextRun),
                        decoration: InputDecoration(
                          labelText: 'Next run date',
                          prefixIcon:
                              Icon(Icons.event_repeat_rounded, color: colors.textMuted),
                        ),
                      ),
                    ),
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
                          : Text(_isEditing ? 'Update Rule' : 'Create Rule',
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

  Widget _typeButton(String label, String type, Color color) {
    final isSelected = _type == type;
    final colors = AppColors.of(context);

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _type = type;
          // Categories differ per side, so drop one that no longer applies.
          if (_categoryId != null && !_visibleCategories.any((c) => c.id == _categoryId)) {
            _categoryId = null;
          }
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: isSelected ? Border.all(color: color.withValues(alpha: 0.4)) : null,
          ),
          child: Center(
            child: Text(label,
                style: TextStyle(
                  color: isSelected ? color : colors.textMuted,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                )),
          ),
        ),
      ),
    );
  }
}
