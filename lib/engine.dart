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
      'ar' || 'ary' => TranslateLanguage.arabic,
      'pt' => TranslateLanguage.portuguese,
      'ro' => TranslateLanguage.romanian,
      'ru' => TranslateLanguage.russian,
      'uk' => TranslateLanguage.ukrainian,
      'pl' => TranslateLanguage.polish,
      'nl' => TranslateLanguage.dutch,
      'tr' => TranslateLanguage.turkish,
      'zh' => TranslateLanguage.chinese,
      'ja' => TranslateLanguage.japanese,
      'ko' => TranslateLanguage.korean,
      'hi' => TranslateLanguage.hindi,
      'ur' => TranslateLanguage.urdu,
      'bn' => TranslateLanguage.bengali,
      'fa' => TranslateLanguage.persian,
      'el' => TranslateLanguage.greek,
      'sq' => TranslateLanguage.albanian,
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

/// Parole frequenti: aiutano con le frasi corte ("ok don't worry", "sì grazie"),
/// dove il riconoscimento automatico da solo sbaglia spesso.
const _common = <String, Set<String>>{
  'en': {
    'the', 'a', 'an', 'you', 'i', "i'm", 'is', 'are', 'was', 'be', 'do',
    "don't", 'dont', 'does', 'yes', 'yeah', 'please', 'thank', 'thanks',
    'okay', 'ok', 'can', 'could', 'would', 'have', 'has', 'what', 'how',
    'much', 'many', 'we', 'my', 'your', 'of', 'to', 'and', 'it', "it's",
    'this', 'that', 'worry', 'sorry', 'hello', 'hi', 'good', 'morning',
    'evening', 'night', 'water', 'bill', 'check', 'table', 'menu', 'like',
    'want', 'need', 'where', 'some', 'with', 'without', 'for', 'two',
    'three', 'one', 'glass', 'wine', 'beer', 'coffee', 'there', 'here',
    'just', 'very', 'nice', 'great', 'fine', 'sure', 'course', 'help',
    'us', 'me', 'card', 'pay', 'cash', 'people', 'outside', 'inside',
    'right', 'no', 'not', 'any', 'free', 'still', 'sparkling', 'which',
  },
  'es': {
    'el', 'los', 'las', 'de', 'que', 'y', 'es', 'por', 'para', 'con',
    'sin', 'una', 'gracias', 'hola', 'buenos', 'buenas', 'días', 'dias',
    'tardes', 'noches', 'sí', 'por favor', 'favor', 'quiero', 'puedo',
    'puede', 'dónde', 'donde', 'cuánto', 'cuanto', 'cuesta', 'está',
    'esta', 'estoy', 'muy', 'bien', 'vale', 'claro', 'también', 'pero',
    'porque', 'cómo', 'como', 'qué', 'yo', 'tú', 'usted', 'nosotros',
    'tengo', 'tiene', 'hay', 'aquí', 'allí', 'ahora', 'mañana', 'hoy',
    'perdón', 'disculpe', 'necesito', 'agua', 'del', 'al', 'lo', 'me',
    'te', 'se', 'nos', 'mi', 'su', 'mucho', 'poco', 'nada', 'todo',
  },
  'it': {
    'il', 'lo', 'la', 'gli', 'le', 'di', 'che', 'non', 'è', 'e', 'sono',
    'per', 'un', 'una', 'uno', 'ciao', 'grazie', 'prego', 'buongiorno',
    'buonasera', 'sì', 'si', 'vorrei', 'posso', 'puoi', 'può', 'dove',
    'quanto', 'quanti', 'conto', 'acqua', 'tavolo', 'bene', 'molto',
    'con', 'senza', 'del', 'della', 'dei', 'questo', 'questa', 'quello',
    'ti', 'ci', 'vi', 'anche', 'ma', 'perché', 'cosa',
    'volete', 'vuole', 'avete', 'abbiamo', 'subito', 'arrivo', 'scusi',
    'scusa', 'certo', 'va', 'tutto', 'piatto', 'vino', 'birra', 'caffè',
    'due', 'tre', 'persone', 'fuori', 'dentro', 'naturale', 'frizzante',
    'nel', 'al', 'alla', 'dal', 'da', 'ho', 'hai', 'siete',
    'tranquillo', 'preoccupare', 'aiutare', 'aiutarvi', 'benvenuti',
  },
};

class Detector {
  final _id = LanguageIdentifier(confidenceThreshold: 0.01);

  /// Sceglie tra le due lingue della conversazione quella del testo.
  /// Se non è chiaro restituisce [fallback] (la lingua di chi aveva il turno).
  Future<String> pick(String text, String a, String b, String fallback,
      {String? hint}) async {
    final score = {a: 0.0, b: 0.0};
    // scrittura araba: è la darija (l'altra lingua usa le lettere latine)
    if (score.containsKey('ary') || score.containsKey('ar')) {
      final ar = score.containsKey('ary') ? 'ary' : 'ar';
      final arab = RegExp(r'[\u0600-\u06FF]').allMatches(text).length;
      final latin = RegExp(r'[A-Za-zÀ-ÿ]').allMatches(text).length;
      if (arab > latin) return ar;
      if (latin > 0 && arab == 0) return a == ar ? b : a;
    }
    if (hint != null && score.containsKey(hint)) score[hint] = 0.35;
    try {
      for (final l in await _id.identifyPossibleLanguages(text)) {
        final c = l.languageTag.split('-').first;
        final k = c == 'ar' && score.containsKey('ary') ? 'ary' : c;
        if (score.containsKey(k)) score[k] = score[k]! + l.confidence;
      }
    } catch (_) {}
    final words = text
        .toLowerCase()
        .replaceAll('’', "'")
        .split(RegExp(r"[^a-zàèéìíòóùú']+"))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isNotEmpty) {
      for (final c in score.keys.toList()) {
        final set = _common[c];
        if (set == null) continue;
        final hits = words.where(set.contains).length;
        score[c] = score[c]! + 0.9 * hits / words.length;
      }
    }
    final sa = score[a]!, sb = score[b]!;
    if ((sa - sb).abs() < 0.08) return fallback; // incerto
    return sa > sb ? a : b;
  }

  void dispose() => _id.close();
}

/// Due testi praticamente uguali (traduzione non avvenuta)?
bool sameText(String x, String y) {
  String n(String s) =>
      s.toLowerCase().replaceAll(RegExp(r"[^a-zàèéìíòóùú0-9]+"), '');
  return n(x) == n(y);
}

// ---------------- Voce ----------------

class Voice {
  final _tts = FlutterTts();
  final Map<String, Map<String, String>> chosen = {}; // lingua -> voce
  double rate = 0.48;
  double pitch = 1.0;
  bool male = false; // voce maschile

  List<Map<String, String>>? _all; // tutte le voci (lette una volta)
  String? _ready; // configurazione già applicata
  final _offline = <String, bool>{}; // lingua -> voce installata sul telefono

  Future<void> init() async {
    try {
      await _tts.awaitSpeakCompletion(true); // speak() aspetta la fine
      await _tts.setPitch(1.0);
      // motore Google se c'è: voci migliori e installabili offline
      final engines = await _tts.getEngines;
      if (engines is List && engines.contains('com.google.android.tts')) {
        await _tts.setEngine('com.google.android.tts');
      }
    } catch (_) {}
  }

  Future<List<Map<String, String>>> _voices() async {
    if (_all != null) return _all!;
    final out = <Map<String, String>>[];
    try {
      final raw = await _tts.getVoices;
      if (raw is List) {
        for (final v in raw) {
          if (v is Map) out.add(v.map((k, val) => MapEntry('$k', '$val')));
        }
      }
    } catch (_) {}
    if (out.isNotEmpty) _all = out;
    return out;
  }

  static bool _isNetwork(Map<String, String> v) {
    final name = (v['name'] ?? '').toLowerCase();
    final feat = (v['features'] ?? '').toLowerCase();
    return name.contains('network') ||
        feat.contains('networktts') ||
        feat.contains('notinstalled') ||
        v['network_required'] == 'true' ||
        v['network_required'] == '1';
  }

  /// Tutte le voci per una lingua: prima quelle installate sul telefono
  /// (parlano subito), poi le altre.
  Future<List<Map<String, String>>> voicesFor(Lang l) async {
    final list = (await _voices()).where((m) {
      final loc = (m['locale'] ?? '').replaceAll('_', '-').toLowerCase();
      return loc.startsWith(l.tts.split('-').first.toLowerCase());
    }).toList();
    int score(Map<String, String> v) {
      final loc = (v['locale'] ?? '').replaceAll('_', '-').toLowerCase();
      var s = 0;
      if (_isNetwork(v)) s -= 1000; // da internet: lenta a partire
      if ((v['name'] ?? '').toLowerCase().contains('local')) s += 50;
      if (loc == l.tts.toLowerCase()) s += 20;
      if (l.code == 'en' && loc == 'en-us') s += 10; // seconda scelta
      final q = int.tryParse(v['quality'] ?? '') ?? 0;
      s += q ~/ 50;
      return s;
    }

    list.sort((a, b) => score(b).compareTo(score(a)));
    _offline[l.code] = list.isNotEmpty && !_isNetwork(list.first);
    return list;
  }

  /// La lingua ha una voce installata sul telefono? (null = non so)
  bool? hasOfflineVoice(String code) => _offline[code];

  Future<bool> available(Lang l) async {
    try {
      final r = await _tts.isLanguageAvailable(l.tts);
      return r == true || r == 1;
    } catch (_) {
      return false;
    }
  }

  /// Prepara la voce in anticipo (mentre si traduce), così parla subito.
  Future<void> prepare(Lang l) async {
    final key = '${l.code}|$male|$rate|$pitch|${chosen[l.code]?['name']}';
    if (_ready == key) return;
    try {
      Map<String, String>? v = chosen[l.code];
      if (v == null) {
        final best = await voicesFor(l);
        if (best.isNotEmpty) v = pickGender(best, male);
      }
      if (v != null) {
        await _tts.setVoice({'name': v['name']!, 'locale': v['locale']!});
      } else {
        await _tts.setLanguage(l.tts);
      }
      await _tts.setSpeechRate(rate);
      await _tts.setPitch(male ? pitch * 0.85 : pitch * 1.03);
      _ready = key;
    } catch (_) {
      _ready = null;
    }
  }

  Future<void> speak(String text, Lang l) async {
    if (text.trim().isEmpty) return;
    await _tts.stop();
    await prepare(l);
    await _tts.speak(text);
  }

  /// Dopo un cambio di impostazioni la voce va riapplicata.
  void reset() => _ready = null;

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
  // prima le voci installate sul telefono, poi quelle da internet
  final local = voices.where((v) => !Voice._isNetwork(v)).toList();
  for (final group in [local, voices]) {
    for (final v in group) {
      if (_has(v, want)) return v;
    }
    for (final v in group) {
      if (!_has(v, avoid)) return v;
    }
  }
  return voices.first;
}
