import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:expenseiq/config/theme.dart';
import 'package:expenseiq/services/api_service.dart';
import 'package:expenseiq/models/split_group.dart';
import 'package:expenseiq/screens/add_group_expense_screen.dart';

class GroupDetailScreen extends StatefulWidget {
  final int groupId;
  const GroupDetailScreen({super.key, required this.groupId});

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  bool _isLoading = true;
  String? _error;
  SplitGroupModel? _group;
  List<GroupExpenseModel> _expenses = [];
  bool _changed = false; // report back to caller so the list refreshes

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final groupData = await ApiService().getGroup(widget.groupId);
      final expenseData = await ApiService().getGroupExpenses(widget.groupId);
      if (!mounted) return;
      setState(() {
        _group = SplitGroupModel.fromJson(groupData);
        _expenses = expenseData.map((e) => GroupExpenseModel.fromJson(Map<String, dynamic>.from(e))).toList();
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to load group');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addExpense() async {
    if (_group == null) return;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AddGroupExpenseScreen(group: _group!)),
    );
    if (result == true) {
      _changed = true;
      _load();
    }
  }

  Future<void> _deleteExpense(GroupExpenseModel exp) async {
    final ok = await _confirm('Delete expense?', 'Remove "${exp.name}" (₹${exp.amount.toStringAsFixed(0)})?');
    if (ok != true) return;
    try {
      await ApiService().deleteGroupExpense(exp.id);
      _changed = true;
      _load();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to delete')));
    }
  }

  Future<void> _deleteGroup() async {
    final ok = await _confirm('Delete group?', 'This removes "${_group?.name}" and all its expenses. This cannot be undone.');
    if (ok != true) return;
    try {
      await ApiService().deleteGroup(widget.groupId);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to delete group')));
    }
  }

  Future<bool?> _confirm(String title, String body) {
    final colors = AppColors.of(context);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text(title, style: TextStyle(color: colors.textPrimary)),
        content: Text(body, style: TextStyle(color: colors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.expense)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {},
      child: Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(
          title: Text(_group?.name ?? 'Group'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
            onPressed: () => Navigator.pop(context, _changed),
          ),
          actions: [
            if (_group != null)
              IconButton(
                icon: const Icon(Icons.delete_outline, color: AppColors.expense),
                onPressed: _deleteGroup,
                tooltip: 'Delete group',
              ),
          ],
        ),
        floatingActionButton: _group == null
            ? null
            : FloatingActionButton.extended(
                onPressed: _addExpense,
                backgroundColor: AppColors.primary,
                icon: const Icon(Icons.add, color: Colors.white),
                label: const Text('Add expense', style: TextStyle(color: Colors.white)),
              ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_error!, style: TextStyle(color: colors.textSecondary)),
                        const SizedBox(height: 12),
                        ElevatedButton(onPressed: _load, child: const Text('Retry')),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    color: AppColors.primary,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                      children: [
                        _buildSummary(colors),
                        const SizedBox(height: 24),
                        _buildBalances(colors),
                        const SizedBox(height: 24),
                        Text('Expenses',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: colors.textPrimary)),
                        const SizedBox(height: 12),
                        if (_expenses.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 32),
                            child: Center(
                              child: Column(
                                children: [
                                  Icon(Icons.receipt_long_outlined, size: 56, color: colors.textMuted),
                                  const SizedBox(height: 12),
                                  Text('No expenses yet', style: TextStyle(color: colors.textSecondary)),
                                ],
                              ),
                            ),
                          )
                        else
                          ..._expenses.map((e) => _buildExpenseCard(e, colors)),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _buildSummary(dynamic colors) {
    final g = _group!;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Total group spend', style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
          const SizedBox(height: 6),
          Text('₹${g.totalSpent.toStringAsFixed(2)}',
              style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.group, size: 16, color: Colors.white.withValues(alpha: 0.85)),
              const SizedBox(width: 6),
              Text('${g.members.length} members · ${g.expenseCount} expenses',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBalances(dynamic colors) {
    final balances = _group!.balances;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Balances',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: colors.textPrimary)),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.border, width: 0.5),
          ),
          child: Column(
            children: balances.map((b) {
              final isLast = b == balances.last;
              Color c = colors.textSecondary;
              String label = 'Settled up';
              if (b.net > 0.01) {
                c = AppColors.income;
                label = 'gets back ₹${b.net.toStringAsFixed(2)}';
              } else if (b.net < -0.01) {
                c = AppColors.expense;
                label = 'owes ₹${b.net.abs().toStringAsFixed(2)}';
              }
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  border: isLast ? null : Border(bottom: BorderSide(color: colors.border, width: 0.5)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                      child: Text(
                        b.name.isNotEmpty ? b.name[0].toUpperCase() : '?',
                        style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(b.name + (b.isOwner ? ' (you)' : ''),
                          style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis),
                    ),
                    Text(label, style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 13)),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildExpenseCard(GroupExpenseModel e, dynamic colors) {
    return Dismissible(
      key: ValueKey(e.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        await _deleteExpense(e);
        return false; // _load() rebuilds the list; don't let Dismissible remove it itself
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppColors.expense.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_outline, color: AppColors.expense),
      ),
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
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(e.categoryIcon ?? '🧾', style: const TextStyle(fontSize: 20)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.name, style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 15), overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text('Paid by ${e.paidByName} · ${DateFormat('dd MMM').format(e.date)}',
                      style: TextStyle(color: colors.textMuted, fontSize: 12), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text('₹${e.amount.toStringAsFixed(0)}',
                style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
          ],
        ),
      ),
    );
  }
}
