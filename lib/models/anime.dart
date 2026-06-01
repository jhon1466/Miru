import '../utils/image_utils.dart';

class AnimeSearchResult {
  final String? id;
  final String title;
  final String? slug;
  final String url;
  final String? image;
  final String? backdrop;
  final String? type;
  final double? score;
  final String? status;
  final String? year;

  AnimeSearchResult({
    this.id,
    required this.title,
    this.slug,
    required this.url,
    this.image,
    this.backdrop,
    this.type,
    this.score,
    this.status,
    this.year,
  });

  factory AnimeSearchResult.fromJson(Map<String, dynamic> json) {
    return AnimeSearchResult(
      id: json['id']?.toString(),
      title: json['title'] ?? 'Sin Título',
      slug: json['slug']?.toString(),
      url: json['url'] ?? '',
      image: pickAnimeImageUrl(json),
      backdrop: normalizeAnimeImageUrl(json['backdrop']?.toString()) ??
          normalizeAnimeImageUrl(json['banner']?.toString()),
      type: json['type']?.toString(),
      score: json['score'] != null ? double.tryParse(json['score'].toString()) : null,
      status: json['status']?.toString(),
      year: json['year']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'slug': slug,
      'url': url,
      'image': image,
      'backdrop': backdrop,
      'type': type,
      'score': score,
      'status': status,
      'year': year,
    };
  }
}

class Genre {
  final String name;
  final String? slug;

  Genre({required this.name, this.slug});

  factory Genre.fromJson(Map<String, dynamic> json) {
    return Genre(
      name: json['name'] ?? '',
      slug: json['slug']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'slug': slug,
    };
  }
}

class Episode {
  final String? id;
  final double number;
  final String title;
  final String url;

  Episode({
    this.id,
    required this.number,
    required this.title,
    required this.url,
  });

  factory Episode.fromJson(Map<String, dynamic> json) {
    return Episode(
      id: json['id']?.toString(),
      number: double.tryParse(json['number']?.toString() ?? '1') ?? 1.0,
      title: json['title'] ?? 'Episodio',
      url: json['url'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'number': number,
      'title': title,
      'url': url,
    };
  }
}

class AnimeDetails {
  final String? id;
  final String title;
  final String? titleJapanese;
  final String? description;
  final String? image;
  final String? backdrop;
  final String? status;
  final String? type;
  final String? year;
  final double? score;
  final double? votes;
  final int? totalEpisodes;
  final dynamic malId;
  final String? trailer;
  final List<Genre> genres;
  final List<Episode> episodes;
  final String? source;

  AnimeDetails({
    this.id,
    required this.title,
    this.titleJapanese,
    this.description,
    this.image,
    this.backdrop,
    this.status,
    this.type,
    this.year,
    this.score,
    this.votes,
    this.totalEpisodes,
    this.malId,
    this.trailer,
    required this.genres,
    required this.episodes,
    this.source,
  });

  factory AnimeDetails.fromJson(Map<String, dynamic> json) {
    var genresList = (json['genres'] as List?)?.map((g) => Genre.fromJson(g)).toList() ?? [];
    var episodesList = (json['episodes'] as List?)?.map((e) => Episode.fromJson(e)).toList() ?? [];
    
    // El orden de episodios suele venir en orden cronológico inverso o directo. Nos aseguramos de mantener el orden o poder ordenarlo.
    // Opcionalmente podemos revertirlo para que el primero de la lista sea el Episodio 1, pero es mejor mostrarlo tal cual viene y dejar que el usuario ordene si quiere, o mantener el orden recibido.
    
    return AnimeDetails(
      id: json['id']?.toString(),
      title: json['title'] ?? 'Sin Título',
      titleJapanese: json['titleJapanese']?.toString(),
      description: json['description'] ?? json['synopsis'],
      image: pickAnimeImageUrl(json),
      backdrop: normalizeAnimeImageUrl(json['backdrop']?.toString()) ??
          normalizeAnimeImageUrl(json['banner']?.toString()),
      status: json['status']?.toString(),
      type: json['type']?.toString(),
      year: json['year']?.toString(),
      score: json['score'] != null ? double.tryParse(json['score'].toString()) : null,
      votes: json['votes'] != null ? double.tryParse(json['votes'].toString()) : null,
      totalEpisodes: json['totalEpisodes'] != null ? int.tryParse(json['totalEpisodes'].toString()) : null,
      malId: json['malId'],
      trailer: json['trailer']?.toString(),
      genres: genresList,
      episodes: episodesList,
      source: json['source']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'titleJapanese': titleJapanese,
      'description': description,
      'image': image,
      'backdrop': backdrop,
      'status': status,
      'type': type,
      'year': year,
      'score': score,
      'votes': votes,
      'totalEpisodes': totalEpisodes,
      'malId': malId,
      'trailer': trailer,
      'genres': genres.map((g) => g.toJson()).toList(),
      'episodes': episodes.map((e) => e.toJson()).toList(),
      'source': source,
    };
  }
}

class EpisodeLink {
  final String server;
  final String url;
  final String? quality;

  EpisodeLink({
    required this.server,
    required this.url,
    this.quality,
  });

  factory EpisodeLink.fromJson(Map<String, dynamic> json) {
    return EpisodeLink(
      server: json['server'] ?? 'Unknown',
      url: json['url'] ?? '',
      quality: json['quality']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'server': server,
      'url': url,
      'quality': quality,
    };
  }
}

class EpisodeLinksResponse {
  final String? id;
  final double? episode;
  final String title;
  final String? season;
  final List<EpisodeLink> subStream;
  final List<EpisodeLink> dubStream;
  final List<EpisodeLink> subDownload;
  final List<EpisodeLink> dubDownload;

  EpisodeLinksResponse({
    this.id,
    this.episode,
    required this.title,
    this.season,
    required this.subStream,
    required this.dubStream,
    required this.subDownload,
    required this.dubDownload,
  });

  factory EpisodeLinksResponse.fromJson(Map<String, dynamic> json) {
    List<EpisodeLink> parseLinks(List? list) {
      return list?.map((e) => EpisodeLink.fromJson(e)).toList() ?? [];
    }

    // La API devuelve:
    // data.streamLinks.SUB, data.streamLinks.DUB
    // data.downloadLinks.SUB, data.downloadLinks.DUB
    var data = json['data'] ?? json;
    
    var subStreamLinks = parseLinks(data['streamLinks']?['SUB'] ?? data['servers']?['sub']);
    var dubStreamLinks = parseLinks(data['streamLinks']?['DUB'] ?? data['servers']?['dub']);
    var subDownloadLinks = parseLinks(data['downloadLinks']?['SUB']);
    var dubDownloadLinks = parseLinks(data['downloadLinks']?['DUB']);

    return EpisodeLinksResponse(
      id: data['id']?.toString(),
      episode: data['episode'] != null ? double.tryParse(data['episode'].toString()) : null,
      title: data['title'] ?? 'Episodio',
      season: data['season']?.toString(),
      subStream: subStreamLinks,
      dubStream: dubStreamLinks,
      subDownload: subDownloadLinks,
      dubDownload: dubDownloadLinks,
    );
  }
}
