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
    String langCode = 'fr',
    String? imageUrl,
    String type = 'text',
    Map<String, dynamic>? extraData,
  }) async {
    final batch = _db.batch();

    // Add message to subcollection
    final msgRef =
        _db.collection('conversations').doc(convId).collection('messages').doc();
    final msgData = <String, dynamic>{
      'senderId': senderId,
      'text': text.trim(),
      'sentAt': FieldValue.serverTimestamp(),
      'type': type,
    };
    if (imageUrl != null) msgData['imageUrl'] = imageUrl;
    if (extraData != null) msgData.addAll(extraData);
    batch.set(msgRef, msgData);

    // Update conversation metadata
    final lastPreview = type == 'custom_request'
        ? '📷 Demande personnalisée'
        : type == 'image'
            ? '📷 Photo'
            : text.trim();
    final convRef = _db.collection('conversations').doc(convId);
    batch.update(convRef, {
      'lastMessage': lastPreview,
      'lastMessageAt': FieldValue.serverTimestamp(),
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
        await _sendAutoReply(convId: convId, salonId: _salonIdFromConv(convId), langCode: langCode);
      }
    }
  }

  // ── Auto-reply helper ───────────────────────────────────────────────────

  static String _autoReplyText(String langCode) {
    if (langCode == 'en') {
      return 'Thank you for your message! ✨\n'
          'An advisor will get back to you shortly.\n'
          'In the meantime, feel free to browse our services and book directly online.';
    }
    return 'Merci pour votre message ! ✨\n'
        'Un conseiller vous répondra dans les plus brefs délais.\n'
        'En attendant, n\'hésitez pas à consulter nos services et réserver directement en ligne.';
  }

  Future<void> _sendAutoReply({
    required String convId,
    required String salonId,
    String langCode = 'fr',
  }) async {
    // Small delay so the auto-reply appears after the client message
    await Future.delayed(const Duration(seconds: 1));

    final text = _autoReplyText(langCode);
    final batch = _db.batch();

    final msgRef =
        _db.collection('conversations').doc(convId).collection('messages').doc();
    batch.set(msgRef, {
      'senderId': 'bot_$salonId',
      'text': text,
      'sentAt': FieldValue.serverTimestamp(),
      'isAutoReply': true,
    });

    final convRef = _db.collection('conversations').doc(convId);
    batch.update(convRef, {
      'lastMessage': text,
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

  static String _outsideHoursText(String langCode) {
    if (langCode == 'en') {
      return 'We are currently closed. 🕐\n'
          'Your message has been received, we will reply when the salon opens.';
    }
    return 'Nous sommes actuellement fermés. 🕐\n'
        'Votre message a bien été reçu, nous vous répondrons dès l\'ouverture du salon.';
  }

  Future<void> sendOutsideHoursReply({
    required String convId,
    required String salonId,
    String langCode = 'fr',
  }) async {
    await Future.delayed(const Duration(seconds: 1));

    final text = _outsideHoursText(langCode);
    final batch = _db.batch();

    final msgRef =
        _db.collection('conversations').doc(convId).collection('messages').doc();
    batch.set(msgRef, {
      'senderId': 'bot_$salonId',
      'text': text,
      'sentAt': FieldValue.serverTimestamp(),
      'isAutoReply': true,
    });

    final convRef = _db.collection('conversations').doc(convId);
    batch.update(convRef, {
      'lastMessage': text,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'unreadByClient': FieldValue.increment(1),
    });

    await batch.commit();
  }

  // ── Streams ───────────────────────────────────────────────────────────────

  /// Max conversations / messages fetched per stream. UI shows "Load older"
  /// to paginate beyond this window.
  static const int _conversationsLimit = 50;
  static const int _messagesLimit = 50;

  /// 50 most recent conversations for a client.
  /// Requires composite index (clientId ASC, lastMessageAt DESC).
  Stream<List<ConversationModel>> getClientConversations(String clientId) {
    return _db
        .collection('conversations')
        .where('clientId', isEqualTo: clientId)
        .orderBy('lastMessageAt', descending: true)
        .limit(_conversationsLimit)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => ConversationModel.fromFirestore(d)).toList());
  }

  /// 50 most recent conversations for a salon (owner view).
  /// Filter by ownerId (not salonId) so the Firestore rule
  /// `read if resource.data.ownerId == request.auth.uid` can validate the
  /// query is safe. `salonId == ownerId` by convention (salon doc id = owner uid).
  /// Requires composite index (ownerId ASC, lastMessageAt DESC).
  Stream<List<ConversationModel>> getOwnerConversations(String ownerId) {
    return _db
        .collection('conversations')
        .where('ownerId', isEqualTo: ownerId)
        .orderBy('lastMessageAt', descending: true)
        .limit(_conversationsLimit)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => ConversationModel.fromFirestore(d)).toList());
  }

  /// 50 most recent messages for a conversation, returned oldest → newest.
  Stream<List<MessageModel>> getMessages(String convId) {
    return _db
        .collection('conversations')
        .doc(convId)
        .collection('messages')
        .orderBy('sentAt', descending: true)
        .limit(_messagesLimit)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => MessageModel.fromFirestore(d))
            .toList()
            .reversed
            .toList());
  }

  /// Fetch [_messagesLimit] older messages BEFORE [olderThan] (sentAt cursor).
  /// One-shot (no stream). Used by chat screen's "Load older" UI. Returns
  /// messages oldest → newest. Empty list = no more history.
  Future<List<MessageModel>> getOlderMessages(
    String convId,
    DateTime olderThan,
  ) async {
    final snap = await _db
        .collection('conversations')
        .doc(convId)
        .collection('messages')
        .where('sentAt', isLessThan: Timestamp.fromDate(olderThan))
        .orderBy('sentAt', descending: true)
        .limit(_messagesLimit)
        .get();
    return snap.docs
        .map((d) => MessageModel.fromFirestore(d))
        .toList()
        .reversed
        .toList();
  }

  /// Total unread messages for the owner across their salon.
  /// Filter by ownerId so the rule can validate. Requires composite index
  /// (ownerId ASC, unreadByOwner ASC) — Firestore will prompt a create link
  /// in the console on first call.
  Stream<int> getOwnerUnreadCount(String ownerId) {
    return _db
        .collection('conversations')
        .where('ownerId', isEqualTo: ownerId)
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

  // ── Update custom request status ──────────────────────────────────────────

  Future<void> updateCustomRequest({
    required String convId,
    required String messageId,
    required String status, // 'approved' or 'rejected'
    double? proposedPrice,
    int? proposedDuration,
    String? ownerResponse,
    String? proposedServiceName,
  }) async {
    final data = <String, dynamic>{
      'customRequestStatus': status,
    };
    if (proposedPrice != null) data['proposedPrice'] = proposedPrice;
    if (proposedDuration != null) data['proposedDuration'] = proposedDuration;
    if (ownerResponse != null) data['ownerResponse'] = ownerResponse;
    if (proposedServiceName != null) data['proposedServiceName'] = proposedServiceName;

    await _db
        .collection('conversations')
        .doc(convId)
        .collection('messages')
        .doc(messageId)
        .update(data);
  }
}
