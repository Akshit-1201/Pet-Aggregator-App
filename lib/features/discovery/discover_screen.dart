import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_swipe_card.dart';
import '../../data/models/pet_profile.dart';
import '../../data/models/swipe.dart';
import '../../data/repositories/providers.dart';

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});
  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  List<PetProfile>? _deck;
  int _index = 0;

  Future<void> _onWoof(PetProfile pet) async {
    final me = ref.read(authRepositoryProvider).currentUser;
    if (me == null) return;
    final swipes = ref.read(swipeRepositoryProvider);
    // Advance first, then talk to the network. Awaiting the write + reciprocity
    // read before advancing left the swiped card animated off-screen with only
    // the empty placeholder showing until Firestore replied — on a real device
    // that reads as a blank white card that's stuck (matching _onPass, which
    // never awaited and so always felt instant).
    setState(() => _index++);
    await swipes.recordSwipe(Swipe(
        fromUid: me.uid, petId: pet.id, ownerId: pet.ownerId, direction: SwipeDirection.woof));
    final matched = await swipes.hasReciprocalWoof(otherUid: pet.ownerId, myUid: me.uid);
    if (!mounted) return;
    if (matched) context.push(Routes.woofMatch, extra: pet);
  }

  void _onPass(PetProfile pet) {
    final me = ref.read(authRepositoryProvider).currentUser;
    if (me == null) return;
    ref.read(swipeRepositoryProvider).recordSwipe(Swipe(
        fromUid: me.uid, petId: pet.id, ownerId: pet.ownerId, direction: SwipeDirection.pass));
    setState(() => _index++);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final profile = ref.watch(currentUserProfileProvider).value;
    final deckAsync = ref.watch(discoverDeckProvider);
    // Seed the deck from the currently-watched value, not from ref.listen: a
    // change-only listener never fires when the provider is already resolved at
    // first build (warm providers / State recreated after a prior resolve), which
    // left the screen spinning forever. Seed once, then freeze so _index walks a
    // stable list even as the provider re-emits a shrinking deck during swipes.
    if (_deck == null && deckAsync.hasValue) _deck = deckAsync.value;

    return Container(
      color: c.bg,
      child: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 8),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Discover', style: PgText.poppins(23, FontWeight.w800, color: c.text, ls: -0.4)),
                Text('Pets near ${profile?.area.isNotEmpty == true ? profile!.area : 'you'}',
                    style: PgText.inter(12.5, FontWeight.w500, color: c.muted)),
              ])),
              GestureDetector(
                onTap: () => context.go(Routes.nearby),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border),
                    borderRadius: BorderRadius.circular(13)),
                  child: Text('🗺 Map view', style: PgText.inter(13, FontWeight.w600, color: c.text))),
              ),
            ]),
          ),
          Expanded(child: _body(c, deckAsync)),
        ]),
      ),
    );
  }

  Widget _body(PgColors c, AsyncValue<List<PetProfile>> deckAsync) {
    if (_deck == null) {
      if (deckAsync.hasError) {
        return Center(child: Text('Could not load pets.', style: PgText.body(context)));
      }
      return const Center(child: CircularProgressIndicator());
    }
    final deck = _deck!;
    if (_index >= deck.length) return _empty(c);
    final pet = deck[_index];
    return Column(children: [
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
          child: Stack(alignment: Alignment.center, children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.only(top: 18),
                child: Container(decoration: BoxDecoration(
                  color: c.surface, borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: c.border), boxShadow: c.shadowSm)))),
            Positioned.fill(
              child: PgSwipeCard(key: ValueKey(pet.id), pet: pet,
                onWoof: () => _onWoof(pet), onPass: () => _onPass(pet))),
          ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 6),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _circleBtn(key: const Key('discover-pass'), c: c, size: 60,
            child: Icon(Icons.close, color: c.faint, size: 26), onTap: () => _onPass(pet)),
          const SizedBox(width: 22),
          _circleBtn(key: const Key('discover-woof'), c: c, size: 78, gradient: true,
            child: const Icon(Icons.pets, color: Colors.white, size: 32), onTap: () => _onWoof(pet)),
          const SizedBox(width: 22),
          _circleBtn(c: c, size: 60, child: const Text('⭐', style: TextStyle(fontSize: 24)),
            onTap: () => _onWoof(pet)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text('Swipe right to Woof · left to pass',
          style: PgText.inter(12.5, FontWeight.w500, color: c.faint))),
    ]);
  }

  Widget _circleBtn({Key? key, required PgColors c, required Widget child, required double size,
      required VoidCallback onTap, bool gradient = false}) {
    return GestureDetector(
      key: key,
      onTap: onTap,
      child: Container(
        width: size, height: size, alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: gradient ? null : c.surface,
          gradient: gradient
              ? const LinearGradient(colors: [Color(0xFFF8B45E), Color(0xFFF59E2E)])
              : null,
          border: gradient ? null : Border.all(color: c.border),
          boxShadow: c.shadowSm),
        child: child),
    );
  }

  Widget _empty(PgColors c) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('🐾', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 10),
          Text("You're all caught up", style: PgText.poppins(18, FontWeight.w700, color: c.text)),
          const SizedBox(height: 4),
          Text('Check back soon for new pets nearby.',
            style: PgText.inter(13, FontWeight.w400, color: c.muted)),
        ]),
      );
}
