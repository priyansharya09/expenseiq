import 'dart:async';

import 'package:flutter/material.dart';
import 'package:expenseiq/config/theme.dart';
import 'package:expenseiq/services/api_service.dart';
import 'package:expenseiq/models/transaction.dart';
import 'package:intl/intl.dart';
import 'package:expenseiq/services/app_detector_service.dart';
import 'package:expenseiq/widgets/calculator_sheet.dart';

class AddTransactionScreen extends StatefulWidget {
  final TransactionModel? existingTransaction;
  final VoidCallback? onSaved;

  const AddTransactionScreen({super.key, this.existingTransaction, this.onSaved});

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String _type = 'expense';
  DateTime _date = DateTime.now();
  int? _categoryId;
  List<CategoryModel> _categories = [];
  bool _isLoading = false;
  bool _isSaving = false;
  final _sharedAmountCtrl = TextEditingController();
  String? _paymentMode;
  String? _paymentApp;
  List<Map<String, String>> _paymentModes = [];
  List<UpiAppInfo> _upiApps = [];

  // ─── Category memory ────────────────────────────────────────────
  /// Debounces the suggest lookup so we don't hit the API on every keystroke.
  Timer? _suggestDebounce;

  /// Name we last auto-filled from, so we don't repeat the same lookup.
  String _lastSuggestedFor = '';

  /// Set when the category was chosen by the memory feature rather than by
  /// the user, so we can show the "auto-filled" hint and safely overwrite it.
  bool _categoryWasAutoFilled = false;

  bool get isEditing => widget.existingTransaction != null;

  /// Categories valid for the currently selected type ('both' always applies).
  List<CategoryModel> get _visibleCategories =>
      _categories.where((c) => c.matches(_type)).toList();

  @override
  void initState() {
    super.initState();
    _paymentModes = AppDetectorService.getPaymentModes();
    if (isEditing) {
      final tx = widget.existingTransaction!;
      _nameCtrl.text = tx.name;
      _amountCtrl.text = tx.amount.toStringAsFixed(0);
      _noteCtrl.text = tx.note;
      _type = tx.type;
      _categoryId = tx.categoryId;
      _date = DateTime.tryParse(tx.date) ?? DateTime.now();
      _sharedAmountCtrl.text = tx.sharedAmount > 0 ? tx.sharedAmount.toStringAsFixed(0) : '';
      _paymentMode = tx.paymentMode;
      _paymentApp = tx.paymentApp;
      // Editing an existing row means the category is already deliberate.
      _lastSuggestedFor = tx.name.trim().toLowerCase();
    }
    _loadCategories();
    _loadUpiApps();
    _nameCtrl.addListener(_onNameChanged);
  }

  Future<void> _loadUpiApps() async {
    final apps = await AppDetectorService.getInstalledUpiApps();
    if (mounted) setState(() => _upiApps = apps);
  }

  @override
  void dispose() {
    _suggestDebounce?.cancel();
    _nameCtrl.removeListener(_onNameChanged);
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    _sharedAmountCtrl.dispose();
    super.dispose();
  }

  // ─── Smart category memory ──────────────────────────────────────

  void _onNameChanged() {
    _suggestDebounce?.cancel();
    _suggestDebounce = Timer(const Duration(milliseconds: 450), _applySuggestion);
  }

  /// Looks up what category (and payment mode) this user picked the last few
  /// times they entered a transaction with this exact name, and fills it in.
  /// Never overrides a choice the user made by hand.
  Future<void> _applySuggestion({bool force = false}) async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    final key = name.toLowerCase();
    if (!force && key == _lastSuggestedFor) return;
    _lastSuggestedFor = key;

    final suggestion = await ApiService().suggestForName(name, type: _type);
    if (!mounted || suggestion.isEmpty) return;
    // The user may have kept typing while the request was in flight.
    if (_nameCtrl.text.trim().toLowerCase() != key) return;

    final suggestedCategory = suggestion['category'] as int?;
    final suggestedMode = suggestion['payment_mode'] as String?;

    // Only auto-fill a field the user hasn't deliberately set.
    final canSetCategory = _categoryId == null || _categoryWasAutoFilled;
    final categoryIsValid = suggestedCategory != null &&
        _visibleCategories.any((c) => c.id == suggestedCategory);

    if (!(canSetCategory && categoryIsValid) && suggestedMode == null) return;

    setState(() {
      if (canSetCategory && categoryIsValid) {
        _categoryId = suggestedCategory;
        _categoryWasAutoFilled = true;
      }
      if (suggestedMode != null && _paymentMode == null && _type == 'expense') {
        _paymentMode = suggestedMode;
      }
    });
  }

  Future<void> _openCalculator() async {
    FocusScope.of(context).unfocus();
    final current = double.tryParse(_amountCtrl.text.trim());
    final result = await showCalculatorSheet(context, initial: current);
    if (result != null && mounted) {
      setState(() {
        _amountCtrl.text = result == result.roundToDouble()
            ? result.toStringAsFixed(0)
            : result.toStringAsFixed(2);
      });
    }
  }

  /// Switching income/expense changes which categories apply, so drop a
  /// selection that no longer belongs to the new side.
  void _onTypeChanged(String type) {
    if (_type == type) return;
    setState(() {
      _type = type;
      if (_categoryId != null && !_visibleCategories.any((c) => c.id == _categoryId)) {
        _categoryId = null;
        _categoryWasAutoFilled = false;
      }
      if (type == 'income') {
        _paymentMode = null;
        _paymentApp = null;
        _sharedAmountCtrl.clear();
      }
    });
    // Category memory is tracked per type, so re-run the lookup.
    _applySuggestion(force: true);
  }

  Future<void> _loadCategories() async {
    setState(() => _isLoading = true);
    try {
      final data = await ApiService().getCategories();
      _categories = data.map((e) => CategoryModel.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Failed to load categories: $e');
    }
    if (mounted) setState(() => _isLoading = false);
    // With categories in hand we can now resolve a remembered one.
    if (!isEditing) _applySuggestion(force: true);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final data = {
        'name': _nameCtrl.text.trim(),
        'amount': _amountCtrl.text.trim(),
        'type': _type,
        'category': _categoryId,
        'date': DateFormat('yyyy-MM-dd').format(_date),
        'note': _noteCtrl.text.trim(),
        'shared_amount': _sharedAmountCtrl.text.trim().isEmpty ? 0 : double.tryParse(_sharedAmountCtrl.text.trim()),
        'payment_mode': _paymentMode,
        'payment_app': _paymentApp,
      };

      if (isEditing) {
        await ApiService().updateTransaction(widget.existingTransaction!.id, data);
      } else {
        await ApiService().createTransaction(data);
      }

      widget.onSaved?.call();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to ${isEditing ? 'update' : 'create'} transaction')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _pickDate() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: (isDark ? ThemeData.dark() : ThemeData.light()).copyWith(
            colorScheme: ColorScheme(
              brightness: isDark ? Brightness.dark : Brightness.light,
              primary: AppColors.primary,
              onPrimary: Colors.white,
              secondary: AppColors.secondary,
              onSecondary: Colors.white,
              surface: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
              onSurface: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
              error: AppColors.expense,
              onError: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Transaction' : 'Add Transaction'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Type selector
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: colors.border, width: 0.5),
                      ),
                      child: Row(
                        children: [
                          _buildTypeButton('Expense', 'expense', Icons.trending_down_rounded, AppColors.expense),
                          const SizedBox(width: 4),
                          _buildTypeButton('Income', 'income', Icons.trending_up_rounded, AppColors.income),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Amount field (large) with calculator shortcut
                    Stack(
                      alignment: Alignment.centerRight,
                      children: [
                        TextFormField(
                          controller: _amountCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: colors.textPrimary),
                          textAlign: TextAlign.center,
                          decoration: InputDecoration(
                            hintText: '0',
                            hintStyle: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: colors.textMuted.withValues(alpha: 0.3)),
                            prefixText: '₹ ',
                            prefixStyle: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: colors.textMuted.withValues(alpha: 0.5)),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: true,
                            fillColor: colors.card,
                            contentPadding: const EdgeInsets.only(left: 48, right: 48, top: 16, bottom: 16),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Amount is required';
                            final n = double.tryParse(v);
                            if (n == null || n <= 0) return 'Enter a valid amount';
                            return null;
                          },
                        ),
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: IconButton(
                            tooltip: 'Calculator',
                            onPressed: _openCalculator,
                            icon: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.calculate_rounded, color: AppColors.primary, size: 22),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Name field — autocompletes from names entered before, and
                    // picking one pulls in the category learned for it.
                    Autocomplete<String>(
                      optionsBuilder: (value) async {
                        if (value.text.trim().isEmpty) return const <String>[];
                        return ApiService().getNameSuggestions(value.text.trim());
                      },
                      onSelected: (selection) {
                        _nameCtrl.text = selection;
                        _applySuggestion(force: true);
                      },
                      fieldViewBuilder: (context, textCtrl, focusNode, onSubmit) {
                        // Keep Autocomplete's internal controller in sync with ours
                        // so edit-mode prefill and programmatic sets both show up.
                        if (textCtrl.text != _nameCtrl.text) {
                          textCtrl.value = _nameCtrl.value;
                        }
                        return TextFormField(
                          controller: textCtrl,
                          focusNode: focusNode,
                          onChanged: (v) {
                            if (_nameCtrl.text != v) _nameCtrl.text = v;
                          },
                          decoration: InputDecoration(
                            labelText: 'Description',
                            prefixIcon: Icon(Icons.edit_outlined, color: colors.textMuted),
                            helperText: 'Categories are remembered per description',
                            helperStyle: TextStyle(color: colors.textMuted, fontSize: 11),
                          ),
                          validator: (v) => v == null || v.trim().isEmpty ? 'Description is required' : null,
                          textInputAction: TextInputAction.next,
                        );
                      },
                      optionsViewBuilder: (context, onSelected, options) {
                        return Align(
                          alignment: Alignment.topLeft,
                          child: Material(
                            elevation: 4,
                            borderRadius: BorderRadius.circular(12),
                            color: colors.surface,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 220),
                              child: ListView.builder(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                itemCount: options.length,
                                itemBuilder: (context, i) {
                                  final option = options.elementAt(i);
                                  return ListTile(
                                    dense: true,
                                    leading: Icon(Icons.history_rounded, size: 18, color: colors.textMuted),
                                    title: Text(option, style: TextStyle(color: colors.textPrimary)),
                                    onTap: () => onSelected(option),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),

                    // Category selector — only categories valid for the
                    // selected income/expense side are offered.
                    DropdownButtonFormField<int>(
                      value: _visibleCategories.any((c) => c.id == _categoryId) ? _categoryId : null,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Category',
                        prefixIcon: Icon(Icons.category_outlined, color: colors.textMuted),
                        suffixIcon: _categoryWasAutoFilled
                            ? Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Icon(Icons.auto_awesome_rounded,
                                    color: AppColors.primary, size: 18),
                              )
                            : null,
                        helperText: _categoryWasAutoFilled ? 'Auto-selected from your history' : null,
                        helperStyle: const TextStyle(color: AppColors.primary, fontSize: 11),
                      ),
                      dropdownColor: colors.surface,
                      items: _visibleCategories.map((cat) {
                        return DropdownMenuItem(
                          value: cat.id,
                          child: Text('${cat.icon} ${cat.name}'),
                        );
                      }).toList(),
                      onChanged: (v) => setState(() {
                        _categoryId = v;
                        // A manual pick outranks the remembered one from here on.
                        _categoryWasAutoFilled = false;
                      }),
                      validator: (v) => v == null ? 'Select a category' : null,
                    ),
                    const SizedBox(height: 16),

                    // Date picker
                    GestureDetector(
                      onTap: _pickDate,
                      child: AbsorbPointer(
                        child: TextFormField(
                          decoration: InputDecoration(
                            labelText: 'Date',
                            prefixIcon: Icon(Icons.calendar_today_outlined, color: colors.textMuted),
                            hintText: DateFormat('dd MMM yyyy').format(_date),
                          ),
                          controller: TextEditingController(text: DateFormat('dd MMM yyyy').format(_date)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Note field
                    TextFormField(
                      controller: _noteCtrl,
                      decoration: InputDecoration(
                        labelText: 'Note (optional)',
                        prefixIcon: Icon(Icons.notes_outlined, color: colors.textMuted),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 16),

                    if (_type == 'expense') ...[
                      // Shared Amount field
                      TextFormField(
                        controller: _sharedAmountCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Paid for others (Shared amount)',
                          prefixIcon: Icon(Icons.people_outline, color: colors.textMuted),
                        ),
                        validator: (v) {
                          if (v != null && v.isNotEmpty) {
                            final n = double.tryParse(v);
                            final total = double.tryParse(_amountCtrl.text) ?? 0;
                            if (n == null || n < 0) return 'Invalid amount';
                            if (n > total) return 'Cannot exceed total amount';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Payment Mode selector
                      DropdownButtonFormField<String>(
                        value: _paymentMode,
                        decoration: InputDecoration(
                          labelText: 'Payment Mode',
                          prefixIcon: Icon(Icons.payment, color: colors.textMuted),
                        ),
                        dropdownColor: colors.surface,
                        items: [
                          const DropdownMenuItem(value: null, child: Text('None')),
                          ..._paymentModes.map((mode) {
                            return DropdownMenuItem(
                              value: mode['key'],
                              child: Text('${mode['icon']} ${mode['label']}'),
                            );
                          }),
                        ],
                        onChanged: (v) => setState(() {
                          _paymentMode = v;
                          if (_paymentMode != 'upi') _paymentApp = null;
                        }),
                      ),
                      const SizedBox(height: 16),

                      // UPI App selector
                      if (_paymentMode == 'upi' && _upiApps.isNotEmpty) ...[
                        DropdownButtonFormField<String>(
                          value: _paymentApp,
                          decoration: InputDecoration(
                            labelText: 'UPI App',
                            prefixIcon: Icon(Icons.apps, color: colors.textMuted),
                          ),
                          dropdownColor: colors.surface,
                          items: [
                            const DropdownMenuItem(value: null, child: Text('Other')),
                            ..._upiApps.map((app) {
                              return DropdownMenuItem(
                                value: app.name,
                                child: Text('${app.icon} ${app.name}'),
                              );
                            }),
                          ],
                          onChanged: (v) => setState(() => _paymentApp = v),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ],
                    const SizedBox(height: 32),

                    // Save button
                    SizedBox(
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _type == 'income' ? AppColors.income : AppColors.primary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: _isSaving
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Text(
                                isEditing ? 'Update Transaction' : 'Add Transaction',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildTypeButton(String label, String type, IconData icon, Color color) {
    final isSelected = _type == type;
    final colors = AppColors.of(context);

    return Expanded(
      child: GestureDetector(
        onTap: () => _onTypeChanged(type),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: isSelected ? Border.all(color: color.withValues(alpha: 0.4)) : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: isSelected ? color : colors.textMuted, size: 20),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(
                color: isSelected ? color : colors.textMuted,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              )),
            ],
          ),
        ),
      ),
    );
  }
}
