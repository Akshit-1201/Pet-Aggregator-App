import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../data/repositories/providers.dart';

/// Get-or-create a 1:1 chat with [otherUid] and open the conversation.
Future<void> openChatWith(BuildContext context, WidgetRef ref,
    {required String otherUid, required String otherName}) async {
  final me = ref.read(authRepositoryProvider).currentUser;
  if (me == null) return;
  final profile = await ref.read(userRepositoryProvider).watchUser(me.uid).first;
  final chat = await ref.read(chatRepositoryProvider).openChat(
      myUid: me.uid, myName: profile?.name ?? 'Someone', otherUid: otherUid, otherName: otherName);
  if (context.mounted) context.push(Routes.chat, extra: chat);
}
