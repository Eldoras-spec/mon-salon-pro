import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/conversation_model.dart';
import '../models/message_model.dart';
import '../services/message_service.dart';

/// 50 most recent conversations for a client. Stream cached as long as
/// at least one listener is mounted.
final clientConversationsProvider =
    StreamProvider.family<List<ConversationModel>, String>((ref, clientId) {
  return MessageService().getClientConversations(clientId);
});

/// 50 most recent conversations for a salon (owner view). Filter by ownerId.
/// `autoDispose` so the listener dies the moment the conversations screen
/// (or any owner-mode container) unmounts — avoids a leftover snapshot
/// firing PERMISSION_DENIED right after the owner signs out under the new
/// (null / employee) auth.
final ownerConversationsProvider =
    StreamProvider.autoDispose.family<List<ConversationModel>, String>((ref, ownerId) {
  return MessageService().getOwnerConversations(ownerId);
});

/// 50 most recent messages for a conversation. `autoDispose` so the stream
/// closes when the chat screen pops — avoids accumulating per-convId streams.
final messagesProvider =
    StreamProvider.autoDispose.family<List<MessageModel>, String>((ref, convId) {
  return MessageService().getMessages(convId);
});
