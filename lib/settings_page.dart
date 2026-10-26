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
            GlossCard(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(children: [
                SwitchListTile(
                  title: const Text('Leggi la traduzione ad alta voce'),
                  value: p.autoSpeak,
                  onChanged: (v) => _set(() => p.autoSpeak = v),
                ),
                SwitchListTile(
                  title: const Text('Capovolgi la parte del turista'),
                  subtitle: const Text(
                      'Per appoggiare il telefono sul tavolo tra voi due'),
                  value: p.flip,
                  onChanged: (v) => _set(() => p.flip = v),
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
                ListTile(
                  title: const Text('Velocità della voce'),
                  subtitle: Slider(
                    value: p.rate,
                    min: 0.3,
                    max: 0.7,
                    divisions: 8,
                    onChanged: (v) => setState(() => p.rate = v),
                    onChangeEnd: (_) => p.save(),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.only(left: 8, bottom: 8),
              child: Text('VOCI',
                  style: TextStyle(
                      color: C.muted,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600)),
            ),
            GlossCard(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(children: [
                for (final l in langs)
                  ListTile(
                    leading:
                        Text(l.flag, style: const TextStyle(fontSize: 26)),
                    title: Text(l.nameIt),
                    subtitle: Text((p.voices[l.code] ?? '').isEmpty
                        ? 'Automatica'
                        : 'Scelta da te'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _voices(l),
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
                    MaterialPageRoute(builder: (_) => const SetupPage())),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Il riconoscimento della voce usa Google sul telefono: per usarlo '
              'senza internet scarica le lingue in Impostazioni › Google › '
              'Riconoscimento vocale offline.',
              style: TextStyle(color: C.muted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
