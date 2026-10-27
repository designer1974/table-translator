import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:table_translator/vad.dart';

/// 100 ms di audio 16 kHz con ampiezza [amp] (0..1).
Uint8List chunk(double amp, {int ms = 100}) {
  final n = 16 * ms;
  final bd = ByteData(n * 2);
  for (var i = 0; i < n; i++) {
    final v = (sin(i * 0.3) * amp * 32767).round();
    bd.setInt16(i * 2, v, Endian.little);
  }
  return bd.buffer.asUint8List();
}

void main() {
  test('voce poi pausa = fine frase', () {
    final v = Vad(pause: const Duration(milliseconds: 1500));
    var events = <VadEvent>[];
    for (var i = 0; i < 10; i++) {
      events.add(v.feed(chunk(0.002))); // silenzio del locale
    }
    expect(events.every((e) => e == VadEvent.none), true);
    events = [];
    for (var i = 0; i < 15; i++) {
      events.add(v.feed(chunk(0.2))); // parla 1,5 s
    }
    expect(events, contains(VadEvent.speechStart));
    events = [];
    for (var i = 0; i < 16; i++) {
      events.add(v.feed(chunk(0.002))); // pausa 1,6 s
    }
    expect(events.last == VadEvent.speechEnd || events.contains(VadEvent.speechEnd), true);
  });

  test('un rumore breve non avvia la frase', () {
    final v = Vad();
    expect(v.feed(chunk(0.3, ms: 50)), VadEvent.none);
    expect(v.feed(chunk(0.001)), VadEvent.none);
    expect(v.speaking, false);
  });

  test('allucinazioni scartate', () {
    expect(isHallucination('Sottotitoli a cura di QTSS'), true);
    expect(isHallucination(' [Musica] '), true);
    expect(isHallucination('Thank you for watching!'), true);
    expect(isHallucination('Vorrei un tavolo per due'), false);
  });
}
