import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_image_slot.dart';
import '../../data/models/pet_profile.dart';
import '../../data/repositories/providers.dart';
import '../chat/chat_actions.dart';

class WoofMatchScreen extends ConsumerWidget {
  final PetProfile? pet;
  const WoofMatchScreen({super.key, this.pet});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = pet?.name ?? 'your match';
    final ownerUid = pet?.ownerId ?? '';
    final ownerName = ref.watch(userByIdProvider(ownerUid)).value?.name ?? 'Pet parent';
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFFF8B45E), Color(0xFFF0871E)]),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(30),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Spacer(),
              Text("It's a Woof match! 🎉",
                textAlign: TextAlign.center,
                style: PgText.poppins(30, FontWeight.w800, color: Colors.white, ls: -0.5)),
              const SizedBox(height: 10),
              Text("You and $name's parent both said Woof. Say hi and plan a playdate!",
                textAlign: TextAlign.center,
                style: PgText.inter(15, FontWeight.w500, color: const Color(0xFFFFF5E8), height: 1.5)),
              const SizedBox(height: 38),
              SizedBox(
                width: 200, height: 112,
                child: Stack(alignment: Alignment.center, children: [
                  Positioned(left: 6, top: 2,
                    child: _circleAvatar(const PgImageSlot(size: 108, circle: true, emoji: '🙂'))),
                  Positioned(right: 6, top: 2,
                    child: _circleAvatar(const PgImageSlot(size: 108, circle: true, emoji: '🐶'))),
                  Container(
                    width: 52, height: 52, alignment: Alignment.center,
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: const Text('🐾', style: TextStyle(fontSize: 24))),
                ]),
              ),
              const Spacer(),
              SizedBox(width: double.infinity, child: _darkButton(
                'Send a message 💬', () => ownerUid.isEmpty
                    ? null
                    : openChatWith(context, ref, otherUid: ownerUid, otherName: ownerName))),
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: _outlineButton(
                'Keep swiping', () => context.pop())),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _circleAvatar(Widget child) => Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4)),
        child: ClipOval(child: child),
      );

  Widget _darkButton(String label, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 17), alignment: Alignment.center,
          decoration: BoxDecoration(color: const Color(0xFF211B17), borderRadius: BorderRadius.circular(16)),
          child: Text(label, style: PgText.poppins(15.5, FontWeight.w700, color: Colors.white)),
        ),
      );

  Widget _outlineButton(String label, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16), alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0x88FFFFFF), width: 1.5),
            borderRadius: BorderRadius.circular(16)),
          child: Text(label, style: PgText.poppins(15, FontWeight.w700, color: Colors.white)),
        ),
      );
}
