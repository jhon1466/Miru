class DownloadedEpisode {
  final String id;
  final String animeTitle;
  final String animeUrl;
  final String animeImage;
  final double episodeNumber;
  final String episodeUrl;
  final String episodeTitle;
  final bool isSub;
  final String serverName;
  final String filePath;
  final int fileSizeBytes;
  final DateTime downloadedAt;

  DownloadedEpisode({
    required this.id,
    required this.animeTitle,
    required this.animeUrl,
    required this.animeImage,
    required this.episodeNumber,
    required this.episodeUrl,
    required this.episodeTitle,
    required this.isSub,
    required this.serverName,
    required this.filePath,
    required this.fileSizeBytes,
    required this.downloadedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'animeTitle': animeTitle,
        'animeUrl': animeUrl,
        'animeImage': animeImage,
        'episodeNumber': episodeNumber,
        'episodeUrl': episodeUrl,
        'episodeTitle': episodeTitle,
        'isSub': isSub,
        'serverName': serverName,
        'filePath': filePath,
        'fileSizeBytes': fileSizeBytes,
        'downloadedAt': downloadedAt.toIso8601String(),
      };

  factory DownloadedEpisode.fromJson(Map<String, dynamic> json) {
    return DownloadedEpisode(
      id: json['id'] as String,
      animeTitle: json['animeTitle'] as String? ?? '',
      animeUrl: json['animeUrl'] as String? ?? '',
      animeImage: json['animeImage'] as String? ?? '',
      episodeNumber: (json['episodeNumber'] as num?)?.toDouble() ?? 0,
      episodeUrl: json['episodeUrl'] as String? ?? '',
      episodeTitle: json['episodeTitle'] as String? ?? '',
      isSub: json['isSub'] as bool? ?? true,
      serverName: json['serverName'] as String? ?? '',
      filePath: json['filePath'] as String,
      fileSizeBytes: json['fileSizeBytes'] as int? ?? 0,
      downloadedAt: DateTime.tryParse(json['downloadedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }

  String get episodeLabel =>
      'Ep. ${episodeNumber.toString().replaceAll(RegExp(r'\.0$'), '')}';

  String get languageLabel => isSub ? 'SUB' : 'DUB';

  String get sizeLabel {
    final mb = fileSizeBytes / (1024 * 1024);
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(1)} GB';
    if (mb >= 1) return '${mb.toStringAsFixed(1)} MB';
    return '${(fileSizeBytes / 1024).toStringAsFixed(0)} KB';
  }
}

enum DownloadTaskStatus { queued, downloading, completed, failed, cancelled }

class ActiveDownloadTask {
  final String id;
  final String animeTitle;
  final String animeUrl;
  final String animeImage;
  final double episodeNumber;
  final String episodeUrl;
  final String episodeTitle;
  final bool isSub;
  DownloadTaskStatus status;
  double progress;
  String? error;

  ActiveDownloadTask({
    required this.id,
    required this.animeTitle,
    required this.animeUrl,
    required this.animeImage,
    required this.episodeNumber,
    required this.episodeUrl,
    required this.episodeTitle,
    required this.isSub,
    this.status = DownloadTaskStatus.queued,
    this.progress = 0,
    this.error,
  });
}
