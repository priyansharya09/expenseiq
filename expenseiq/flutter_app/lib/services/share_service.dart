import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';

class ShareService {
  /// Share a debt reminder via WhatsApp
  static Future<bool> shareViaWhatsApp(String phone, String message) async {
    // Clean phone number
    String cleanPhone = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (!cleanPhone.startsWith('+')) {
      cleanPhone = '+91$cleanPhone'; // Default to India
    }

    final uri = Uri.parse('https://wa.me/${cleanPhone.replaceAll('+', '')}?text=${Uri.encodeComponent(message)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return true;
    }
    return false;
  }

  /// Share via SMS
  static Future<bool> shareViaSMS(String phone, String message) async {
    final uri = Uri.parse('sms:$phone?body=${Uri.encodeComponent(message)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      return true;
    }
    return false;
  }

  /// Share via system share sheet
  static Future<void> shareGeneral(String message) async {
    await Share.share(message);
  }

  /// Generate a formatted debt reminder message
  static String generateDebtReminder({
    required String contactName,
    required double totalAmount,
    required List<Map<String, dynamic>> pendingItems,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('💰 ExpenseIQ Reminder');
    buffer.writeln();
    buffer.writeln('Hey $contactName! Here\'s a summary of our expenses:');
    buffer.writeln();

    if (pendingItems.isNotEmpty) {
      buffer.writeln('📋 Pending Items:');
      for (final item in pendingItems) {
        buffer.writeln('• ${item['description']} — ₹${item['amount']} (${item['date']})');
      }
      buffer.writeln();
    }

    if (totalAmount > 0) {
      buffer.writeln('💵 Total Due: ₹${totalAmount.toStringAsFixed(0)}');
    } else {
      buffer.writeln('💵 I owe you: ₹${totalAmount.abs().toStringAsFixed(0)}');
    }

    buffer.writeln();
    buffer.writeln('Please settle when convenient! 🙏');
    buffer.writeln('— Sent via ExpenseIQ');

    return buffer.toString();
  }

  /// Generate settlement confirmation message
  static String generateSettlementMessage(String contactName, double amount) {
    return '✅ Settlement Confirmed!\n\n'
        'Hey $contactName, our dues of ₹${amount.toStringAsFixed(0)} have been settled.\n\n'
        'Thanks! 🤝\n'
        '— Sent via ExpenseIQ';
  }
}
