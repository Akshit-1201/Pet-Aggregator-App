import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/widgets/pg_snackbar.dart';
import '../../data/repositories/providers.dart';

/// Chats currently being opened, so a second tap while the first is still
/// talking to Firestore doesn't push the conversation twice.
final _opening = <String>{};

/// Get-or-create a 1:1 chat with [otherUid] and open the conversation.
///
/// Every failure is now said out loud. This used to have no error handling at
/// all, so any problem — offline, a rules rejection, a slow profile read —
/// left a Message button that simply did nothing, which is exactly how testers
/// reported it.
Future<void> openChatWith(BuildContext context, WidgetRef ref,
    {required String otherUid, required String otherName}) async {
  final me = ref.read(authRepositoryProvider).currentUser;
  if (me == null) {
    showPgSnack(context, 'Please sign in to send a message.');
    return;
  }
  if (otherUid.isEmpty) {
    showPgSnack(context, "This listing can't receive messages yet.");
    return;
  }
  if (otherUid == me.uid) {
    // A pro or host viewing their own listing — a chat with yourself would be
    // created and then make no sense in the inbox.
    showPgSnack(context, "That's your own listing — customers will message you here.");
    return;
  }
  if (!_opening.add(otherUid)) return;
  try {
    final profile = await ref
        .read(userRepositoryProvider)
        .watchUser(me.uid)
        .first
        .timeout(const Duration(seconds: 10), onTimeout: () => null);
    final chat = await ref.read(chatRepositoryProvider).openChat(
        myUid: me.uid,
        myName: profile?.name ?? 'Someone',
        otherUid: otherUid,
        otherName: otherName);
    if (context.mounted) context.push(Routes.chat, extra: chat);
  } catch (e, st) {
    debugPrint('openChatWith failed: $e\n$st');
    if (context.mounted) {
      showPgSnack(context, "Couldn't open the chat. Check your connection and try again.");
    }
  } finally {
    _opening.remove(otherUid);
  }
}
