import 'package:http/http.dart' as http;

void main() async {
  try {
    print("Fetching https://tunovelaligera.com/novelas/...");
    final uri = Uri.parse('https://tunovelaligera.com/novelas/');
    final response = await http.get(
      uri,
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      },
    );
    print("Status Code: ${response.statusCode}");
    print("Body length: ${response.body.length}");
    
    // Test parsing
    final html = response.body;
    // We want to test matching the items
    final itemRegex = RegExp(r'<div[^>]*class="[^"]*page-item-detail[^"]*"[^>]*>([\s\S]*?)<\/div>\s*<\/div>\s*<\/div>');
    final matches = itemRegex.allMatches(html);
    print("Regex Matches found: ${matches.length}");
    
    for (var i = 0; i < matches.length; i++) {
      final m = matches.elementAt(i);
      final block = m.group(0) ?? '';
      print("Match $i length: ${block.length}");
      // Test parsing title and url
      final urlRegex = RegExp(r'href="([^"]+)"');
      final titleRegex = RegExp(r'title="([^"]+)"');
      final srcRegex = RegExp(r'src="([^"]+)"');

      final urlMatch = urlRegex.firstMatch(block);
      final titleMatch = titleRegex.firstMatch(block);
      final srcMatch = srcRegex.firstMatch(block);

      print("  Title: ${titleMatch?.group(1)}");
      print("  URL:   ${urlMatch?.group(1)}");
      print("  Src:   ${srcMatch?.group(1)}");
    }
  } catch (e) {
    print("Error: $e");
  }
}
