// Lingue supportate e testi dell'interfaccia.

class Lang {
  final String code; // es. "ar"
  final String name; // nome nella propria lingua
  final String nameIt; // nome in italiano
  final String flag;
  final String speech; // locale per il riconoscimento vocale
  final String tts; // locale per la voce
  final bool rtl;
  const Lang(this.code, this.name, this.nameIt, this.flag, this.speech,
      this.tts, {this.rtl = false});
}

/// Lingue attive. La darija si ascolta con il riconoscimento marocchino
/// di Google (ar-MA) e si traduce con il modello arabo.
const langs = <Lang>[
  Lang('it', 'Italiano', 'Italiano', '🇮🇹', 'it-IT', 'it-IT'),
  Lang('en', 'English', 'Inglese', '🇬🇧', 'en-GB', 'en-GB'),
  Lang('es', 'Español', 'Spagnolo', '🇪🇸', 'es-ES', 'es-ES'),
  Lang('ar', 'الدارجة', 'Darija (Marocco)', '🇲🇦', 'ar-MA', 'ar-MA', rtl: true),
];

Lang langOf(String code) =>
    langs.firstWhere((l) => l.code == code, orElse: () => langs.first);

/// Testi dell'interfaccia mostrati al turista nella sua lingua.
const touristUi = <String, Map<String, String>>{
  'it': {'again': 'Non ho capito, ripeti', 'speak': 'Parla in italiano', 'listening': 'Sto ascoltando…', 'you': 'Hai detto'},
  'en': {'again': 'Sorry, please repeat', 'speak': 'Speak in English', 'listening': 'Listening…', 'you': 'You said'},
  'fr': {'again': 'Pardon, répétez', 'speak': 'Parlez en français', 'listening': 'J\'écoute…', 'you': 'Vous avez dit'},
  'de': {'again': 'Bitte wiederholen', 'speak': 'Bitte auf Deutsch sprechen', 'listening': 'Ich höre zu…', 'you': 'Sie sagten'},
  'es': {'again': 'Perdón, repite', 'speak': 'Habla en español', 'listening': 'Escuchando…', 'you': 'Has dicho'},
  'ar': {'again': 'ما فهمتش، عاود عافاك', 'speak': 'هضر بالدارجة', 'listening': '…كنسمع', 'you': 'قلتي'},
};

String ui(String lang, String key) =>
    touristUi[lang]?[key] ?? touristUi['en']![key]!;
