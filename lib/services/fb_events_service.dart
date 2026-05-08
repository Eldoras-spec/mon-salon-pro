import 'dart:io' show Platform;

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:facebook_app_events/facebook_app_events.dart';
import 'package:flutter/foundation.dart';

/// Wraps the Facebook App Events SDK so install + activation tracking can be
/// gated on iOS ATT consent. RevenueCat already pushes Subscribe/Trial/Renewal
/// to Meta server-side (Conversions API, Mode A) — this service only
/// covers the install / app_open / custom-event side that ad campaigns
/// need to optimize "App Install" objectives.
class FbEventsService {
  FbEventsService._();
  static final FacebookAppEvents _fb = FacebookAppEvents();
  static bool _initialized = false;

  /// Call once at app launch, after Firebase init. Asks for ATT on iOS,
  /// configures advertiser tracking accordingly, then logs an activate
  /// event so installs flow into Meta Events Manager. ATT is requested
  /// FIRST in its own try-block so that any FB SDK failure can't prevent
  /// the system prompt from appearing.
  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    bool attGranted = false;
    if (Platform.isIOS) {
      attGranted = await _ensureAttRequested();
    } else {
      attGranted = true;
    }

    try {
      await _fb.setAdvertiserTracking(enabled: attGranted);
      await _fb.setAutoLogAppEventsEnabled(true);
      // First call after init triggers activateApp — Meta uses this
      // signal as the "App Activate" / "App Install" event.
      await _fb.logEvent(name: 'fb_mobile_activate_app');
    } catch (e, st) {
      debugPrint('FbEventsService FB SDK init error: $e\n$st');
    }
  }

  /// Trigger the iOS ATT system prompt if the user hasn't responded yet.
  /// Returns true when authorized. Isolated in its own try so that errors
  /// in the FB SDK below can't prevent the prompt from being shown.
  static Future<bool> _ensureAttRequested() async {
    try {
      final current = await AppTrackingTransparency.trackingAuthorizationStatus;
      debugPrint('FbEventsService ATT current status: $current');
      if (current == TrackingStatus.notDetermined) {
        final result = await AppTrackingTransparency.requestTrackingAuthorization();
        debugPrint('FbEventsService ATT response: $result');
        return result == TrackingStatus.authorized;
      }
      return current == TrackingStatus.authorized;
    } catch (e, st) {
      debugPrint('FbEventsService ATT request error: $e\n$st');
      return false;
    }
  }

  /// Tag the current Firebase user inside Meta so events can be
  /// reconciled across devices/sessions.
  static Future<void> setUserId(String? userId) async {
    try {
      if (userId == null || userId.isEmpty) {
        await _fb.clearUserID();
      } else {
        await _fb.setUserID(userId);
      }
    } catch (_) {}
  }

  /// Generic custom event passthrough (e.g. completed_registration,
  /// onboarding_finished, salon_published). Use sparingly.
  static Future<void> logEvent(String name, {Map<String, dynamic>? params}) async {
    try {
      await _fb.logEvent(name: name, parameters: params);
    } catch (_) {}
  }
}
