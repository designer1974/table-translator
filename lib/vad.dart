// Rilevatore di voce (VAD): capisce quando qualcuno inizia a parlare
// e quando ha finito (pausa), regolandosi da solo sul rumore del locale.

import 'dart:math';
import 'dart:typed_data';

enum VadEvent { none, speechStart, speechEnd, tooLong }

class Vad {
  /// Silenzio che chiude la frase.
  Duration pause;

  /// Durata massima di una frase (Whisper lavora a blocchi di 30 s).
  final Duration maxUtterance;

  /// Sensibilità: più basso = più sensibile.
  double minLevel;

  Vad({
    this.pause = const Duration(milliseconds: 2000),
    this.maxUtterance = const Duration(seconds: 28),
    this.minLevel = 0.010,
  });

  double _floor = 0.01; // rumore di fondo stimato
  bool speaking = false;
  int _loudMs = 0; // voce consecutiva prima di "inizio"
  int _silentMs = 0;
  int _speechMs = 0;
  double level = 0; // ultimo livello (0..1) per l'animazione

  double _ratio = 2.5;

  /// Sensibilità 0..1 (1 = sente anche la voce molto bassa / lontana).
  set sensitivity(double v) {
    final s = v.clamp(0.0, 1.0);
    minLevel = 0.02 * pow(0.1, s).toDouble(); // 0.02 … 0.002
    _ratio = 3.0 - s * 1.3; // 3.0 … 1.7 volte il rumore di fondo
  }

  double get threshold => max(_floor * _ratio, minLevel);

  // filtro "voce umana": passa-alto ~200 Hz + passa-basso ~3,8 kHz
  double _hpIn = 0, _hpOut = 0, _lp = 0;

  /// Energia nella banda della voce (ignora rombi bassi e fruscii acuti).
  double voiceRms(Uint8List pcm) {
    final n = pcm.length ~/ 2;
    if (n == 0) return 0;
    final bd = ByteData.sublistView(pcm);
    const a = 0.926; // passa-alto 200 Hz a 16 kHz
    const b = 0.6; // passa-basso ~3,8 kHz a 16 kHz
    var sum = 0.0;
    for (var i = 0; i < n; i++) {
      final x = bd.getInt16(i * 2, Endian.little) / 32768.0;
      _hpOut = a * (_hpOut + x - _hpIn);
      _hpIn = x;
      _lp += b * (_hpOut - _lp);
      sum += _lp * _lp;
    }
    return sqrt(sum / n);
  }

  void reset() {
    speaking = false;
    _loudMs = 0;
    _silentMs = 0;
    _speechMs = 0;
  }

  /// RMS normalizzato (0..1) di PCM 16 bit mono.
  static double rms(Uint8List pcm) {
    final n = pcm.length ~/ 2;
    if (n == 0) return 0;
    final bd = ByteData.sublistView(pcm);
    var sum = 0.0;
    for (var i = 0; i < n; i++) {
      final v = bd.getInt16(i * 2, Endian.little) / 32768.0;
      sum += v * v;
    }
    return sqrt(sum / n);
  }

  /// Analizza un pezzo di audio (16 kHz mono) e dice cosa è successo.
  VadEvent feed(Uint8List pcm, {int sampleRate = 16000}) {
    final ms = (pcm.length ~/ 2) * 1000 ~/ sampleRate;
    final r = voiceRms(pcm);
    level = r;
    final loud = r > threshold;

    if (!speaking) {
      // aggiorna il rumore di fondo solo quando nessuno parla
      if (!loud) _floor = (_floor * 0.95 + r * 0.05).clamp(0.002, 0.06);
      _loudMs = loud ? _loudMs + ms : 0;
      if (_loudMs >= 120) {
        speaking = true;
        _speechMs = _loudMs;
        _silentMs = 0;
        return VadEvent.speechStart;
      }
      return VadEvent.none;
    }

    _speechMs += ms;
    // durante la frase serve un po' meno volume per restare "voce"
    if (r > threshold * 0.8) {
      _silentMs = 0;
    } else {
      _silentMs += ms;
    }
    if (_silentMs >= pause.inMilliseconds) {
      speaking = false;
      return VadEvent.speechEnd;
    }
    if (_speechMs >= maxUtterance.inMilliseconds) {
      speaking = false;
      return VadEvent.tooLong;
    }
    return VadEvent.none;
  }
}

/// Frasi che Whisper "inventa" sul silenzio o sul rumore: da scartare.
final _hallucination = RegExp(
  r'(sottotitoli|amara\.org|grazie per (la|l\x27) (visione|attenzione)|'
  r'thank you for watching|thanks for watching|subscribe|'
  r'merci d\x27avoir regardé|sous-titres|untertitel|'
  r'subtítulos|gracias por ver|ترجمة|اشترك)',
  caseSensitive: false,
);

bool isHallucination(String t) {
  final s = t.trim();
  if (s.isEmpty) return true;
  if (RegExp(r'^[\[\(♪*].*[\]\)♪*]$').hasMatch(s)) return true;
  if (RegExp(r'^[\s.,!?…-]*$').hasMatch(s)) return true;
  return _hallucination.hasMatch(s);
}

/// Intestazione WAV per PCM 16 bit.
Uint8List wavHeader(int dataLen, {int channels = 1, int rate = 16000}) {
  final h = ByteData(44);
  void str(int o, String s) {
    for (var i = 0; i < 4; i++) {
      h.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  h.setUint32(4, 36 + dataLen, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  h.setUint32(16, 16, Endian.little);
  h.setUint16(20, 1, Endian.little);
  h.setUint16(22, channels, Endian.little);
  h.setUint32(24, rate, Endian.little);
  h.setUint32(28, rate * channels * 2, Endian.little);
  h.setUint16(32, channels * 2, Endian.little);
  h.setUint16(34, 16, Endian.little);
  str(36, 'data');
  h.setUint32(40, dataLen, Endian.little);
  return h.buffer.asUint8List();
}

/// Amplifica la voce bassa: porta il picco vicino al massimo (max 20×).
Uint8List normalizeVoice(Uint8List pcm) {
  final n = pcm.length ~/ 2;
  if (n == 0) return pcm;
  final bd = ByteData.sublistView(pcm);
  var peak = 1;
  for (var i = 0; i < n; i++) {
    final v = bd.getInt16(i * 2, Endian.little).abs();
    if (v > peak) peak = v;
  }
  final gain = min(20.0, 29000 / peak);
  if (gain < 1.2) return pcm;
  final out = ByteData(n * 2);
  for (var i = 0; i < n; i++) {
    final v = (bd.getInt16(i * 2, Endian.little) * gain).round();
    out.setInt16(i * 2, v.clamp(-32768, 32767).toInt(), Endian.little);
  }
  return out.buffer.asUint8List();
}
