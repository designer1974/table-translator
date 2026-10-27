import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Impostazioni salvate sul telefono.
class Prefs extends ChangeNotifier {
  String waiter = 'it';
  String tourist = 'en';
  bool autoSpeak = true;
  bool flip = false; // (non più usato)
  double pauseSec = 0.6; // silenzio che chiude la frase
  String stt = 'balanced'; // qualità Whisper
  String engine = 'google'; // 'google' (veloce) o 'whisper' (offline)
  double textScale = 1.0;
  double rate = 0.52;
  double pitch = 1.0;
  bool male = false; // voce maschile
  bool showText = true; // mostra il testo tradotto
  double sens = 0.7; // sensibilità microfono (modalità Sensibile)
  Map<String, String> voices = {}; // lingua -> "nome|locale"

  static Future<Prefs> load() async {
    final p = await SharedPreferences.getInstance();
    final x = Prefs()
      ..waiter = p.getString('waiter') ?? 'it'
      ..tourist = p.getString('tourist') ?? 'en'
      ..autoSpeak = p.getBool('autoSpeak') ?? true
      ..pauseSec = p.getDouble('pause2') ?? 0.6
      ..stt = p.getString('stt') ?? 'balanced'
      ..engine = p.getString('engine') ?? 'google'
      ..textScale = p.getDouble('textScale') ?? 1.0
      ..rate = p.getDouble('rate') ?? 0.52
      ..pitch = p.getDouble('pitch') ?? 1.0
      ..male = p.getBool('male') ?? false
      ..showText = p.getBool('showText') ?? true
      ..sens = p.getDouble('sens') ?? 0.7;
    const ok = {'it', 'en', 'es', 'ar'};
    if (!ok.contains(x.waiter) || !ok.contains(x.tourist) || x.waiter == x.tourist) {
      x
        ..waiter = 'it'
        ..tourist = 'en';
    }
    for (final k in p.getKeys().where((k) => k.startsWith('voice_'))) {
      x.voices[k.substring(6)] = p.getString(k) ?? '';
    }
    return x;
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('waiter', waiter);
    await p.setString('tourist', tourist);
    await p.setBool('autoSpeak', autoSpeak);
    await p.setDouble('pause2', pauseSec);
    await p.setString('stt', stt);
    await p.setString('engine', engine);
    await p.setDouble('textScale', textScale);
    await p.setDouble('rate', rate);
    await p.setDouble('pitch', pitch);
    await p.setBool('male', male);
    await p.setBool('showText', showText);
    await p.setDouble('sens', sens);
    for (final e in voices.entries) {
      if (e.value.isEmpty) {
        await p.remove('voice_${e.key}');
      } else {
        await p.setString('voice_${e.key}', e.value);
      }
    }
    notifyListeners();
  }
}
