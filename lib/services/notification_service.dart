import 'dart:io' show Platform;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz;
import 'database_service.dart';

/// Top-level handler for background messages (must be a top-level function).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('🔔 Background message: ${message.notification?.title}');
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final DatabaseService _databaseService = DatabaseService();

  // Android notification channel
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'mon_salon_channel',
    'Mon Salon Notifications',
    description: 'Notifications for appointments, reminders, and updates.',
    importance: Importance.high,
    playSound: true,
  );

  /// Initialize FCM, permissions, local notifications, and register handlers.
  Future<void> initialize() async {
    // 1. Initialize timezone data
    tz.initializeTimeZones();

    // 2. Request permissions
    await _requestPermissions();

    // 3. Create Android notification channel
    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_channel);

    // 4. Initialize local notifications plugin
    const initSettingsAndroid = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const initSettingsIOS = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: initSettingsAndroid,
      iOS: initSettingsIOS,
    );
    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // 5. Register background handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // 6. Listen for foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // 7. Handle notification that opened the app
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

    // 8. Check if the app was opened via a notification (terminated state)
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleMessageOpenedApp(initialMessage);
    }
  }

  /// Request notification permissions from the user.
  Future<void> _requestPermissions() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    debugPrint('🔔 Notification permission: ${settings.authorizationStatus}');
  }

  /// Get the current FCM token and save it to Firestore for the given user.
  Future<void> saveTokenForUser(String userId) async {
    try {
      // On iOS, wait for the APNS token before requesting FCM token
      if (Platform.isIOS) {
        String? apnsToken = await _messaging.getAPNSToken();
        if (apnsToken == null) {
          await Future.delayed(const Duration(seconds: 2));
          apnsToken = await _messaging.getAPNSToken();
        }
        if (apnsToken == null) {
          debugPrint('🔔 APNS token not available yet, skipping FCM token save');
          return;
        }
      }
      final token = await _messaging.getToken();
      if (token != null) {
        await _databaseService.updateFcmToken(userId, token);
        debugPrint('🔔 FCM Token saved for user $userId');
      }
    } catch (e) {
      debugPrint('🔔 Error getting FCM token: $e');
    }

    // Listen for token refresh
    _messaging.onTokenRefresh.listen((newToken) {
      _databaseService.updateFcmToken(userId, newToken);
      debugPrint('🔔 FCM Token refreshed for user $userId');
    });
  }

  /// Handle a message received while the app is in the foreground.
  void _handleForegroundMessage(RemoteMessage message) {
    final notification = message.notification;
    if (notification != null) {
      showLocalNotification(
        title: notification.title ?? 'Mon Salon',
        body: notification.body ?? '',
        payload: message.data['route'] ?? '',
      );
      // Also persist in Firestore so it appears in the notifications screen
      _saveToFirestore(
        title: notification.title ?? 'Mon Salon',
        body: notification.body ?? '',
        type: message.data['type'] ?? 'general',
      );
    }
  }

  /// Persist a received FCM notification to Firestore for the current user.
  /// Skips types that are saved by Cloud Functions for a different user.
  Future<void> _saveToFirestore({
    required String title,
    required String body,
    required String type,
  }) async {
    // These notification types are created by Cloud Functions for the
    // correct recipient — don't duplicate them for the currently logged-in user.
    const cloudFunctionTypes = {'new_appointment'};
    if (cloudFunctionTypes.contains(type)) return;

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      await _databaseService.saveNotification(
        userId: uid,
        title: title,
        body: body,
        type: type,
      );
    } catch (e) {
      debugPrint('🔔 Error saving notification to Firestore: $e');
    }
  }

  /// Handle a notification tap that opened the app.
  void _handleMessageOpenedApp(RemoteMessage message) {
    debugPrint('🔔 Notification opened app: ${message.data}');
    // Future: navigate to a specific screen based on message.data['route']
  }

  /// Handle local notification tap.
  void _onNotificationTapped(NotificationResponse response) {
    debugPrint('🔔 Local notification tapped: ${response.payload}');
    // Future: navigate based on payload
  }

  /// Show a local notification (used for foreground messages and booking confirmations).
  Future<void> showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000, // unique ID
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: payload,
    );
  }

  /// Schedule a local notification 30 minutes before an appointment.
  /// Does nothing if the reminder time is already in the past.
  Future<void> scheduleReminderNotification({
    required String appointmentId,
    required String serviceName,
    required String salonName,
    required DateTime appointmentTime,
  }) async {
    final reminderTime = appointmentTime.subtract(const Duration(minutes: 30));
    if (reminderTime.isBefore(DateTime.now())) {
      debugPrint('🔔 Reminder skipped — appointment is less than 30min away');
      return;
    }

    final scheduledTZ = tz.TZDateTime.from(reminderTime, tz.local);

    try {
      await _localNotifications.zonedSchedule(
        appointmentId.hashCode.abs() % 2147483647,
        'Rappel de rendez-vous ⏰',
        '$serviceName chez $salonName dans 30 minutes',
        scheduledTZ,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexact,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: 'reminder_$appointmentId',
      );
      debugPrint('🔔 Reminder scheduled for $reminderTime ($serviceName @ $salonName)');
    } catch (e) {
      debugPrint('🔔 Could not schedule reminder: $e');
    }
  }
}
