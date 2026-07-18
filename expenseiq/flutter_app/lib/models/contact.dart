class ContactModel {
  final int id;
  final String name;
  final String phone;
  final double netBalance; // positive = they owe you
  final int unsettledCount;
  final DateTime? createdAt;

  ContactModel({
    required this.id,
    required this.name,
    this.phone = '',
    this.netBalance = 0,
    this.unsettledCount = 0,
    this.createdAt,
  });

  factory ContactModel.fromJson(Map<String, dynamic> json) {
    return ContactModel(
      id: json['id'],
      name: json['name'] ?? '',
      phone: json['phone'] ?? '',
      netBalance: (json['net_balance'] ?? 0).toDouble(),
      unsettledCount: json['unsettled_count'] ?? 0,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'phone': phone,
    };
  }

  /// Whether they owe you money
  bool get theyOweYou => netBalance > 0;

  /// Whether you owe them money
  bool get youOweThem => netBalance < 0;

  /// Whether all debts are settled
  bool get isSettled => netBalance == 0 && unsettledCount == 0;
}
