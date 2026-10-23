import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/navigation/pg_back_scope.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_app_bar.dart';
import '../../core/widgets/pg_buttons.dart';
import '../../core/widgets/pg_text_field.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/providers.dart';
import 'social_sign_in_buttons.dart';

/// Indian mobile numbers: 10 digits starting 6-9. Pawgo Pets is Mumbai-only,
/// so the +91 prefix is fixed rather than a country picker.
final _indianMobile = RegExp(r'^[6-9]\d{9}$');

/// Strips spaces, dashes, a leading 0 or +91/91 so pasted numbers work.
String? normaliseIndianMobile(String raw) {
  var d = raw.replaceAll(RegExp(r'\D'), '');
  if (d.length == 12 && d.startsWith('91')) d = d.substring(2);
  if (d.length == 11 && d.startsWith('0')) d = d.substring(1);
  return _indianMobile.hasMatch(d) ? '+91$d' : null;
}

/// Sign in (or sign up) with a phone number and a one-time SMS code.
class PhoneSignInScreen extends ConsumerStatefulWidget {
  const PhoneSignInScreen({super.key});
  @override
  ConsumerState<PhoneSignInScreen> createState() => _PhoneSignInScreenState();
}

class _PhoneSignInScreenState extends ConsumerState<PhoneSignInScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  PhoneVerification? _sent;
  bool _busy = false;
  String? _error;
  int _resendIn = 0;
  Timer? _timer;
  StreamSubscription? _authSub;
  bool _routed = false;

  @override
  void initState() {
    super.initState();
    // Android can read the SMS itself and sign in with no typing; react to
    // that the same way as a typed code.
    _authSub = ref.read(authRepositoryProvider).authStateChanges().listen((u) {
      if (u != null && _sent != null) _finish(SocialSignIn(user: u, displayName: ''));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _authSub?.cancel();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _resendIn = 30);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _resendIn--);
      if (_resendIn <= 0) t.cancel();
    });
  }

  Future<void> _send({bool resend = false}) async {
    final number = normaliseIndianMobile(_phone.text);
    if (number == null) {
      setState(() => _error = 'Enter a 10-digit Indian mobile number.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final v = await ref.read(authRepositoryProvider)
          .sendPhoneCode(number, resendToken: resend ? _sent?.resendToken : null);
      if (!mounted) return;
      setState(() => _sent = v);
      if (v.autoVerified) {
        final u = ref.read(authRepositoryProvider).currentUser;
        if (u != null) await _finish(SocialSignIn(user: u, displayName: ''));
        return;
      }
      _startCooldown();
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      debugPrint('sendPhoneCode failed: $e');
      if (mounted) setState(() => _error = "Couldn't send the code. Please try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final v = _sent;
    final code = _code.text.trim();
    if (v == null) return;
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = 'Enter the 6-digit code from the SMS.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final result = await ref.read(authRepositoryProvider).confirmPhoneCode(v, code);
      await _finish(result);
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      debugPrint('confirmPhoneCode failed: $e');
      if (mounted) setState(() => _error = "Couldn't check the code. Please try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish(SocialSignIn result) async {
    if (_routed || !mounted) return;
    _routed = true;
    await routeAfterSignIn(context, ref, result);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final sent = _sent;
    return PgBackScope(
      child: Scaffold(
        backgroundColor: c.surface,
        body: SafeArea(
          child: Column(children: [
            Builder(builder: (ctx) => PgAppBar(
                title: sent == null ? 'Continue with phone' : 'Enter the code',
                onBack: () {
                  if (sent != null) {
                    setState(() { _sent = null; _code.clear(); _error = null; });
                  } else {
                    PgBackScope.pop(ctx);
                  }
                })),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
                children: sent == null
                    ? [
                        Text("We'll text you a 6-digit code. No password needed.",
                            style: PgText.inter(14, FontWeight.w400, color: c.muted, height: 1.5)),
                        const SizedBox(height: 16),
                        PgTextField(
                          key: const Key('phone-number'),
                          label: 'Mobile number (+91)',
                          controller: _phone,
                          icon: Icons.phone_iphone_rounded,
                          keyboardType: TextInputType.phone,
                          hint: '98765 43210',
                        ),
                      ]
                    : [
                        Text('Sent to ${sent.phoneNumber}.',
                            style: PgText.inter(14, FontWeight.w500, color: c.muted)),
                        const SizedBox(height: 16),
                        PgTextField(
                          key: const Key('phone-code'),
                          label: '6-digit code',
                          controller: _code,
                          icon: Icons.sms_outlined,
                          keyboardType: TextInputType.number,
                          hint: '123456',
                        ),
                        const SizedBox(height: 14),
                        // Wrap, not Row: "Resend code in 30s" + "Change number" don't
                        // fit side by side on a small phone or at large text sizes.
                        Wrap(alignment: WrapAlignment.spaceBetween, spacing: 8, children: [
                          TextButton(
                            onPressed: _busy || _resendIn > 0 ? null : () => _send(resend: true),
                            child: Text(_resendIn > 0 ? 'Resend code in ${_resendIn}s' : 'Resend code',
                                style: PgText.inter(13.5, FontWeight.w600,
                                    color: _resendIn > 0 ? c.faint : c.brand))),
                          TextButton(
                            onPressed: _busy ? null : () => setState(() {
                              _sent = null; _code.clear(); _error = null;
                            }),
                            child: Text('Change number',
                                style: PgText.inter(13.5, FontWeight.w600, color: c.muted))),
                        ]),
                      ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(_error!, style: PgText.inter(13, FontWeight.w600, color: c.heart))),
            Container(
              decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border))),
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
              child: PgPrimaryButton(
                label: _busy
                    ? (sent == null ? 'Sending…' : 'Checking…')
                    : (sent == null ? 'Send code' : 'Verify & continue'),
                onPressed: _busy ? () {} : () {
                  HapticFeedback.selectionClick();
                  sent == null ? _send() : _verify();
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
