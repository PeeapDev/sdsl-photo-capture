import 'package:shared_preferences/shared_preferences.dart';

class PinService {
  static const _key = 'deletion_pin_v1';

  static Future<bool> hasPin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_key);
  }

  static Future<void> setPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, pin);
  }

  static Future<bool> verifyPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    return saved == pin;
  }
}
