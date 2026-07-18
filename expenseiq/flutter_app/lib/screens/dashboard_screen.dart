import 'package:flutter/material.dart';
import 'package:expenseiq/config/theme.dart';
import 'package:expenseiq/services/api_service.dart';
import 'package:expenseiq/models/transaction.dart';
import 'package:expenseiq/widgets/app_widgets.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _summary;
  List<TransactionModel> _recentTransactions = [];
  bool _isLoading = true;
  String? _error;
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _loadData();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final now = DateTime.now();
      final results = await Future.wait([
        ApiService().getSummary(month: now.month, year: now.year),
        ApiService().getTransactions(month: now.month, year: now.year),
      ]);
      _summary = results[0] as Map<String, dynamic>;
      final txData = results[1] as Map<String, dynamic>;
      _recentTransactions = (txData['results'] as List)
          .take(5)
          .map((e) => TransactionModel.fromJson(e))
          .toList();
      _animController.forward(from: 0);
    } catch (e) {
      _error = 'Failed to load data. Check connection.';
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatAmount(dynamic amount) {
    final num = double.tryParse(amount.toString()) ?? 0;
    if (num >= 100000) {
      return '${(num / 1000).toStringAsFixed(1)}K';
    }
    return NumberFormat('#,##,###').format(num.toInt());
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadData,
          color: AppColors.primary,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : _error != null
                  ? _buildError()
                  : _buildContent(),
        ),
      ),
    );
  }

  Widget _buildError() {
    final colors = AppColors.of(context);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off_rounded, size: 64, color: colors.textMuted),
          const SizedBox(height: 16),
          Text(_error!, style: TextStyle(color: colors.textSecondary, fontSize: 16)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final colors = AppColors.of(context);
    final income = double.tryParse(_summary?['total_income']?.toString() ?? '0') ?? 0;
    final expense = double.tryParse(_summary?['total_expense']?.toString() ?? '0') ?? 0;
    final balance = income - expense;
    final catBreakdown = (_summary?['category_breakdown'] as List?) ?? [];

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hello! 👋',
                  style: TextStyle(color: colors.textSecondary, fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat('MMMM yyyy').format(DateTime.now()),
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: colors.textPrimary),
                ),
              ],
            ),
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colors.border, width: 0.5),
              ),
              child: Icon(Icons.notifications_outlined, color: colors.textSecondary, size: 22),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Summary cards row
        Row(
          children: [
            Expanded(
              child: SummaryCard(
                title: 'Income',
                amount: _formatAmount(income),
                icon: Icons.trending_up_rounded,
                gradient: AppColors.incomeGradient,
                subtitle: '${_summary?['transaction_count'] ?? 0} transactions',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SummaryCard(
                title: 'Expenses',
                amount: _formatAmount(expense),
                icon: Icons.trending_down_rounded,
                gradient: AppColors.expenseGradient,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Balance card
        SummaryCard(
          title: 'Balance',
          amount: _formatAmount(balance),
          icon: Icons.account_balance_wallet_rounded,
          gradient: AppColors.balanceGradient,
          subtitle: balance >= 0 ? 'You\'re doing great! 🎉' : 'Spending exceeds income ⚠️',
        ),
        const SizedBox(height: 28),

        // Category breakdown
        if (catBreakdown.isNotEmpty) ...[
          Text('Expense Breakdown', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: colors.textPrimary)),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: _buildPieChart(catBreakdown, expense),
          ),
          const SizedBox(height: 28),
        ],

        // Daily spending trend
        if (_summary?['daily_spending'] != null && (_summary!['daily_spending'] as List).isNotEmpty) ...[
          _buildLineChart(_summary!['daily_spending'] as List),
          const SizedBox(height: 28),
        ],

        // Insights
        _buildInsights(_summary),
        const SizedBox(height: 28),

        // Recent transactions
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Recent Transactions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: colors.textPrimary)),
            if (_recentTransactions.isNotEmpty)
              Text('${_recentTransactions.length} items', style: TextStyle(color: colors.textMuted, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 12),

        if (_recentTransactions.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.border, width: 0.5),
            ),
            child: Column(
              children: [
                Icon(Icons.receipt_long_outlined, size: 48, color: colors.textMuted),
                const SizedBox(height: 12),
                Text('No transactions yet', style: TextStyle(color: colors.textSecondary, fontSize: 15)),
                const SizedBox(height: 4),
                Text('Tap + to add your first one', style: TextStyle(color: colors.textMuted, fontSize: 13)),
              ],
            ),
          )
        else
          ..._recentTransactions.map((tx) => TransactionCard(
                name: tx.name,
                amount: tx.amount,
                type: tx.type,
                categoryName: tx.categoryName,
                categoryIcon: tx.categoryIcon,
                date: tx.date,
                note: tx.note,
              )),
      ],
    );
  }

  Widget _buildInsights(Map<String, dynamic>? summary) {
    if (summary == null) return const SizedBox.shrink();
    final colors = AppColors.of(context);
    
    final comparison = summary['comparison'] as Map<String, dynamic>?;
    final avgDaily = double.tryParse(summary['avg_daily_expense']?.toString() ?? '0') ?? 0;
    
    if (comparison == null) return const SizedBox.shrink();
    
    final expenseChange = double.tryParse(comparison['expense_change_pct']?.toString() ?? '0') ?? 0;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Insights', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: colors.textPrimary)),
        const SizedBox(height: 12),
        _buildInsightCard(
          icon: Icons.auto_graph,
          title: 'Daily Average',
          subtitle: 'You spend ₹${avgDaily.toStringAsFixed(0)} on average per day this month.',
          color: AppColors.primary,
        ),
        const SizedBox(height: 8),
        _buildInsightCard(
          icon: expenseChange > 0 ? Icons.trending_up : Icons.trending_down,
          title: 'Expense Trend',
          subtitle: expenseChange > 0 
              ? 'Your expenses are up by ${expenseChange.toStringAsFixed(1)}% compared to last month.'
              : 'Great job! Expenses are down by ${expenseChange.abs().toStringAsFixed(1)}% from last month.',
          color: expenseChange > 0 ? AppColors.expense : AppColors.income,
        ),
      ],
    );
  }

  Widget _buildInsightCard({required IconData icon, required String title, required String subtitle, required Color color}) {
    final colors = AppColors.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: colors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(color: colors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLineChart(List<dynamic> dailySpending) {
    if (dailySpending.isEmpty) return const SizedBox.shrink();
    final colors = AppColors.of(context);
    
    final spots = dailySpending.map((e) {
      final day = double.tryParse(e['day']?.toString() ?? '0') ?? 0;
      final amount = double.tryParse(e['amount']?.toString() ?? '0') ?? 0;
      return FlSpot(day, amount);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Daily Spending Trend', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: colors.textPrimary)),
        const SizedBox(height: 24),
        SizedBox(
          height: 180,
          child: LineChart(
            LineChartData(
              gridData: const FlGridData(show: false),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 22,
                    interval: 5,
                    getTitlesWidget: (value, meta) {
                      return Text(
                        value.toInt().toString(),
                        style: TextStyle(color: colors.textMuted, fontSize: 11),
                      );
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  color: AppColors.primary,
                  barWidth: 3,
                  isStrokeCapRound: true,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: AppColors.primary.withValues(alpha: 0.15),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPieChart(List<dynamic> breakdown, double totalExpense) {
    final colors = AppColors.of(context);
    final pieColors = [
      const Color(0xFF6C63FF), const Color(0xFF00D1FF), const Color(0xFFFF5252),
      const Color(0xFF00E676), const Color(0xFFFFAB40), const Color(0xFFE040FB),
      const Color(0xFF40C4FF), const Color(0xFFFF6E40), const Color(0xFF69F0AE),
      const Color(0xFFEA80FC),
    ];

    return Row(
      children: [
        Expanded(
          child: PieChart(
            PieChartData(
              sections: breakdown.asMap().entries.map((entry) {
                final cat = entry.value;
                final amount = double.tryParse(cat['total'].toString()) ?? 0;
                final percentage = totalExpense > 0 ? (amount / totalExpense * 100) : 0;
                return PieChartSectionData(
                  value: amount,
                  color: pieColors[entry.key % pieColors.length],
                  radius: 40,
                  title: '${percentage.toStringAsFixed(0)}%',
                  titleStyle: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                );
              }).toList(),
              sectionsSpace: 2,
              centerSpaceRadius: 36,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: breakdown.asMap().entries.take(5).map((entry) {
              final cat = entry.value;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Container(
                      width: 10, height: 10,
                      decoration: BoxDecoration(
                        color: pieColors[entry.key % pieColors.length],
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${cat['category__icon'] ?? '📦'} ${cat['category__name'] ?? 'Other'}',
                        style: TextStyle(color: colors.textSecondary, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '₹${_formatAmount(cat['total'])}',
                      style: TextStyle(color: colors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
