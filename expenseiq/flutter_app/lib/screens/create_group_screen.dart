import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:expenseiq/config/theme.dart';
import 'package:expenseiq/services/api_service.dart';

/// One editable member row (name + optional phone) in the create-group form.
class _MemberInput {
  final TextEditingController name = TextEditingController();
  final TextEditingController phone = TextEditingController();
  void dispose() {
    name.dispose();
    phone.dispose();
  }
}

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final List<_MemberInput> _members = [_MemberInput(), _MemberInput()];
  bool _isSaving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    for (final m in _members) {
      m.dispose();
    }
    super.dispose();
  }

  void _addMemberRow() => setState(() => _members.add(_MemberInput()));

  void _removeMemberRow(int i) {
    setState(() {
      _members[i].dispose();
      _members.removeAt(i);
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final members = <Map<String, String>>[];
    for (final m in _members) {
      final name = m.name.text.trim();
      if (name.isEmpty) continue; // skip blank rows
      members.add({'name': name, 'phone': m.phone.text.trim()});
    }

    if (members.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one member besides yourself.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ApiService().createGroup(_nameCtrl.text.trim(), members);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      String msg = 'Failed to create group';
      if (e is DioException && e.response?.data is Map) {
        final data = e.response!.data as Map;
        msg = data.values.first is List ? (data.values.first as List).join(' ') : data.values.first.toString();
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('New Group'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Group name',
                  hintText: 'e.g. Flat, Goa Trip',
                  prefixIcon: Icon(Icons.groups_outlined, color: AppColors.textMuted),
                ),
                validator: (v) => v == null || v.trim().isEmpty ? 'Group name is required' : null,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Text('Members',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: colors.textPrimary)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text("(you're added automatically)",
                        style: TextStyle(fontSize: 12, color: colors.textMuted)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...List.generate(_members.length, (i) => _buildMemberRow(i)),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _addMemberRow,
                  icon: const Icon(Icons.add, color: AppColors.primary, size: 20),
                  label: const Text('Add member', style: TextStyle(color: AppColors.primary)),
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: AppColors.primary, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Add a phone number to link a member to their ExpenseIQ account when they join.',
                        style: TextStyle(fontSize: 12, color: colors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 54,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _isSaving
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Create Group', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMemberRow(int i) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: TextFormField(
              controller: _members[i].name,
              decoration: const InputDecoration(labelText: 'Name', isDense: true),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 5,
            child: TextFormField(
              controller: _members[i].phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone', isDense: true),
            ),
          ),
          IconButton(
            onPressed: _members.length > 1 ? () => _removeMemberRow(i) : null,
            icon: Icon(Icons.remove_circle_outline,
                color: _members.length > 1 ? AppColors.expense : colors.textMuted),
            tooltip: 'Remove',
          ),
        ],
      ),
    );
  }
}
