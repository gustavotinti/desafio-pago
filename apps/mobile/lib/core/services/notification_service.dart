import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

@pragma('vm:entry-point')
Future<void> _bgHandler(RemoteMessage _) async {}

class NotificationService {
  static Future<void> init() async {
    FirebaseMessaging.onBackgroundMessage(_bgHandler);
  }

  static Future<void> requestAndSaveToken(String userId) async {
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await _persistToken(userId, token);
      FirebaseMessaging.instance.onTokenRefresh
          .listen((t) => _persistToken(userId, t));
    } catch (_) {
      // Web emulator or simulator — FCM not available
    }
  }

  static Future<void> _persistToken(String userId, String token) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .update({'fcmToken': token});
  }
}
