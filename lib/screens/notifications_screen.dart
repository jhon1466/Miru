import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../models/comment.dart';
import '../providers/auth_provider.dart' as app_auth;
import '../providers/notification_provider.dart';
import '../services/notification_service.dart';
import '../utils/notification_routing.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotificationProvider>().refreshUnread();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<app_auth.AuthProvider>();

    if (!auth.isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('Notificaciones')),
        body: Center(
          child: Text(
            'Inicia sesión para ver tus notificaciones',
            style: TextStyle(color: context.textSecondary),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificaciones'),
        actions: [
          TextButton(
            onPressed: () async {
              await NotificationService.markAllRead(auth.userId!);
              if (context.mounted) {
                context.read<NotificationProvider>().refreshUnread();
              }
            },
            child: Text('Marcar leídas', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
          ),
        ],
      ),
      body: StreamBuilder<List<AppNotification>>(
        stream: NotificationService.watchNotifications(auth.userId!),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(Theme.of(context).colorScheme.primary),
              ),
            );
          }

          final items = snapshot.data ?? [];
          if (items.isEmpty) {
            return Center(
              child: Text(
                'No tienes notificaciones',
                style: TextStyle(color: context.textSecondary),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: items.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: context.cardColor),
            itemBuilder: (context, index) {
              final n = items[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: n.read ? context.cardColor : Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                  child: Icon(
                    Icons.reply_rounded,
                    color: n.read ? context.textSecondary : Theme.of(context).colorScheme.primary,
                  ),
                ),
                title: Text(
                  n.title,
                  style: TextStyle(
                    color: context.textPrimary,
                    fontWeight: n.read ? FontWeight.normal : FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                subtitle: Text(
                  '${n.animeTitle}\n${n.body}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.textSecondary, fontSize: 12),
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
    if (context.mounted) {
      context.read<NotificationProvider>().refreshUnread();
    }
    if (!context.mounted) return;

    NotificationRouting.openFromNotification(n);
  }
}
