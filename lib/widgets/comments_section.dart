import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/theme.dart';
import '../models/comment.dart';
import '../providers/auth_provider.dart' as app_auth;
import '../services/comment_service.dart';
import '../screens/user_profile_screen.dart';
import 'dart:math' as math;

/// Widget reutilizable de comentarios. Funciona tanto para el anime general
/// (episodeNumber == null) como para un episodio específico.
class CommentsSection extends StatefulWidget {
  final String animeSlug;
  final String animeTitle;
  final double? episodeNumber;

  const CommentsSection({
    super.key,
    required this.animeSlug,
    required this.animeTitle,
    this.episodeNumber,
  });

  @override
  State<CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends State<CommentsSection> {
  final TextEditingController _commentController = TextEditingController();
  bool _isSending = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _sendComment(app_auth.AuthProvider authProvider) async {
    final text = _commentController.text.trim();
    if (text.isEmpty || !authProvider.isLoggedIn) return;

    setState(() => _isSending = true);

    try {
      await CommentService.addComment(
        animeSlug: widget.animeSlug,
        userId: authProvider.userId!,
        userDisplayName: authProvider.displayName ?? 'Usuario',
        userPhotoUrl: authProvider.photoUrl,
        text: text,
        episodeNumber: widget.episodeNumber,
      );
      _commentController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al enviar comentario: $e'),
            backgroundColor: AppTheme.dangerColor,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _deleteComment(String commentId, String commentUserId, app_auth.AuthProvider authProvider) async {
    if (!authProvider.isLoggedIn || authProvider.userId != commentUserId) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        title: const Text('Eliminar comentario', style: TextStyle(color: Colors.white)),
        content: const Text('¿Estás seguro de que deseas eliminar este comentario?',
            style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar', style: TextStyle(color: AppTheme.dangerColor)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await CommentService.deleteComment(widget.animeSlug, commentId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<app_auth.AuthProvider>(context);
    final label = widget.episodeNumber != null
        ? 'Comentarios del Episodio ${widget.episodeNumber!.toInt()}'
        : 'Comentarios del Anime';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.chat_bubble_outline, color: AppTheme.primaryColor, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Divider(color: AppTheme.cardColor, height: 1),
        ),
        const SizedBox(height: 12),

        // Input o prompt de login
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: authProvider.isLoggedIn
              ? _buildCommentInput(authProvider)
              : _buildLoginPrompt(authProvider),
        ),
        const SizedBox(height: 16),

        // Lista de comentarios en tiempo real
        StreamBuilder<List<Comment>>(
          stream: CommentService.getComments(
            widget.animeSlug,
            episodeNumber: widget.episodeNumber,
          ),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor),
                  ),
                ),
              );
            }

            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'Error al cargar comentarios: ${snapshot.error}',
                  style: const TextStyle(color: AppTheme.dangerColor),
                ),
              );
            }

            final comments = snapshot.data ?? [];

            if (comments.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 32, horizontal: 20),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.chat_bubble_outline, size: 40, color: AppTheme.textSecondary),
                      SizedBox(height: 12),
                      Text(
                        'Sé el primero en comentar',
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              );
            }

            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: comments.length,
              itemBuilder: (context, index) {
                return _buildCommentTile(comments[index], authProvider);
              },
            );
          },
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildCommentInput(app_auth.AuthProvider authProvider) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar del usuario
              _buildAvatar(authProvider.photoUrl, authProvider.displayName ?? 'U', radius: 18),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _commentController,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  maxLines: 3,
                  minLines: 1,
                  maxLength: 500,
                  decoration: InputDecoration(
                    hintText: 'Escribe tu comentario...',
                    hintStyle: TextStyle(color: AppTheme.textSecondary.withOpacity(0.6), fontSize: 14),
                    border: InputBorder.none,
                    counterStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 10),
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: ElevatedButton.icon(
              onPressed: _isSending ? null : () => _sendComment(authProvider),
              icon: _isSending
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send_rounded, size: 16),
              label: const Text('Publicar', style: TextStyle(fontSize: 13)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginPrompt(app_auth.AuthProvider authProvider) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryColor.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline, color: AppTheme.textSecondary, size: 20),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Inicia sesión para comentar y que tu voz sea escuchada',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () => _showLoginDialog(context, authProvider),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            child: const Text('Entrar'),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentTile(Comment comment, app_auth.AuthProvider authProvider) {
    final isOwner = authProvider.userId == comment.userId;
    final timeAgo = _formatTimeAgo(comment.createdAt);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar clickable -> perfil del usuario
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => UserProfileScreen(
                  userId: comment.userId,
                  displayName: comment.userDisplayName,
                  photoUrl: comment.userPhotoUrl,
                ),
              ),
            ),
            child: _buildAvatar(comment.userPhotoUrl, comment.userDisplayName, radius: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.cardColor,
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => UserProfileScreen(
                                userId: comment.userId,
                                displayName: comment.userDisplayName,
                                photoUrl: comment.userPhotoUrl,
                              ),
                            ),
                          ),
                          child: Text(
                            comment.userDisplayName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: AppTheme.primaryColor,
                              decoration: TextDecoration.underline,
                              decorationColor: AppTheme.primaryColor,
                            ),
                          ),
                        ),
                      ),
                      Text(
                        timeAgo,
                        style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                      ),
                      if (isOwner) ...[
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () => _deleteComment(comment.id, comment.userId, authProvider),
                          child: const Icon(Icons.delete_outline, size: 16, color: AppTheme.dangerColor),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    comment.text,
                    style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary, height: 1.4),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(String? photoUrl, String name, {double radius = 20}) {
    if (photoUrl != null && photoUrl.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: photoUrl,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => _buildInitialsAvatar(name, radius),
        ),
      );
    }
    return _buildInitialsAvatar(name, radius);
  }

  Widget _buildInitialsAvatar(String name, double radius) {
    final initials = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final hue = (name.codeUnits.fold(0, (a, b) => a + b) * 137) % 360;
    final color = HSLColor.fromAHSL(1, hue.toDouble(), 0.6, 0.4).toColor();
    return CircleAvatar(
      radius: radius,
      backgroundColor: color,
      child: Text(initials, style: TextStyle(color: Colors.white, fontSize: radius * 0.7, fontWeight: FontWeight.bold)),
    );
  }

  String _formatTimeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inSeconds < 60) return 'Ahora';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes}m';
    if (diff.inHours < 24) return 'hace ${diff.inHours}h';
    if (diff.inDays < 7) return 'hace ${diff.inDays}d';
    return '${date.day}/${date.month}/${date.year}';
  }

  void _showLoginDialog(BuildContext context, app_auth.AuthProvider authProvider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Iniciar sesión', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Inicia sesión con Google para comentar y guardar tus favoritos en la nube.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 20),
            _buildGoogleButton(ctx, authProvider),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: AppTheme.textSecondary)),
          ),
        ],
      ),
    );
  }

  Widget _buildGoogleButton(BuildContext ctx, app_auth.AuthProvider authProvider) {
    return ElevatedButton(
      onPressed: () async {
        Navigator.pop(ctx);
        final success = await authProvider.signInWithGoogle();
        if (!mounted) return;
        if (!success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No se pudo iniciar sesión con Google'),
              backgroundColor: AppTheme.dangerColor,
            ),
          );
        }
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        minimumSize: const Size(double.infinity, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Google "G" icon usando Canvas
          SizedBox(
            width: 20,
            height: 20,
            child: CustomPaint(painter: _GoogleGPainter()),
          ),
          const SizedBox(width: 12),
          const Text('Continuar con Google', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        ],
      ),
    );
  }
}

/// Pinta la "G" de Google con sus colores oficiales.
class _GoogleGPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    const sweepAngle = math.pi * 2 * 0.75;
    const startAngle = -math.pi / 4;

    // Rojo
    canvas.drawArc(rect, startAngle, sweepAngle / 4, false, Paint()..color = const Color(0xFFEA4335)..style = PaintingStyle.stroke..strokeWidth = size.width * 0.2);
    // Amarillo
    canvas.drawArc(rect, startAngle + sweepAngle / 4, sweepAngle / 4, false, Paint()..color = const Color(0xFFFBBC05)..style = PaintingStyle.stroke..strokeWidth = size.width * 0.2);
    // Verde
    canvas.drawArc(rect, startAngle + sweepAngle / 2, sweepAngle / 4, false, Paint()..color = const Color(0xFF34A853)..style = PaintingStyle.stroke..strokeWidth = size.width * 0.2);
    // Azul (el arco más largo)
    canvas.drawArc(rect, startAngle + sweepAngle * 0.75, math.pi * 2 * 0.25 + math.pi * 0.25, false, Paint()..color = const Color(0xFF4285F4)..style = PaintingStyle.stroke..strokeWidth = size.width * 0.2);

    // Línea horizontal del "G"
    final paint = Paint()
      ..color = const Color(0xFF4285F4)
      ..strokeWidth = size.width * 0.2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * 0.5, size.height * 0.5),
      Offset(size.width, size.height * 0.5),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
