import 'package:flutter/material.dart';
import 'package:expenseiq/config/theme.dart';

/// A bottom-sheet calculator for entering an amount.
///
/// Handy for the common case of "split this bill 3 ways" or "120 + 45 + 30"
/// without leaving the add-transaction form. Returns the computed value, or
/// null if the user dismissed it.
Future<double?> showCalculatorSheet(BuildContext context, {double? initial}) {
  return showModalBottomSheet<double>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => CalculatorSheet(initial: initial),
  );
}

class CalculatorSheet extends StatefulWidget {
  final double? initial;
  const CalculatorSheet({super.key, this.initial});

  @override
  State<CalculatorSheet> createState() => _CalculatorSheetState();
}

class _CalculatorSheetState extends State<CalculatorSheet> {
  String _expr = '';

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    if (init != null && init > 0) {
      _expr = init == init.roundToDouble()
          ? init.toStringAsFixed(0)
          : init.toString();
    }
  }

  /// Live preview of the expression's value, or null when it isn't yet valid
  /// (e.g. the user just typed an operator).
  double? get _preview => _CalcEngine.evaluate(_expr);

  void _tap(String key) {
    setState(() {
      switch (key) {
        case 'C':
          _expr = '';
        case '⌫':
          if (_expr.isNotEmpty) _expr = _expr.substring(0, _expr.length - 1);
        default:
          // Typing an operator right after another replaces it, so "5 + ×"
          // becomes "5 ×" instead of an unparseable string.
          const ops = {'+', '-', '×', '÷', '%'};
          if (ops.contains(key) && _expr.isNotEmpty && ops.contains(_expr[_expr.length - 1])) {
            _expr = _expr.substring(0, _expr.length - 1) + key;
          } else if (ops.contains(key) && _expr.isEmpty) {
            // Leading operator is meaningless — ignore, except unary minus.
            if (key == '-') _expr = key;
          } else {
            _expr += key;
          }
      }
    });
  }

  void _submit() {
    final value = _preview;
    if (value != null && value > 0) {
      Navigator.pop(context, double.parse(value.toStringAsFixed(2)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final preview = _preview;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: colors.textMuted,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),

              // Expression + live result
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _expr.isEmpty ? '0' : _expr,
                      style: TextStyle(
                        fontSize: 22,
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      preview == null ? '—' : '₹ ${_fmt(preview)}',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        color: preview == null ? colors.textMuted : AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Keypad
              for (final row in const [
                ['C', '⌫', '%', '÷'],
                ['7', '8', '9', '×'],
                ['4', '5', '6', '-'],
                ['1', '2', '3', '+'],
                ['00', '0', '.', '='],
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      for (final key in row) ...[
                        Expanded(child: _key(key)),
                        if (key != row.last) const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  Widget _key(String label) {
    final colors = AppColors.of(context);
    const operators = {'+', '-', '×', '÷', '%'};
    final isEquals = label == '=';
    final isOperator = operators.contains(label);
    final isClear = label == 'C' || label == '⌫';

    final Color bg;
    final Color fg;
    if (isEquals) {
      bg = AppColors.primary;
      fg = Colors.white;
    } else if (isOperator) {
      bg = AppColors.primary.withValues(alpha: 0.12);
      fg = AppColors.primary;
    } else if (isClear) {
      bg = AppColors.expense.withValues(alpha: 0.12);
      fg = AppColors.expense;
    } else {
      bg = colors.card;
      fg = colors.textPrimary;
    }

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => isEquals ? _submit() : _tap(label),
        child: SizedBox(
          height: 54,
          child: Center(
            child: Text(
              label,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: fg),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small shunting-yard evaluator for the flat arithmetic the keypad can
/// produce: numbers, + - × ÷ and a trailing % (read as "percent of the
/// preceding value", so `500-10%` is 450).
class _CalcEngine {
  static double? evaluate(String input) {
    if (input.trim().isEmpty) return null;

    final tokens = _tokenize(input);
    if (tokens == null || tokens.isEmpty) return null;

    // Expression must end on a number, otherwise it's still being typed.
    if (tokens.last is! double) return null;

    const precedence = {'+': 1, '-': 1, '×': 2, '÷': 2};
    final values = <double>[];
    final ops = <String>[];

    void apply() {
      if (values.length < 2 || ops.isEmpty) return;
      final b = values.removeLast();
      final a = values.removeLast();
      final op = ops.removeLast();
      switch (op) {
        case '+':
          values.add(a + b);
        case '-':
          values.add(a - b);
        case '×':
          values.add(a * b);
        case '÷':
          values.add(b == 0 ? double.nan : a / b);
      }
    }

    for (final t in tokens) {
      if (t is double) {
        values.add(t);
      } else {
        final op = t as String;
        while (ops.isNotEmpty && precedence[ops.last]! >= precedence[op]!) {
          apply();
        }
        ops.add(op);
      }
    }
    while (ops.isNotEmpty) {
      apply();
    }

    if (values.length != 1) return null;
    final result = values.first;
    return result.isFinite ? result : null;
  }

  /// Splits into a flat list of doubles and operator strings, or null if the
  /// input contains something unparseable.
  static List<Object>? _tokenize(String input) {
    final tokens = <Object>[];
    final buffer = StringBuffer();
    const operators = {'+', '-', '×', '÷'};

    void flush() {
      if (buffer.isEmpty) return;
      final n = double.tryParse(buffer.toString());
      if (n != null) tokens.add(n);
      buffer.clear();
    }

    for (var i = 0; i < input.length; i++) {
      final ch = input[i];
      if (ch == '%') {
        flush();
        // Percent binds to the pending +/- operand: 500-10% → 500 - (500*0.10).
        if (tokens.isNotEmpty && tokens.last is double) {
          final pct = tokens.removeLast() as double;
          if (tokens.length >= 2 &&
              tokens[tokens.length - 1] is String &&
              tokens[tokens.length - 2] is double &&
              (tokens[tokens.length - 1] == '+' || tokens[tokens.length - 1] == '-')) {
            final base = tokens[tokens.length - 2] as double;
            tokens.add(base * pct / 100);
          } else {
            tokens.add(pct / 100);
          }
        }
      } else if (operators.contains(ch)) {
        // A '-' at the very start is a sign, not a binary operator.
        if (buffer.isEmpty && tokens.isEmpty && ch == '-') {
          buffer.write(ch);
          continue;
        }
        flush();
        if (tokens.isEmpty || tokens.last is String) return null;
        tokens.add(ch);
      } else if (RegExp(r'[0-9.]').hasMatch(ch)) {
        buffer.write(ch);
      } else {
        return null;
      }
    }
    flush();
    return tokens;
  }
}
