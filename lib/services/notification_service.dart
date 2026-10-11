import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz;
import 'database_service.dart';
import '../screens/conversations_screen.dart';
import '../screens/notifications_screen.dart';
import '../screens/owner_boutique_screen.dart';
import '../screens/owner_inventory_screen.dart';

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

  /// Conversation the user is actively viewing. When a push arrives with a
  /// matching `conversationId` in its data payload, the foreground banner is
  /// suppressed (the user is already reading the conversation live).
  /// Set from [ChatScreen] in initState / resume and cleared in dispose / pause.
  static String? activeConversationId;

  /// Root navigator, wired on MaterialApp, used to open the screen a
  /// notification is about when the user taps it.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  // One token-refresh listener per signed-in user. A new listener used to
  // be stacked on every save (incl. from a build method), so after an
  // account switch refreshed tokens were written to the previous users.
  StreamSubscription<String>? _tokenRefreshSub;
  String? _tokenRefreshUser;
  String? _savedTokenFor;

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

    // 2b. iOS-only foreground display knob (no-op on Android). Letting
    // FCM auto-show the banner from the `notification` payload — `alert:
    // false` was tried but FCM's UNUserNotificationCenter delegate then
    // also suppresses any flutter_local_notifications.show() we'd attempt
    // ourselves (delegate slot conflict), so foreground stays empty.
    // Tradeoff: chat-screen suppression via `activeConversationId` only
    // works on Android — iOS shows the banner even on the matching chat.
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

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
    if (_tokenRefreshUser != userId) {
      await _tokenRefreshSub?.cancel();
      _tokenRefreshUser = userId;
      _savedTokenFor = null;
      _tokenRefreshSub = _messaging.onTokenRefresh.listen((newToken) {
        _databaseService.updateFcmToken(userId, newToken);
        debugPrint('🔔 FCM Token refreshed for user $userId');
      });
    }
    // Already written this session for this user: skip the write.
    if (_savedTokenFor == userId) return;
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
        _savedTokenFor = userId;
        debugPrint('🔔 FCM Token saved for user $userId');
      }
    } catch (e) {
      debugPrint('🔔 Error getting FCM token: $e');
    }
  }

  /// Stops token syncing (call on sign-out).
  Future<void> stopTokenSync() async {
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
    _tokenRefreshUser = null;
    _savedTokenFor = null;
  }

  /// Handle a message received while the app is in the foreground.
  /// The Firestore notification doc was already created by the Cloud Function
  /// that triggered this push — do NOT re-save it (would cause an infinite
  /// loop with onNewNotification).
  void _handleForegroundMessage(RemoteMessage message) {
    // iOS: FCM auto-displays the banner via the OS (see setForeground call
    // in `initialize`). Calling showLocalNotification here would put a
    // SECOND banner on screen because the local-notifs path goes through
    // the same UNUserNotificationCenter that FCM is already presenting.
    // Skip — chat-screen suppression cannot work on iOS as a result.
    if (Platform.isIOS) return;

    // Android: we own foreground presentation via flutter_local_notifs.
    // The active-chat check skips the banner when the recipient is
    // already viewing the matching conversation (live stream renders
    // the message, banner would be redundant noise).
    final incomingConvId = message.data['conversationId'];
    if (incomingConvId != null &&
        activeConversationId != null &&
        incomingConvId == activeConversationId) {
      return;
    }

    final notification = message.notification;
    if (notification != null) {
      showLocalNotification(
        title: notification.title ?? 'Mon Salon',
        body: notification.body ?? '',
        payload: jsonEncode(message.data),
      );
    }
  }

  /// Handle a notification tap that opened the app.
  void _handleMessageOpenedApp(RemoteMessage message) {
    debugPrint('🔔 Notification opened app: ${message.data}');
    _openFor(Map<String, dynamic>.from(message.data));
  }

  /// Handle local notification tap.
  void _onNotificationTapped(NotificationResponse response) {
    debugPrint('🔔 Local notification tapped: ${response.payload}');
    final p = response.payload;
    if (p == null || p.isEmpty) return;
    try {
      final data = jsonDecode(p);
      if (data is Map) _openFor(Map<String, dynamic>.from(data));
    } catch (_) {}
  }

  /// Opens the screen matching a push payload `type`. Waits for the app to
  /// be signed in and the navigator mounted (cold start from a tap).
  Future<void> _openFor(Map<String, dynamic> data) async {
    for (var i = 0; i < 30; i++) {
      if (navigatorKey.currentState != null &&
          FirebaseAuth.instance.currentUser != null) {
        break;
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }
    final nav = navigatorKey.currentState;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (nav == null || uid == null) return;
    // Give the router a moment to settle on the home screen first.
    await Future.delayed(const Duration(milliseconds: 300));
    final isEmployee = uid.startsWith('emp_');
    final type = (data['type'] ?? '').toString();
    final Widget screen = switch (type) {
      'new_message' || 'bot_handover' when !isEmployee =>
        ConversationsScreen(currentUserId: uid, isClient: false, salonId: uid),
      'new_order' || 'order_status' when !isEmployee =>
        const OwnerBoutiqueScreen(),
      'low_stock' when !isEmployee => const OwnerInventoryScreen(),
      _ => const NotificationsScreen(),
    };
    nav.push(MaterialPageRoute(builder: (_) => screen));
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
