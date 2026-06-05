import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../services/rating_service.dart';

class MediaRatingSection extends StatelessWidget {
  final String mediaId;
  final String mediaType;
  final String title;
  final String? image;

  const MediaRatingSection({
    super.key,
    required this.mediaId,
    required this.mediaType,
    required this.title,
    this.image,
  });

  String _getRatingLabel(double rating) {
    if (rating >= 5.0) return '¡Excelente!';
    if (rating >= 4.0) return 'Muy bueno';
    if (rating >= 3.0) return 'Bueno';
    if (rating >= 2.0) return 'Regular';
    if (rating >= 1.0) return 'Malo';
    return 'Sin calificar';
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: context.textSecondary.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Valoración',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: context.textPrimary,
                ),
              ),
              const Icon(
                Icons.star_rounded,
                color: Colors.amber,
                size: 24,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Community Average and Count
          StreamBuilder<Map<String, dynamic>>(
            stream: RatingService.getMediaRatingStatsStream(
              mediaId: mediaId,
              mediaType: mediaType,
            ),
            builder: (context, snapshot) {
              final stats = snapshot.data ?? {'average': 0.0, 'count': 0};
              final double average = stats['average'];
              final int count = stats['count'];

              return Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            average > 0 ? average.toStringAsFixed(1) : '-',
                            style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              color: context.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '/5',
                            style: TextStyle(
                              fontSize: 14,
                              color: context.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        count == 1 ? '$count voto' : '$count votos',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: List.generate(5, (index) {
                            final starIndex = index + 1;
                            if (average >= starIndex) {
                              return const Icon(Icons.star_rounded, color: Colors.amber, size: 20);
                            } else if (average >= starIndex - 0.5) {
                              return const Icon(Icons.star_half_rounded, color: Colors.amber, size: 20);
                            } else {
                              return Icon(Icons.star_border_rounded, color: context.textSecondary.withValues(alpha: 0.3), size: 20);
                            }
                          }),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          average > 0
                              ? 'Promedio de la comunidad'
                              : 'Sé el primero en calificar',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),

          const Divider(height: 32, thickness: 1),

          // User Interactive Rating
          if (!authProvider.isLoggedIn)
            Center(
              child: Column(
                children: [
                  Text(
                    'Inicia sesión para valorar este contenido',
                    style: TextStyle(
                      fontSize: 13,
                      color: context.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      minimumSize: const Size(120, 36),
                    ),
                    onPressed: () {
                      authProvider.signInWithGoogle();
                    },
                    icon: const Icon(Icons.login_rounded, size: 18),
                    label: const Text('Iniciar Sesión', style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            )
          else
            StreamBuilder<double?>(
              stream: RatingService.getUserRatingStream(
                userId: authProvider.userId!,
                mediaId: mediaId,
                mediaType: mediaType,
              ),
              builder: (context, snapshot) {
                final double? userRating = snapshot.data;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      userRating != null ? 'Tu valoración:' : '¿Qué te pareció?',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (index) {
                        final starValue = index + 1.0;
                        final isSelected = userRating != null && userRating >= starValue;

                        return GestureDetector(
                          onTap: () async {
                            await RatingService.rateMedia(
                              userId: authProvider.userId!,
                              mediaId: mediaId,
                              mediaType: mediaType,
                              title: title,
                              image: image,
                              rating: starValue,
                            );
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).clearSnackBars();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Valorado con $starValue estrellas!'),
                                backgroundColor: context.successColor,
                                duration: const Duration(seconds: 1),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4.0),
                            child: Icon(
                              isSelected ? Icons.star_rounded : Icons.star_border_rounded,
                              color: isSelected ? Colors.amber : context.textSecondary.withValues(alpha: 0.4),
                              size: 36,
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _getRatingLabel(userRating ?? 0.0),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: userRating != null ? context.primaryColor : context.textSecondary,
                          ),
                        ),
                        if (userRating != null) ...[
                          const SizedBox(width: 12),
                          GestureDetector(
                            onTap: () async {
                              await RatingService.deleteRating(
                                userId: authProvider.userId!,
                                mediaId: mediaId,
                                mediaType: mediaType,
                              );
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).clearSnackBars();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text('Valoración eliminada'),
                                  backgroundColor: context.dangerColor,
                                  duration: const Duration(seconds: 1),
                                ),
                              );
                            },
                            child: Text(
                              'Quitar',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: context.dangerColor,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}
