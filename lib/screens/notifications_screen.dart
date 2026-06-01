import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../models/comment.dart';
import '../providers/auth_provider.dart' as app_auth;
import '../services/notification_service.dart';
import 'detail_screen.dart';
import 'player_screen.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<app_auth.AuthProvider>();

    if (!auth.isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('Notificaciones')),
        body: const Center(
          child: Text(
            'Inicia sesión para ver tus notificaciones',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificaciones'),
        actions: [
          TextButton(
            onPressed: () => NotificationService.markAllRead(auth.userId!),
            child: const Text('Marcar leídas', style: TextStyle(color: AppTheme.primaryColor)),
          ),
        ],
      ),
      body: StreamBuilder<List<AppNotification>>(
        stream: NotificationService.watchNotifications(auth.userId!),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor),
              ),
            );
          }

          final items = snapshot.data ?? [];
          if (items.isEmpty) {
            return const Center(
              child: Text(
                'No tienes notificaciones',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.cardColor),
            itemBuilder: (context, index) {
              final n = items[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: n.read ? AppTheme.cardColor : AppTheme.primaryColor.withValues(alpha: 0.3),
                  child: Icon(
                    Icons.reply_rounded,
                    color: n.read ? AppTheme.textSecondary : AppTheme.primaryColor,
                  ),
                ),
                title: Text(
                  n.title,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: n.read ? FontWeight.normal : FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                subtitle: Text(
                  '${n.animeTitle}\n${n.body}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
                onTap: () => _openNotification(context, auth, n),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _openNotification(
    BuildContext context,
    app_auth.AuthProvider auth,
    AppNotification n,
  ) async {
    await NotificationService.markAsRead(auth.userId!, n.id);
    if (!context.mounted) return;

    final animeUrl = n.animeUrl?.isNotEmpty == true
        ? n.animeUrl!
        : 'https://animeav1.com/media/${n.animeSlug}';

    if (n.episodeNumber != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlayerScreen(
            episodeUrl: '$animeUrl/${n.episodeNumber!.toString().replaceAll('.0', '')}',
            episodeNumber: n.episodeNumber!,
            animeTitle: n.animeTitle,
            animeUrl: animeUrl,
            focusCommentId: n.commentId ?? n.parentCommentId,
          ),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DetailScreen(
          animeUrl: animeUrl,
          animeTitle: n.animeTitle,
          focusCommentId: n.commentId ?? n.parentCommentId,
        ),
      ),
    );
  }
}
