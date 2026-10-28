import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import 'engine.dart';
import 'gemini.dart';
import 'langs.dart';
import 'prefs.dart';
import 'setup_page.dart' show buildNumber;
import 'theme.dart';

/// Impostazioni essenziali: voce donna/uomo, velocità, voce sì/no, testo sì/no.
class SettingsPage extends StatefulWidget {
  final Prefs prefs;
  final Voice voice;
  const SettingsPage({super.key, required this.prefs, required this.voice});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

const _sample = {
  'it': 'Ciao! Come posso aiutarti?',
  'en': 'Hello! How can I help you?',
  'es': '¡Hola! ¿Cómo puedo ayudarte?',
  'ary': 'السلام! كيفاش نقدر نعاونك؟',
};

class _SettingsPageState extends State<SettingsPage> {
  Prefs get p => widget.prefs;
  late final _key = TextEditingController(text: p.geminiKey);
  String? _keyMsg;
  bool _testing = false;

  static const _ch = MethodChannel('tt/stt');

  Future<void> _saveKey() async {
    final k = _key.text.trim();
    FocusScope.of(context).unfocus();
    if (k.isEmpty) {
      _set(() {
        p.geminiKey = '';
        _keyMsg = 'Interprete AI spento';
      });
      return;
    }
    // la chiave si salva subito; poi la proviamo
    _set(() {
      p.geminiKey = k;
      _testing = true;
      _keyMsg = 'Chiave salvata. Controllo che funzioni…';
    });
    final t = Stopwatch()..start();
    final g = Gemini()..key = k;
    try {
      await g.test();
      final s = (t.elapsedMilliseconds / 1000).toStringAsFixed(1);
      setState(() => _keyMsg =
          '✅ Funziona: Google risponde in $s s. Interprete AI attivo');
    } on GeminiError catch (e) {
      setState(() => _keyMsg = '❌ ${e.message}');
    } catch (e) {
      setState(() => _keyMsg = '❌ Errore: $e');
    }
    if (mounted) setState(() => _testing = false);
  }

  Widget _aiCard() => GlossCard(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.auto_awesome_rounded, color: C.tourist),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Interprete AI (Gemini)',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              if (p.geminiKey.isNotEmpty)
                const Text('ATTIVO',
                    style: TextStyle(
                        color: Colors.green, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 8),
            const Text(
              'Ascolta sempre, riconosce da solo la lingua di chi parla '
              '(anche la darija) e traduce in modo naturale. Serve internet.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            const Text(
              '1. Tocca "Crea la chiave gratis" ed entra con il tuo account Google\n'
              '2. Premi "Create API key" e copia la chiave\n'
              '3. Incollala qui sotto e premi Salva',
              style: TextStyle(fontSize: 14, color: C.muted),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => _ch.invokeMethod(
                  'open', {'url': 'https://aistudio.google.com/apikey'}),
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Crea la chiave gratis'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _key,
              obscureText: p.geminiKey.isNotEmpty,
              decoration: InputDecoration(
                hintText: 'Incolla qui la chiave (AIza…)',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _testing ? null : _saveKey,
                child: const Text('Salva'),
              ),
            ),
            if (_keyMsg != null) ...[
              const SizedBox(height: 8),
              Text(_keyMsg!, style: const TextStyle(fontSize: 14)),
            ],
            const SizedBox(height: 8),
            const Text(
              'Con il piano gratuito Google può usare le conversazioni per '
              'migliorare i suoi servizi e c\'è un limite di richieste al minuto.',
              style: TextStyle(fontSize: 12, color: C.muted),
            ),
          ],
        ),
      );

  void _set(VoidCallback f) {
    setState(f);
    p.save();
  }

  Future<void> _try() async {
    final v = widget.voice
      ..rate = p.rate
      ..pitch = p.pitch
      ..male = p.male
      ..reset();
    await v.speak('Ciao! Come posso aiutarti?', langOf(p.waiter));
    await v.speak(_sample[p.tourist] ?? 'Hello! How can I help you?',
        langOf(p.tourist));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Impostazioni')),
      body: MilkBackground(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _aiCard(),
            const SizedBox(height: 16),
            GlossCard(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Voce',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                            value: false,
                            icon: Icon(Icons.face_3_rounded),
                            label: Text('Donna')),
                        ButtonSegment(
                            value: true,
                            icon: Icon(Icons.face_rounded),
                            label: Text('Uomo')),
                      ],
                      selected: {p.male},
                      onSelectionChanged: (v) {
                        _set(() => p.male = v.first);
                        _try();
                      },
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text('Velocità  ·  ${(p.rate / 0.5 * 100).round()}%'),
                  Slider(
                    value: p.rate,
                    min: 0.3,
                    max: 0.7,
                    divisions: 8,
                    onChanged: (v) => setState(() => p.rate = v),
                    onChangeEnd: (_) => p.save(),
                  ),
                  Text('Risposta dopo la pausa  ·  ${p.pauseSec.toStringAsFixed(1)} s'
                      '${p.pauseSec <= 0.6 ? '  (rapidissima)' : ''}'),
                  Slider(
                    value: p.pauseSec,
                    min: 0.4,
                    max: 1.5,
                    divisions: 11,
                    onChanged: (v) => setState(() => p.pauseSec = v),
                    onChangeEnd: (_) => p.save(),
                  ),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: _try,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Prova la voce'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            GlossCard(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(children: [
                SwitchListTile(
                  title: const Text('Leggi la traduzione ad alta voce'),
                  value: p.autoSpeak,
                  onChanged: (v) => _set(() => p.autoSpeak = v),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                SwitchListTile(
                  title: const Text('Mostra il testo'),
                  subtitle: const Text('Spento = solo voce'),
                  value: p.showText,
                  onChanged: (v) => _set(() => p.showText = v),
                ),
              ]),
            ),
            if (widget.voice.hasOfflineVoice(p.tourist) == false) ...[
              const SizedBox(height: 16),
              GlossCard(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '⚠️ La voce ${langOf(p.tourist).nameIt} non è installata sul '
                  'telefono: parla in ritardo perché la scarica ogni volta. Vai '
                  'in Impostazioni del telefono › Sintesi vocale › Motore Google '
                  '› Installa dati vocali e scarica '
                  '${p.tourist == 'ary' ? 'Arabo' : langOf(p.tourist).nameIt}.',
                  style: TextStyle(fontSize: 14),
                ),
              ),
            ],
            const SizedBox(height: 20),
            const Center(
              child: Text('Devoo Translator · versione $buildNumber',
                  style: TextStyle(color: C.muted, fontSize: 13)),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'Se "Uomo" e "Donna" suonano simili, il telefono ha poche voci '
                'per quella lingua: installa "Servizi vocali di Google" dal '
                'Play Store per averne di più.',
                style: TextStyle(color: C.muted, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
