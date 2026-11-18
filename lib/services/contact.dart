import 'package:url_launcher/url_launcher.dart';

import '../data/gym_repository.dart';

/// Opens WhatsApp or the dialer. Nothing is sent automatically.
abstract final class Contact {
  /// International digits for wa.me: 0300 123 4567 → 923001234567 (with country code 92).
  static String whatsAppNumber(String phone, String countryCode) {
    final trimmed = phone.trim();
    var digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    if (trimmed.startsWith('+')) return digits;
    if (digits.startsWith('00')) return digits.substring(2);
    final cc = countryCode.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('0') && cc.isNotEmpty) return cc + digits.substring(1);
    if (cc.isNotEmpty && digits.length <= 10 && !digits.startsWith(cc)) return cc + digits;
    return digits;
  }

  static Future<void> whatsApp({required String phone, required String countryCode, required String message}) async {
    final number = whatsAppNumber(phone, countryCode);
    if (number.isEmpty) throw const AppError('Add a phone number for this member first.');
    final uri = Uri.parse('https://wa.me/$number?text=${Uri.encodeComponent(message)}');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw const AppError('WhatsApp could not be opened.');
    }
  }

  static Future<void> call(String phone) async {
    final digits = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (digits.isEmpty) throw const AppError('Add a phone number for this member first.');
    if (!await launchUrl(Uri.parse('tel:$digits'))) throw const AppError('The dialer could not be opened.');
  }
}
