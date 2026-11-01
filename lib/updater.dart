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
  // le app si scaricano da «devoo-apps» (pubblico); il progetto col codice può essere privato
  static const _sources = [
    ('designer1974/devoo-apps', 'translator-build-'),
    ('designer1974/table-translator', 'build-'),
  ];

  static int get current => int.tryParse(buildNumber) ?? 0;

  /// Versione più recente, se è più nuova di quella installata.
  static Future<Update?> check() async {
    if (current == 0) return null;
    Update? best;
    for (final (repo, prefix) in _sources) {
      final c = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      try {
        final req = await c.getUrl(Uri.parse('https://api.github.com/repos/$repo/releases?per_page=20'));
        req.headers.set('Accept', 'application/vnd.github+json');
        req.headers.set('User-Agent', 'DevooTranslator');
        final res = await req.close().timeout(const Duration(seconds: 10));
        if (res.statusCode != 200) continue;
        final list = jsonDecode(await res.transform(utf8.decoder).join());
        if (list is! List) continue;
        for (final j in list) {
          if (j is! Map) continue;
          final tag = '${j['tag_name']}';
          if (!tag.startsWith(prefix)) continue;
          final n = int.tryParse(tag.substring(prefix.length));
          if (n == null || n <= current || (best != null && n <= best.build)) continue;
          for (final a in (j['assets'] as List? ?? const [])) {
            if (a is Map && a['name'] == 'DevooTranslator.apk') {
              best = Update(n, '${a['browser_download_url']}');
            }
          }
        }
      } catch (_) {
      } finally {
        c.close();
      }
    }
    return best;
  }

  static Future<void> install(Update u) =>
      _m.invokeMethod('update', {'url': u.url});
}
