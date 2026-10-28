// Controlla su GitHub se c'è una versione nuova e la installa (come uno store).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'setup_page.dart' show buildNumber;

class Update {
  final int build;
  final String url;
  Update(this.build, this.url);
}

class Updater {
  static const _m = MethodChannel('tt/stt');
  static const _api =
      'https://api.github.com/repos/designer1974/table-translator/releases/latest';

  static int get current => int.tryParse(buildNumber) ?? 0;

  /// Versione più recente, se è più nuova di quella installata.
  static Future<Update?> check() async {
    if (current == 0) return null;
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await c.getUrl(Uri.parse(_api));
      req.headers.set('Accept', 'application/vnd.github+json');
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final j = jsonDecode(await res.transform(utf8.decoder).join()) as Map;
      final n = int.tryParse('${j['tag_name']}'.replaceAll(RegExp(r'\D'), ''));
      if (n == null || n <= current) return null;
      for (final a in (j['assets'] as List)) {
        if (a['name'] == 'DevooTranslator.apk') {
          return Update(n, a['browser_download_url'] as String);
        }
      }
    } catch (_) {
    } finally {
      c.close();
    }
    return null;
  }

  static Future<void> install(Update u) =>
      _m.invokeMethod('update', {'url': u.url});
}
