import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/conversation_model.dart';
import '../models/message_model.dart';

class MessageService {
  final _db = FirebaseFirestore.instance;

  // Deterministic conversation ID
  static String conversationId(String clientId, String salonId) =>
      '${clientId}_$salonId';

  // ── Get or create a conversation ─────────────────────────────────────────

  Future<String> getOrCreateConversation({
    required String clientId,
    required String clientName,
    required String salonId,
    required String salonName,
    required String ownerId,
  }) async {
    final id = conversationId(clientId, salonId);
    final ref = _db.collection('conversations').doc(id);
    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set({
        'clientId': clientId,
        'clientName': clientName,
        'salonId': salonId,
        'salonName': salonName,
        'ownerId': ownerId,
        'lastMessage': '',
        'lastMessageAt': FieldValue.serverTimestamp(),
        'unreadByOwner': 0,
        'unreadByClient': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    return id;
  }

  // ── Send a message ────────────────────────────────────────────────────────

  Future<void> sendMessage({
    required String convId,
    required String senderId,
    required String text,
    required bool senderIsClient,
  }) async {
    final batch = _db.batch();

    // Add message to subcollection
    final msgRef =
        _db.collection('conversations').doc(convId).collection('messages').doc();
    batch.set(msgRef, {
      'senderId': senderId,
      'text': text.trim(),
      'sentAt': FieldValue.serverTimestamp(),
    });

    // Update conversation metadata
    final convRef = _db.collection('conversations').doc(convId);
    batch.update(convRef, {
      'lastMessage': text.trim(),
      'lastMessageAt': FieldValue.serverTimestamp(),
      // Increment unread counter for the OTHER party
      if (senderIsClient) 'unreadByOwner': FieldValue.increment(1),
      if (!senderIsClient) 'unreadByClient': FieldValue.increment(1),
    });

    await batch.commit();

    // ── Auto-reply on first client message ────────────────────────────────
    if (senderIsClient) {
      final msgs = await _db
          .collection('conversations')
          .doc(convId)
          .collection('messages')
          .orderBy('sentAt')
          .limit(2)
          .get();
      // Only 1 message means this is the first → send auto-reply
      if (msgs.docs.length <= 1) {
        await _sendAutoReply(convId: convId, salonId: _salonIdFromConv(convId));
      }
    }
  }

  // ── Auto-reply helper ───────────────────────────────────────────────────

  static const String _autoReplyText =
      'Merci pour votre message ! ✨\n'
      'Un conseiller vous répondra dans les plus brefs délais.\n'
      'En attendant, n\'hésitez pas à consulter nos services et réserver directement en ligne.';

  Future<void> _sendAutoReply({
    required String convId,
    required String salonId,
  }) async {
    // Small delay so the auto-reply appears after the client message
    await Future.delayed(const Duration(seconds: 1));

    final batch = _db.batch();

    final msgRef =
        _db.collection('conversations').doc(convId).collection('messages').doc();
    batch.set(msgRef, {
      'senderId': 'bot_$salonId',
      'text': _autoReplyText,
      'sentAt': FieldValue.serverTimestamp(),
      'isAutoReply': true,
    });

    final convRef = _db.collection('conversations').doc(convId);
    batch.update(convRef, {
      'lastMessage': _autoReplyText,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'unreadByClient': FieldValue.increment(1),
    });

    await batch.commit();
  }

  /// Extract salonId from deterministic conv ID "clientId_salonId"
  String _salonIdFromConv(String convId) {
    final parts = convId.split('_');
    return parts.length > 1 ? parts.sublist(1).join('_') : convId;
  }

  // ── Send auto-reply for outside working hours ──────────────────────────

  static const String _outsideHoursText =
      'Nous sommes actuellement fermés. 🕐\n'
      'Votre message a bien été reçu, nous vous répondrons dès l\'ouverture du salon.';

  Future<void> sendOutsideHoursReply({
    required String convId,
    required String salonId,
  }) async {
    await Future.delayed(const Duration(seconds: 1));

    final batch = _db.batch();

    final msgRef =
        _db.collection('conversations').doc(convId).collection('messages').doc();
    batch.set(msgRef, {
      'senderId': 'bot_$salonId',
      'text': _outsideHoursText,
      'sentAt': FieldValue.serverTimestamp(),
      'isAutoReply': true,
    });

    final convRef = _db.collection('conversations').doc(convId);
    batch.update(convRef, {
      'lastMessage': _outsideHoursText,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'unreadByClient': FieldValue.increment(1),
    });

    await batch.commit();
  }

  // ── Streams ───────────────────────────────────────────────────────────────

  /// All conversations for a client, sorted by most recent.
  Stream<List<ConversationModel>> getClientConversations(String clientId) {
    return _db
        .collection('conversations')
        .where('clientId', isEqualTo: clientId)
        .snapshots()
        .map((snap) {
      final list =
          snap.docs.map((d) => ConversationModel.fromFirestore(d)).toList();
      list.sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
      return list;
    });
  }

  /// All conversations for a salon (owner view), sorted by most recent.
  Stream<List<ConversationModel>> getOwnerConversations(String salonId) {
    return _db
        .collection('conversations')
        .where('salonId', isEqualTo: salonId)
        .snapshots()
        .map((snap) {
      final list =
          snap.docs.map((d) => ConversationModel.fromFirestore(d)).toList();
      list.sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
      return list;
    });
  }

  /// Messages for a conversation, ordered oldest → newest.
  Stream<List<MessageModel>> getMessages(String convId) {
    return _db
        .collection('conversations')
        .doc(convId)
        .collection('messages')
        .orderBy('sentAt')
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => MessageModel.fromFirestore(d)).toList());
  }

  /// Total unread messages for the owner across their salon.
  Stream<int> getOwnerUnreadCount(String salonId) {
    return _db
        .collection('conversations')
        .where('salonId', isEqualTo: salonId)
        .where('unreadByOwner', isGreaterThan: 0)
        .snapshots()
        .map((snap) => snap.docs.fold<int>(
            0, (acc, d) => acc + ((d['unreadByOwner'] ?? 0) as int)));
  }

  /// Total unread messages for a client.
  Stream<int> getClientUnreadCount(String clientId) {
    return _db
        .collection('conversations')
        .where('clientId', isEqualTo: clientId)
        .where('unreadByClient', isGreaterThan: 0)
        .snapshots()
        .map((snap) => snap.docs.fold<int>(
            0, (acc, d) => acc + ((d['unreadByClient'] ?? 0) as int)));
  }

  // ── Mark as read ──────────────────────────────────────────────────────────

  Future<void> markReadByOwner(String convId) async {
    await _db
        .collection('conversations')
        .doc(convId)
        .update({'unreadByOwner': 0});
  }

  Future<void> markReadByClient(String convId) async {
    await _db
        .collection('conversations')
        .doc(convId)
        .update({'unreadByClient': 0});
  }
}
