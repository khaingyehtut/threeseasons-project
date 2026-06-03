/// Formats a price: shows decimals only when non-zero (e.g. 10000.00 → "10000", 10000.50 → "10000.5")
String fmtPrice(double? v) {
  final val = v ?? 0.0;
  return 'Ks ${val % 1 == 0 ? val.toStringAsFixed(0) : val.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '')}';
}

class AppConstants {
  // static const String baseUrl = 'http://10.0.2.2:5001/api';        // Android emulator
  // static const String baseUrl = 'http://localhost:5001/api';         // iOS simulator / web
  // static const String baseUrl = 'http://192.168.0.116:5001/api';   // local dev (Mac LAN IP)
  static const String baseUrl = 'http://168.144.143.60:5001/api';     // DigitalOcean VPS
  // static const String socketUrl = 'http://192.168.0.116:5001';     // local dev (Mac LAN IP)
  static const String socketUrl = 'http://168.144.143.60:5001';       // DigitalOcean VPS
  static const String appName = 'TSfootwear';
  static const String googleMapsApiKey = 'AIzaSyBXmJ-t25_VCKLFZRoXQhRibGiO4mIoRew';
  static const String tokenKey = 'auth_token';
  static const String userKey = 'user_data';
  // Get this from: Firebase Console → Project Settings → Cloud Messaging → Web Push certificates
  static const String fcmVapidKey = 'YOUR_VAPID_KEY_HERE';
}
