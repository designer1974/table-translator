import 'package:flutter/material.dart';

import 'engine.dart';
import 'langs.dart';
import 'theme.dart';

/// Scarica i dizionari di traduzione (una volta sola, poi funziona offline).
class SetupPage extends StatefulWidget {
  final bool first;
  final VoidCallback? onDone;
  const SetupPage({super.key, this.first = false, this.onDone});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

enum _St { checking, missing, downloading, ready, error }

class _SetupPageState extends State<SetupPage> {
  final _st = <String, _St>{for (final l in langs) l.code: _St.checking};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    for (final l in langs) {
      bool ok = false;
      try {
        ok = await Models.has(l.code);
      } catch (_) {}
      if (!mounted) return;
      setState(() => _st[l.code] = ok ? _St.ready : _St.missing);
    }
  }

  Future<void> _download(String code) async {
    setState(() => _st[code] = _St.downloading);
    bool ok = false;
    try {
      ok = await Models.download(code);
    } catch (_) {}
    if (mounted) setState(() => _st[code] = ok ? _St.ready : _St.error);
  }

  Future<void> _downloadAll() async {
    // l'inglese per primo: serve da ponte per tutte le coppie
    final order = ['en', ...langs.map((l) => l.code).where((c) => c != 'en')];
    await Future.wait(order
        .where((c) => _st[c] != _St.ready)
        .map((c) => _download(c)));
  }

  Future<void> _delete(String code) async {
    if (code == 'en') return;
    try {
      await Models.delete(code);
    } catch (_) {}
    if (mounted) setState(() => _st[code] = _St.missing);
  }

  bool get _allReady => _st.values.every((s) => s == _St.ready);
  bool get _busy => _st.values.any((s) => s == _St.downloading);
  bool get _enoughReady =>
      _st['en'] == _St.ready &&
      _st.entries.where((e) => e.value == _St.ready).length >= 2;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.first
          ? null
          : AppBar(title: const Text('Lingue offline')),
      body: MilkBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (widget.first) ...[
                const SizedBox(height: 12),
                const Text('Table Translator',
                    style:
                        TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                const Text(
                  'Scarica le lingue una volta sola (circa 30 MB ciascuna). '
                  'Dopo la traduzione funziona gratis, anche senza internet.',
                  style: TextStyle(fontSize: 16, color: C.muted),
                ),
                const SizedBox(height: 20),
              ],
              GlossCard(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: [
                    for (final l in langs) _row(l),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 56,
                child: FilledButton.icon(
                  onPressed: _allReady || _busy ? null : _downloadAll,
                  icon: const Icon(Icons.download_rounded),
                  label: Text(_busy
                      ? 'Download in corso…'
                      : _allReady
                          ? 'Tutte le lingue pronte'
                          : 'Scarica tutte le lingue',
                      style: const TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(height: 12),
              if (widget.first)
                SizedBox(
                  height: 52,
                  child: OutlinedButton(
                    onPressed: _enoughReady && !_busy ? widget.onDone : null,
                    child: const Text('Inizia', style: TextStyle(fontSize: 16)),
                  ),
                ),
              const SizedBox(height: 12),
              const Text(
                'Consiglio: usa il Wi-Fi per il primo download.',
                textAlign: TextAlign.center,
                style: TextStyle(color: C.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(Lang l) {
    final s = _st[l.code]!;
    Widget trailing;
    switch (s) {
      case _St.checking:
      case _St.downloading:
        trailing = const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5));
      case _St.ready:
        trailing = Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.check_circle, color: Color(0xFF2E8B57)),
          if (!widget.first && l.code != 'en')
            IconButton(
              tooltip: 'Elimina',
              icon: const Icon(Icons.delete_outline, color: C.muted),
              onPressed: () => _delete(l.code),
            ),
        ]);
      case _St.missing:
      case _St.error:
        trailing = TextButton.icon(
          onPressed: () => _download(l.code),
          icon: Icon(s == _St.error ? Icons.refresh : Icons.download),
          label: Text(s == _St.error ? 'Riprova' : 'Scarica'),
        );
    }
    return ListTile(
      leading: Text(l.flag, style: const TextStyle(fontSize: 30)),
      title: Text(l.nameIt,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      subtitle: Text(l.code == 'en' ? '${l.name} · necessaria' : l.name),
      trailing: trailing,
    );
  }
}
