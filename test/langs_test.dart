import 'package:flutter_test/flutter_test.dart';
import 'package:table_translator/langs.dart';

void main() {
  test('lingue e testi', () {
    expect(langs.map((l) => l.code).toSet(),
        {'it', 'en', 'fr', 'de', 'es', 'ar'});
    for (final l in langs) {
      expect(ui(l.code, 'speak').isNotEmpty, true);
      expect(ui(l.code, 'listening').isNotEmpty, true);
    }
    expect(langOf('ar').rtl, true);
    expect(langOf('xx').code, 'it');
  });
}
