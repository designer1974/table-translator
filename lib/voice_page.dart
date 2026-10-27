import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'engine.dart';
import 'google_stt.dart';
import 'langs.dart';
import 'orb.dart';
import 'prefs.dart';
import 'settings_page.dart';
import 'theme.dart';

enum Side { waiter, tourist }

class Msg {
  final Side from;
  final String fromLang, toLang, original, translated;
  Msg(this.from, this.fromLang, this.toLang, this.original, this.translated);
}

/// Schermata unica: sfera al centro, turni automatici, traduzione grande.
class VoicePage extends StatefulWidget {
  final Prefs prefs;
  const VoicePage({super.key, required this.prefs});

  @override
  State<VoicePage> createState() => _VoicePageState();
}

class _VoicePageState extends State<VoicePage> with WidgetsBindingObserver {
  Prefs get p => widget.prefs;
  final _tr = Translator();
  final _det = Detector();
  final _voice = Voice();
  final _ear = Ear();
  late Stt _stt;
  final _g = GoogleStt(); // riconoscimento veloce (predefinito)
  bool get _fast => p.engine != 'whisper';
  String _live = ''; // testo che arriva mentre la persona parla

  final _msgs = <Msg>[];
  final _text = TextEditingController();
  Side _turn = Side.waiter;
  OrbMode _mode = OrbMode.idle;
  bool _running = false; // conversazione avviata
  double _level = 0;
  String? _hint; // messaggio sotto la sfera (es. "Non ho capito")

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _stt = Stt(SttQuality.values.firstWhere((q) => q.name == p.stt,
        orElse: () => SttQuality.balanced));
    _voice.init();
    _applyPrefs();
    p.addListener(_applyPrefs);
    _ear
      ..onLevel = (v) {
        if (mounted &&
            (_mode == OrbMode.listening || _mode == OrbMode.hearing)) {
          setState(() => _level = v);
        }
      }
      ..onSpeechStart = () {
        if (mounted) setState(() => _mode = OrbMode.hearing);
      }
      ..onUtterance = _onUtterance;
    _g
      ..onReady = () {
        if (mounted && _running) setState(() => _mode = OrbMode.listening);
      }
      ..onBegin = () {
        if (mounted && _running) setState(() => _mode = OrbMode.hearing);
      }
      ..onLevel = (v) {
        if (mounted &&
            (_mode == OrbMode.listening || _mode == OrbMode.hearing)) {
          setState(() => _level = v);
        }
      }
      ..onPartial = (t) {
        if (mounted && _running) {
          setState(() {
            _live = t;
            _mode = OrbMode.hearing;
          });
        }
      }
      ..onFinal = _onText
      ..onError = (code) {
        if (!mounted || !_running) return;
        if (code == 6 || code == 7) {
          // nessuno ha parlato: continua ad ascoltare
          Future.delayed(const Duration(milliseconds: 250), _listen);
          return;
        }
        if (code == 8 || code == 5 || code == 11) {
          Future.delayed(const Duration(milliseconds: 700), _listen);
          return;
        }
        setState(() {
          _mode = OrbMode.paused;
          _hint = sttErrorText(code);
        });
      };
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    p.removeListener(_applyPrefs);
    _ear.dispose();
    _g.dispose();
    _voice.stop();
    _tr.dispose();
    _det.dispose();
    _stt.release();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    // app in secondo piano: ferma il microfono
    if (s == AppLifecycleState.paused && _running) _stop();
  }

  void _applyPrefs() {
    _voice.rate = p.rate;
    _voice.pitch = p.pitch;
    _voice.chosen.clear();
    p.voices.forEach((k, v) {
      final parts = v.split('|');
      if (parts.length == 2) {
        _voice.chosen[k] = {'name': parts[0], 'locale': parts[1]};
      }
    });
    _ear.vad.pause = Duration(milliseconds: (p.pauseSec * 1000).round());
    _g.pause = Duration(milliseconds: (p.pauseSec * 1000).round());
    final q = SttQuality.values
        .firstWhere((x) => x.name == p.stt, orElse: () => SttQuality.balanced);
    if (q != _stt.quality) {
      _stt.release();
      _stt = Stt(q);
    }
  }

  String _lang(Side s) => s == Side.waiter ? p.waiter : p.tourist;
  Side _other(Side s) => s == Side.waiter ? Side.tourist : Side.waiter;
  Color _color(Side s) => s == Side.waiter ? C.waiter : C.tourist;

  void _snack(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  // ---------------- conversazione ----------------

  Future<void> _start() async {
    if (!await _ear.permission()) {
      _snack('Serve il permesso del microfono');
      return;
    }
    if (_fast) {
      final info = await _g.info();
      if (info['available'] != true || info['using'] == null) {
        if (mounted) _noGoogleDialog();
        return;
      }
    } else {
      if (!await _stt.hasModel()) {
        _snack('Scarica prima il riconoscimento offline in Impostazioni');
        return;
      }
      if (!await _ear.start()) return;
      _ear.pause();
    }
    WakelockPlus.enable();
    HapticFeedback.mediumImpact();
    setState(() {
      _running = true;
      _hint = null;
    });
    _listen();
  }

  void _noGoogleDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Riconoscimento vocale non trovato'),
        content: const Text(
          'Per la modalità veloce serve l\'app "Google" sul telefono '
          '(dal Play Store). Puoi anche usare la modalità offline '
          '(più lenta) in Impostazioni.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _stop() async {
    await _g.cancel();
    await _ear.close();
    await _voice.stop();
    WakelockPlus.disable();
    if (mounted) {
      setState(() {
        _running = false;
        _mode = OrbMode.idle;
        _level = 0;
        _live = '';
      });
    }
  }

  void _listen() {
    if (!_running || !mounted) return;
    setState(() {
      _mode = OrbMode.listening;
      _level = 0;
      _live = '';
    });
    if (_fast) {
      _g.start(langOf(_lang(_turn)).speech).catchError((e) {
        if (mounted) setState(() => _hint = 'Errore: $e');
      });
    } else {
      _ear.resume();
    }
  }

  void _pauseListening() {
    if (_fast) {
      _g.cancel();
    } else {
      _ear.pause();
    }
  }

  /// Testo riconosciuto (modalità veloce).
  Future<void> _onText(String text) async {
    if (!mounted || !_running) return;
    final side = _turn;
    if (text.trim().isEmpty) {
      setState(() => _hint = ui(_lang(side), 'again'));
      _listen();
      return;
    }
    await _deliver(side, text, _lang(side));
  }

  Future<void> _onOrbTap() async {
    switch (_mode) {
      case OrbMode.idle:
        await _start();
      case OrbMode.listening:
      case OrbMode.hearing:
        _pauseListening();
        setState(() {
          _mode = OrbMode.paused;
          _live = '';
        });
      case OrbMode.paused:
        _listen();
      case OrbMode.speaking:
        await _voice.stop(); // salta la lettura
      case OrbMode.thinking:
        break;
    }
  }

  Future<void> _onUtterance(Uint8List pcm) async {
    final side = _turn;
    if (!mounted) return;
    setState(() {
      _mode = OrbMode.thinking;
      _level = 0;
    });
    String text = '';
    try {
      text = await _stt.transcribe(pcm, _lang(side));
    } catch (e) {
      _snack('Errore riconoscimento: $e');
    }
    if (!mounted || !_running) return;
    if (text.isEmpty) {
      setState(() => _hint = ui(_lang(side), 'again'));
      _listen();
      return;
    }
    await _deliver(side, text, _lang(side));
  }

  /// Traduce, mostra, legge e passa il turno all'altra persona.
  Future<void> _deliver(Side side, String text, String from) async {
    final to = from == p.waiter ? p.tourist : p.waiter;
    final fromSide = from == p.waiter ? Side.waiter : Side.tourist;
    setState(() {
      _mode = OrbMode.thinking;
      _hint = null;
      _live = text;
    });
    String out;
    try {
      out = await _tr.translate(text, from, to);
    } catch (e) {
      _snack('Traduzione non riuscita: scarica le lingue in Impostazioni');
      if (_running) _listen();
      return;
    }
    if (!mounted) return;
    setState(() {
      _msgs.add(Msg(fromSide, from, to, text, out));
      _turn = _other(fromSide); // ora tocca all'altra persona
      _mode = OrbMode.speaking;
      _live = '';
    });
    if (p.autoSpeak) {
      try {
        await _voice.speak(out, langOf(to));
      } catch (_) {}
    }
    if (!mounted) return;
    if (_running) {
      _listen();
    } else {
      setState(() => _mode = OrbMode.idle);
    }
  }

  Future<void> _sendTyped() async {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    _text.clear();
    FocusScope.of(context).unfocus();
    _pauseListening();
    // rileva la lingua scritta: decide la direzione
    final d = await _det.detect(t);
    final from = (d == p.tourist || d == p.waiter) ? d! : _lang(_turn);
    await _deliver(from == p.waiter ? Side.waiter : Side.tourist, t, from);
  }

  void _swapTurn() {
    HapticFeedback.selectionClick();
    setState(() {
      _turn = _other(_turn);
      _hint = null;
    });
    if (_running && (_mode == OrbMode.hearing || _mode == OrbMode.listening)) {
      _pauseListening();
      _listen();
    }
  }

  Future<void> _pickLang(Side side) async {
    final current = _lang(side);
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
                          color: l.code == current ? _color(side) : C.border,
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
      _snack('Scarico ${missing.map((c) => langOf(c).nameIt).join(', ')}…');
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
    if (phrase == null) return;
    _pauseListening();
    if (p.waiter == 'it') {
      await _deliver(Side.waiter, phrase, 'it');
    } else {
      // frasi scritte in italiano: prima nella lingua del cameriere
      final w = await _tr.translate(phrase, 'it', p.waiter);
      await _deliver(Side.waiter, w, p.waiter);
    }
  }

  void _history() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.bgTop,
      showDragHandle: true,
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
                            color: _color(m.from).withValues(alpha: 0.35)),
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
    if (_running) await _stop();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SettingsPage(prefs: p, voice: _voice)),
    );
    if (mounted) setState(() {});
  }

  // ---------------- interfaccia ----------------

  /// Etichetta di stato: sempre chiaro se sta ascoltando o no.
  (IconData, String, Color) _badge(Color color) {
    final l = langOf(_lang(_turn));
    return switch (_mode) {
      OrbMode.idle => (Icons.play_arrow_rounded, 'TOCCA PER INIZIARE', C.muted),
      OrbMode.listening => (Icons.mic_rounded, 'IN ASCOLTO · ${l.nameIt.toUpperCase()}', C.listening),
      OrbMode.hearing => (Icons.graphic_eq_rounded, 'TI SENTO…', C.listening),
      OrbMode.thinking => (Icons.translate_rounded, 'TRADUCO…', color),
      OrbMode.speaking => (Icons.volume_up_rounded, 'LEGGO LA TRADUZIONE', color),
      OrbMode.paused => (Icons.pause_rounded, 'IN PAUSA · TOCCA LA SFERA', C.muted),
    };
  }

  Widget _statusArea(Color color) {
    final (icon, label, c) = _badge(color);
    final l = langOf(_lang(_turn));
    final big = _live.isNotEmpty
        ? _live
        : _hint ??
            switch (_mode) {
              OrbMode.listening => ui(l.code, 'speak'),
              OrbMode.idle => _msgs.isEmpty
                  ? 'Il cameriere parla per primo'
                  : 'Tocca la sfera per continuare',
              _ => '',
            };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: c.withValues(alpha: 0.5)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (_mode == OrbMode.listening || _mode == OrbMode.hearing)
                Container(
                  width: 9,
                  height: 9,
                  margin: const EdgeInsets.only(right: 7),
                  decoration:
                      BoxDecoration(color: c, shape: BoxShape.circle),
                ),
              Icon(icon, size: 18, color: c),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      color: c,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      fontSize: 13)),
            ]),
          ),
          const SizedBox(height: 10),
          Text(
            big,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            textDirection: _hint == null && l.rtl && _mode != OrbMode.idle
                ? TextDirection.rtl
                : null,
            style: TextStyle(
              fontSize: _live.isNotEmpty ? 22 : 18,
              fontWeight: _live.isNotEmpty ? FontWeight.w600 : FontWeight.w500,
              color: _live.isNotEmpty ? C.ink : (_hint != null ? C.listening : color),
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = _color(_turn);
    final last = _msgs.isEmpty ? null : _msgs.last;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: MilkBackground(
        child: SafeArea(
          child: Column(
            children: [
              // barra in alto
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    _roundBtn(Icons.chat_bubble_outline_rounded, _history),
                    const Spacer(),
                    _roundBtn(Icons.bolt_rounded, _phrases),
                    const SizedBox(width: 10),
                    _roundBtn(Icons.tune_rounded, _openSettings),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // le due lingue
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(child: _langPill(Side.waiter)),
                    IconButton(
                      tooltip: 'Cambia turno',
                      onPressed: _swapTurn,
                      icon: const Icon(Icons.swap_horiz_rounded,
                          color: C.muted, size: 28),
                    ),
                    Expanded(child: _langPill(Side.tourist)),
                  ],
                ),
              ),
              // sfera
              Expanded(
                flex: 5,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Orb(
                        mode: _mode,
                        level: _level,
                        color: color,
                        flag: langOf(_lang(_turn)).flag,
                        size: 190,
                        onTap: _onOrbTap,
                      ),
                      _statusArea(color),
                    ],
                  ),
                ),
              ),
              // ultima traduzione
              Expanded(
                flex: 4,
                child: last == null
                    ? const SizedBox()
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: GlossCard(
                          padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
                          child: _lastCard(last),
                        ),
                      ),
              ),
              _bottomBar(color),
            ],
          ),
        ),
      ),
    );
  }

  Widget _lastCard(Msg m) {
    final to = langOf(m.toLang), from = langOf(m.fromLang);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('${from.flag}  ${m.original}',
                    textDirection:
                        from.rtl ? TextDirection.rtl : TextDirection.ltr,
                    style: const TextStyle(fontSize: 15, color: C.muted)),
                const SizedBox(height: 10),
                Text(
                  '${to.flag}  ${m.translated}',
                  textDirection: to.rtl ? TextDirection.rtl : TextDirection.ltr,
                  style: TextStyle(
                    fontSize: 26 * p.textScale,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                    color: C.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
        Column(
          children: [
            IconButton(
              tooltip: 'Ripeti voce',
              icon: const Icon(Icons.volume_up_rounded, color: C.muted),
              onPressed: () => _voice.speak(m.translated, to),
            ),
            IconButton(
              tooltip: 'Schermo intero',
              icon: const Icon(Icons.open_in_full_rounded, color: C.muted),
              onPressed: () => _fullScreen(m),
            ),
          ],
        ),
      ],
    );
  }

  void _fullScreen(Msg m) {
    final to = langOf(m.toLang);
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: true,
        pageBuilder: (_, __, ___) => GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Scaffold(
            backgroundColor: Colors.white,
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(
                      width: MediaQuery.of(context).size.width - 48,
                      child: Text(
                        '${to.flag}\n${m.translated}',
                        textAlign: TextAlign.center,
                        textDirection:
                            to.rtl ? TextDirection.rtl : TextDirection.ltr,
                        style: const TextStyle(
                            fontSize: 44,
                            height: 1.2,
                            fontWeight: FontWeight.w800,
                            color: C.ink),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _roundBtn(IconData i, VoidCallback f) => Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 2,
        shadowColor: const Color(0x336B5A3A),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: f,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Icon(i, color: C.ink, size: 24),
          ),
        ),
      );

  Widget _langPill(Side side) {
    final l = langOf(_lang(side));
    final active = _turn == side && _mode != OrbMode.idle;
    final color = _color(side);
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => _pickLang(side),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.12) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: active ? color : C.border, width: active ? 2 : 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(l.flag, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(l.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: active ? color : C.ink)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar(Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x1A6B5A3A),
                      blurRadius: 12,
                      offset: Offset(0, 4)),
                ],
              ),
              child: TextField(
                controller: _text,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendTyped(),
                style: const TextStyle(fontSize: 17),
                decoration: InputDecoration(
                  hintText: 'Scrivi… (lingua riconosciuta da sola)',
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 16),
                  suffixIcon: IconButton(
                    icon: Icon(Icons.send_rounded, color: color),
                    onPressed: _sendTyped,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // avvia / ferma la conversazione
          Material(
            color: _running ? C.ink : color,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _running ? _stop : _start,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Icon(
                    _running ? Icons.close_rounded : Icons.mic_rounded,
                    color: Colors.white,
                    size: 28),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
