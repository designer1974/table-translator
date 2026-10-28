// Interprete con l'intelligenza artificiale di Google (Gemini):
// ascolta l'audio, capisce da solo la lingua, trascrive e traduce.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'langs.dart';

class Interpretation {
  final String lang; // lingua parlata (es. "it", "en", "ary")
  final String text; // cosa ha detto
  final String to; // lingua della traduzione
  final String translation;
  Interpretation(this.lang, this.text, this.to, this.translation);
}

class GeminiError implements Exception {
  final String message;
  GeminiError(this.message);
  @override
  String toString() => message;
}

class Gemini {
  String key = '';

  /// Il primo è il più veloce; se non è disponibile si passa al successivo.
  static const models = ['gemini-3.5-flash-lite', 'gemini-3.6-flash'];
  int _model = 0;

  static const _schema = {
    'type': 'OBJECT',
    'properties': {
      'lang': {'type': 'STRING'},
      'text': {'type': 'STRING'},
      'to': {'type': 'STRING'},
      'translation': {'type': 'STRING'},
    },
    'required': ['lang', 'text', 'to', 'translation'],
  };

  String _system(String mine, String other) {
    final m = langOf(mine), o = langOf(other);
    return '''
You are a live voice interpreter between two people.
Person A speaks ${m.english} (code "$mine").
Person B speaks another language; the last one used was ${o.english} (code "$other"), but it can be ANY language.

Rules:
1. Transcribe exactly what was said, in the language and script it was spoken (field "text").
2. Detect the spoken language (field "lang"): a short code like "it", "en", "es", "fr", "de", "ar", "ro", "zh". Use "ary" for Moroccan Arabic (Darija).
3. If the speech is in ${m.english}, translate it into ${o.english} (field "to" = "$other").
   Otherwise translate it into ${m.english} (field "to" = "$mine").
4. The translation must sound natural and spoken, the way a native speaker would really say it, keeping the meaning and tone. Fix obvious speech recognition slips using context.
5. Moroccan Darija: understand Darija properly (including French and Spanish loanwords). When translating INTO Darija ("ary"), write everyday Moroccan Darija in Arabic script, as Moroccans really speak, NOT Modern Standard Arabic.
6. If there is no clear human speech (silence, noise, music, cough), return empty strings for "text" and "translation".
Reply only with the JSON object.''';
  }

  Future<Interpretation?> audio(Uint8List wav, String mine, String other) =>
      _ask(mine, other, [
        {
          'inlineData': {'mimeType': 'audio/wav', 'data': base64Encode(wav)}
        },
        {'text': 'Interpret this audio.'},
      ]);

  Future<Interpretation?> text(String t, String mine, String other) =>
      _ask(mine, other, [
        {'text': 'The person typed this (treat it as speech): $t'}
      ]);

  /// Controlla che la chiave funzioni.
  Future<void> test() async {
    await _post({
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': 'Reply with: ok'}
          ]
        }
      ],
    });
  }

  Future<Interpretation?> _ask(
      String mine, String other, List<Map<String, Object>> parts) async {
    final j = await _post({
      'systemInstruction': {
        'parts': [
          {'text': _system(mine, other)}
        ]
      },
      'contents': [
        {'role': 'user', 'parts': parts}
      ],
      'generationConfig': {
        'temperature': 0.2,
        'responseMimeType': 'application/json',
        'responseSchema': _schema,
      },
    });
    final raw = _textOf(j);
    if (raw == null) return null;
    final s = raw.indexOf('{'), e = raw.lastIndexOf('}');
    if (s < 0 || e <= s) return null;
    final m = jsonDecode(raw.substring(s, e + 1)) as Map;
    String f(String k) => '${m[k] ?? ''}'.trim();
    final text = f('text'), tr = f('translation');
    if (text.isEmpty || tr.isEmpty) return null;
    return Interpretation(
        normCode(f('lang')), text, normCode(f('to')), tr);
  }

  static String? _textOf(Map j) {
    final c = (j['candidates'] as List?)?.cast<Map>();
    if (c == null || c.isEmpty) return null;
    final parts = ((c.first['content'] as Map?)?['parts'] as List?) ?? [];
    final b = StringBuffer();
    for (final p in parts) {
      if (p is Map && p['thought'] != true && p['text'] != null) {
        b.write(p['text']);
      }
    }
    return b.isEmpty ? null : b.toString();
  }

  /// Modello che ha risposto per ultimo.
  String get model => models[_model];

  Future<Map> _post(Map body) async {
    if (key.trim().isEmpty) throw GeminiError('Manca la chiave Gemini');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..idleTimeout = const Duration(seconds: 30);
    final bytes = utf8.encode(jsonEncode(body));
    var timeouts = 0;
    try {
      while (true) {
        final model = models[_model];
        late final HttpClientResponse res;
        late final String txt;
        try {
          final req = await client.postUrl(Uri.parse(
              'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent'));
          req.headers
            ..set('content-type', 'application/json; charset=utf-8')
            ..set('x-goog-api-key', key.trim());
          req.contentLength = bytes.length; // niente invio "a pezzi"
          req.add(bytes);
          res = await req.close().timeout(const Duration(seconds: 15));
          txt = await res
              .transform(utf8.decoder)
              .join()
              .timeout(const Duration(seconds: 15));
        } on TimeoutException {
          // nessuna risposta: prova l'altro modello, poi rinuncia
          timeouts++;
          if (timeouts >= models.length) {
            throw GeminiError(
                'Google non risponde: controlla internet e riprova');
          }
          _model = (_model + 1) % models.length;
          continue;
        }
        if (res.statusCode == 200) return jsonDecode(txt) as Map;
        // modello non disponibile: prova il successivo
        if ((res.statusCode == 404 || res.statusCode == 400 && txt.contains('model')) &&
            _model < models.length - 1) {
          _model++;
          continue;
        }
        String msg;
        try {
          msg = '${(jsonDecode(txt) as Map)['error']['message']}';
        } catch (_) {
          msg = 'errore ${res.statusCode}';
        }
        if (res.statusCode == 429) {
          msg = 'Limite gratuito raggiunto per ora: riprova tra un minuto';
        } else if (res.statusCode == 400 && msg.toLowerCase().contains('api key') ||
            res.statusCode == 403) {
          msg = 'Chiave Gemini non valida';
        }
        throw GeminiError(msg);
      }
    } on SocketException {
      throw GeminiError('Niente internet');
    } on HandshakeException {
      throw GeminiError('Niente internet');
    } finally {
      client.close();
    }
  }
}

/// Uniforma il codice lingua: "en-US" → "en", "ar-MA" → "ary".
String normCode(String c) {
  final s = c.toLowerCase().replaceAll('_', '-').trim();
  if (s == 'ary' || s == 'ar-ma' || s.contains('darija') || s.contains('moroc')) {
    return 'ary';
  }
  final base = s.split('-').first;
  return base.isEmpty ? 'en' : base;
}
