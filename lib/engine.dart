// Motore: traduzione (ML Kit), rilevamento lingua del testo (ML Kit)
// e voce (sintesi vocale del telefono, donna o uomo).

import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import 'langs.dart';

TranslateLanguage mlLang(String code) => switch (code) {
      'it' => TranslateLanguage.italian,
      'en' => TranslateLanguage.english,
      'fr' => TranslateLanguage.french,
      'de' => TranslateLanguage.german,
      'es' => TranslateLanguage.spanish,
      'ar' => TranslateLanguage.arabic,
      _ => TranslateLanguage.english,
    };

// ---------------- Modelli di traduzione ----------------

class Models {
  static final _mgr = OnDeviceTranslatorModelManager();

  static Future<bool> has(String code) =>
      _mgr.isModelDownloaded(mlLang(code).bcpCode);

  static Future<bool> download(String code) =>
      _mgr.downloadModel(mlLang(code).bcpCode, isWifiRequired: false);

  static Future<bool> delete(String code) =>
      _mgr.deleteModel(mlLang(code).bcpCode);

  /// Lingue che mancano (l'inglese serve sempre: fa da "ponte").
  static Future<List<String>> missing(Iterable<String> codes) async {
    final out = <String>[];
    for (final c in {...codes, 'en'}) {
      if (!await has(c)) out.add(c);
    }
    return out;
  }
}

// ---------------- Traduzione ----------------

class Translator {
  final _cache = <String, OnDeviceTranslator>{};

  Future<String> translate(String text, String from, String to) async {
    final t = text.trim();
    if (t.isEmpty || from == to) return t;
    final key = '$from>$to';
    final tr = _cache[key] ??= OnDeviceTranslator(
      sourceLanguage: mlLang(from),
      targetLanguage: mlLang(to),
    );
    return tr.translateText(t);
  }

  void dispose() {
    for (final t in _cache.values) {
      t.close();
    }
    _cache.clear();
  }
}

// ---------------- Rilevamento lingua ----------------

class Detector {
  final _id = LanguageIdentifier(confidenceThreshold: 0.35);

  /// Restituisce il codice di una lingua supportata, oppure null.
  Future<String?> detect(String text) async {
    try {
      final all = await _id.identifyPossibleLanguages(text);
      for (final l in all) {
        final c = l.languageTag.split('-').first;
        if (langs.any((x) => x.code == c)) return c;
      }
    } catch (_) {}
    return null;
  }

  void dispose() => _id.close();
}

// ---------------- Voce ----------------

class Voice {
  final _tts = FlutterTts();
  final Map<String, Map<String, String>> chosen = {}; // lingua -> voce
  double rate = 0.48;
  double pitch = 1.0;
  bool male = false; // voce maschile

  Future<void> init() async {
    try {
      await _tts.awaitSpeakCompletion(true); // speak() aspetta la fine
      await _tts.setPitch(1.0);
    } catch (_) {}
  }

  /// Tutte le voci disponibili per una lingua, le migliori per prime.
  Future<List<Map<String, String>>> voicesFor(Lang l) async {
    final raw = await _tts.getVoices;
    final list = <Map<String, String>>[];
    if (raw is List) {
      for (final v in raw) {
        if (v is Map) {
          final m = v.map((k, val) => MapEntry('$k', '$val'));
          final loc = (m['locale'] ?? '').replaceAll('_', '-').toLowerCase();
          if (loc.startsWith(l.code)) list.add(m);
        }
      }
    }
    int score(Map<String, String> v) {
      final name = (v['name'] ?? '').toLowerCase();
      final loc = (v['locale'] ?? '').replaceAll('_', '-').toLowerCase();
      var s = 0;
      if (loc == l.tts.toLowerCase()) s += 20;
      final q = int.tryParse(v['quality'] ?? '') ?? 0;
      s += q ~/ 20; // qualità alta = punteggio alto
      if (name.contains('network')) s -= 5; // richiede internet
      if (name.contains('local')) s += 5;
      if (v['network_required'] == 'true' || v['network_required'] == '1') {
        s -= 5;
      }
      return s;
    }

    list.sort((a, b) => score(b).compareTo(score(a)));
    return list;
  }

  Future<bool> available(Lang l) async {
    try {
      final r = await _tts.isLanguageAvailable(l.tts);
      return r == true || r == 1;
    } catch (_) {
      return false;
    }
  }

  Future<void> speak(String text, Lang l) async {
    if (text.trim().isEmpty) return;
    await _tts.stop();
    await _tts.setLanguage(l.tts);
    final v = chosen[l.code];
    if (v != null) {
      try {
        await _tts.setVoice({'name': v['name']!, 'locale': v['locale']!});
      } catch (_) {}
    } else {
      final best = await voicesFor(l);
      if (best.isNotEmpty) {
        final v = pickGender(best, male);
        try {
          await _tts.setVoice({'name': v['name']!, 'locale': v['locale']!});
        } catch (_) {}
      }
    }
    await _tts.setSpeechRate(rate);
    // tono: più basso per la voce maschile
    await _tts.setPitch(male ? pitch * 0.82 : pitch * 1.05);
    await _tts.speak(text);
  }

  Future<void> stop() => _tts.stop();
}

// Codici delle voci Google TTS (le più comuni) per genere.
const _maleCodes = [
  'iol', 'iom', 'tpd', 'itd', 'ite', 'frd', 'vlf', 'deb', 'ded', 'dea',
  'eed', 'eef', 'arc', 'ard', 'gba', 'rjs', 'male', 'man',
];
const _femaleCodes = [
  'iob', 'iog', 'tpc', 'tpf', 'sfg', 'itb', 'itc', 'fra', 'frc', 'frb',
  'dfc', 'nfh', 'eea', 'eec', 'arz', 'ara', 'gbb', 'gbc', 'gbg', 'female', 'woman',
];

bool _has(Map<String, String> v, List<String> codes) {
  final parts = (v['name'] ?? '').toLowerCase().split(RegExp(r'[-_#\s]'));
  return codes.any(parts.contains);
}

/// Sceglie una voce del genere richiesto (se il telefono la ha).
Map<String, String> pickGender(List<Map<String, String>> voices, bool male) {
  final want = male ? _maleCodes : _femaleCodes;
  final avoid = male ? _femaleCodes : _maleCodes;
  for (final v in voices) {
    if (_has(v, want)) return v;
  }
  for (final v in voices) {
    if (!_has(v, avoid)) return v;
  }
  return voices.first;
}
