import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'engine.dart';
import 'langs.dart';
import 'prefs.dart';
import 'settings_page.dart';
import 'theme.dart';

enum Side { waiter, tourist }

class Msg {
  final Side from;
  final String fromLang, toLang;
  final String original, translated;
  final DateTime time = DateTime.now();
  Msg(this.from, this.fromLang, this.toLang, this.original, this.translated);
}

class ConversationPage extends StatefulWidget {
  final Prefs prefs;
  const ConversationPage({super.key, required this.prefs});

  @override
  State<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends State<ConversationPage> {
  Prefs get p => widget.prefs;
  final _tr = Translator();
  final _det = Detector();
  final _listener = SpeechListener();
  final _voice = Voice();

  final _msgs = <Msg>[];
  Side? _listening;
  String _partial = '';
  double _level = 0;
  bool _translating = false;

  @override
  void initState() {
    super.initState();
    _voice.init();
    _syncVoice();
    p.addListener(_syncVoice);
    _listener
      ..onText = _onSpeech
      ..onLevel = (v) {
        if (mounted) setState(() => _level = v);
      }
      ..onDone = () {
        if (mounted) setState(() => _level = 0);
      }
      ..onError = (e) {
        if (!mounted) return;
        setState(() {
          _listening = null;
          _partial = '';
        });
        _snack(_sttError(e));
      };
    _listener.init();
  }

  @override
  void dispose() {
    p.removeListener(_syncVoice);
    _tr.dispose();
    _det.dispose();
    _listener.cancel();
    _voice.stop();
    super.dispose();
  }

  void _syncVoice() {
    _voice.rate = p.rate;
    _voice.chosen.clear();
    p.voices.forEach((k, v) {
      final parts = v.split('|');
      if (parts.length == 2) {
        _voice.chosen[k] = {'name': parts[0], 'locale': parts[1]};
      }
    });
  }

  String _sttError(String e) {
    if (e.contains('network')) {
      return 'Riconoscimento vocale: serve internet o il pacchetto offline della lingua.';
    }
    if (e.contains('permission')) return 'Permesso microfono negato.';
    if (e.contains('busy')) return 'Microfono occupato, riprova.';
    return 'Errore riconoscimento vocale ($e)';
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  String _langOf(Side s) => s == Side.waiter ? p.waiter : p.tourist;
  Side _other(Side s) => s == Side.waiter ? Side.tourist : Side.waiter;

  // ---------------- azioni ----------------

  Future<void> _mic(Side s) async {
    HapticFeedback.lightImpact();
    if (_listening == s) {
      await _listener.stop();
      return;
    }
    if (_listening != null) await _listener.cancel();
    await _voice.stop();
    setState(() {
      _listening = s;
      _partial = '';
    });
    await _listener.start(langOf(_langOf(s)));
  }

  void _onSpeech(String text, bool isFinal) {
    if (!mounted || _listening == null) return;
    final side = _listening!;
    if (!isFinal) {
      setState(() => _partial = text);
      return;
    }
    setState(() {
      _listening = null;
      _partial = '';
    });
    _process(side, text);
  }

  Future<void> _process(Side side, String text, {String? fromLang}) async {
    final t = text.trim();
    if (t.isEmpty) return;
    final from = fromLang ?? _langOf(side);
    final to = _langOf(_other(side));
    setState(() => _translating = true);
    try {
      final out = await _tr.translate(t, from, to);
      if (!mounted) return;
      setState(() => _msgs.add(Msg(side, from, to, t, out)));
      if (p.autoSpeak) _voice.speak(out, langOf(to));
    } catch (e) {
      _snack('Traduzione non riuscita: scarica le lingue in Impostazioni.');
    } finally {
      if (mounted) setState(() => _translating = false);
    }
  }

  Future<void> _type(Side side) async {
    if (_listening != null) await _listener.cancel();
    setState(() => _listening = null);
    if (!mounted) return;
    final ctrl = TextEditingController();
    final lang = langOf(_langOf(side));
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.bgTop,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              minLines: 2,
              maxLines: 5,
              style: const TextStyle(fontSize: 20),
              textDirection: lang.rtl ? TextDirection.rtl : null,
              decoration: InputDecoration(
                hintText: side == Side.tourist
                    ? 'Scrivi in qualsiasi lingua (riconosciuta in automatico)'
                    : 'Scrivi in ${lang.nameIt}',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(color: C.border)),
              ),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, ctrl.text),
                icon: const Icon(Icons.translate),
                label: const Text('Traduci', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
    if (text == null || text.trim().isEmpty) return;
    String? from;
    // rilevamento automatico della lingua scritta
    final d = await _det.detect(text);
    if (d != null && d != _langOf(side)) {
      if (side == Side.tourist && d != p.waiter) {
        p.tourist = d;
        await p.save();
        _snack('Lingua rilevata: ${langOf(d).flag} ${langOf(d).nameIt}');
      } else {
        from = d;
      }
    }
    await _process(side, text, fromLang: from);
  }

  Future<void> _pickLang(Side side) async {
    final current = _langOf(side);
    final code = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: C.bgTop,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.05,
            children: [
              for (final l in langs)
                InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: () => Navigator.pop(ctx, l.code),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                          color: l.code == current ? C.waiter : C.border,
                          width: l.code == current ? 2.5 : 1),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(l.flag, style: const TextStyle(fontSize: 40)),
                        const SizedBox(height: 4),
                        Text(l.name,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (code == null || code == current) return;
    if (side == Side.waiter) {
      if (code == p.tourist) p.tourist = p.waiter;
      p.waiter = code;
    } else {
      if (code == p.waiter) p.waiter = p.tourist;
      p.tourist = code;
    }
    await p.save();
    setState(() {});
    final missing = await Models.missing([p.waiter, p.tourist]);
    if (missing.isNotEmpty && mounted) {
      _snack('Scarico la lingua ${missing.map((c) => langOf(c).nameIt).join(', ')}…');
      for (final c in missing) {
        await Models.download(c);
      }
      if (mounted) _snack('Lingua pronta');
    }
  }

  Future<void> _phrases() async {
    final phrase = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.bgTop,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (ctx, sc) => ListView(
          controller: sc,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text('Frasi pronte → ${langOf(p.tourist).flag}',
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            for (final e in quickPhrases.entries) ...[
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 8),
                child: Text(e.key.toUpperCase(),
                    style: const TextStyle(
                        color: C.muted,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600)),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final f in e.value)
                    ActionChip(
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: C.border),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      label: Text(f, style: const TextStyle(fontSize: 15)),
                      onPressed: () => Navigator.pop(ctx, f),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
    if (phrase != null) {
      await _process(Side.waiter, phrase, fromLang: 'it');
    }
  }

  void _history() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.bgTop,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        builder: (ctx, sc) => _msgs.isEmpty
            ? const Center(child: Text('Nessuna conversazione'))
            : ListView.builder(
                controller: sc,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: _msgs.length,
                itemBuilder: (_, i) {
                  final m = _msgs[i];
                  final w = m.from == Side.waiter;
                  return Align(
                    alignment:
                        w ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      padding: const EdgeInsets.all(14),
                      constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(ctx).size.width * 0.8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                            color: (w ? C.waiter : C.tourist)
                                .withValues(alpha: 0.35)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${langOf(m.fromLang).flag}  ${m.original}',
                              style: const TextStyle(
                                  fontSize: 15, color: C.muted)),
                          const SizedBox(height: 4),
                          Text('${langOf(m.toLang).flag}  ${m.translated}',
                              style: const TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _openSettings() async {
    if (_listening != null) await _listener.cancel();
    setState(() => _listening = null);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => SettingsPage(prefs: p, voice: _voice)),
    );
    if (mounted) setState(() {});
  }

  // ---------------- interfaccia ----------------

  @override
  Widget build(BuildContext context) {
    final tourist = _panel(Side.tourist);
    return Scaffold(
      body: MilkBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(
              children: [
                Expanded(
                  child: p.flip
                      ? RotatedBox(quarterTurns: 2, child: tourist)
                      : tourist,
                ),
                _middleBar(),
                Expanded(child: _panel(Side.waiter)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _middleBar() {
    Widget btn(IconData i, String tip, VoidCallback f, {bool big = false}) =>
        Tooltip(
          message: tip,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: f,
            child: Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: big ? 14 : 10, vertical: 8),
              child: big
                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(i, color: C.waiter),
                      const SizedBox(width: 6),
                      Text(tip,
                          style: const TextStyle(
                              color: C.waiter, fontWeight: FontWeight.w600)),
                    ])
                  : Icon(i, color: C.muted),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          btn(Icons.history, 'Cronologia', _history),
          const SizedBox(width: 4),
          btn(Icons.bolt_rounded, 'Frasi pronte', _phrases, big: true),
          const SizedBox(width: 4),
          btn(Icons.tune_rounded, 'Impostazioni', _openSettings),
          if (_translating) ...[
            const SizedBox(width: 8),
            const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2)),
          ],
        ],
      ),
    );
  }

  /// Ultimo messaggio rilevante per questo lato.
  Msg? get _last => _msgs.isEmpty ? null : _msgs.last;

  Widget _panel(Side side) {
    final code = _langOf(side);
    final lang = langOf(code);
    final accent = side == Side.waiter ? C.waiter : C.tourist;
    final listening = _listening == side;
    final m = _last;
    final scale = p.textScale;

    // cosa mostrare
    Widget content;
    if (listening) {
      content = _bigText(
        _partial.isEmpty ? ui(code, 'listening') : _partial,
        lang,
        size: 30 * scale,
        color: _partial.isEmpty ? C.muted : C.ink.withValues(alpha: 0.75),
        italic: _partial.isEmpty,
      );
    } else if (m != null && m.from != side) {
      // il messaggio dell'altro, tradotto nella mia lingua
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _bigText(m.translated, lang, size: 34 * scale),
          const SizedBox(height: 12),
          _smallText('${langOf(m.fromLang).flag}  ${m.original}',
              langOf(m.fromLang)),
        ],
      );
    } else if (m != null && m.from == side) {
      // quello che ho appena detto
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.check_circle, size: 18, color: accent),
            const SizedBox(width: 6),
            Text(side == Side.waiter ? 'Hai detto' : ui(code, 'you'),
                style: TextStyle(color: accent, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 8),
          _bigText(m.original, lang,
              size: 24 * scale, color: C.ink.withValues(alpha: 0.7)),
        ],
      );
    } else {
      content = _bigText(ui(code, 'speak'), lang,
          size: 26 * scale, color: C.muted);
    }

    return GlossCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        children: [
          Row(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _pickLang(side),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(lang.flag, style: const TextStyle(fontSize: 24)),
                    const SizedBox(width: 8),
                    Text(lang.name,
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: accent)),
                    Icon(Icons.expand_more, color: accent),
                  ]),
                ),
              ),
              const Spacer(),
              if (m != null && m.from != side)
                IconButton(
                  tooltip: 'Ripeti voce',
                  icon: const Icon(Icons.volume_up_rounded, color: C.muted),
                  onPressed: () => _voice.speak(m.translated, lang),
                ),
              IconButton(
                tooltip: 'Scrivi',
                icon: const Icon(Icons.keyboard_alt_outlined, color: C.muted),
                onPressed: () => _type(side),
              ),
            ],
          ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: KeyedSubtree(
                    key: ValueKey('${_msgs.length}-$listening-${_partial.length}'),
                    child: content,
                  ),
                ),
              ),
            ),
          ),
          _MicButton(
            accent: accent,
            listening: listening,
            level: listening ? _level : 0,
            onTap: () => _mic(side),
          ),
        ],
      ),
    );
  }

  Widget _bigText(String t, Lang l,
      {double size = 30, Color color = C.ink, bool italic = false}) {
    return Text(
      t,
      textAlign: TextAlign.center,
      textDirection: l.rtl ? TextDirection.rtl : TextDirection.ltr,
      style: TextStyle(
        fontSize: size,
        height: 1.25,
        fontWeight: FontWeight.w600,
        color: color,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      ),
    );
  }

  Widget _smallText(String t, Lang l) => Text(
        t,
        textAlign: TextAlign.center,
        textDirection: l.rtl ? TextDirection.rtl : TextDirection.ltr,
        style: const TextStyle(fontSize: 15, color: C.muted),
      );
}

/// Grande pulsante microfono lucido, pulsa con il volume della voce.
class _MicButton extends StatelessWidget {
  final Color accent;
  final bool listening;
  final double level; // circa -2..10 dal riconoscimento vocale
  final VoidCallback onTap;
  const _MicButton({
    required this.accent,
    required this.listening,
    required this.level,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = listening ? C.listening : accent;
    final ring = listening ? 4 + max(0.0, min(level, 10)) * 1.2 : 0.0;
    return SizedBox(
      width: 104,
      height: 104,
      child: Center(
        child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 72 + ring * 2,
        height: 72 + ring * 2,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: listening ? 0.15 : 0),
        ),
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color.lerp(color, Colors.white, 0.25)!, color],
            ),
            boxShadow: [
              BoxShadow(
                  color: color.withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 8)),
            ],
          ),
          child: Icon(listening ? Icons.stop_rounded : Icons.mic_rounded,
              color: Colors.white, size: 36),
        ),
      ),
        ),
      ),
    );
  }
}
