import 'package:flutter/material.dart';
import '../core/app_navigator.dart';
import '../screens/detail_screen.dart';
import '../screens/notifications_screen.dart';
import '../screens/player_screen.dart';

/// Navegación desde push o notificación local.
class NotificationNavigation {
  static void handlePayload(String payload) {
    final parts = payload.split('|');
    if (parts.length < 2) {
      _openNotificationsList();
      return;
    }

    final animeSlug = parts[0];
    final animeTitle = parts.length > 1 ? parts[1] : 'Anime';
    final animeUrl = parts.length > 2 ? parts[2] : '';
    final episodeRaw = parts.length > 3 ? parts[3] : '';
    final commentId = parts.length > 4 ? parts[4] : '';

    final resolvedUrl = animeUrl.isNotEmpty
        ? animeUrl
        : (animeSlug.isNotEmpty ? 'https://animeav1.com/media/$animeSlug' : '');

    if (resolvedUrl.isEmpty) {
      _openNotificationsList();
      return;
    }

    final episodeNumber = double.tryParse(episodeRaw);
    final nav = AppNavigator.key.currentState;
    if (nav == null) return;

    if (episodeNumber != null) {
      nav.push(
        MaterialPageRoute(
          builder: (_) => PlayerScreen(
            episodeUrl: '$resolvedUrl/${episodeNumber.toString().replaceAll('.0', '')}',
            episodeNumber: episodeNumber,
            animeTitle: animeTitle,
            animeUrl: resolvedUrl,
            focusCommentId: commentId.isNotEmpty ? commentId : null,
          ),
        ),
      );
      return;
    }

    nav.push(
      MaterialPageRoute(
        builder: (_) => DetailScreen(
          animeUrl: resolvedUrl,
          animeTitle: animeTitle,
          focusCommentId: commentId.isNotEmpty ? commentId : null,
        ),
      ),
    );
  }

  static void _openNotificationsList() {
    final nav = AppNavigator.key.currentState;
    if (nav == null) return;
    nav.push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
  }
}
