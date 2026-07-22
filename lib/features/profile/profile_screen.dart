import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_image_slot.dart';
import '../../core/widgets/pg_snackbar.dart';
import '../../data/models/booking.dart';
import '../../data/models/pet_profile.dart';
import '../../data/repositories/providers.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _uploading = false;

  Future<void> _pickAndUploadAvatar() async {
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    if (uid == null || _uploading) return;
    try {
      final bytes = await ref.read(imagePickerServiceProvider).pickImage();
      if (!mounted || bytes == null) return;
      setState(() => _uploading = true);
      final url = await ref.read(storageRepositoryProvider)
          .uploadImage(path: 'users/$uid/avatar.jpg', bytes: bytes);
      await ref.read(userRepositoryProvider).setPhotoUrl(uid, url);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(
            content: Text("Couldn't upload the photo. Please try again."),
            behavior: SnackBarBehavior.floating));
      }
    } finally {
      if (mounted && _uploading) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final profile = ref.watch(currentUserProfileProvider).value;
    final pets = ref.watch(myPetsProvider).value ?? const <PetProfile>[];
    final bookings = ref.watch(myBookingsProvider).value ?? const <Booking>[];
    final woofs = ref.watch(myWoofCountProvider).value ?? 0;
    final name = profile?.name ?? '';
    final roleArea = profile == null ? '' : '${profile.role.label} · ${profile.area}';

    return Container(color: c.bg, child: SafeArea(bottom: false, child: ListView(padding: EdgeInsets.zero, children: [
      Container(height: 130, decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFFF59E2E), Color(0xFFF0871E)]))),
      Transform.translate(offset: const Offset(0, -40), child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(22), boxShadow: c.shadow),
            child: Column(children: [
              Row(children: [
                GestureDetector(
                  onTap: _pickAndUploadAvatar,
                  child: Stack(alignment: Alignment.center, children: [
                    PgImageSlot(size: 72, circle: true, emoji: '🙂', imageUrl: profile?.photoUrl),
                    if (_uploading)
                      const SizedBox(width: 26, height: 26,
                        child: CircularProgressIndicator(strokeWidth: 2.5)),
                  ]),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name.isEmpty ? 'Your profile' : name, style: PgText.poppins(19, FontWeight.w800, color: c.text)),
                  const SizedBox(height: 2),
                  Text(roleArea, style: PgText.inter(13, FontWeight.w400, color: c.muted)),
                ])),
              ]),
              const SizedBox(height: 16),
              Container(height: 1, color: c.border),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: _stat(c, '${pets.length}', 'Pets')),
                Container(width: 1, height: 34, color: c.border),
                Expanded(child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => context.push(Routes.bookings),
                  child: _stat(c, '${bookings.length}', 'Bookings'))),
                Container(width: 1, height: 34, color: c.border),
                Expanded(child: _stat(c, '$woofs', 'Woofs')),
              ]),
            ]),
          ),
          const SizedBox(height: 16),
          if (pets.isNotEmpty)
            GestureDetector(
              onTap: () => context.push(Routes.petProfile, extra: pets.first),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: c.brandSoft, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(18)),
                child: Row(children: [
                  PgImageSlot(size: 52, circle: true, emoji: '🐾', imageUrl: pets.first.photoUrl),
                  const SizedBox(width: 13),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(pets.first.displayName, style: PgText.poppins(15, FontWeight.w700, color: c.text)),
                    Text(PetProfile.detailLine([pets.first.breed, 'View profile →']),
                        style: PgText.inter(12.5, FontWeight.w400, color: c.muted)),
                  ])),
                ]),
              ),
            )
          else
            GestureDetector(
              onTap: () => context.push(Routes.createPet),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(18)),
                child: Row(children: [
                  const Text('➕', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 13),
                  Expanded(child: Text('Add a pet', style: PgText.poppins(14.5, FontWeight.w700, color: c.text))),
                  Icon(Icons.chevron_right, color: c.faint),
                ]),
              ),
            ),
          const SizedBox(height: 16),
          _menuGroup(c, [
            ('🗓️', 'My bookings', () => context.push(Routes.bookings)),
            // Received (tab 1) is where a host sees the stays booked with them.
            ('🏡', 'My homestays', () => context.push(Routes.bookings, extra: 1)),
            ('💳', 'Payments & wallet', () => showComingSoon(context, 'Payments & wallet')),
            ('🎒', 'Become a pro or host', () => showComingSoon(context, 'Become a pro or host')),
          ]),
          const SizedBox(height: 14),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(18)),
            child: Column(children: [
              _row(c, '⚙️', 'Settings', () => context.push(Routes.settings), border: true),
              _row(c, '↩️', 'Sign out', () => ref.read(authRepositoryProvider).signOut(), danger: true),
            ]),
          ),
          const SizedBox(height: 30),
        ]),
      )),
    ])));
  }

  Widget _stat(PgColors c, String value, String label) => Column(children: [
        Text(value, style: PgText.poppins(18, FontWeight.w800, color: c.text)),
        Text(label, style: PgText.inter(11.5, FontWeight.w400, color: c.faint)),
      ]);

  Widget _menuGroup(PgColors c, List<(String, String, VoidCallback)> items) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(18)),
        child: Column(children: [
          for (var i = 0; i < items.length; i++)
            _row(c, items[i].$1, items[i].$2, items[i].$3, border: i != items.length - 1),
        ]),
      );

  Widget _row(PgColors c, String emoji, String title, VoidCallback onTap, {bool border = false, bool danger = false}) =>
      GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(border: border ? Border(bottom: BorderSide(color: c.border)) : null),
          child: Row(children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 13),
            Expanded(child: Text(title, style: PgText.inter(14, FontWeight.w600, color: danger ? c.heart : c.text))),
            if (!danger) Icon(Icons.chevron_right, color: c.faint, size: 20),
          ]),
        ),
      );
}
