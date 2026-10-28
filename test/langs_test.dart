import 'package:flutter_test/flutter_test.dart';
import 'package:table_translator/engine.dart';
import 'package:table_translator/gemini.dart';
import 'package:table_translator/langs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('lingue', () {
    expect(langs.map((l) => l.code).toSet(), {'it', 'en', 'es', 'ary'});
    expect(langOf('ary').speech, 'ar-MA');
    expect(langOf('ary').rtl, true);
    expect(langOf('fr').flag, '🇫🇷');
    expect(langOf('sw').flag, '🌐'); // lingua sconosciuta: voce generica
    expect(langOf('xx').code, 'it');
    for (final l in allLangs) {
      expect(l.english.isNotEmpty, true, reason: l.code);
    }
  });

  test('codici lingua da Gemini', () {
    expect(normCode('en-US'), 'en');
    expect(normCode('ar-MA'), 'ary');
    expect(normCode('ary'), 'ary');
    expect(normCode('Moroccan Arabic'), 'ary');
    expect(normCode('IT'), 'it');
  });

  test('riconosce la lingua anche nelle frasi corte', () async {
    final d = Detector();
    expect(await d.pick("okay don't worry", 'it', 'en', 'it'), 'en');
    expect(await d.pick('Sì certo, arrivo subito', 'it', 'en', 'en'), 'it');
    expect(await d.pick('Hola, ¿dónde está la estación?', 'it', 'es', 'it'), 'es');
    expect(await d.pick('السلام، كيداير؟', 'it', 'ary', 'it'), 'ary');
    expect(await d.pick('Buongiorno, come stai?', 'it', 'ary', 'ary'), 'it');
  });
}
