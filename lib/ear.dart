// Microfono sempre acceso con rilevatore di pausa: consegna ogni frase
// appena la persona smette di parlare.

import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import 'vad.dart';

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
    onLevel?.call((vad.level * 12).clamp(0.0, 1.0));
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
          // toglie la pausa finale (lascia 0,25 s)
          final cut = ((vad.pause.inMilliseconds - 250) * 32)
              .clamp(0, pcm.length)
              .toInt();
          pcm = Uint8List.sublistView(pcm, 0, pcm.length - cut);
        }
        _paused = true; // il chiamante decide quando riascoltare
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
