import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final mangaId = 'a1c7c817-4e59-43b7-9365-09675a149a6f'; // One Piece
  final targetLangs = ['es', 'es-la'];
  
  final Map<String, dynamic> queryParams = {
    'limit': '250',
    'offset': '0',
    'order[chapter]': 'desc',
    'includes[]': ['scanlation_group'],
  };
  if (targetLangs.isNotEmpty) {
    queryParams['translatedLanguage[]'] = targetLangs;
  }

  final uri = Uri.parse('https://api.mangadex.org/manga/$mangaId/feed').replace(queryParameters: queryParams);
  print('Requesting: $uri');
  
  try {
    final response = await http.get(uri);
    print('Status Code: ${response.statusCode}');
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final list = data['data'] as List? ?? [];
      print('Chapters count: ${list.length}');
      if (list.isNotEmpty) {
        print('First chapter: ${list.first['attributes']['chapter']} - ${list.first['attributes']['title']} (${list.first['attributes']['translatedLanguage']})');
      }
    } else {
      print('Body: ${response.body}');
    }
  } catch (e) {
    print('Error: $e');
  }
}
