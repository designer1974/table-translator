// Riconoscimento vocale veloce (servizio Google del telefono),
// con testo in tempo reale e chiusura automatica dopo la pausa.

import 'dart:async';

import 'package:flutter/services.dart';

class GoogleStt {
  static const _m = MethodChannel('tt/stt');
  static const _e = EventChannel('tt/stt/events');
  StreamSubscription? _sub;
  Timer? _silence;
  String _partial = '';
  bool _active = false;

  /// Silenzio dopo l'ultima parola che chiude la frase.
  Duration pause = const Duration(milliseconds: 1000);

  void Function()? onReady;
  void Function()? onBegin;
  void Function(double level)? onLevel; // 0..1
  void Function(String text)? onPartial;
  void Function(String text)? onFinal;
  void Function(int code)? onError;

  bool get active => _active;

  void attach() {
    _sub ??= _e.receiveBroadcastStream().listen((ev) {
      if (ev is! Map || !_active) return;
      switch (ev['type']) {
        case 'ready':
          onReady?.call();
        case 'begin':
          onBegin?.call();
        case 'rms':
          final db = (ev['value'] as num).toDouble();
          onLevel?.call(((db + 2) / 12).clamp(0.0, 1.0));
        case 'partial':
          final t = (ev['text'] as String?) ?? '';
          if (t.isNotEmpty) {
            _partial = t;
            onPartial?.call(t);
            _armSilence();
          }
        case 'final':
          final t = (ev['text'] as String?) ?? '';
          _finish(t.isNotEmpty ? t : _partial);
        case 'error':
          final code = ev['code'] as int;
          // "nessuna corrispondenza" con testo già sentito: usalo
          if ((code == 7 || code == 6) && _partial.isNotEmpty) {
            _finish(_partial);
          } else {
            _active = false;
            _silence?.cancel();
            onError?.call(code);
          }
      }
    });
  }

  /// Dopo [pause] senza nuove parole, chiude la frase.
  void _armSilence() {
    _silence?.cancel();
    _silence = Timer(pause, () {
      if (_active && _partial.isNotEmpty) _m.invokeMethod('stop');
      // se il servizio non risponde, chiudi comunque
      Timer(const Duration(milliseconds: 1500), () {
        if (_active && _partial.isNotEmpty) {
          _m.invokeMethod('cancel');
          _finish(_partial);
        }
      });
    });
  }

  void _finish(String text) {
    if (!_active) return;
    _active = false;
    _silence?.cancel();
    onFinal?.call(text.trim());
  }

  Future<Map<String, dynamic>> info() async =>
      Map<String, dynamic>.from(await _m.invokeMethod('info') as Map);

  /// Chiede il permesso del microfono (se manca).
  Future<bool> permission() async =>
      (await _m.invokeMethod<bool>('permission')) ?? false;

  Future<void> start(String locale, {String? other}) async {
    attach();
    _partial = '';
    _active = true;
    _silence?.cancel();
    await _m.invokeMethod('start', {'lang': locale, 'other': other});
  }

  Future<void> cancel() async {
    _active = false;
    _silence?.cancel();
    try {
      await _m.invokeMethod('cancel');
    } catch (_) {}
  }

  void dispose() {
    cancel();
    _sub?.cancel();
  }
}

/// Messaggio chiaro per gli errori del riconoscimento vocale.
String sttErrorText(int code) => switch (code) {
      1 || 2 => 'Serve internet per il riconoscimento veloce (o usa la modalità offline)',
      3 => 'Problema con il microfono',
      4 => 'Servizio vocale non disponibile, riprova',
      5 => 'Riconoscimento interrotto, riprova',
      8 => 'Microfono occupato, riprova tra un attimo',
      9 => 'Manca il permesso del microfono',
      11 => 'Servizio vocale disconnesso, riprova',
      12 || 13 => 'Lingua non supportata dal riconoscimento vocale',
      _ => 'Errore riconoscimento vocale ($code)',
    };
