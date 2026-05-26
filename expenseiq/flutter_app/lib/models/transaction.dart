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
    };
  }

  bool get isIncome => type == 'income';
  bool get isExpense => type == 'expense';
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
