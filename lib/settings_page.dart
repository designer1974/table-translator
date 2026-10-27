import 'package:flutter/material.dart';

import 'engine.dart';
import 'langs.dart';
import 'prefs.dart';
import 'setup_page.dart';
import 'theme.dart';

class SettingsPage extends StatefulWidget {
  final Prefs prefs;
  final Voice voice;
  const SettingsPage({super.key, required this.prefs, required this.voice});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Prefs get p => widget.prefs;

  void _snack(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
        child: Text(t,
            style: const TextStyle(
                color: C.muted, letterSpacing: 1.2, fontWeight: FontWeight.w600)),
      );

  void _set(VoidCallback f) {
    setState(f);
    p.save();
  }

  Future<void> _voices(Lang l) async {
    final list = await widget.voice.voicesFor(l);
    if (!mounted) return;
    if (list.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Nessuna voce ${l.nameIt}'),
          content: const Text(
            'Installa la voce dal telefono:\n'
            'Impostazioni › Accessibilità › Sintesi vocale › Motore di Google › '
            'Installa dati vocali.\n\n'
            'Consiglio: usa "Servizi vocali di Google" come motore: '
            'ha le voci più naturali.',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK')),
          ],
        ),
      );
      return;
    }
    final sample = await Translator()
        .translate('Buongiorno, benvenuti! Cosa vi porto da bere?', 'it', l.code)
        .catchError((_) => 'Hello!');
    if (!mounted) return;
    final current = p.voices[l.code] ?? '';
    await showModalBottomSheet(
      context: context,
      backgroundColor: C.bgTop,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (ctx, sc) => StatefulBuilder(
          builder: (ctx, setSheet) {
            final sel = p.voices[l.code] ?? current;
            return ListView(
              controller: sc,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                Text('Voce ${l.flag} ${l.nameIt}',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w700)),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Tocca ▶ per ascoltare, poi scegli la più chiara.',
                      style: TextStyle(color: C.muted)),
                ),
                RadioListTile<String>(
                  value: '',
                  groupValue: sel,
                  title: const Text('Automatica (la migliore disponibile)'),
                  onChanged: (v) {
                    p.voices[l.code] = '';
                    p.save();
                    setSheet(() {});
                  },
                ),
                for (var i = 0; i < list.length; i++)
                  _voiceTile(l, list[i], i, sel, sample, setSheet),
              ],
            );
          },
        ),
      ),
    );
    setState(() {});
  }

  Widget _voiceTile(Lang l, Map<String, String> v, int i, String sel,
      String sample, StateSetter setSheet) {
    final id = '${v['name']}|${v['locale']}';
    final net = (v['name'] ?? '').contains('network') ||
        v['network_required'] == 'true';
    return RadioListTile<String>(
      value: id,
      groupValue: sel,
      title: Text('Voce ${i + 1}${i == 0 ? '  ★ consigliata' : ''}'),
      subtitle: Text(
          '${v['locale']}${net ? ' · richiede internet' : ' · offline'}',
          style: const TextStyle(fontSize: 12)),
      secondary: IconButton(
        icon: const Icon(Icons.play_circle_fill, color: C.waiter, size: 32),
        onPressed: () async {
          final old = widget.voice.chosen[l.code];
          widget.voice.chosen[l.code] = {
            'name': v['name']!,
            'locale': v['locale']!
          };
          await widget.voice.speak(sample, l);
          if (old == null) {
            widget.voice.chosen.remove(l.code);
          } else {
            widget.voice.chosen[l.code] = old;
          }
        },
      ),
      onChanged: (x) {
        p.voices[l.code] = id;
        p.save();
        setSheet(() {});
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Impostazioni')),
      body: MilkBackground(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _section('ASCOLTO'),
            GlossCard(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(children: [
                ListTile(
                  title: const Text('Modalità di ascolto'),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                                value: 'google',
                                icon: Icon(Icons.bolt_rounded),
                                label: Text('Veloce')),
                            ButtonSegment(
                                value: 'whisper',
                                icon: Icon(Icons.hearing_rounded),
                                label: Text('Sensibile')),
                          ],
                          selected: {p.engine},
                          onSelectionChanged: (v) =>
                              _set(() => p.engine = v.first),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          p.engine == 'whisper'
                              ? 'Sente anche la voce bassa e a distanza, filtra rumori ed eco, accetta solo voce umana. Funziona senza internet, ma è più lenta.'
                              : 'Consigliata: scrive mentre parli, risposta immediata. Serve internet.',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
                if (p.engine == 'whisper')
                  ListTile(
                    title: Text(
                        'Sensibilità microfono  ·  ${(p.sens * 100).round()}%'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Slider(
                          value: p.sens,
                          min: 0,
                          max: 1,
                          divisions: 10,
                          onChanged: (v) => setState(() => p.sens = v),
                          onChangeEnd: (_) => p.save(),
                        ),
                        const Text(
                            'Più alta = sente voce bassa e lontana. Se capta troppi rumori, abbassala.',
                            style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ListTile(
                  title: const Text('Pausa che chiude la frase'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Slider(
                        value: p.pauseSec,
                        min: 1.0,
                        max: 3.0,
                        divisions: 8,
                        label: '${p.pauseSec.toStringAsFixed(2)} s',
                        onChanged: (v) => setState(() => p.pauseSec = v),
                        onChangeEnd: (_) => p.save(),
                      ),
                      Text(
                          'Quando smetti di parlare per ${p.pauseSec.toStringAsFixed(1)} secondi, traduce da solo.',
                          style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                ListTile(
                  title: const Text('Qualità offline (Whisper)'),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: SegmentedButton<String>(
                      segments: [
                        for (final q in SttQuality.values)
                          ButtonSegment(value: q.name, label: Text(q.label)),
                      ],
                      selected: {p.stt},
                      onSelectionChanged: (v) async {
                        final q = SttQuality.values.byName(v.first);
                        if (!await Stt(q).hasModel()) {
                          if (!mounted) return;
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: Text('Qualità ${q.label}'),
                              content: Text(
                                  'Serve scaricare ${q.size} (una volta sola). '
                                  'Più precisa = più lenta.'),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Annulla')),
                                FilledButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Scarica')),
                              ],
                            ),
                          );
                          if (ok != true || !mounted) return;
                          _snack('Scarico ${q.size}… attendi');
                          try {
                            await Stt(q).download((_) {});
                          } catch (e) {
                            _snack('Download non riuscito');
                            return;
                          }
                          _snack('Pronto');
                        }
                        _set(() => p.stt = q.name);
                      },
                    ),
                  ),
                ),
              ]),
            ),
            _section('VOCE'),
            GlossCard(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(children: [
                SwitchListTile(
                  title: const Text('Leggi la traduzione ad alta voce'),
                  value: p.autoSpeak,
                  onChanged: (v) => _set(() => p.autoSpeak = v),
                ),
                ListTile(
                  title: Text('Velocità  ·  ${(p.rate / 0.5 * 100).round()}%'),
                  subtitle: Slider(
                    value: p.rate,
                    min: 0.3,
                    max: 0.7,
                    divisions: 8,
                    onChanged: (v) => setState(() => p.rate = v),
                    onChangeEnd: (_) => p.save(),
                  ),
                ),
                ListTile(
                  title: Text('Tono  ·  ${p.pitch < 0.95 ? 'più basso' : p.pitch > 1.05 ? 'più alto' : 'normale'}'),
                  subtitle: Slider(
                    value: p.pitch,
                    min: 0.7,
                    max: 1.3,
                    divisions: 6,
                    onChanged: (v) => setState(() => p.pitch = v),
                    onChangeEnd: (_) => p.save(),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.play_circle_fill,
                      color: C.waiter, size: 32),
                  title: const Text('Prova la voce'),
                  subtitle: const Text('Ascolta come suona con queste impostazioni'),
                  onTap: () async {
                    widget.voice.rate = p.rate;
                    widget.voice.pitch = p.pitch;
                    await widget.voice.speak(
                        'Buongiorno, benvenuti! Cosa vi porto da bere?',
                        langOf('it'));
                  },
                ),
                const Divider(height: 8),
                for (final l in langs)
                  ListTile(
                    leading:
                        Text(l.flag, style: const TextStyle(fontSize: 26)),
                    title: Text('Voce ${l.nameIt}'),
                    subtitle: Text((p.voices[l.code] ?? '').isEmpty
                        ? 'Automatica (la migliore)'
                        : 'Scelta da te'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _voices(l),
                  ),
              ]),
            ),
            _section('SCHERMO'),
            GlossCard(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(children: [
                SwitchListTile(
                  title: const Text('Mostra il testo'),
                  subtitle: const Text(
                      'OFF = solo voce: niente scritte, si sente solo la traduzione'),
                  value: p.showText,
                  onChanged: (v) => _set(() => p.showText = v),
                ),
                ListTile(
                title: const Text('Grandezza testo'),
                subtitle: Slider(
                  value: p.textScale,
                  min: 0.8,
                  max: 1.5,
                  divisions: 7,
                  label: '${(p.textScale * 100).round()}%',
                  onChanged: (v) => setState(() => p.textScale = v),
                  onChangeEnd: (_) => p.save(),
                ),
              ),
              ]),
            ),
            const SizedBox(height: 16),
            GlossCard(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ListTile(
                leading: const Icon(Icons.download_done_rounded),
                title: const Text('Lingue offline'),
                subtitle: const Text('Scarica o elimina i dizionari'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => SetupPage(prefs: p))),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Tutto funziona sul telefono: voce→testo con Whisper, '
              'traduzione con i dizionari offline, voce con la sintesi vocale. '
              'Gratis, senza crediti.',
              style: TextStyle(color: C.muted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
