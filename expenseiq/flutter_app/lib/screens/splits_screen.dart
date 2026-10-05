import 'package:flutter/material.dart';
import 'package:expenseiq/config/theme.dart';
import 'package:expenseiq/services/api_service.dart';
import 'package:expenseiq/models/contact.dart';
import 'package:expenseiq/models/split_group.dart';
import 'package:expenseiq/screens/add_debt_screen.dart';
import 'package:expenseiq/screens/contact_details_screen.dart';
import 'package:expenseiq/screens/create_group_screen.dart';
import 'package:expenseiq/screens/group_detail_screen.dart';

class SplitsScreen extends StatefulWidget {
  final VoidCallback? onRefresh;
  const SplitsScreen({super.key, this.onRefresh});

  @override
  State<SplitsScreen> createState() => _SplitsScreenState();
}

class _SplitsScreenState extends State<SplitsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _summary;
  List<ContactModel> _contacts = [];
  List<SplitGroupModel> _groups = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() {}));
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final summaryData = await ApiService().getDebtSummary();
      final contactsResponse = await ApiService().getContacts();
      final groupsData = await ApiService().getGroups();

      if (!mounted) return;
      setState(() {
        _summary = summaryData.data;
        _contacts = (contactsResponse.data['results'] as List).map((e) => ContactModel.fromJson(e)).toList();
        _groups = groupsData.map((e) => SplitGroupModel.fromJson(Map<String, dynamic>.from(e))).toList();
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to load splits data');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _onAdd() async {
    final onGroups = _tabController.index == 0;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => onGroups ? const CreateGroupScreen() : const AddDebtScreen(),
      ),
    );
    if (result == true) {
      _loadData();
      widget.onRefresh?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final onGroups = _tabController.index == 0;

    return Scaffold(
      backgroundColor: colors.background,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _onAdd,
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text(onGroups ? 'New group' : 'New record', style: const TextStyle(color: Colors.white)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Text('Splits', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: colors.textPrimary)),
                ],
              ),
            ),
            TabBar(
              controller: _tabController,
              indicatorColor: AppColors.primary,
              labelColor: AppColors.primary,
              unselectedLabelColor: colors.textSecondary,
              tabs: const [
                Tab(text: 'Groups'),
                Tab(text: 'People'),
              ],
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(_error!, style: TextStyle(color: colors.textSecondary)),
                              const SizedBox(height: 12),
                              ElevatedButton(onPressed: _loadData, child: const Text('Retry')),
                            ],
                          ),
                        )
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            _buildGroupsTab(colors),
                            _buildPeopleTab(colors),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Groups tab ──────────────────────────────────────────────────────────

  Widget _buildGroupsTab(dynamic colors) {
    return RefreshIndicator(
      onRefresh: _loadData,
      color: AppColors.primary,
      child: _groups.isEmpty
          ? ListView(
              children: [
                const SizedBox(height: 80),
                _emptyState(Icons.groups_outlined, 'No groups yet',
                    'Create a group like "Flat" to split shared expenses.', colors),
              ],
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
              children: _groups.map((g) => _buildGroupCard(g, colors)).toList(),
            ),
    );
  }

  Widget _buildGroupCard(SplitGroupModel g, dynamic colors) {
    // "You" balance = the owner member's net.
    final ownerBal = g.balances.where((b) => b.isOwner).toList();
    final net = ownerBal.isNotEmpty ? ownerBal.first.net : 0.0;
    Color c = colors.textSecondary;
    String label = 'Settled up';
    if (net > 0.01) {
      c = AppColors.income;
      label = 'You get ₹${net.toStringAsFixed(0)}';
    } else if (net < -0.01) {
      c = AppColors.expense;
      label = 'You owe ₹${net.abs().toStringAsFixed(0)}';
    }

    return GestureDetector(
      onTap: () async {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => GroupDetailScreen(groupId: g.id)),
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
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.groups, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(g.name,
                      style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text('${g.members.length} members · ₹${g.totalSpent.toStringAsFixed(0)} spent',
                      style: TextStyle(color: colors.textMuted, fontSize: 12), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  // ─── People (1:1 debts) tab ──────────────────────────────────────────────

  Widget _buildPeopleTab(dynamic colors) {
    return RefreshIndicator(
      onRefresh: _loadData,
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
        children: [
          _buildSummaryCards(colors),
          const SizedBox(height: 24),
          Text('Contacts', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: colors.textPrimary)),
          const SizedBox(height: 12),
          if (_contacts.isEmpty)
            _emptyState(Icons.people_outline, 'No split records yet',
                'Tap "New record" to lend or borrow with someone.', colors)
          else
            ..._contacts.map((cModel) => _buildContactCard(cModel, colors)),
        ],
      ),
    );
  }

  Widget _buildSummaryCards(dynamic colors) {
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
                    Flexible(child: Text('You are owed', style: TextStyle(color: colors.textSecondary, fontSize: 13), overflow: TextOverflow.ellipsis)),
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
                    Flexible(child: Text('You owe', style: TextStyle(color: colors.textSecondary, fontSize: 13), overflow: TextOverflow.ellipsis)),
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

  Widget _buildContactCard(ContactModel contact, dynamic colors) {
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
              child: Text(
                contact.name.isNotEmpty ? contact.name.substring(0, 1).toUpperCase() : '?',
                style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(contact.name, style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                  if (contact.phone.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(contact.phone, style: TextStyle(color: colors.textMuted, fontSize: 12)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(amountText, style: TextStyle(color: amountColor, fontSize: 14, fontWeight: FontWeight.w600)),
                if (contact.unsettledCount > 0) ...[
                  const SizedBox(height: 2),
                  Text('${contact.unsettledCount} active', style: TextStyle(color: colors.textMuted, fontSize: 11)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(IconData icon, String title, String subtitle, dynamic colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      child: Center(
        child: Column(
          children: [
            Icon(icon, size: 64, color: colors.textMuted),
            const SizedBox(height: 16),
            Text(title, style: TextStyle(color: colors.textSecondary, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(subtitle, textAlign: TextAlign.center, style: TextStyle(color: colors.textMuted, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
