import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class UpiAppInfo {
  final String name;
  final String packageName;
  final String icon;
  final bool isInstalled;

  UpiAppInfo({
    required this.name,
    required this.packageName,
    required this.icon,
    this.isInstalled = false,
  });
}

class AppDetectorService {
  static const MethodChannel _channel = MethodChannel('com.expenseiq/app_detector');

  static final List<UpiAppInfo> _knownUpiApps = [
    UpiAppInfo(name: 'Google Pay', packageName: 'com.google.android.apps.nbu.paisa.user', icon: '💳'),
    UpiAppInfo(name: 'PhonePe', packageName: 'com.phonepe.app', icon: '📱'),
    UpiAppInfo(name: 'Paytm', packageName: 'net.one97.paytm', icon: '💰'),
    UpiAppInfo(name: 'BHIM', packageName: 'in.org.npci.upiapp', icon: '🏦'),
    UpiAppInfo(name: 'Amazon Pay', packageName: 'in.amazon.mShop.android.shopping', icon: '🛒'),
    UpiAppInfo(name: 'CRED', packageName: 'com.dreamplug.androidapp', icon: '💎'),
    UpiAppInfo(name: 'WhatsApp Pay', packageName: 'com.whatsapp', icon: '💬'),
    UpiAppInfo(name: 'Samsung Pay', packageName: 'com.samsung.android.spay', icon: '📲'),
    UpiAppInfo(name: 'MobiKwik', packageName: 'com.mobikwik_new', icon: '💵'),
    UpiAppInfo(name: 'Freecharge', packageName: 'com.freecharge.android', icon: '⚡'),
  ];

  /// Returns all known UPI apps. On Android, marks installed ones.
  /// On other platforms, returns all apps as available options.
  static Future<List<UpiAppInfo>> getInstalledUpiApps() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      // On non-Android, return all as options (no detection)
      return _knownUpiApps;
    }

    try {
      final List<String> packageNames = _knownUpiApps.map((a) => a.packageName).toList();
      final result = await _channel.invokeMethod<List<dynamic>>('checkInstalledApps', {
        'packages': packageNames,
      });

      if (result == null) return _knownUpiApps;

      final installedSet = Set<String>.from(result.cast<String>());
      return _knownUpiApps.map((app) {
        return UpiAppInfo(
          name: app.name,
          packageName: app.packageName,
          icon: app.icon,
          isInstalled: installedSet.contains(app.packageName),
        );
      }).toList();
    } on PlatformException {
      return _knownUpiApps;
    }
  }

  /// Returns common payment modes
  static List<Map<String, String>> getPaymentModes() {
    return [
      {'key': 'cash', 'label': 'Cash', 'icon': '💵'},
      {'key': 'upi', 'label': 'UPI', 'icon': '📱'},
      {'key': 'neft', 'label': 'NEFT/IMPS', 'icon': '🏦'},
      {'key': 'card_debit', 'label': 'Debit Card', 'icon': '💳'},
      {'key': 'card_credit', 'label': 'Credit Card', 'icon': '💳'},
      {'key': 'wallet', 'label': 'Wallet', 'icon': '👛'},
      {'key': 'cheque', 'label': 'Cheque', 'icon': '📝'},
      {'key': 'other', 'label': 'Other', 'icon': '📦'},
    ];
  }
}
