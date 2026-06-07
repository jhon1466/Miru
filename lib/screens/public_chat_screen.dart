import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../providers/auth_provider.dart' as app_auth;
import '../providers/supporter_provider.dart';
import '../widgets/sticker_picker_sheet.dart';
import '../widgets/fullscreen_image_viewer.dart';
import '../widgets/emoji_reaction_picker.dart';
import '../widgets/reactions_row.dart';
import 'user_profile_screen.dart';

class PublicChatScreen extends StatefulWidget {
  const PublicChatScreen({super.key});

  @override
  State<PublicChatScreen> createState() => _PublicChatScreenState();
}

class _PublicChatScreenState extends State<PublicChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  MessageModel? _replyToMessage;
  bool _isSending = false;
  DateTime? _lastMessageTime;
  int _cooldownRemaining = 0;

  final GlobalKey _targetMessageKey = GlobalKey();
  String? _scrollTargetId;
  String? _highlightedMessageId;

  late final Stream<QuerySnapshot> _chatStream;

  @override
  void initState() {
    super.initState();
    _chatStream = _db
        .collection('public_chat')
        .orderBy('timestamp', descending: true)
        .limit(100)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<app_auth.AuthProvider>(context);
    final currentUserId = authProvider.userId;

    return Scaffold(
      backgroundColor: context.backgroundColor,
      appBar: AppBar(
        title: const Text('Chat Público'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Stream de mensajes
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _chatStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation(Theme.of(context).colorScheme.primary),
                    ),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 64,
                          color: context.textSecondary.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '¡Di hola en el chat público!',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: context.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Los mensajes antiguos se borran de forma automática.',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final docs = snapshot.data!.docs;
                final messages = docs.map((d) => MessageModel.fromFirestore(d)).toList();

                return ListView.builder(
                  controller: _scrollController,
                  reverse: true, // El input está abajo, el chat fluye hacia arriba
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isMe = msg.userId == currentUserId;
                    return Dismissible(
                      key: ValueKey('reply_dismiss_${msg.id}'),
                      direction: DismissDirection.startToEnd,
                      confirmDismiss: (direction) async {
                        setState(() {
                          _replyToMessage = msg;
                        });
                        return false; // Retorna false para que el elemento regrese a su posición original
                      },
                      background: Container(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.only(left: 16),
                        child: CircleAvatar(
                          radius: 18,
                          backgroundColor: context.primaryColor.withValues(alpha: 0.15),
                          child: Icon(
                            Icons.reply,
                            color: context.primaryColor,
                            size: 20,
                          ),
                        ),
                      ),
                      child: _buildMessageItem(context, msg, isMe, messages),
                    );
                  },
                );
              },
            ),
          ),

          // Área de carga
          if (_isSending)
            LinearProgressIndicator(
              valueColor: AlwaysStoppedAnimation(Theme.of(context).colorScheme.primary),
              minHeight: 2,
            ),

          // Panel de responder previo
          if (_replyToMessage != null) _buildReplyPreviewPanel(context),

          // Barra de entrada
          _buildInputBar(context, authProvider),
        ],
      ),
    );
  }

  Widget _buildMessageItem(BuildContext context, MessageModel msg, bool isMe, List<MessageModel> messages) {
    final isSticker = msg.stickerCode != null && msg.stickerCode!.isNotEmpty;
    final isHighlighted = _highlightedMessageId == msg.id;
    
    final bubbleDecoration = isSticker
        ? BoxDecoration(
            color: isHighlighted
                ? context.primaryColor.withValues(alpha: 0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          )
        : BoxDecoration(
            color: isHighlighted
                ? context.primaryColor.withValues(alpha: 0.35)
                : (isMe ? context.primaryColor : context.cardColor),
            borderRadius: BorderRadius.only(
              topLeft: msg.replyToId != null ? Radius.zero : const Radius.circular(16),
              topRight: msg.replyToId != null ? Radius.zero : const Radius.circular(16),
              bottomLeft: const Radius.circular(16),
              bottomRight: const Radius.circular(16),
            ),
            border: Border.all(
              color: isHighlighted
                  ? context.accentColor
                  : (isMe ? context.primaryColor : context.textSecondary.withValues(alpha: 0.1)),
              width: isHighlighted ? 2.0 : 1.0,
            ),
          );

    final bubblePadding = isSticker
        ? EdgeInsets.zero
        : const EdgeInsets.symmetric(horizontal: 14, vertical: 10);

    final key = (msg.id == _scrollTargetId) ? _targetMessageKey : ValueKey(msg.id);

    return Column(
      key: key,
      crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMe) ...[
              GestureDetector(
                onTap: () => _navigateToProfile(context, msg),
                child: _buildAvatar(msg.userAvatar, msg.userName, radius: 18),
              ),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: GestureDetector(
                onLongPress: () => _showMessageActions(context, msg, isMe),
                child: Column(
                  crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    if (!isMe)
                      GestureDetector(
                        onTap: () => _navigateToProfile(context, msg),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (msg.isSupporter) ...[
                              const Text('👑', style: TextStyle(fontSize: 11)),
                              const SizedBox(width: 3),
                            ],
                            Text(
                              msg.userName,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: msg.isSupporter
                                    ? context.supporterColor
                                    : context.textSecondary,
                              ),
                            ),
                            if (msg.isSupporter) ...[
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: context.supporterColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(color: context.supporterColor.withValues(alpha: 0.4), width: 0.5),
                                ),
                                child: Text(
                                  'Supporter',
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w600,
                                    color: context.supporterColor,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    const SizedBox(height: 2),
                    // Si el mensaje es una respuesta, pintar preview
                    if (msg.replyToId != null) ...[
                      GestureDetector(
                        onTap: () => _scrollToMessage(msg.replyToId!, messages),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          margin: const EdgeInsets.only(bottom: 2),
                          decoration: BoxDecoration(
                            color: context.cardColor.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(8),
                              topRight: const Radius.circular(8),
                              bottomLeft: isMe ? const Radius.circular(8) : Radius.zero,
                              bottomRight: isMe ? Radius.zero : const Radius.circular(8),
                            ),
                            border: Border(
                              left: BorderSide(
                                color: isMe ? context.primaryColor : context.accentColor,
                                width: 3,
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '@${msg.replyToName}',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isMe ? context.primaryColor : context.accentColor,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                msg.replyToText ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: context.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    // Cuerpo del mensaje
                    Container(
                      padding: bubblePadding,
                      decoration: bubbleDecoration,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (msg.fileUrl != null && msg.fileUrl!.isNotEmpty) ...[
                            TappableNetworkImage(
                              imageUrl: msg.fileUrl!,
                              heroTag: 'chat_img_${msg.id}',
                              width: isSticker ? 100 : 200,
                              fit: BoxFit.contain,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            if (msg.text.isNotEmpty) const SizedBox(height: 6),
                          ] else if (isSticker) ...[
                            // Sticker de emoji (sin imagen): mostrar emoji grande
                            Text(
                              msg.stickerCode!,
                              style: const TextStyle(fontSize: 56),
                            ),
                            if (msg.text.isNotEmpty) const SizedBox(height: 6),
                          ],
                          if (msg.text.isNotEmpty)
                            Text(
                              msg.text,
                              style: TextStyle(
                                color: isMe ? Colors.white : context.textPrimary,
                                fontSize: 14,
                                height: 1.3,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (msg.reactions.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      ReactionsRow(
                        reactions: msg.reactions,
                        currentUserId: Provider.of<app_auth.AuthProvider>(context, listen: false).userId ?? '',
                        onReactionTapped: (emoji) => _toggleReaction(
                          msg.id,
                          Provider.of<app_auth.AuthProvider>(context, listen: false).userId ?? '',
                          emoji,
                        ),
                      ),
                    ],
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _formatTime(msg.timestamp),
                          style: TextStyle(
                            fontSize: 9,
                            color: context.textSecondary.withValues(alpha: 0.7),
                          ),
                        ),
                        if (msg.isEdited) ...[
                          const SizedBox(width: 4),
                          Text(
                            '• editado',
                            style: TextStyle(
                              fontSize: 9,
                              fontStyle: FontStyle.italic,
                              color: context.textSecondary.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (isMe) ...[
              const SizedBox(width: 8),
              _buildAvatar(msg.userAvatar, msg.userName, radius: 18),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildAvatar(String? photoUrl, String name, {double radius = 16}) {
    if (photoUrl != null && photoUrl.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: CachedNetworkImageProvider(photoUrl),
        backgroundColor: context.cardColor,
      );
    }
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.25),
      child: Text(
        initial,
        style: TextStyle(
          fontSize: radius * 0.9,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildReplyPreviewPanel(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: context.cardColor,
        border: Border(
          top: BorderSide(color: context.textSecondary.withValues(alpha: 0.15)),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.reply, color: context.primaryColor, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Respondiendo a ${_replyToMessage!.userName}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: context.primaryColor,
                  ),
                ),
                Text(
                  _replyToMessage!.text.isNotEmpty
                      ? _replyToMessage!.text
                      : (_replyToMessage!.fileUrl != null ? '📷 Imagen/GIF' : 'Sticker'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() => _replyToMessage = null),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar(BuildContext context, app_auth.AuthProvider authProvider) {
    final supporter = context.watch<SupporterProvider>();
    final maxLength = supporter.maxMessageLength;
    final isCooling = _cooldownRemaining > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: context.cardColor,
        border: Border(
          top: BorderSide(color: context.textSecondary.withValues(alpha: 0.15)),
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isCooling)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.timer_outlined, size: 12, color: context.textSecondary),
                    const SizedBox(width: 4),
                    Text(
                      'Espera $_cooldownRemaining s para enviar otro mensaje',
                      style: TextStyle(fontSize: 11, color: context.textSecondary),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                // Botón adjuntar imagen
                IconButton(
                  icon: Icon(Icons.image, color: context.primaryColor),
                  onPressed: () => _pickAndUploadImage(authProvider),
                ),
                // Botón stickers
                IconButton(
                  icon: Icon(Icons.emoji_emotions, color: context.accentColor),
                  onPressed: () => _pickSticker(authProvider),
                ),
                // Input texto
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: context.backgroundColor,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: context.textSecondary.withValues(alpha: 0.15),
                      ),
                    ),
                    child: TextField(
                      controller: _messageController,
                      maxLines: null,
                      maxLength: maxLength,
                      style: TextStyle(color: context.textPrimary, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Escribe un mensaje...',
                        filled: false,
                        border: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        counterStyle: TextStyle(fontSize: 10, color: context.textSecondary),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Botón enviar
                isCooling
                    ? CircleAvatar(
                        radius: 20,
                        backgroundColor: context.textSecondary.withValues(alpha: 0.1),
                        child: Text(
                          '$_cooldownRemaining',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: context.textSecondary,
                          ),
                        ),
                      )
                    : IconButton(
                        icon: Icon(Icons.send_rounded, color: context.primaryColor),
                        onPressed: () => _sendMessage(authProvider),
                      ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleReaction(String messageId, String userId, String emoji) async {
    if (userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Inicia sesión para reaccionar'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    final ref = _db.collection('public_chat').doc(messageId);
    try {
      await _db.runTransaction((transaction) async {
        final snap = await transaction.get(ref);
        if (!snap.exists) return;

        final data = snap.data() as Map<String, dynamic>? ?? {};
        final reactions = Map<String, String>.from(data['reactions'] is Map ? data['reactions'] : {});

        if (reactions[userId] == emoji) {
          reactions.remove(userId);
        } else {
          reactions[userId] = emoji;
        }

        transaction.update(ref, {'reactions': reactions});
      });
    } catch (e) {
      debugPrint('Error toggling reaction: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo reaccionar: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _sendMessage(
    app_auth.AuthProvider authProvider, {
    String? fileUrl,
    String? stickerCode,
  }) async {
    final text = _messageController.text.trim();
    if (text.isEmpty && fileUrl == null && stickerCode == null) return;

    final supporter = context.read<SupporterProvider>();

    // Cooldown check
    if (!supporter.isSupporter && _lastMessageTime != null) {
      final elapsed = DateTime.now().difference(_lastMessageTime!);
      final cooldown = supporter.messageCooldown;
      if (elapsed < cooldown) {
        final remaining = (cooldown - elapsed).inSeconds + 1;
        _startCooldownTimer(remaining);
        return;
      }
    }

    setState(() => _isSending = true);

    final docRef = _db.collection('public_chat').doc();
    final messageData = {
      'id': docRef.id,
      'userId': authProvider.userId,
      'userName': authProvider.displayName ?? 'Usuario',
      'userAvatar': authProvider.photoUrl,
      'text': text,
      'fileUrl': fileUrl,
      'stickerCode': stickerCode,
      'isEdited': false,
      'isSupporter': supporter.isSupporter,
      'replyToId': _replyToMessage?.id,
      'replyToName': _replyToMessage?.userName,
      'replyToText': _replyToMessage != null
          ? (_replyToMessage!.text.isNotEmpty
              ? _replyToMessage!.text
              : (_replyToMessage!.fileUrl != null ? '📷 Imagen' : 'Sticker'))
          : null,
      'timestamp': FieldValue.serverTimestamp(),
    };

    final messenger = ScaffoldMessenger.of(context);
    final dangerColor = context.dangerColor;

    try {
      await docRef.set(messageData);
      _messageController.clear();
      _lastMessageTime = DateTime.now();
      setState(() {
        _replyToMessage = null;
      });
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Error al enviar mensaje: $e'),
          backgroundColor: dangerColor,
        ),
      );
    } finally {
      setState(() => _isSending = false);
    }
  }

  void _startCooldownTimer(int seconds) {
    setState(() => _cooldownRemaining = seconds);
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _cooldownRemaining--);
      return _cooldownRemaining > 0;
    });
  }

  Future<void> _pickAndUploadImage(
    app_auth.AuthProvider authProvider,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final dangerColor = context.dangerColor;

    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    setState(() => _isSending = true);

    try {
      final docRef = _db.collection('public_chat').doc();
      final extension = picked.path.split('.').last;
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('public_chat/${docRef.id}.$extension');

      final uploadTask = await storageRef.putFile(File(picked.path));
      final fileUrl = await uploadTask.ref.getDownloadURL();

      // Enviar el mensaje con la URL del archivo
      await _sendMessage(authProvider, fileUrl: fileUrl);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Error al subir imagen: $e'),
          backgroundColor: dangerColor,
        ),
      );
      setState(() => _isSending = false);
    }
  }

  Future<void> _pickSticker(
    app_auth.AuthProvider authProvider,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final dangerColor = context.dangerColor;

    final sticker = await StickerPickerSheet.pick(context);
    if (sticker == null) return;

    setState(() => _isSending = true);

    try {
      String? fileUrl;

      // Determinar si filePath es una URL remota o un archivo local real
      final path = sticker.filePath;
      final isRemoteUrl = path.startsWith('http');
      final isLocalFile = !isRemoteUrl && await File(path).exists();

      if (isRemoteUrl) {
        fileUrl = path;
      } else if (isLocalFile) {
        // Sticker local: subir a Firebase Storage
        final docRef = _db.collection('public_chat').doc();
        final extension = path.split('.').last;
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('public_chat/${docRef.id}.$extension');
        final uploadTask = await storageRef.putFile(File(path));
        fileUrl = await uploadTask.ref.getDownloadURL();
      }
      // Si no es URL ni archivo real (p.ej. emoji como 👑), se envía solo stickerCode

      // Para stickers emoji (sin archivo real) usar filePath (el emoji) como
      // stickerCode para que el renderer lo muestre directamente.
      final stickerCode = (fileUrl == null && !sticker.filePath.startsWith('http'))
          ? sticker.filePath   // '🔥', '👑', etc.
          : sticker.id;

      await _sendMessage(
        authProvider,
        fileUrl: fileUrl,
        stickerCode: stickerCode,
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Error al subir sticker: $e'),
          backgroundColor: dangerColor,
        ),
      );
      setState(() => _isSending = false);
    }
  }

  void _showMessageActions(BuildContext context, MessageModel msg, bool isMe) {
    final currentUid = Provider.of<app_auth.AuthProvider>(context, listen: false).userId ?? '';
    showModalBottomSheet(
      context: context,
      backgroundColor: context.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    ...['👍', '❤️', '😂', '😮', '😢', '🙏'].map((emoji) {
                      final hasReacted = msg.reactions[currentUid] == emoji;
                      return GestureDetector(
                        onTap: () {
                          Navigator.pop(ctx);
                          _toggleReaction(msg.id, currentUid, emoji);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: hasReacted
                                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(emoji, style: const TextStyle(fontSize: 24)),
                        ),
                      );
                    }),
                    GestureDetector(
                      onTap: () async {
                        Navigator.pop(ctx);
                        final selectedEmoji = await EmojiReactionPicker.show(context);
                        if (selectedEmoji != null) {
                          _toggleReaction(msg.id, currentUid, selectedEmoji);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: context.textSecondary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.add, color: context.textPrimary, size: 22),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.reply),
                title: const Text('Responder'),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _replyToMessage = msg;
                  });
                },
              ),
              if (isMe) ...[
                ListTile(
                  leading: const Icon(Icons.edit, color: Colors.amber),
                  title: const Text('Editar mensaje'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showEditDialog(context, msg);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.delete, color: context.dangerColor),
                  title: Text('Eliminar mensaje', style: TextStyle(color: context.dangerColor)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final delete = await _showConfirmDeleteDialog(context);
                    if (delete == true) {
                      await _db.collection('public_chat').doc(msg.id).delete();
                    }
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  void _showEditDialog(BuildContext context, MessageModel msg) {
    final controller = TextEditingController(text: msg.text);
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: context.cardColor,
          title: Text(
            'Editar mensaje',
            style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold),
          ),
          content: TextField(
            controller: controller,
            maxLines: null,
            style: TextStyle(color: context.textPrimary),
            decoration: const InputDecoration(
              hintText: 'Edita tu mensaje...',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancelar', style: TextStyle(color: context.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () async {
                final newText = controller.text.trim();
                if (newText.isNotEmpty) {
                  await _db.collection('public_chat').doc(msg.id).update({
                    'text': newText,
                    'isEdited': true,
                  });
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(backgroundColor: context.primaryColor),
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );
  }

  Future<bool?> _showConfirmDeleteDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.cardColor,
        title: Text('Eliminar mensaje', style: TextStyle(color: context.textPrimary)),
        content: Text(
          '¿Estás seguro de que deseas eliminar este mensaje? Esta acción no se puede deshacer.',
          style: TextStyle(color: context.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar', style: TextStyle(color: context.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Eliminar', style: TextStyle(color: context.dangerColor)),
          ),
        ],
      ),
    );
  }

  void _navigateToProfile(BuildContext context, MessageModel msg) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserProfileScreen(
          userId: msg.userId,
          displayName: msg.userName,
          photoUrl: msg.userAvatar,
        ),
      ),
    );
  }

  void _scrollToMessage(String targetId, List<MessageModel> messages) {
    final targetIndex = messages.indexWhere((m) => m.id == targetId);
    if (targetIndex == -1) return;

    setState(() {
      _scrollTargetId = targetId;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      
      final targetContext = _targetMessageKey.currentContext;
      if (targetContext != null) {
        Scrollable.ensureVisible(
          targetContext,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
        _highlightMessage(targetId);
      } else {
        final double avgHeight = 90.0;
        final double targetOffset = targetIndex * avgHeight;
        _scrollController.animateTo(
          targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        ).then((_) {
          Future.delayed(const Duration(milliseconds: 100), () {
            if (!mounted) return;
            final preciseContext = _targetMessageKey.currentContext;
            if (preciseContext != null && preciseContext.mounted) {
              Scrollable.ensureVisible(
                preciseContext,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
              );
            }
            _highlightMessage(targetId);
          });
        });
      }
    });
  }

  void _highlightMessage(String targetId) {
    setState(() {
      _highlightedMessageId = targetId;
      _scrollTargetId = null; // Revert target back to standard ValueKey
    });
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && _highlightedMessageId == targetId) {
        setState(() {
          _highlightedMessageId = null;
        });
      }
    });
  }

  String _formatTime(DateTime? date) {
    if (date == null) return '';
    final hour = date.hour.toString().padLeft(2, '0');
    final min = date.minute.toString().padLeft(2, '0');
    return '$hour:$min';
  }
}

class MessageModel {
  final String id;
  final String userId;
  final String userName;
  final String? userAvatar;
  final String text;
  final String? fileUrl;
  final String? stickerCode;
  final bool isEdited;
  final String? replyToId;
  final String? replyToName;
  final String? replyToText;
  final DateTime? timestamp;
  final Map<String, String> reactions;
  final bool isSupporter;

  MessageModel({
    required this.id,
    required this.userId,
    required this.userName,
    this.userAvatar,
    required this.text,
    this.fileUrl,
    this.stickerCode,
    required this.isEdited,
    this.replyToId,
    this.replyToName,
    this.replyToText,
    this.timestamp,
    required this.reactions,
    this.isSupporter = false,
  });

  factory MessageModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return MessageModel(
      id: data['id']?.toString() ?? '',
      userId: data['userId']?.toString() ?? '',
      userName: data['userName']?.toString() ?? 'Usuario',
      userAvatar: data['userAvatar']?.toString(),
      text: data['text']?.toString() ?? '',
      fileUrl: data['fileUrl']?.toString(),
      stickerCode: data['stickerCode']?.toString(),
      isEdited: data['isEdited'] == true,
      replyToId: data['replyToId']?.toString(),
      replyToName: data['replyToName']?.toString(),
      replyToText: data['replyToText']?.toString(),
      timestamp: (data['timestamp'] as Timestamp?)?.toDate(),
      reactions: Map<String, String>.from(data['reactions'] is Map ? data['reactions'] : {}),
      isSupporter: data['isSupporter'] == true,
    );
  }
}
