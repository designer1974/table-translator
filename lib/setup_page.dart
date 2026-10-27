import 'package:flutter/material.dart';

import 'engine.dart';
import 'langs.dart';
import 'prefs.dart';
import 'theme.dart';

/// Primo avvio: prepara da solo le lingue, con una sola barra.
class SetupPage extends StatefulWidget {
  final Prefs prefs;
  final VoidCallback onDone;
  const SetupPage({super.key, required this.prefs, required this.onDone});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  int _done = 0, _total = 1;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() => _error = false);
    try {
      final missing =
          await Models.missing([widget.prefs.waiter, widget.prefs.tourist]);
      setState(() {
        _total = missing.isEmpty ? 1 : missing.length;
        _done = 0;
      });
      for (final c in missing) {
        final ok = await Models.download(c);
        if (!ok) throw Exception('download');
        if (mounted) setState(() => _done++);
      }
      if (mounted) widget.onDone();
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = langOf(widget.prefs.waiter), t = langOf(widget.prefs.tourist);
    return Scaffold(
      body: MilkBackground(
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${w.flag}  ⇄  ${t.flag}',
                      style: const TextStyle(fontSize: 44)),
                  const SizedBox(height: 16),
                  const Text('Devoo Translator',
                      style:
                          TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 28),
                  if (!_error) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        minHeight: 10,
                        value: _done == 0 ? null : _done / _total,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text('Preparo le lingue… (solo la prima volta)',
                        style: TextStyle(color: C.muted, fontSize: 16)),
                  ] else ...[
                    const Text('Serve internet per il primo avvio.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16)),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _run,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Riprova'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
