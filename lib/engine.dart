// Motore: microfono + rilevatore di pausa, voce→testo (Whisper, offline),
// traduzione offline (ML Kit), rilevamento lingua del testo (ML Kit)
// e voce (sintesi vocale del telefono).

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

import 'langs.dart';
import 'vad.dart';

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
        try {
          await _tts.setVoice(
              {'name': best.first['name']!, 'locale': best.first['locale']!});
        } catch (_) {}
      }
    }
    await _tts.setSpeechRate(rate);
    await _tts.setPitch(pitch);
    await _tts.speak(text);
  }

  Future<void> stop() => _tts.stop();
}

// ---------------- Microfono + pausa automatica ----------------

class Ear {
  final _rec = AudioRecorder();
  StreamSubscription<Uint8List>? _sub;
  final vad = Vad();
  final _pre = <Uint8List>[]; // ~0,5 s prima dell'inizio, per non tagliare
  int _preBytes = 0;
  final _buf = BytesBuilder(copy: false);
  bool _paused = true;

  void Function(double level)? onLevel;
  void Function()? onSpeechStart;
  void Function(Uint8List pcm)? onUtterance;

  bool get open => _sub != null;

  Future<bool> permission() => _rec.hasPermission();
  bool get listening => open && !_paused;

  Future<bool> start() async {
    if (_sub == null) {
      if (!await _rec.hasPermission()) return false;
      final stream = await _rec.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
      ));
      _sub = stream.listen(_onData);
    }
    resume();
    return true;
  }

  /// Ignora l'audio (mentre traduce o parla la voce).
  void pause() {
    _paused = true;
    vad.reset();
    _buf.clear();
    onLevel?.call(0);
  }

  void resume() {
    vad.reset();
    _buf.clear();
    _pre.clear();
    _preBytes = 0;
    _paused = false;
  }

  void _onData(Uint8List d) {
    if (_paused) return;
    final ev = vad.feed(d);
    onLevel?.call(vad.level);
    if (vad.speaking || ev == VadEvent.speechEnd || ev == VadEvent.tooLong) {
      if (ev == VadEvent.speechStart) {
        for (final p in _pre) {
          _buf.add(p);
        }
        _pre.clear();
        _preBytes = 0;
        onSpeechStart?.call();
      }
      _buf.add(d);
      if (ev == VadEvent.speechEnd || ev == VadEvent.tooLong) {
        var pcm = _buf.takeBytes();
        if (ev == VadEvent.speechEnd) {
          // toglie la pausa finale (lascia 0,3 s)
          final cutBytes = ((vad.pause.inMilliseconds - 300) * 32).clamp(0, pcm.length).toInt();
          pcm = Uint8List.sublistView(pcm, 0, pcm.length - cutBytes);
        }
        _paused = true; // il chiamante deciderà quando riascoltare
        onLevel?.call(0);
        onUtterance?.call(pcm);
      }
    } else {
      _pre.add(d);
      _preBytes += d.length;
      while (_preBytes > 16000 && _pre.length > 1) {
        _preBytes -= _pre.removeAt(0).length;
      }
    }
  }

  Future<void> close() async {
    _paused = true;
    await _sub?.cancel();
    _sub = null;
    try {
      await _rec.stop();
    } catch (_) {}
  }

  Future<void> dispose() async {
    await close();
    await _rec.dispose();
  }
}

// ---------------- Voce → testo (Whisper sul telefono) ----------------

enum SttQuality { fast, balanced, precise }

extension SttQualityX on SttQuality {
  WhisperModel get model => switch (this) {
        SttQuality.fast => WhisperModel.tiny,
        SttQuality.balanced => WhisperModel.base,
        SttQuality.precise => WhisperModel.small,
      };
  String get label => switch (this) {
        SttQuality.fast => 'Veloce',
        SttQuality.balanced => 'Bilanciata',
        SttQuality.precise => 'Precisa',
      };
  String get size => switch (this) {
        SttQuality.fast => '75 MB',
        SttQuality.balanced => '142 MB',
        SttQuality.precise => '466 MB',
      };
}

class Stt {
  final _ctrl = WhisperController();
  SttQuality quality;
  bool _keep = true;
  Stt(this.quality);

  Future<String> _path(SttQuality q) => _ctrl.getPath(q.model);

  Future<bool> hasModel([SttQuality? q]) async =>
      File(await _path(q ?? quality)).existsSync();

  /// Scarica il modello (una volta sola) con avanzamento 0..1.
  Future<void> download(void Function(double) progress, [SttQuality? q]) async {
    final qq = q ?? quality;
    final path = await _path(qq);
    if (File(path).existsSync()) return;
    await Directory(File(path).parent.path).create(recursive: true);
    final tmp = File('$path.part');
    final client = HttpClient();
    try {
      final res = await (await client.getUrl(qq.model.modelUri)).close();
      if (res.statusCode != 200) {
        throw HttpException('download non riuscito (${res.statusCode})');
      }
      final total = res.contentLength;
      var got = 0;
      final sink = tmp.openWrite();
      await for (final c in res) {
        sink.add(c);
        got += c.length;
        if (total > 0) progress(got / total);
      }
      await sink.close();
      await tmp.rename(path);
    } catch (_) {
      if (tmp.existsSync()) await tmp.delete();
      rethrow;
    } finally {
      client.close();
    }
  }

  /// Trascrive PCM 16 kHz mono nella lingua [lang].
  Future<String> transcribe(Uint8List pcm, String lang) async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/frase.wav';
    final loud = normalizeVoice(pcm); // voce bassa amplificata
    final b = BytesBuilder(copy: false)
      ..add(wavHeader(loud.length))
      ..add(loud);
    await File(path).writeAsBytes(b.takeBytes(), flush: true);
    Future<dynamic> run(bool keep) => _ctrl.transcribe(
          model: quality.model,
          audioPath: path,
          lang: lang,
          keepModelLoaded: keep, // modello pronto: frasi successive veloci
          suppressNonSpeechTokens: true,
          noContext: true,
        );
    var res = await run(_keep);
    if (res == null && _keep) {
      // su alcuni telefoni il modello "parcheggiato" non riparte: ricarica
      _keep = false;
      await release();
      res = await run(false);
    }
    final String t = res?.transcription.text.trim() ?? '';
    return isHallucination(t) ? '' : t;
  }

  Future<void> release() async {
    try {
      await _ctrl.releaseModel();
    } catch (_) {}
  }
}
