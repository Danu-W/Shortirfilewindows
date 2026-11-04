final _separators = RegExp(r'[\r\n,;\t]+');
final _whitespace = RegExp(r'\s+');
final _pathSeparators = RegExp(r'[\\/]');
final _listItemPrefix = RegExp(r'^\s*(?:[-*•]+|\d+[.)])\s*');
final _quotes = RegExp(r'''^["'`“”‘’]+|["'`“”‘’]+$''');
final _nonNameCharacters = RegExp(r'[^a-z0-9]+');

/// Returns a comparison key for a pasted name or a file name.
///
/// Camera files commonly have a leading underscore while copied lists often
/// omit it, so punctuation around the actual identifier is ignored.
String normalizeSearchName(String value) {
  var name = value.trim().toLowerCase();
  name = name.split(_pathSeparators).last;
  final dotIndex = name.lastIndexOf('.');
  if (dotIndex > 0) name = name.substring(0, dotIndex);
  name = name.replaceAll(_nonNameCharacters, '');
  return name;
}

/// Extracts file names from pasted text.
///
/// Accepts names separated by spaces, new lines, commas, semicolons, or tabs,
/// and understands numbered/bulleted lists, quoted names, and full paths.
/// Every space-separated word becomes its own entry, except when the whole
/// value is wrapped in quotes, which keeps it as a single name.
List<String> detectFileNames(
  String raw, {
  required Set<String> extensions,
}) {
  if (extensions.isEmpty) return const [];
  final names = <String>[];
  final seen = <String>{};

  bool isQuoted(String value) {
    final token = value.trim();
    if (token.isEmpty) return false;
    const pairs = {
      '"': '"',
      "'": "'",
      '`': '`',
      '“': '”',
      '‘': '’',
    };
    final close = pairs[token[0]];
    return close != null && token[token.length - 1] == close;
  }

  void add(String value) {
    var token = value.trim();
    token = token.replaceAll(_quotes, '').trim();
    token = token.replaceFirst(_listItemPrefix, '').trim();
    token = token.split(_pathSeparators).last.trim();
    token = token.replaceAll(_quotes, '').trim();
    if (token.isEmpty) return;
    final key = normalizeSearchName(token);
    if (key.isEmpty) return;
    if (seen.add(key)) names.add(token);
  }

  for (final line in raw.split(_separators)) {
    final value = line.trim();
    if (value.isEmpty) continue;
    final words = value.split(_whitespace).where((word) => word.isNotEmpty).toList();
    if (words.length > 1 && !isQuoted(value)) {
      for (final word in words) {
        add(word);
      }
    } else {
      add(value);
    }
  }
  return names;
}
