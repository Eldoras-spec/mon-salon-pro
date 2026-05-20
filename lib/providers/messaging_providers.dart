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
final ownerConversationsProvider =
    StreamProvider.family<List<ConversationModel>, String>((ref, ownerId) {
  return MessageService().getOwnerConversations(ownerId);
});

/// 50 most recent messages for a conversation. `autoDispose` so the stream
/// closes when the chat screen pops — avoids accumulating per-convId streams.
final messagesProvider =
    StreamProvider.autoDispose.family<List<MessageModel>, String>((ref, convId) {
  return MessageService().getMessages(convId);
});
