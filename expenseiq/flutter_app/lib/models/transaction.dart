class TransactionModel {
  final int id;
  final String name;
  final double amount;
  final String type; // 'income' or 'expense'
  final int? categoryId;
  final String? categoryName;
  final String? categoryIcon;
  final String date;
  final String note;
  final String? createdAt;
  final String? updatedAt;
  final double sharedAmount;
  final String? paymentMode;
  final String? paymentApp;

  TransactionModel({
    required this.id,
    required this.name,
    required this.amount,
    required this.type,
    this.categoryId,
    this.categoryName,
    this.categoryIcon,
    required this.date,
    this.note = '',
    this.createdAt,
    this.updatedAt,
    this.sharedAmount = 0.0,
    this.paymentMode,
    this.paymentApp,
  });

  factory TransactionModel.fromJson(Map<String, dynamic> json) {
    return TransactionModel(
      id: json['id'],
      name: json['name'] ?? '',
      amount: double.tryParse(json['amount'].toString()) ?? 0.0,
      type: json['type'] ?? 'expense',
      categoryId: json['category'],
      categoryName: json['category_name'],
      categoryIcon: json['category_icon'],
      date: json['date'] ?? '',
      note: json['note'] ?? '',
      createdAt: json['created_at'],
      updatedAt: json['updated_at'],
      sharedAmount: double.tryParse(json['shared_amount']?.toString() ?? '0') ?? 0.0,
      paymentMode: json['payment_mode'],
      paymentApp: json['payment_app'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'amount': amount.toStringAsFixed(2),
      'type': type,
      'category': categoryId,
      'date': date,
      'note': note,
      if (sharedAmount > 0) 'shared_amount': sharedAmount.toStringAsFixed(2),
      if (paymentMode != null) 'payment_mode': paymentMode,
      if (paymentApp != null) 'payment_app': paymentApp,
    };
  }

  bool get isIncome => type == 'income';
  bool get isExpense => type == 'expense';
  bool get isShared => sharedAmount > 0;
  double get selfAmount => amount - sharedAmount;
}

class CategoryModel {
  final int id;
  final String name;
  final String icon;

  /// 'income', 'expense', or 'both'. Drives which categories are offered
  /// when the user is entering money in vs money out.
  final String kind;

  /// False for the shared system defaults, which cannot be edited or deleted.
  final bool isCustom;

  CategoryModel({
    required this.id,
    required this.name,
    required this.icon,
    this.kind = 'expense',
    this.isCustom = false,
  });

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    return CategoryModel(
      id: json['id'],
      name: json['name'] ?? '',
      icon: json['icon'] ?? '📦',
      kind: json['kind'] ?? 'expense',
      isCustom: json['is_custom'] ?? false,
    );
  }

  /// Whether this category should be offered for a transaction of [type].
  bool matches(String type) => kind == 'both' || kind == type;

  static const Map<String, String> defaultIcons = {
    'food': '🍔',
    'transport': '🚗',
    'shopping': '🛍',
    'health': '💊',
    'entertainment': '🎬',
    'salary': '💰',
    'freelance': '💼',
    'utilities': '💡',
    'education': '📚',
    'other': '📦',
  };
}

/// A monthly spending cap, either overall (categoryId == null) or per-category.
/// spent/remaining/pct are computed server-side against real transactions.
class BudgetModel {
  final int id;
  final int? categoryId;
  final String? categoryName;
  final String? categoryIcon;
  final double amount;
  final int month;
  final int year;
  final double spent;
  final double remaining;
  final double pct;

  BudgetModel({
    required this.id,
    this.categoryId,
    this.categoryName,
    this.categoryIcon,
    required this.amount,
    required this.month,
    required this.year,
    this.spent = 0,
    this.remaining = 0,
    this.pct = 0,
  });

  factory BudgetModel.fromJson(Map<String, dynamic> json) {
    double d(dynamic v) => double.tryParse(v?.toString() ?? '0') ?? 0;
    return BudgetModel(
      id: json['id'],
      categoryId: json['category'],
      categoryName: json['category_name'],
      categoryIcon: json['category_icon'],
      amount: d(json['amount']),
      month: json['month'] ?? 1,
      year: json['year'] ?? 0,
      spent: d(json['spent']),
      remaining: d(json['remaining']),
      pct: d(json['pct']),
    );
  }

  bool get isOverall => categoryId == null;
  bool get isExceeded => pct > 100;
  bool get isNearLimit => pct >= 80 && pct <= 100;
  String get label => isOverall ? 'Overall Budget' : '${categoryIcon ?? '📦'} $categoryName';
}

/// A rule that posts a real transaction on a schedule.
class RecurringModel {
  final int id;
  final String name;
  final double amount;
  final String type;
  final int? categoryId;
  final String? categoryName;
  final String? categoryIcon;
  final String? paymentMode;
  final String frequency; // 'weekly' or 'monthly'
  final String nextRun;
  final bool active;
  final String note;

  RecurringModel({
    required this.id,
    required this.name,
    required this.amount,
    required this.type,
    this.categoryId,
    this.categoryName,
    this.categoryIcon,
    this.paymentMode,
    this.frequency = 'monthly',
    required this.nextRun,
    this.active = true,
    this.note = '',
  });

  factory RecurringModel.fromJson(Map<String, dynamic> json) {
    return RecurringModel(
      id: json['id'],
      name: json['name'] ?? '',
      amount: double.tryParse(json['amount']?.toString() ?? '0') ?? 0,
      type: json['type'] ?? 'expense',
      categoryId: json['category'],
      categoryName: json['category_name'],
      categoryIcon: json['category_icon'],
      paymentMode: json['payment_mode'],
      frequency: json['frequency'] ?? 'monthly',
      nextRun: json['next_run'] ?? '',
      active: json['active'] ?? true,
      note: json['note'] ?? '',
    );
  }

  bool get isIncome => type == 'income';
  DateTime? get nextRunDate => DateTime.tryParse(nextRun);
}
