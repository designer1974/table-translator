import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'engine.dart';
import 'prefs.dart';
import 'setup_page.dart';
import 'theme.dart';
import 'voice_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: C.bgBottom,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final prefs = await Prefs.load();
  runApp(TableTranslatorApp(prefs: prefs));
}

class TableTranslatorApp extends StatelessWidget {
  final Prefs prefs;
  const TableTranslatorApp({super.key, required this.prefs});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Devoo Translator',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: StartGate(prefs: prefs),
    );
  }
}

/// Al primo avvio controlla che le lingue siano scaricate.
class StartGate extends StatefulWidget {
  final Prefs prefs;
  const StartGate({super.key, required this.prefs});

  @override
  State<StartGate> createState() => _StartGateState();
}

class _StartGateState extends State<StartGate> {
  bool? _ready;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final p = widget.prefs;
    List<String> missing;
    try {
      missing = await Models.missing([p.waiter, p.tourist]);
      final q = SttQuality.values.firstWhere((x) => x.name == p.stt,
          orElse: () => SttQuality.balanced);
      if (p.engine == 'whisper' && !await Stt(q).hasModel()) {
        missing.add('whisper');
      }
    } catch (_) {
      missing = [];
    }
    if (mounted) setState(() => _ready = missing.isEmpty);
  }

  @override
  Widget build(BuildContext context) {
    if (_ready == null) {
      return const Scaffold(
        body: MilkBackground(child: Center(child: CircularProgressIndicator())),
      );
    }
    if (_ready == false) {
      return SetupPage(
        first: true,
        prefs: widget.prefs,
        onDone: () => setState(() => _ready = true),
      );
    }
    return VoicePage(prefs: widget.prefs);
  }
}
