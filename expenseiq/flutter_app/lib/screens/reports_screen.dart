import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import 'package:expenseiq/config/theme.dart';
import 'package:expenseiq/services/api_service.dart';

/// Which slice of time the report covers. The backend supports either a
/// month+year pair or an explicit start/end range, so the UI mirrors that.
enum ReportRange { thisMonth, lastMonth, thisYear, last3Months, custom }

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  ReportRange _range = ReportRange.thisMonth;
  DateTime _anchor = DateTime.now(); // month/year being viewed
  DateTimeRange? _customRange;

  Map<String, dynamic>? _summary;
  bool _isLoading = true;
  String? _error;

  final _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Resolves the current selection into the parameters the summary
  /// endpoint expects, then fetches.
  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final Map<String, dynamic> data;
      switch (_range) {
        case ReportRange.thisMonth:
        case ReportRange.lastMonth:
          data = await ApiService().getSummary(month: _anchor.month, year: _anchor.year);
        case ReportRange.thisYear:
          data = await ApiService().getSummary(
            startDate: DateTime(_anchor.year, 1, 1),
            endDate: DateTime(_anchor.year, 12, 31),
          );
        case ReportRange.last3Months:
          final end = DateTime.now();
          final start = DateTime(end.year, end.month - 2, 1);
          data = await ApiService().getSummary(startDate: start, endDate: end);
        case ReportRange.custom:
          final r = _customRange!;
          data = await ApiService().getSummary(startDate: r.start, endDate: r.end);
      }
      if (mounted) setState(() { _summary = data; _isLoading = false; });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load report. Check your connection.';
          _isLoading = false;
        });
      }
    }
  }

  void _selectRange(ReportRange range) async {
    if (range == ReportRange.custom) {
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime.now(),
        initialDateRange: _customRange ??
            DateTimeRange(
              start: DateTime.now().subtract(const Duration(days: 30)),
              end: DateTime.now(),
            ),
        builder: (context, child) => Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(primary: AppColors.primary),
          ),
          child: child!,
        ),
      );
      if (picked == null) return;
      setState(() { _customRange = picked; _range = range; });
    } else {
      setState(() {
        _range = range;
        _anchor = switch (range) {
          ReportRange.lastMonth => DateTime(DateTime.now().year, DateTime.now().month - 1),
          _ => DateTime.now(),
        };
      });
    }
    _load();
  }

  /// Steps the anchor month back/forward. Only meaningful in month mode.
  void _shiftMonth(int delta) {
    setState(() {
      _anchor = DateTime(_anchor.year, _anchor.month + delta);
      _range = ReportRange.thisMonth;
    });
    _load();
  }

  bool get _isMonthMode =>
      _range == ReportRange.thisMonth || _range == ReportRange.lastMonth;

  Future<void> _exportCsv() async {
    try {
      final csv = await ApiService().exportTransactionsCsv(
        month: _isMonthMode ? _anchor.month : null,
        year: _isMonthMode ? _anchor.year : null,
      );
      final label = (_summary?['period']?['label'] ?? 'report').toString();
      await Share.share(csv, subject: 'ExpenseIQ – $label');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Export failed')),
        );
      }
    }
  }

  double _num(dynamic v) => double.tryParse(v?.toString() ?? '0') ?? 0;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('Reports'),
        actions: [
          IconButton(
            tooltip: 'Export CSV',
            onPressed: _summary == null ? null : _exportCsv,
            icon: const Icon(Icons.ios_share_rounded, size: 20),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.primary,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _buildRangeSelector(),
            const SizedBox(height: 12),
            _buildPeriodHeader(),
            const SizedBox(height: 16),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 80),
                child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
              )
            else if (_error != null)
              _buildError()
            else if (_summary != null) ...[
              _buildTotals(),
              const SizedBox(height: 16),
              _buildInsights(),
              const SizedBox(height: 16),
              _buildTrendChart(),
              const SizedBox(height: 16),
              _buildCategoryBreakdown('Expenses by Category', 'category_breakdown', AppColors.expense),
              const SizedBox(height: 16),
              _buildCategoryBreakdown('Income by Category', 'income_category_breakdown', AppColors.income),
              const SizedBox(height: 16),
              _buildPaymentModes(),
            ],
          ],
        ),
      ),
    );
  }

  // ─── Range selector chips ───────────────────────────────────────

  Widget _buildRangeSelector() {
    const labels = {
      ReportRange.thisMonth: 'This Month',
      ReportRange.lastMonth: 'Last Month',
      ReportRange.last3Months: 'Last 3 Months',
      ReportRange.thisYear: 'This Year',
      ReportRange.custom: 'Custom',
    };

    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final entry in labels.entries) ...[
            _chip(
              entry.value,
              selected: _range == entry.key,
              icon: entry.key == ReportRange.custom ? Icons.date_range_rounded : null,
              onTap: () => _selectRange(entry.key),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _chip(String label, {required bool selected, IconData? icon, required VoidCallback onTap}) {
    final colors = AppColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : colors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.primary : colors.border,
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: selected ? Colors.white : colors.textSecondary),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : colors.textSecondary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Shows exactly which dates the numbers below come from — with month
  /// arrows when a single month is in view.
  Widget _buildPeriodHeader() {
    final colors = AppColors.of(context);
    final period = _summary?['period'] as Map<String, dynamic>?;
    final label = period?['label']?.toString() ??
        DateFormat('MMMM yyyy').format(_anchor);
    final start = period?['start_date'];
    final end = period?['end_date'];

    String? sub;
    if (start != null && end != null) {
      final s = DateTime.tryParse(start.toString());
      final e = DateTime.tryParse(end.toString());
      if (s != null && e != null) {
        final f = DateFormat('dd MMM yyyy');
        sub = '${f.format(s)}  →  ${f.format(e)}';
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border, width: 0.5),
      ),
      child: Row(
        children: [
          if (_isMonthMode)
            IconButton(
              onPressed: () => _shiftMonth(-1),
              icon: Icon(Icons.chevron_left_rounded, color: colors.textSecondary),
            ),
          Expanded(
            child: Column(
              children: [
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                if (sub != null) ...[
                  const SizedBox(height: 2),
                  Text(sub, style: TextStyle(color: colors.textMuted, fontSize: 11)),
                ],
              ],
            ),
          ),
          if (_isMonthMode)
            IconButton(
              // Don't let the user page into the future.
              onPressed: DateTime(_anchor.year, _anchor.month).isBefore(
                      DateTime(DateTime.now().year, DateTime.now().month))
                  ? () => _shiftMonth(1)
                  : null,
              icon: Icon(Icons.chevron_right_rounded, color: colors.textSecondary),
            ),
        ],
      ),
    );
  }

  Widget _buildError() {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: [
          Icon(Icons.cloud_off_rounded, size: 44, color: colors.textMuted),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: colors.textSecondary)),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: _load, child: const Text('Retry')),
        ],
      ),
    );
  }

  // ─── Totals ─────────────────────────────────────────────────────

  Widget _buildTotals() {
    final income = _num(_summary!['total_income']);
    final expense = _num(_summary!['total_expense']);
    final balance = _num(_summary!['balance']);
    final count = _summary!['transaction_count'] ?? 0;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: balance >= 0 ? AppColors.balanceGradient : AppColors.expenseGradient,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              Text(
                balance >= 0 ? 'Net Savings' : 'Net Deficit',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 6),
              Text(
                _inr.format(balance.abs()),
                style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                '$count transaction${count == 1 ? '' : 's'}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _statCard('Income', income, AppColors.income, Icons.trending_up_rounded)),
            const SizedBox(width: 12),
            Expanded(child: _statCard('Expense', expense, AppColors.expense, Icons.trending_down_rounded)),
          ],
        ),
      ],
    );
  }

  Widget _statCard(String label, double value, Color color, IconData icon) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: colors.textMuted, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _inr.format(value),
              style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Insights ───────────────────────────────────────────────────

  /// Derived numbers that aren't obvious from the totals alone: burn rate,
  /// savings rate, month-over-month movement, and how much of the spend was
  /// actually on behalf of other people.
  Widget _buildInsights() {
    final colors = AppColors.of(context);
    final income = _num(_summary!['total_income']);
    final expense = _num(_summary!['total_expense']);
    final avgDaily = _num(_summary!['avg_daily_expense']);
    final shared = _num(_summary!['total_shared']);
    final comparison = _summary!['comparison'] as Map<String, dynamic>? ?? {};
    final expenseChange = _num(comparison['expense_change_pct']);

    final savingsRate = income > 0 ? ((income - expense) / income * 100) : 0.0;

    final tiles = <Widget>[
      _insightTile(Icons.local_fire_department_rounded, 'Avg / day',
          _inr.format(avgDaily), AppColors.expense),
      _insightTile(Icons.savings_rounded, 'Savings rate',
          '${savingsRate.toStringAsFixed(0)}%',
          savingsRate >= 20 ? AppColors.income : AppColors.expense),
      if (_isMonthMode)
        _insightTile(
          expenseChange >= 0 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
          'vs last month',
          '${expenseChange >= 0 ? '+' : ''}${expenseChange.toStringAsFixed(0)}%',
          expenseChange > 0 ? AppColors.expense : AppColors.income,
        ),
      if (shared > 0)
        _insightTile(Icons.people_rounded, 'Paid for others',
            _inr.format(shared), AppColors.secondary),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Insights',
              style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 14),
          Wrap(spacing: 12, runSpacing: 14, children: tiles),
        ],
      ),
    );
  }

  Widget _insightTile(IconData icon, String label, String value, Color color) {
    final colors = AppColors.of(context);
    return SizedBox(
      width: (MediaQuery.of(context).size.width - 32 - 32 - 12) / 2,
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: colors.textMuted, fontSize: 11)),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value,
                      style: TextStyle(
                          color: colors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Spending trend ─────────────────────────────────────────────

  /// The backend returns day-of-month buckets for a single month and full
  /// dates for a custom range, so handle both shapes.
  Widget _buildTrendChart() {
    final colors = AppColors.of(context);
    final raw = (_summary!['daily_spending'] as List?) ?? [];
    if (raw.isEmpty) return _emptyCard('Spending Trend', 'No spending in this period');

    final points = <FlSpot>[];
    final labels = <int, String>{};
    for (var i = 0; i < raw.length; i++) {
      final row = raw[i] as Map<String, dynamic>;
      final amount = _num(row['amount']);
      points.add(FlSpot(i.toDouble(), amount));
      if (row.containsKey('day')) {
        labels[i] = row['day'].toString();
      } else {
        final d = DateTime.tryParse(row['date']?.toString() ?? '');
        labels[i] = d != null ? DateFormat('d MMM').format(d) : '';
      }
    }

    final maxY = points.map((p) => p.y).reduce((a, b) => a > b ? a : b);
    // Show at most ~6 x-axis labels regardless of how many points there are.
    final labelStep = (points.length / 6).ceil().clamp(1, points.length);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Spending Trend',
              style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 20),
          SizedBox(
            height: 170,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: maxY * 1.2,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) =>
                      FlLine(color: colors.border.withValues(alpha: 0.4), strokeWidth: 0.5),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 44,
                      getTitlesWidget: (value, meta) {
                        if (value == meta.max) return const SizedBox.shrink();
                        return Text(
                          _compact(value),
                          style: TextStyle(color: colors.textMuted, fontSize: 10),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 26,
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        if (i % labelStep != 0 || !labels.containsKey(i)) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(labels[i]!,
                              style: TextStyle(color: colors.textMuted, fontSize: 9)),
                        );
                      },
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (spots) => spots
                        .map((s) => LineTooltipItem(
                              '${labels[s.x.toInt()] ?? ''}\n${_inr.format(s.y)}',
                              const TextStyle(color: Colors.white, fontSize: 11),
                            ))
                        .toList(),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: points,
                    isCurved: true,
                    curveSmoothness: 0.3,
                    gradient: AppColors.primaryGradient,
                    barWidth: 2.5,
                    dotData: FlDotData(show: points.length <= 20),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppColors.primary.withValues(alpha: 0.25),
                          AppColors.primary.withValues(alpha: 0.0),
                        ],
                      ),
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

  static String _compact(double v) {
    if (v >= 10000000) return '${(v / 10000000).toStringAsFixed(1)}Cr';
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}k';
    return v.toStringAsFixed(0);
  }

  // ─── Category breakdown ─────────────────────────────────────────

  Widget _buildCategoryBreakdown(String title, String key, Color accent) {
    final colors = AppColors.of(context);
    final rows = ((_summary![key] as List?) ?? [])
        .cast<Map<String, dynamic>>()
        .where((r) => _num(r['total']) > 0)
        .toList();

    if (rows.isEmpty) return _emptyCard(title, 'Nothing recorded yet');

    final total = rows.fold<double>(0, (sum, r) => sum + _num(r['total']));
    final palette = _palette(rows.length, accent);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 16),
          SizedBox(
            height: 150,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 42,
                sections: [
                  for (var i = 0; i < rows.length; i++)
                    PieChartSectionData(
                      value: _num(rows[i]['total']),
                      color: palette[i],
                      radius: 26,
                      showTitle: false,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < rows.length; i++) ...[
            _categoryRow(rows[i], total, palette[i]),
            if (i != rows.length - 1) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _categoryRow(Map<String, dynamic> row, double total, Color color) {
    final colors = AppColors.of(context);
    final amount = _num(row['total']);
    final pct = total > 0 ? amount / total * 100 : 0.0;
    final name = row['category__name']?.toString() ?? 'Uncategorized';
    final icon = row['category__icon']?.toString() ?? '📦';

    return Column(
      children: [
        Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 15)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(name,
                  style: TextStyle(color: colors.textPrimary, fontSize: 13),
                  overflow: TextOverflow.ellipsis),
            ),
            Text('${pct.toStringAsFixed(0)}%',
                style: TextStyle(color: colors.textMuted, fontSize: 11)),
            const SizedBox(width: 10),
            Text(_inr.format(amount),
                style: TextStyle(
                    color: colors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: (pct / 100).clamp(0.0, 1.0),
            minHeight: 5,
            backgroundColor: colors.border.withValues(alpha: 0.4),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }

  /// Spreads hues around [base] so adjacent slices stay distinguishable.
  List<Color> _palette(int n, Color base) {
    final hsl = HSLColor.fromColor(base);
    return List.generate(n, (i) {
      final hue = (hsl.hue + i * (300 / (n == 1 ? 1 : n))) % 360;
      return hsl
          .withHue(hue)
          .withSaturation((hsl.saturation * 0.9).clamp(0.35, 0.95))
          .withLightness((0.52 + (i.isEven ? 0.06 : -0.04)).clamp(0.35, 0.72))
          .toColor();
    });
  }

  // ─── Payment modes ──────────────────────────────────────────────

  Widget _buildPaymentModes() {
    final colors = AppColors.of(context);
    final rows = ((_summary!['payment_mode_breakdown'] as List?) ?? [])
        .cast<Map<String, dynamic>>();
    if (rows.isEmpty) return _emptyCard('Payment Methods', 'No payment methods recorded');

    const names = {
      'cash': '💵 Cash',
      'upi': '📱 UPI',
      'neft': '🏦 NEFT/IMPS',
      'card_debit': '💳 Debit Card',
      'card_credit': '💳 Credit Card',
      'wallet': '👛 Wallet',
      'cheque': '📝 Cheque',
      'other': '📦 Other',
    };
    final total = rows.fold<double>(0, (s, r) => s + _num(r['total']));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Payment Methods',
              style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 14),
          for (final row in rows) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      names[row['payment_mode']] ?? row['payment_mode'].toString(),
                      style: TextStyle(color: colors.textSecondary, fontSize: 13),
                    ),
                  ),
                  Text(
                    '${(total > 0 ? _num(row['total']) / total * 100 : 0).toStringAsFixed(0)}%',
                    style: TextStyle(color: colors.textMuted, fontSize: 11),
                  ),
                  const SizedBox(width: 10),
                  Text(_inr.format(_num(row['total'])),
                      style: TextStyle(
                          color: colors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _emptyCard(String title, String message) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 12),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(message, style: TextStyle(color: colors.textMuted, fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }
}
