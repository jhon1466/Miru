import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import '../core/theme.dart';
import '../models/comment.dart';
import '../providers/auth_provider.dart' as app_auth;
import '../services/comment_service.dart';
import '../models/sticker.dart';
import '../services/comment_image_service.dart';
import '../services/sticker_service.dart';
import '../services/user_service.dart';
import 'sticker_picker_sheet.dart';
import 'emoji_reaction_picker.dart';
import 'reactions_row.dart';
import '../screens/user_profile_screen.dart';
import '../utils/auth_ui.dart';
import 'fullscreen_image_viewer.dart';

class CommentsSection extends StatefulWidget {
  final String animeSlug;
  final String animeTitle;
  final String? animeUrl;
  final String? episodeUrl;
  final double? episodeNumber;
  final String? focusCommentId;
  final GlobalKey? sectionKey;

  const CommentsSection({
    super.key,
    required this.animeSlug,
    required this.animeTitle,
    this.animeUrl,
    this.episodeUrl,
    this.episodeNumber,
    this.focusCommentId,
    this.sectionKey,
  });

  @override
  State<CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends State<CommentsSection> {
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  final Map<String, GlobalKey> _commentKeys = {};
  bool _isSending = false;
  bool _didScrollToFocus = false;
  XFile? _pendingImage;
  StickerItem? _pendingSticker;
  Comment? _replyTarget;
  Comment? _replyRoot;

  late Stream<List<Comment>> _commentsStream;

  @override
  void initState() {
    super.initState();
    _commentsStream = CommentService.getComments(
      widget.animeSlug,
      episodeNumber: widget.episodeNumber,
    );
  }

  @override
  void didUpdateWidget(covariant CommentsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animeSlug != widget.animeSlug ||
        oldWidget.episodeNumber != widget.episodeNumber) {
      _commentsStream = CommentService.getComments(
        widget.animeSlug,
        episodeNumber: widget.episodeNumber,
      );
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  GlobalKey _keyFor(String id) => _commentKeys.putIfAbsent(id, () => GlobalKey());

  void _scrollToFocusOnce(List<Comment> comments) {
    final id = widget.focusCommentId;
    if (_didScrollToFocus || id == null || id.isEmpty) return;
    _didScrollToFocus = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final key = _commentKeys[id];
      final ctx = key?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeInOut,
          alignment: 0.25,
        );
      }
    });
  }

  Future<void> _sendComment(app_auth.AuthProvider auth) async {
    final text = _commentController.text.trim();
    if ((text.isEmpty && _pendingImage == null && _pendingSticker == null) || !auth.isLoggedIn) {
      return;
    }

    setState(() => _isSending = true);
    try {
      String? imageUrl;
      String? stickerUrl;
      if (_pendingImage != null) {
        imageUrl = await CommentImageService.uploadCompressed(
          animeSlug: widget.animeSlug,
          file: _pendingImage!,
        );
      }
      if (_pendingSticker != null) {
        if (_pendingSticker!.filePath.startsWith('http')) {
          stickerUrl = _pendingSticker!.filePath;
        } else {
          stickerUrl = await StickerService.uploadForComment(
            animeSlug: widget.animeSlug,
            file: File(_pendingSticker!.filePath),
          );
        }
      }

      final parent = _replyRoot;
      final messageText = text.isEmpty
          ? (stickerUrl != null ? '🎭' : '📷 Imagen')
          : text;

      await CommentService.addComment(
        animeSlug: widget.animeSlug,
        animeTitle: widget.animeTitle,
        animeUrl: widget.animeUrl,
        userId: auth.userId!,
        userDisplayName: auth.displayName ?? 'Usuario',
        userPhotoUrl: auth.photoUrl,
        text: messageText,
        imageUrl: imageUrl,
        stickerUrl: stickerUrl,
        episodeNumber: widget.episodeNumber,
        episodeUrl: widget.episodeUrl,
        parentId: parent?.id,
        replyToUserId: _replyTarget?.userId,
        replyToUserName: _replyTarget?.userDisplayName,
      );

      _commentController.clear();
      setState(() {
        _pendingImage = null;
        _pendingSticker = null;
        _replyTarget = null;
        _replyRoot = null;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al enviar: $e'), backgroundColor: AppTheme.dangerColor),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _pickImage() async {
    final file = await CommentImageService.pickImage();
    if (file != null && mounted) setState(() => _pendingImage = file);
  }

  Future<void> _pickSticker() async {
    final sticker = await StickerPickerSheet.pick(context);
    if (sticker != null && mounted) {
      setState(() {
        _pendingSticker = sticker;
        _pendingImage = null;
      });
    }
  }

  void _startReply(Comment target, Comment? root) {
    _replyTarget = target;
    _replyRoot = root ?? target;
    _commentController.text = '@${target.userDisplayName} ';
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _inputFocus.requestFocus();
    });
  }

  void _cancelReply() {
    setState(() {
      _replyTarget = null;
      _replyRoot = null;
    });
  }

  Future<void> _editComment(Comment comment, app_auth.AuthProvider auth) async {
    final textCtrl = TextEditingController(text: comment.text);
    XFile? newImage;
    var removeImage = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          backgroundColor: context.cardColor,
          title: const Text('Editar comentario', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: textCtrl,
                  maxLines: 4,
                  style: TextStyle(color: context.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Mensaje',
                    hintStyle: TextStyle(color: context.textSecondary),
                  ),
                ),
                if (comment.imageUrl != null && !removeImage) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(imageUrl: comment.imageUrl!, height: 120, fit: BoxFit.cover),
                  ),
                  TextButton(
                    onPressed: () => setDialog(() => removeImage = true),
                    child: Text('Quitar imagen', style: TextStyle(color: AppTheme.dangerColor)),
                  ),
                ],
                TextButton.icon(
                  onPressed: () async {
                    final picked = await CommentImageService.pickImage();
                    if (picked != null) setDialog(() => newImage = picked);
                  },
                  icon: Icon(Icons.image_outlined, color: AppTheme.primaryColor),
                  label: Text('Cambiar imagen', style: TextStyle(color: AppTheme.primaryColor)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
          ],
        ),
      ),
    );

    if (saved != true) return;

    String? imageUrl = comment.imageUrl;
    if (removeImage) {
      await CommentImageService.deleteIfOwned(comment.imageUrl);
      imageUrl = null;
    } else if (newImage != null) {
      await CommentImageService.deleteIfOwned(comment.imageUrl);
      imageUrl = await CommentImageService.uploadCompressed(
        animeSlug: widget.animeSlug,
        file: newImage!,
      );
    }

    await CommentService.updateComment(
      animeSlug: widget.animeSlug,
      commentId: comment.id,
      userId: auth.userId!,
      text: textCtrl.text,
      imageUrl: imageUrl,
      removeImage: removeImage && newImage == null,
    );
  }

  Future<void> _deleteComment(Comment comment, app_auth.AuthProvider auth) async {
    if (auth.userId != comment.userId) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.cardColor,
        title: const Text('Eliminar', style: TextStyle(color: Colors.white)),
        content: Text('¿Eliminar este comentario?', style: TextStyle(color: context.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Sí', style: TextStyle(color: AppTheme.dangerColor)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await CommentImageService.deleteIfOwned(comment.imageUrl);
      await CommentService.deleteComment(widget.animeSlug, comment.id);
    }
  }

  void _showCommentActions(
    BuildContext context,
    Comment comment,
    app_auth.AuthProvider auth,
    bool isReply,
    Comment? root,
  ) {
    if (!auth.isLoggedIn) return;

    final currentUid = auth.userId ?? '';
    final isOwner = comment.userId == currentUid;

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
                      final hasReacted = comment.reactions[currentUid] == emoji;
                      return GestureDetector(
                        onTap: () {
                          Navigator.pop(ctx);
                          CommentService.toggleReaction(
                            animeSlug: widget.animeSlug,
                            commentId: comment.id,
                            userId: currentUid,
                            emoji: emoji,
                          );
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: hasReacted
                                ? AppTheme.primaryColor.withValues(alpha: 0.15)
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
                          CommentService.toggleReaction(
                            animeSlug: widget.animeSlug,
                            commentId: comment.id,
                            userId: currentUid,
                            emoji: selectedEmoji,
                          );
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
                  _startReply(comment, isReply ? root : comment);
                },
              ),
              if (comment.text.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.copy),
                  title: const Text('Copiar texto'),
                  onTap: () {
                    Navigator.pop(ctx);
                    Clipboard.setData(ClipboardData(text: comment.text));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Texto copiado'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),
              if (isOwner) ...[
                ListTile(
                  leading: const Icon(Icons.edit, color: Colors.amber),
                  title: const Text('Editar comentario'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _editComment(comment, auth);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.delete, color: context.dangerColor),
                  title: Text('Eliminar comentario', style: TextStyle(color: context.dangerColor)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _deleteComment(comment, auth);
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  List<Comment> _roots(List<Comment> all) =>
      all.where((c) => c.parentId == null || c.parentId!.isEmpty).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  List<Comment> _repliesFor(String parentId, List<Comment> all) =>
      all.where((c) => c.parentId == parentId).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<app_auth.AuthProvider>(context);
    final label = widget.episodeNumber != null
        ? 'Comentarios del Episodio ${widget.episodeNumber!.toInt()}'
        : 'Comentarios del Anime';

    return Container(
      key: widget.sectionKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.chat_bubble_outline, color: AppTheme.primaryColor, size: 20),
                const SizedBox(width: 8),
                Text(label, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimary)),
              ],
            ),
          ),
          Divider(color: context.cardColor, height: 1),
          const SizedBox(height: 12),
          StreamBuilder<List<Comment>>(
            stream: _commentsStream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor))),
                );
              }
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text('Error: ${snapshot.error}', style: TextStyle(color: AppTheme.dangerColor)),
                );
              }

              final all = snapshot.data ?? [];
              _scrollToFocusOnce(all);
              final roots = _roots(all);

              if (roots.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: Text('Sé el primero en comentar', style: TextStyle(color: context.textSecondary))),
                );
              }

              return Column(
                children: roots.map((root) {
                  final replies = _repliesFor(root.id, all);
                  return Column(
                    key: ValueKey('group_${root.id}'),
                    children: [
                      _tile(root, auth, isReply: false),
                      ...replies.map((r) => Padding(
                            key: ValueKey('padding_${r.id}'),
                            padding: const EdgeInsets.only(left: 36),
                            child: _tile(r, auth, isReply: true, root: root),
                          )),
                    ],
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: auth.isLoggedIn ? _buildInput(auth) : _buildLoginPrompt(auth),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildInput(app_auth.AuthProvider auth) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _replyTarget != null
                ? Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Respondiendo a ${_replyTarget!.userDisplayName}',
                          style: TextStyle(color: AppTheme.primaryColor, fontSize: 12),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, size: 18, color: context.textSecondary),
                        onPressed: _cancelReply,
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
          if (_pendingImage != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(File(_pendingImage!.path), height: 100, fit: BoxFit.cover),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                icon: Icon(Icons.close, color: AppTheme.dangerColor, size: 20),
                onPressed: () => setState(() => _pendingImage = null),
              ),
            ),
          ],
          if (_pendingSticker != null) ...[
            SizedBox(
              height: 96,
              width: 96,
              child: _pendingSticker!.filePath.startsWith('http')
                  ? CachedNetworkImage(
                      imageUrl: _pendingSticker!.filePath,
                      fit: BoxFit.contain,
                      placeholder: (_, __) => const SizedBox(
                        width: 24,
                        height: 24,
                        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                    )
                  : Image.file(
                      File(_pendingSticker!.filePath),
                      fit: BoxFit.contain,
                    ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                icon: Icon(Icons.close, color: AppTheme.dangerColor, size: 20),
                onPressed: () => setState(() => _pendingSticker = null),
              ),
            ),
          ],
          TextField(
            controller: _commentController,
            focusNode: _inputFocus,
            style: TextStyle(color: context.textPrimary, fontSize: 14),
            maxLines: 3,
            minLines: 1,
            maxLength: 500,
            scrollPadding: const EdgeInsets.only(bottom: 24),
            textInputAction: TextInputAction.send,
            onSubmitted: (_) {
              if (!_isSending) _sendComment(auth);
            },
            decoration: InputDecoration(
              hintText: 'Escribe tu comentario...',
              hintStyle: TextStyle(color: context.textSecondary),
              border: InputBorder.none,
              counterStyle: TextStyle(color: context.textSecondary, fontSize: 10),
            ),
          ),
          Row(
            children: [
              IconButton(
                onPressed: _isSending ? null : _pickSticker,
                icon: Icon(Icons.emoji_emotions_outlined, color: AppTheme.accentColor),
                tooltip: 'Sticker',
              ),
              IconButton(
                onPressed: _isSending ? null : _pickImage,
                icon: Icon(Icons.image_outlined, color: AppTheme.primaryColor),
                tooltip: 'Adjuntar imagen',
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _isSending ? null : () => _sendComment(auth),
                icon: _isSending
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded, size: 16),
                label: Text(_replyTarget != null ? 'Responder' : 'Publicar', style: const TextStyle(fontSize: 13)),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tile(Comment comment, app_auth.AuthProvider auth, {required bool isReply, Comment? root}) {
    final isOwner = auth.userId == comment.userId;
    final isFocused = widget.focusCommentId == comment.id;
    final key = _keyFor(comment.id);

    return StreamBuilder<UserProfile?>(
      key: key,
      stream: UserService.profileStream(comment.userId),
      builder: (context, authorSnap) {
        final authorProfile = authorSnap.data;
        final displayName = authorProfile?.displayName ?? comment.userDisplayName;
        final photoUrl = authorProfile?.photoUrl ?? comment.userPhotoUrl;
        final liveComment = comment.withAuthor(displayName: displayName, photoUrl: photoUrl);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => UserProfileScreen(
                      userId: liveComment.userId,
                      displayName: displayName,
                      photoUrl: photoUrl,
                    ),
                  ),
                ),
                child: _avatar(photoUrl, displayName),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onLongPress: () => _showCommentActions(context, liveComment, auth, isReply, root),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.cardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: isFocused ? Border.all(color: AppTheme.accentColor, width: 2) : null,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                displayName,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: AppTheme.primaryColor,
                                ),
                              ),
                            ),
                            Text(
                              _timeAgo(liveComment.createdAt),
                              style: TextStyle(fontSize: 10, color: context.textSecondary),
                            ),
                            if (liveComment.wasEdited)
                              Text(' · editado', style: TextStyle(fontSize: 10, color: context.textSecondary)),
                            if (isOwner) ...[
                              const SizedBox(width: 6),
                              PopupMenuButton<String>(
                                icon: Icon(Icons.more_vert, size: 16, color: context.textSecondary),
                                padding: EdgeInsets.zero,
                                iconSize: 16,
                                onSelected: (value) {
                                  if (value == 'edit') {
                                    _editComment(liveComment, auth);
                                  } else if (value == 'delete') {
                                    _deleteComment(liveComment, auth);
                                  }
                                },
                                itemBuilder: (context) => [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Row(
                                      children: [
                                        Icon(Icons.edit, size: 16, color: context.textPrimary),
                                        const SizedBox(width: 8),
                                        const Text('Editar', style: TextStyle(fontSize: 13)),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete, size: 16, color: AppTheme.dangerColor),
                                        const SizedBox(width: 8),
                                        Text('Eliminar', style: TextStyle(fontSize: 13, color: AppTheme.dangerColor)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                        if (isReply && liveComment.replyToUserId != null)
                          StreamBuilder<UserProfile?>(
                            stream: UserService.profileStream(liveComment.replyToUserId!),
                            builder: (context, replySnap) {
                              final replyName =
                                  replySnap.data?.displayName ?? liveComment.replyToUserName ?? 'Usuario';
                              return Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  '→ $replyName',
                                  style: TextStyle(fontSize: 11, color: AppTheme.accentColor),
                                ),
                              );
                            },
                          )
                        else if (isReply && liveComment.replyToUserName != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              '→ ${liveComment.replyToUserName}',
                              style: TextStyle(fontSize: 11, color: AppTheme.accentColor),
                            ),
                          ),
                        if (liveComment.text.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            liveComment.text,
                            style: TextStyle(fontSize: 14, color: context.textPrimary, height: 1.4),
                          ),
                        ],
                        if (liveComment.hasSticker) ...[
                          const SizedBox(height: 8),
                          TappableNetworkImage(
                            imageUrl: liveComment.stickerUrl!,
                            heroTag: 'comment_sticker_${liveComment.id}',
                            width: 120,
                            height: 120,
                            fit: BoxFit.contain,
                          ),
                        ],
                        if (liveComment.imageUrl != null && liveComment.imageUrl!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          TappableNetworkImage(
                            imageUrl: liveComment.imageUrl!,
                            heroTag: 'comment_img_${liveComment.id}',
                            fit: BoxFit.cover,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ],
                        if (liveComment.reactions.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          ReactionsRow(
                            reactions: liveComment.reactions,
                            currentUserId: auth.userId ?? '',
                            onReactionTapped: (emoji) => CommentService.toggleReaction(
                              animeSlug: widget.animeSlug,
                              commentId: liveComment.id,
                              userId: auth.userId ?? '',
                              emoji: emoji,
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            if (liveComment.text.isNotEmpty)
                              TextButton(
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: liveComment.text));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Texto copiado'),
                                      duration: Duration(seconds: 1),
                                    ),
                                  );
                                },
                                child: const Text('Copiar', style: TextStyle(fontSize: 12)),
                              ),
                            TextButton(
                              onPressed: auth.isLoggedIn
                                  ? () => _startReply(liveComment, isReply ? root : liveComment)
                                  : null,
                              child: const Text('Responder', style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _avatar(String? photo, String name) {
    if (photo != null && photo.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(imageUrl: photo, width: 32, height: 32, fit: BoxFit.cover),
      );
    }
    return CircleAvatar(
      radius: 16,
      child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(fontSize: 12)),
    );
  }

  Widget _buildLoginPrompt(app_auth.AuthProvider auth) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: context.cardColor, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Expanded(child: Text('Inicia sesión para comentar', style: TextStyle(color: context.textSecondary))),
          ElevatedButton(
            onPressed: () => signInWithGoogleAndWelcome(context, auth),
            child: const Text('Entrar'),
          ),
        ],
      ),
    );
  }

  String _timeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'Ahora';
    if (diff.inHours < 1) return 'hace ${diff.inMinutes}m';
    if (diff.inDays < 1) return 'hace ${diff.inHours}h';
    if (diff.inDays < 7) return 'hace ${diff.inDays}d';
    return '${date.day}/${date.month}/${date.year}';
  }
}
