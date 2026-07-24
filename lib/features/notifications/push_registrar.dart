import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/widgets/pg_snackbar.dart';
import '../../data/repositories/providers.dart';

/// Connects the signed-in user to their device's push token, and routes taps.
///
/// Wraps the app rather than living on a screen, because all three jobs outlive
/// any one route: the token has to be registered as soon as someone signs in,
/// rotate silently while they use the app, and a tapped notification has to be
/// able to deep-link from a cold start.
///
/// Registration deliberately waits for a **verified** user — an unverified
/// account cannot reach any screen a notification would link to.
class PushRegistrar extends ConsumerStatefulWidget {
  final Widget child;
  const PushRegistrar({super.key, required this.child});

  @override
  ConsumerState<PushRegistrar> createState() => _PushRegistrarState();
}

class _PushRegistrarState extends ConsumerState<PushRegistrar> {
  final _subs = <StreamSubscription<dynamic>>[];
  String? _registeredUid;
  String? _token;
  bool _listenersAttached = false;

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  Future<void> _attachListenersOnce() async {
    if (_listenersAttached) return;
    _listenersAttached = true;
    final push = ref.read(pushServiceProvider);

    _subs.add(push.onTokenRefresh().listen((token) async {
      _token = token;
      final uid = _registeredUid;
      if (uid != null) {
        await ref.read(pushTokenRepositoryProvider).saveToken(uid, token);
      }
    }));

    // FCM draws no system notification while the app is foregrounded, so
    // surface it in-app or the event is invisible to someone already looking.
    _subs.add(push.onForegroundMessage().listen((payload) {
      if (!mounted) return;
      final text = payload['title'] ?? payload['body'];
      if (text != null && text.isNotEmpty) showPgSnack(context, text);
    }));

    _subs.add(push.onNotificationTap().listen(_handleTap));

    // A cold start from a tapped notification: the payload is waiting rather
    // than arriving on the stream.
    final initial = await push.initialTapPayload();
    if (initial != null) _handleTap(initial);
  }

  /// Notification payloads carry a `route` the server chose. Anything unknown
  /// falls back to the Notifications screen instead of crashing on a bad path.
  void _handleTap(Map<String, String> payload) {
    if (!mounted) return;
    const known = {
      Routes.bookings, Routes.chatList, Routes.notifications,
      Routes.home, Routes.discover, Routes.community, Routes.payments,
    };
    final route = payload['route'];
    context.go(known.contains(route) ? route! : Routes.notifications);
  }

  Future<void> _syncRegistration(String? uid) async {
    // Bail before touching any provider: this runs on every build, and reading
    // the repositories would construct Firebase-backed objects even when signed
    // out — which is both wasteful and, with no Firebase app, throwing.
    if (_registeredUid == uid) return;

    // Signed out (or switched user): stop notifying this device for them.
    if (_registeredUid != null) {
      final old = _registeredUid!;
      final token = _token;
      _registeredUid = null;
      if (token != null) {
        try {
          await ref.read(pushTokenRepositoryProvider).removeToken(old, token);
        } catch (_) {/* best effort — never block sign-out */}
      }
    }
    if (uid == null) return;

    final tokens = ref.read(pushTokenRepositoryProvider);
    final push = ref.read(pushServiceProvider);
    try {
      if (!await push.requestPermission()) return; // declined: no push, no error
      await _attachListenersOnce();
      final token = await push.currentToken();
      if (token == null) return;
      _token = token;
      await tokens.saveToken(uid, token);
      _registeredUid = uid;
    } catch (_) {
      // Push is an enhancement; a failure here must never break the app.
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).value;
    final uid = (user != null && user.emailVerified) ? user.uid : null;
    // Fire-and-forget: registration must not gate the first frame.
    scheduleMicrotask(() => _syncRegistration(uid));
    return widget.child;
  }
}
