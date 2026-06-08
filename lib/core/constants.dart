/// Formats a price: strips trailing .0 (e.g. 10000.0 → "Ks 10000", 10000.5 → "Ks 10000.5")
String fmtPrice(double? v) {
  final val = v ?? 0.0;
  return 'Ks ${val % 1 == 0 ? val.toStringAsFixed(0) : val.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '')}';
}

/// Converts a double to string without trailing .0 (e.g. 1000.0 → "1000", 1000.5 → "1000.5")
String numStr(double v) =>
    v % 1 == 0 ? v.toStringAsFixed(0) : v.toString();

class AppConstants {
  // static const String baseUrl = 'http://10.0.2.2:5001/api';        // Android emulator
  // static const String baseUrl = 'http://localhost:5001/api';         // iOS simulator / web
  // static const String baseUrl = 'http://192.168.0.116:5001/api';   // local dev (Mac LAN IP)
  static const String baseUrl = 'http://168.144.143.60:5001/api';     // DigitalOcean VPS
  // static const String socketUrl = 'http://192.168.0.116:5001';     // local dev (Mac LAN IP)
  static const String socketUrl = 'http://168.144.143.60:5001';       // DigitalOcean VPS

  static const String _vpsHost = 'http://168.144.143.60:5001';
  static const List<String> _oldHosts = [
    'http://192.168.0.116:5001',
    'http://10.0.2.2:5001',
    'http://localhost:5001',
  ];

  /// Rewrites any locally-stored image URL to use the current VPS host.
  static String fixImageUrl(String url) {
    if (url.isEmpty) return url;
    for (final old in _oldHosts) {
      if (url.startsWith(old)) {
        return url.replaceFirst(old, _vpsHost);
      }
    }
    return url;
  }
  static const String appName = 'TSfootwear';
  static const String googleMapsApiKey = 'AIzaSyBXmJ-t25_VCKLFZRoXQhRibGiO4mIoRew';
  static const String tokenKey = 'auth_token';
  static const String userKey = 'user_data';
  // Get this from: Firebase Console → Project Settings → Cloud Messaging → Web Push certificates
  static const String fcmVapidKey = 'YOUR_VAPID_KEY_HERE';
}
