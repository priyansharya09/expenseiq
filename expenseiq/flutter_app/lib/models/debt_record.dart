class DebtRecordModel {
  final int id;
  final int contactId;
  final String contactName;
  final String contactPhone;
  final double amount;
  final String type; // 'lend' or 'borrow'
  final String description;
  final DateTime date;
  final bool isSettled;
  final DateTime? settledDate;
  final String note;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  DebtRecordModel({
    required this.id,
    required this.contactId,
    required this.contactName,
    this.contactPhone = '',
    required this.amount,
    required this.type,
    required this.description,
    required this.date,
    this.isSettled = false,
    this.settledDate,
    this.note = '',
    this.createdAt,
    this.updatedAt,
  });

  factory DebtRecordModel.fromJson(Map<String, dynamic> json) {
    return DebtRecordModel(
      id: json['id'],
      contactId: json['contact'] is int ? json['contact'] : json['contact_id'] ?? 0,
      contactName: json['contact_name'] ?? '',
      contactPhone: json['contact_phone'] ?? '',
      amount: (json['amount'] is String ? double.parse(json['amount']) : json['amount']).toDouble(),
      type: json['type'] ?? 'lend',
      description: json['description'] ?? '',
      date: DateTime.parse(json['date']),
      isSettled: json['is_settled'] ?? false,
      settledDate: json['settled_date'] != null ? DateTime.parse(json['settled_date']) : null,
      note: json['note'] ?? '',
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'contact': contactId,
      'amount': amount,
      'type': type,
      'description': description,
      'date': '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
      'note': note,
    };
  }

  bool get isLend => type == 'lend';
  bool get isBorrow => type == 'borrow';
}
