import 'dart:async';

import 'package:flutter/material.dart';

import 'engine.dart';
import 'langs.dart';
import 'prefs.dart';
import 'theme.dart';

const buildNumber = String.fromEnvironment('BUILD', defaultValue: 'dev');

enum _St { wait, loading, ok, fail }

/// Scarica le lingue mancanti mostrando lo stato di ognuna.
/// Non blocca mai: "Apri comunque" è sempre disponibile.
class SetupPage extends StatefulWidget {
  final Prefs prefs;
  final VoidCallback onDone;
  const SetupPage({super.key, required this.prefs, required this.onDone});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final _st = <String, _St>{};
  bool _slow = false; // ci sta mettendo troppo
  int _secs = 0;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _run() async {
    _clock?.cancel();
    setState(() {
      _slow = false;
      _secs = 0;
    });
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _secs++;
        if (_secs >= 40) _slow = true;
      });
    });
    List<String> missing;
    try {
      missing = await Models.missing([widget.prefs.waiter, widget.prefs.tourist])
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      missing = {widget.prefs.waiter, widget.prefs.tourist, 'en'}.toList();
    }
    if (!mounted) return;
    setState(() {
      for (final c in missing) {
        _st[c] = _St.wait;
      }
    });
    // tutte insieme, non una dopo l'altra
    await Future.wait(missing.map((c) async {
      setState(() => _st[c] = _St.loading);
      bool ok;
      try {
        ok = await Models.download(c).timeout(const Duration(minutes: 3));
      } catch (_) {
        ok = false;
      }
      if (mounted) setState(() => _st[c] = ok ? _St.ok : _St.fail);
    }));
    _clock?.cancel();
    if (mounted && _st.values.every((s) => s == _St.ok)) widget.onDone();
  }

  Widget _row(String code) {
    final l = langOf(code);
    final s = _st[code]!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Text(l.flag, style: const TextStyle(fontSize: 26)),
        const SizedBox(width: 12),
        Expanded(
            child: Text(l.nameIt,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
        switch (s) {
          _St.ok => const Icon(Icons.check_circle, color: Colors.green),
          _St.fail => const Icon(Icons.error, color: Colors.red),
          _ => const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5)),
        },
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = langOf(widget.prefs.waiter), t = langOf(widget.prefs.tourist);
    final failed = _st.values.contains(_St.fail);
    return Scaffold(
      body: MilkBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${w.flag}  ⇄  ${t.flag}',
                      style: const TextStyle(fontSize: 44)),
                  const SizedBox(height: 12),
                  const Text('Devoo Translator',
                      style:
                          TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                  const Text('versione $buildNumber',
                      style: TextStyle(color: C.muted)),
                  const SizedBox(height: 24),
                  const Text('Scarico le lingue sul telefono',
                      style: TextStyle(fontSize: 16, color: C.muted)),
                  const SizedBox(height: 8),
                  GlossCard(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    child: Column(children: [
                      for (final c in _st.keys) _row(c),
                      if (_st.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(),
                        ),
                    ]),
                  ),
                  if (_slow || failed) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Il download è bloccato o lento.\n'
                      '• Togli il Risparmio energetico (la batteria è bassa?)\n'
                      '• Collegati al Wi-Fi\n'
                      '• Controlla che Google Play Services sia aggiornato',
                      style: TextStyle(fontSize: 15),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _run,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Riprova'),
                    ),
                  ],
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: widget.onDone,
                    child: const Text('Apri comunque →',
                        style: TextStyle(fontSize: 16)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
