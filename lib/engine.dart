// Motore: riconoscimento vocale (Android), traduzione offline (ML Kit),
// rilevamento lingua (ML Kit) e voce (sintesi vocale del telefono).

import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

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

// ---------------- Riconoscimento vocale ----------------

class SpeechListener {
  final _stt = SpeechToText();
  bool ready = false;
  String? error;
  List<LocaleName> _locales = [];

  void Function(String text, bool isFinal)? onText;
  void Function(double level)? onLevel;
  void Function()? onDone;
  void Function(String error)? onError;

  bool _gotFinal = false;
  String _last = '';
  bool _active = false;

  Future<bool> init() async {
    if (ready) return true;
    try {
      ready = await _stt.initialize(
        onError: (e) {
          if (!_active) return;
          final msg = e.errorMsg;
          // "no match" = non ha capito: chiudiamo senza testo
          _finish();
          if (msg != 'error_no_match' && msg != 'error_speech_timeout') {
            onError?.call(msg);
          }
        },
        onStatus: (s) {
          if ((s == 'done' || s == 'notListening') && _active) {
            // nessun risultato finale: usiamo l'ultimo parziale
            Future.delayed(const Duration(milliseconds: 400), () {
              if (_active && !_gotFinal) _finish();
            });
          }
        },
      );
      if (ready) _locales = await _stt.locales();
    } catch (e) {
      error = '$e';
      ready = false;
    }
    return ready;
  }

  String _localeFor(Lang l) {
    String norm(String s) => s.replaceAll('_', '-').toLowerCase();
    final want = norm(l.speech);
    for (final x in _locales) {
      if (norm(x.localeId) == want) return x.localeId;
    }
    for (final x in _locales) {
      if (norm(x.localeId).startsWith('${l.code}-') ||
          norm(x.localeId) == l.code) {
        return x.localeId;
      }
    }
    return l.speech;
  }

  bool get isListening => _active;

  Future<void> start(Lang lang) async {
    if (!await init()) {
      onError?.call(error ?? 'Riconoscimento vocale non disponibile');
      return;
    }
    if (_stt.isListening) await _stt.cancel();
    _gotFinal = false;
    _last = '';
    _active = true;
    await _stt.listen(
      localeId: _localeFor(lang),
      listenFor: const Duration(seconds: 45),
      pauseFor: const Duration(seconds: 3),
      onSoundLevelChange: (v) => onLevel?.call(v),
      listenOptions: SpeechListenOptions(
        partialResults: true,
        listenMode: ListenMode.dictation,
        cancelOnError: true,
      ),
      onResult: (SpeechRecognitionResult r) {
        if (!_active) return;
        _last = r.recognizedWords;
        if (r.finalResult) {
          _gotFinal = true;
          onText?.call(_last, true);
          _active = false;
          onDone?.call();
        } else {
          onText?.call(_last, false);
        }
      },
    );
  }

  /// Ferma l'ascolto: il testo finora sentito viene tradotto.
  Future<void> stop() async {
    if (!_active) return;
    await _stt.stop();
    Future.delayed(const Duration(milliseconds: 700), () {
      if (_active && !_gotFinal) _finish();
    });
  }

  Future<void> cancel() async {
    _active = false;
    await _stt.cancel();
  }

  void _finish() {
    if (!_active) return;
    _active = false;
    if (_last.trim().isNotEmpty) onText?.call(_last, true);
    onDone?.call();
  }
}

// ---------------- Voce ----------------

class Voice {
  final _tts = FlutterTts();
  final Map<String, Map<String, String>> chosen = {}; // lingua -> voce
  double rate = 0.48;

  Future<void> init() async {
    try {
      await _tts.awaitSpeakCompletion(false);
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
        try {
          await _tts.setVoice(
              {'name': best.first['name']!, 'locale': best.first['locale']!});
        } catch (_) {}
      }
    }
    await _tts.setSpeechRate(rate);
    await _tts.speak(text);
  }

  Future<void> stop() => _tts.stop();
}
