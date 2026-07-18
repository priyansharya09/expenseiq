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

  CategoryModel({required this.id, required this.name, required this.icon});

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    return CategoryModel(
      id: json['id'],
      name: json['name'] ?? '',
      icon: json['icon'] ?? '📦',
    );
  }

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
