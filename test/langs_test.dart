import 'package:flutter_test/flutter_test.dart';
import 'package:table_translator/engine.dart';
import 'package:table_translator/langs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('per ora solo italiano e inglese', () {
    expect(langs.map((l) => l.code).toSet(), {'it', 'en'});
    for (final l in langs) {
      expect(ui(l.code, 'speak').isNotEmpty, true);
    }
    expect(langOf('xx').code, 'it');
  });

  test('riconosce la lingua anche nelle frasi corte', () async {
    final d = Detector();
    // turno dell'italiano, ma parla il cliente inglese
    expect(await d.pick("okay don't worry", 'it', 'en', 'it'), 'en');
    expect(await d.pick('Yes of course I can help you', 'it', 'en', 'it'), 'en');
    expect(await d.pick('Can we have the bill please', 'it', 'en', 'it'), 'en');
    // turno dell'inglese, ma parla il cameriere
    expect(await d.pick('Sì certo, arrivo subito', 'it', 'en', 'en'), 'it');
    expect(await d.pick('Volete acqua naturale o frizzante?', 'it', 'en', 'en'), 'it');
    expect(await d.pick('Grazie mille', 'it', 'en', 'en'), 'it');
    // incerto: resta di chi aveva il turno
    expect(await d.pick('Pizza', 'it', 'en', 'en'), 'en');
  });

  test('traduzione non avvenuta', () {
    expect(sameText("Okay, don't worry.", "okay dont worry"), true);
    expect(sameText('Grazie', 'Thank you'), false);
  });
}
