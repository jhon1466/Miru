import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/app_navigator.dart';
import '../models/comment.dart';
import '../models/novel.dart';
import '../screens/detail_screen.dart';
import '../screens/notifications_screen.dart';
import '../screens/player_screen.dart';
import '../screens/manga_detail_screen.dart';
import '../screens/novel_detail_screen.dart';
import '../core/update_service.dart';
import '../widgets/update_dialog.dart';

/// Abre el anime/episodio/comentario indicado por una notificación.
class NotificationRouting {
  static String animeSlugFromUrl(String? url) {
    if (url == null || url.isEmpty) return '';
    try {
      final segments = Uri.parse(url).pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.isEmpty) return '';
      return segments.last;
    } catch (_) {
      return '';
    }
  }

  static String resolveAnimeUrl({String? animeUrl, String? animeSlug}) {
    if (animeUrl != null && animeUrl.trim().isNotEmpty) return animeUrl.trim();
    if (animeSlug != null && animeSlug.isNotEmpty) {
      return 'https://animeav1.com/media/$animeSlug';
    }
    return '';
  }

  static String? focusCommentId({String? commentId, String? parentCommentId}) {
    if (commentId != null && commentId.isNotEmpty) return commentId;
    if (parentCommentId != null && parentCommentId.isNotEmpty) return parentCommentId;
    return null;
  }

  static void openFromNotification(AppNotification n) {
    open(
      animeSlug: n.animeSlug,
      animeTitle: n.animeTitle,
      animeUrl: n.animeUrl,
      episodeUrl: n.episodeUrl,
      episodeNumber: n.episodeNumber,
      commentId: n.commentId,
      parentCommentId: n.parentCommentId,
      mediaType: n.mediaType,
      mangaId: n.mangaId,
      novelId: n.novelId,
    );
  }

  static Future<void> open({
    required String animeSlug,
    required String animeTitle,
    String? animeUrl,
    String? episodeUrl,
    double? episodeNumber,
    String? commentId,
    String? parentCommentId,
    String? mediaType,
    String? mangaId,
    String? novelId,
    String? novelTitle,
    String? novelUrl,
    String? novelCover,
    String? novelStatus,
    String? novelAuthor,
  }) async {
    final NavigatorState nav;
    try {
      nav = await _getNavigator();
    } catch (_) {
      return;
    }

    final finalMediaType = mediaType?.toLowerCase();

    // 0. App Update Navigation
    if (finalMediaType == 'app_update' || finalMediaType == 'update') {
      final updateInfo = await UpdateService.checkForUpdates();
      if (!nav.mounted) return;
      if (updateInfo.hasUpdate) {
        showAppUpdateDialog(nav.context, updateInfo);
      } else {
        ScaffoldMessenger.of(nav.context).showSnackBar(
          SnackBar(
            content: Text('Tu aplicación ya está en la versión más reciente (${UpdateService.appVersion}).'),
            backgroundColor: Theme.of(nav.context).colorScheme.primary,
          ),
        );
      }
      return;
    }

    // 1. Manga Navigation
    if (finalMediaType == 'manga' || (mangaId != null && mangaId.isNotEmpty)) {
      final actualMangaId = mangaId ?? animeSlug;
      if (actualMangaId.isNotEmpty) {
        nav.push(
          MaterialPageRoute(
            builder: (_) => MangaDetailScreen(mangaId: actualMangaId),
          ),
        );
        return;
      }
    }

    // 2. Novel Navigation
    if (finalMediaType == 'novel' || finalMediaType == 'novela' || (novelId != null && novelId.isNotEmpty)) {
      final actualNovelId = novelId ?? animeSlug;
      if (actualNovelId.isNotEmpty) {
        final novelObj = Novel(
          id: actualNovelId,
          title: novelTitle ?? animeTitle,
          url: novelUrl ?? actualNovelId,
          coverUrl: novelCover ?? animeUrl,
          status: novelStatus,
          author: novelAuthor,
        );
        nav.push(
          MaterialPageRoute(
            builder: (_) => NovelDetailScreen(novel: novelObj),
          ),
        );
        return;
      }
    }

    // 3. Anime/Default Navigation
    final resolvedAnimeUrl = resolveAnimeUrl(animeUrl: animeUrl, animeSlug: animeSlug);
    if (resolvedAnimeUrl.isEmpty) {
      _openNotificationsList();
      return;
    }

    final focus = focusCommentId(commentId: commentId, parentCommentId: parentCommentId);

    if (episodeUrl != null && episodeUrl.trim().isNotEmpty) {
      nav.push(
        MaterialPageRoute(
          builder: (_) => PlayerScreen(
            episodeUrl: episodeUrl.trim(),
            episodeNumber: episodeNumber ?? 1,
            animeTitle: animeTitle,
            animeUrl: resolvedAnimeUrl,
            focusCommentId: focus,
          ),
        ),
      );
      return;
    }

    if (episodeNumber != null) {
      nav.push(
        MaterialPageRoute(
          builder: (_) => DetailScreen(
            animeUrl: resolvedAnimeUrl,
            animeTitle: animeTitle,
            focusCommentId: focus,
            initialEpisodeNumber: episodeNumber,
          ),
        ),
      );
      return;
    }

    nav.push(
      MaterialPageRoute(
        builder: (_) => DetailScreen(
          animeUrl: resolvedAnimeUrl,
          animeTitle: animeTitle,
          focusCommentId: focus,
        ),
      ),
    );
  }

  /// Payload FCM / notificación local (JSON en base64; compatible con formato legacy).
  static String encodePayload({
    required String animeSlug,
    required String animeTitle,
    String? animeUrl,
    String? episodeUrl,
    double? episodeNumber,
    String? commentId,
    String? parentCommentId,
    String? notificationId,
    String? mediaType,
    String? mangaId,
    String? novelId,
  }) {
    final map = <String, dynamic>{
      'animeSlug': animeSlug,
      'animeTitle': animeTitle,
      'animeUrl': animeUrl ?? '',
      'episodeUrl': episodeUrl ?? '',
      'episodeNumber': episodeNumber,
      'commentId': commentId ?? '',
      'parentCommentId': parentCommentId ?? '',
      'notificationId': notificationId ?? '',
      'mediaType': mediaType ?? '',
      'mangaId': mangaId ?? '',
      'novelId': novelId ?? '',
    };
    return base64Url.encode(utf8.encode(jsonEncode(map)));
  }

  static Future<void> handlePayload(String payload) async {
    if (payload.isEmpty) {
      _openNotificationsList();
      return;
    }

    try {
      final decoded = utf8.decode(base64Url.decode(payload));
      final map = jsonDecode(decoded) as Map<String, dynamic>;
      
      final animeSlug = map['animeSlug']?.toString() ?? map['anime_slug']?.toString() ?? '';
      final animeTitle = map['animeTitle']?.toString() ?? map['anime_title']?.toString() ?? 'Anime';
      final animeUrl = map['animeUrl']?.toString() ?? map['anime_url']?.toString();
      final episodeUrl = map['episodeUrl']?.toString() ?? map['episode_url']?.toString();
      final episodeNumber = (map['episodeNumber'] as num?)?.toDouble() ?? 
                            (map['episode_number'] as num?)?.toDouble() ??
                            double.tryParse(map['episodeNumber']?.toString() ?? map['episode_number']?.toString() ?? '');
      final commentId = map['commentId']?.toString() ?? map['comment_id']?.toString();
      final parentCommentId = map['parentCommentId']?.toString() ?? map['parent_comment_id']?.toString();
      final mediaType = map['mediaType']?.toString() ?? map['media_type']?.toString();
      final mangaId = map['mangaId']?.toString() ?? map['manga_id']?.toString();
      final novelId = map['novelId']?.toString() ?? map['novel_id']?.toString();

      await open(
        animeSlug: animeSlug,
        animeTitle: animeTitle,
        animeUrl: animeUrl,
        episodeUrl: episodeUrl,
        episodeNumber: episodeNumber,
        commentId: commentId,
        parentCommentId: parentCommentId,
        mediaType: mediaType,
        mangaId: mangaId,
        novelId: novelId,
      );
      return;
    } catch (_) {
      // Formato legacy separado por |
    }

    final parts = payload.split('|');
    if (parts.length < 2) {
      _openNotificationsList();
      return;
    }

    open(
      animeSlug: parts[0],
      animeTitle: parts.length > 1 ? parts[1] : 'Anime',
      animeUrl: parts.length > 2 ? parts[2] : null,
      episodeUrl: null,
      episodeNumber: parts.length > 3 ? double.tryParse(parts[3]) : null,
      commentId: parts.length > 4 ? parts[4] : null,
    );
  }

  static Future<void> _openNotificationsList() async {
    final NavigatorState nav;
    try {
      nav = await _getNavigator();
    } catch (_) {
      return;
    }
    nav.push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
  }

  static Future<NavigatorState> _getNavigator() async {
    var nav = AppNavigator.key.currentState;
    if (nav == null) {
      for (int i = 0; i < 20; i++) {
        await Future.delayed(const Duration(milliseconds: 150));
        nav = AppNavigator.key.currentState;
        if (nav != null) break;
      }
    }
    if (nav == null) {
      throw Exception("NavigatorState is not available");
    }
    return nav;
  }
}
