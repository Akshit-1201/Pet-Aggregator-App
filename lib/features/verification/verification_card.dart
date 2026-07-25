import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_snackbar.dart';
import '../../data/models/verification_request.dart';
import '../../data/repositories/providers.dart';

/// The applicant side of KYC, embedded in both Pro-setup and Host-setup.
///
/// Verification is **optional** — an unverified partner can still list, they
/// simply read "not yet Pawgo-verified", which is already true. This card is
/// how they stop being that.
class VerificationCard extends ConsumerStatefulWidget {
  final VerificationKind kind;
  const VerificationCard({super.key, required this.kind});

  @override
  ConsumerState<VerificationCard> createState() => _VerificationCardState();
}

class _VerificationCardState extends ConsumerState<VerificationCard> {
  final List<Uint8List> _picked = [];
  bool _busy = false;

  static const _maxDocs = 3;

  Future<void> _pick() async {
    if (_picked.length >= _maxDocs) return;
    try {
      final bytes = await ref.read(imagePickerServiceProvider).pickImage();
      if (bytes != null && mounted) setState(() => _picked.add(bytes));
    } catch (_) {
      if (mounted) showPgSnack(context, "Couldn't open your photos. Please try again.");
    }
  }

  Future<void> _submit() async {
    if (_picked.isEmpty) {
      showPgSnack(context, 'Add at least one document first.');
      return;
    }
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    if (uid == null) return;
    setState(() => _busy = true);
    try {
      final repo = ref.read(verificationRepositoryProvider);
      final profile = await ref.read(userRepositoryProvider).watchUser(uid).first;
      // Upload first, then write the request — a request pointing at objects
      // that failed to upload would sit in the queue as an unreviewable dead end.
      final paths = <String>[];
      for (var i = 0; i < _picked.length; i++) {
        paths.add(await repo.uploadDocument(uid: uid, bytes: _picked[i], index: i));
      }
      await repo.submit(VerificationRequest(
        uid: uid,
        kind: widget.kind,
        applicantName: profile?.name ?? '',
        area: profile?.area ?? '',
        docPaths: paths,
        submittedAt: DateTime.now().millisecondsSinceEpoch,
      ));
      if (mounted) {
        setState(() => _picked.clear());
        showPgSnack(context, 'Sent for review — we usually reply within 2 days.');
      }
    } catch (_) {
      if (mounted) showPgSnack(context, "Couldn't submit that. Please try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final request = ref.watch(myVerificationRequestProvider).value;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: c.surface, border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('🛡️', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(child: Text('Get Pawgo Verified',
              style: PgText.poppins(16, FontWeight.w800, color: c.text))),
        ]),
        const SizedBox(height: 6),
        ..._body(context, c, request),
      ]),
    );
  }

  List<Widget> _body(BuildContext context, PgColors c, VerificationRequest? request) {
    switch (request?.status) {
      case VerificationStatus.approved:
        return [
          Text("You're verified. The badge shows on your listing.",
              style: PgText.inter(13, FontWeight.w400, color: c.muted, height: 1.5)),
        ];

      case VerificationStatus.pending:
        return [
          Text('Under review. We usually reply within 2 days.',
              style: PgText.inter(13, FontWeight.w400, color: c.muted, height: 1.5)),
          const SizedBox(height: 10),
          _chip(c, '⏳ Pending', c.brandSoft, c.brandDeep),
        ];

      case VerificationStatus.rejected:
        return [
          _chip(c, '✕ Not approved', c.surface2, c.heart),
          const SizedBox(height: 8),
          if (request!.reason.isNotEmpty)
            Text(request.reason,
                style: PgText.inter(13, FontWeight.w400, color: c.muted, height: 1.5)),
          const SizedBox(height: 12),
          ..._form(context, c, retry: true),
        ];

      case null:
        return _form(context, c);
    }
  }

  List<Widget> _form(BuildContext context, PgColors c, {bool retry = false}) => [
        Text(
            retry
                ? 'You can send new documents.'
                : 'Add a photo ID (and address proof if you have one). Only the '
                    'Pawgo team can see these — they are never shown to other users.',
            style: PgText.inter(13, FontWeight.w400, color: c.muted, height: 1.5)),
        const SizedBox(height: 12),
        // Wrap, not Row: three thumbnails plus the add tile overflow a narrow
        // phone otherwise.
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final bytes in _picked)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.memory(bytes, width: 56, height: 56, fit: BoxFit.cover,
                  // A picker can hand back something undecodable; showing a
                  // placeholder beats throwing inside build().
                  errorBuilder: (_, _, _) => Container(
                        width: 56, height: 56, alignment: Alignment.center,
                        color: c.surface2,
                        child: Icon(Icons.description_outlined, color: c.muted, size: 22),
                      ))),
          if (_picked.length < _maxDocs)
            GestureDetector(
              onTap: _busy ? null : _pick,
              child: Container(
                width: 56, height: 56, alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: c.surface2, border: Border.all(color: c.border),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.add, color: c.muted, size: 22))),
        ]),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: _busy ? null : _submit,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 13),
            alignment: Alignment.center,
            decoration: BoxDecoration(
                gradient: LinearGradient(colors: [c.brand, c.brand2]),
                borderRadius: BorderRadius.circular(14)),
            child: Text(_busy ? 'Sending…' : 'Submit for review',
                style: PgText.poppins(14.5, FontWeight.w700, color: Colors.white))),
        ),
      ];

  Widget _chip(PgColors c, String label, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Text(label, style: PgText.inter(12.5, FontWeight.w700, color: fg)),
      );
}
