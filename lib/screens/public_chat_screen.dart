import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../providers/auth_provider.dart' as app_auth;
import '../widgets/sticker_picker_sheet.dart';
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
                  return const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor),
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
                    return _buildMessageItem(context, msg, isMe, messages);
                  },
                );
              },
            ),
          ),

          // Área de carga
          if (_isSending)
            const LinearProgressIndicator(
              valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor),
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
                        child: Text(
                          msg.userName,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: context.textSecondary,
                          ),
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
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: CachedNetworkImage(
                                imageUrl: msg.fileUrl!,
                                width: isSticker ? 100 : 200,
                                fit: BoxFit.contain,
                                placeholder: (context, url) => const SizedBox(
                                  width: 100,
                                  height: 100,
                                  child: Center(
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                ),
                                errorWidget: (context, url, error) => const Icon(Icons.broken_image),
                              ),
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
      backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.25),
      child: Text(
        initial,
        style: TextStyle(
          fontSize: radius * 0.9,
          fontWeight: FontWeight.bold,
          color: AppTheme.primaryColor,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: context.cardColor,
        border: Border(
          top: BorderSide(color: context.textSecondary.withValues(alpha: 0.15)),
        ),
      ),
      child: SafeArea(
        child: Row(
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
                  style: TextStyle(color: context.textPrimary, fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: 'Escribe un mensaje...',
                    filled: false,
                    border: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Botón enviar
            IconButton(
              icon: Icon(Icons.send_rounded, color: context.primaryColor),
              onPressed: () => _sendMessage(authProvider),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendMessage(
    app_auth.AuthProvider authProvider, {
    String? fileUrl,
    String? stickerCode,
  }) async {
    final text = _messageController.text.trim();
    if (text.isEmpty && fileUrl == null && stickerCode == null) return;

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
      String fileUrl = sticker.filePath;

      // Si el sticker está local, subirlo primero
      if (!sticker.filePath.startsWith('http')) {
        final docRef = _db.collection('public_chat').doc();
        final extension = sticker.filePath.split('.').last;
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('public_chat/${docRef.id}.$extension');

        final uploadTask = await storageRef.putFile(File(sticker.filePath));
        fileUrl = await uploadTask.ref.getDownloadURL();
      }

      await _sendMessage(
        authProvider,
        fileUrl: fileUrl,
        stickerCode: sticker.id,
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
    );
  }
}
