import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:expenseiq/config/theme.dart';
import 'package:expenseiq/services/api_service.dart';
import 'package:expenseiq/models/contact.dart';
import 'package:intl/intl.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as fc;

class AddDebtScreen extends StatefulWidget {
  final int? preselectedContactId;
  const AddDebtScreen({super.key, this.preselectedContactId});

  @override
  State<AddDebtScreen> createState() => _AddDebtScreenState();
}

class _AddDebtScreenState extends State<AddDebtScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  
  String _type = 'lend'; // lend = they owe me, borrow = I owe them
  DateTime _date = DateTime.now();
  int? _contactId;
  List<ContactModel> _contacts = [];
  bool _isLoading = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _contactId = widget.preselectedContactId;
    _loadContacts();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiService().getContacts();
      if (mounted) {
        setState(() {
          _contacts = (response.data['results'] as List).map((e) => ContactModel.fromJson(e)).toList();
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _pickContactFromPhone() async {
    try {
      final granted = await fc.FlutterContacts.requestPermission(readonly: true);
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Contacts permission denied. Add the contact manually instead.')),
          );
        }
        return;
      }
      final contact = await fc.FlutterContacts.openExternalPick();
      if (contact == null) return;
      final name = contact.displayName;
      final phone = contact.phones.isNotEmpty ? contact.phones.first.number : '';
      await _createAndSelectContact(name, phone);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open phone contacts. Add the contact manually instead.')),
        );
      }
    }
  }

  /// Manual contact entry — the reliable path that does not depend on the
  /// phone's contacts permission or picker being available.
  Future<void> _addManualContact() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('New Contact', style: TextStyle(color: AppColors.textPrimary)),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name', prefixIcon: Icon(Icons.person_outline, color: AppColors.textMuted)),
                validator: (v) => v == null || v.trim().isEmpty ? 'Name required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone (optional)', prefixIcon: Icon(Icons.phone_outlined, color: AppColors.textMuted)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(ctx, true);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (saved == true) {
      await _createAndSelectContact(nameCtrl.text.trim(), phoneCtrl.text.trim());
    }
  }

  Future<void> _createAndSelectContact(String name, String phone) async {
    setState(() => _isSaving = true);
    try {
      final response = await ApiService().createContact({'name': name, 'phone': phone});
      final newContact = ContactModel.fromJson(response.data);
      setState(() {
        _contacts.add(newContact);
        _contactId = newContact.id;
      });
    } catch (e) {
      if (mounted) {
        String msg = 'Failed to add contact';
        if (e is DioException && e.response?.data is Map) {
          final data = e.response!.data as Map;
          if (data['name'] is List) msg = (data['name'] as List).join(' ');
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_contactId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a contact')));
      return;
    }
    
    setState(() => _isSaving = true);
    try {
      final data = {
        'contact': _contactId,
        'amount': _amountCtrl.text.trim(),
        'type': _type,
        'description': _descCtrl.text.trim(),
        'date': DateFormat('yyyy-MM-dd').format(_date),
        'note': _noteCtrl.text.trim(),
      };
      
      await ApiService().createDebt(data);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save record')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: AppColors.primary, surface: AppColors.surface),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Add Split/Debt'),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_rounded, size: 20), onPressed: () => Navigator.pop(context)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Type selector
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border, width: 0.5),
                      ),
                      child: Row(
                        children: [
                          _buildTypeButton('I Lent', 'lend', Icons.arrow_upward, AppColors.primary),
                          const SizedBox(width: 4),
                          _buildTypeButton('I Borrowed', 'borrow', Icons.arrow_downward, AppColors.secondary),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Amount
                    TextFormField(
                      controller: _amountCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        hintText: '0',
                        hintStyle: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: AppColors.textMuted.withValues(alpha: 0.3)),
                        prefixText: '₹ ',
                        prefixStyle: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: AppColors.textMuted.withValues(alpha: 0.5)),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: true,
                        fillColor: AppColors.card,
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Required';
                        final n = double.tryParse(v);
                        if (n == null || n <= 0) return 'Invalid amount';
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    
                    // Contact
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: _contactId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Contact',
                              prefixIcon: Icon(Icons.person_outline, color: AppColors.textMuted),
                            ),
                            dropdownColor: AppColors.surface,
                            items: _contacts
                                .map((c) => DropdownMenuItem(
                                      value: c.id,
                                      child: Text(c.name, overflow: TextOverflow.ellipsis),
                                    ))
                                .toList(),
                            onChanged: (v) => setState(() => _contactId = v),
                            validator: (v) => v == null ? 'Required' : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: _isSaving ? null : _addManualContact,
                          icon: const Icon(Icons.person_add_alt_1, color: AppColors.primary),
                          tooltip: 'Add new contact',
                        ),
                        IconButton(
                          onPressed: _isSaving ? null : _pickContactFromPhone,
                          icon: const Icon(Icons.contact_phone, color: AppColors.secondary),
                          tooltip: 'Pick from phone',
                        ),
                      ],
                    ),
                    if (_contacts.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'No contacts yet — tap the person-add icon to create one.',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                        ),
                      ),
                    const SizedBox(height: 16),
                    
                    // Description
                    TextFormField(
                      controller: _descCtrl,
                      decoration: const InputDecoration(
                        labelText: 'For what?',
                        prefixIcon: Icon(Icons.edit_outlined, color: AppColors.textMuted),
                      ),
                      validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    
                    // Date
                    GestureDetector(
                      onTap: _pickDate,
                      child: AbsorbPointer(
                        child: TextFormField(
                          decoration: InputDecoration(
                            labelText: 'Date',
                            prefixIcon: const Icon(Icons.calendar_today_outlined, color: AppColors.textMuted),
                          ),
                          controller: TextEditingController(text: DateFormat('dd MMM yyyy').format(_date)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Note
                    TextFormField(
                      controller: _noteCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Note (optional)',
                        prefixIcon: Icon(Icons.notes_outlined, color: AppColors.textMuted),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 32),
                    
                    // Save
                    SizedBox(
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _type == 'lend' ? AppColors.primary : AppColors.secondary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: _isSaving
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Save Record', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildTypeButton(String label, String type, IconData icon, Color color) {
    final isSelected = _type == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _type = type),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: isSelected ? Border.all(color: color.withValues(alpha: 0.4)) : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: isSelected ? color : AppColors.textMuted, size: 20),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(
                color: isSelected ? color : AppColors.textMuted,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              )),
            ],
          ),
        ),
      ),
    );
  }
}
