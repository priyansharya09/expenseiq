// Models for the group-split feature (SplitGroup, members, expenses, shares).

class GroupMemberModel {
  final int id;
  final String name;
  final String phone;
  final bool isOwner;
  final bool isAppUser;

  GroupMemberModel({
    required this.id,
    required this.name,
    this.phone = '',
    this.isOwner = false,
    this.isAppUser = false,
  });

  factory GroupMemberModel.fromJson(Map<String, dynamic> json) {
    return GroupMemberModel(
      id: json['id'],
      name: json['name'] ?? '',
      phone: json['phone'] ?? '',
      isOwner: json['is_owner'] ?? false,
      isAppUser: json['is_app_user'] ?? false,
    );
  }
}

/// Net position of one member within a group: positive = others owe them.
class MemberBalance {
  final int memberId;
  final String name;
  final bool isOwner;
  final double net;

  MemberBalance({
    required this.memberId,
    required this.name,
    this.isOwner = false,
    this.net = 0,
  });

  factory MemberBalance.fromJson(Map<String, dynamic> json) {
    return MemberBalance(
      memberId: json['member'],
      name: json['name'] ?? '',
      isOwner: json['is_owner'] ?? false,
      net: (json['net'] ?? 0).toDouble(),
    );
  }
}

class SplitGroupModel {
  final int id;
  final String name;
  final List<GroupMemberModel> members;
  final List<MemberBalance> balances;
  final int expenseCount;
  final double totalSpent;
  final DateTime? createdAt;

  SplitGroupModel({
    required this.id,
    required this.name,
    this.members = const [],
    this.balances = const [],
    this.expenseCount = 0,
    this.totalSpent = 0,
    this.createdAt,
  });

  factory SplitGroupModel.fromJson(Map<String, dynamic> json) {
    return SplitGroupModel(
      id: json['id'],
      name: json['name'] ?? '',
      members: ((json['members'] ?? []) as List)
          .map((e) => GroupMemberModel.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      balances: ((json['balances'] ?? []) as List)
          .map((e) => MemberBalance.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      expenseCount: json['expense_count'] ?? 0,
      totalSpent: (json['total_spent'] ?? 0).toDouble(),
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at']) : null,
    );
  }
}

class ExpenseShareModel {
  final int? id;
  final int memberId;
  final String memberName;
  final double amount;

  ExpenseShareModel({
    this.id,
    required this.memberId,
    this.memberName = '',
    required this.amount,
  });

  factory ExpenseShareModel.fromJson(Map<String, dynamic> json) {
    return ExpenseShareModel(
      id: json['id'],
      memberId: json['member'],
      memberName: json['member_name'] ?? '',
      amount: (json['amount'] ?? 0).toDouble(),
    );
  }
}

class GroupExpenseModel {
  final int id;
  final String name;
  final double amount;
  final int paidById;
  final String paidByName;
  final String? categoryName;
  final String? categoryIcon;
  final DateTime date;
  final String note;
  final List<ExpenseShareModel> shares;

  GroupExpenseModel({
    required this.id,
    required this.name,
    required this.amount,
    required this.paidById,
    this.paidByName = '',
    this.categoryName,
    this.categoryIcon,
    required this.date,
    this.note = '',
    this.shares = const [],
  });

  factory GroupExpenseModel.fromJson(Map<String, dynamic> json) {
    return GroupExpenseModel(
      id: json['id'],
      name: json['name'] ?? '',
      amount: (json['amount'] ?? 0).toDouble(),
      paidById: json['paid_by'],
      paidByName: json['paid_by_name'] ?? '',
      categoryName: json['category_name'],
      categoryIcon: json['category_icon'],
      date: DateTime.tryParse(json['date'] ?? '') ?? DateTime.now(),
      note: json['note'] ?? '',
      shares: ((json['shares'] ?? []) as List)
          .map((e) => ExpenseShareModel.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}
