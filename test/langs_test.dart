import 'package:flutter_test/flutter_test.dart';
import 'package:table_translator/engine.dart';
import 'package:table_translator/langs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('lingue attive', () {
    expect(langs.map((l) => l.code).toSet(), {'it', 'en', 'es', 'ar'});
    for (final l in langs) {
      expect(ui(l.code, 'speak').isNotEmpty, true);
    }
    expect(langOf('ar').speech, 'ar-MA');
    expect(langOf('ar').rtl, true);
    expect(langOf('xx').code, 'it');
  });

  test('riconosce la lingua anche nelle frasi corte', () async {
    final d = Detector();
    expect(await d.pick("okay don't worry", 'it', 'en', 'it'), 'en');
    expect(await d.pick('Yes of course I can help you', 'it', 'en', 'it'), 'en');
    expect(await d.pick('Sì certo, arrivo subito', 'it', 'en', 'en'), 'it');
    expect(await d.pick('Grazie mille', 'it', 'en', 'en'), 'it');
    expect(await d.pick('Pizza', 'it', 'en', 'en'), 'en');
    // spagnolo
    expect(await d.pick('Hola, ¿dónde está la estación?', 'it', 'es', 'it'), 'es');
    expect(await d.pick('Gracias, muy bien', 'it', 'es', 'it'), 'es');
    // darija: scrittura araba
    expect(await d.pick('السلام، كيداير؟', 'it', 'ar', 'it'), 'ar');
    expect(await d.pick('Buongiorno, come stai?', 'it', 'ar', 'ar'), 'it');
  });

  test('traduzione non avvenuta', () {
    expect(sameText("Okay, don't worry.", "okay dont worry"), true);
    expect(sameText('Grazie', 'Thank you'), false);
  });
}
