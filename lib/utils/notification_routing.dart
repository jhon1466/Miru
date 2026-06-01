import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/app_navigator.dart';
import '../models/comment.dart';
import '../screens/detail_screen.dart';
import '../screens/notifications_screen.dart';
import '../screens/player_screen.dart';

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
    );
  }

  static void open({
    required String animeSlug,
    required String animeTitle,
    String? animeUrl,
    String? episodeUrl,
    double? episodeNumber,
    String? commentId,
    String? parentCommentId,
  }) {
    final resolvedAnimeUrl = resolveAnimeUrl(animeUrl: animeUrl, animeSlug: animeSlug);
    if (resolvedAnimeUrl.isEmpty) {
      _openNotificationsList();
      return;
    }

    final focus = focusCommentId(commentId: commentId, parentCommentId: parentCommentId);
    final nav = AppNavigator.key.currentState;
    if (nav == null) return;

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
    };
    return base64Url.encode(utf8.encode(jsonEncode(map)));
  }

  static void handlePayload(String payload) {
    if (payload.isEmpty) {
      _openNotificationsList();
      return;
    }

    try {
      final decoded = utf8.decode(base64Url.decode(payload));
      final map = jsonDecode(decoded) as Map<String, dynamic>;
      open(
        animeSlug: map['animeSlug']?.toString() ?? '',
        animeTitle: map['animeTitle']?.toString() ?? 'Anime',
        animeUrl: map['animeUrl']?.toString(),
        episodeUrl: map['episodeUrl']?.toString(),
        episodeNumber: (map['episodeNumber'] as num?)?.toDouble(),
        commentId: map['commentId']?.toString(),
        parentCommentId: map['parentCommentId']?.toString(),
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

  static void _openNotificationsList() {
    final nav = AppNavigator.key.currentState;
    if (nav == null) return;
    nav.push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
  }
}
