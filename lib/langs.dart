// Lingue supportate e frasi pronte per il cameriere.

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

const langs = <Lang>[
  Lang('it', 'Italiano', 'Italiano', '🇮🇹', 'it-IT', 'it-IT'),
  Lang('en', 'English', 'Inglese', '🇬🇧', 'en-GB', 'en-GB'),
  Lang('fr', 'Français', 'Francese', '🇫🇷', 'fr-FR', 'fr-FR'),
  Lang('de', 'Deutsch', 'Tedesco', '🇩🇪', 'de-DE', 'de-DE'),
  Lang('es', 'Español', 'Spagnolo', '🇪🇸', 'es-ES', 'es-ES'),
  Lang('ar', 'العربية', 'Arabo', '🇸🇦', 'ar-SA', 'ar-SA', rtl: true),
];

Lang langOf(String code) =>
    langs.firstWhere((l) => l.code == code, orElse: () => langs.first);

/// Testi dell'interfaccia mostrati al turista nella sua lingua.
const touristUi = <String, Map<String, String>>{
  'it': {'speak': 'Tocca e parla', 'listening': 'Sto ascoltando…', 'you': 'Hai detto'},
  'en': {'speak': 'Tap and speak', 'listening': 'Listening…', 'you': 'You said'},
  'fr': {'speak': 'Touchez et parlez', 'listening': 'J\'écoute…', 'you': 'Vous avez dit'},
  'de': {'speak': 'Tippen und sprechen', 'listening': 'Ich höre zu…', 'you': 'Sie sagten'},
  'es': {'speak': 'Toca y habla', 'listening': 'Escuchando…', 'you': 'Has dicho'},
  'ar': {'speak': 'اضغط وتحدث', 'listening': '…أستمع', 'you': 'قلت'},
};

String ui(String lang, String key) =>
    touristUi[lang]?[key] ?? touristUi['en']![key]!;

/// Frasi pronte del cameriere (in italiano), divise per momento del servizio.
const quickPhrases = <String, List<String>>{
  'Accoglienza': [
    'Buongiorno, benvenuti!',
    'Buonasera, benvenuti!',
    'Avete prenotato?',
    'Per quante persone?',
    'Prego, seguitemi.',
    'Preferite dentro o fuori?',
    'Un momento, preparo il tavolo.',
  ],
  'Ordine': [
    'Ecco il menù.',
    'Cosa vi porto da bere?',
    'Siete pronti per ordinare?',
    'Avete allergie o intolleranze?',
    'Questo piatto contiene glutine.',
    'Questo piatto contiene latte.',
    'Questo piatto contiene frutta secca.',
    'Questo piatto contiene carne di maiale.',
    'Questo piatto è vegetariano.',
    'Come preferisce la cottura della carne?',
    'Acqua naturale o frizzante?',
    'Il piatto del giorno è questo.',
    'Ci vogliono circa venti minuti.',
  ],
  'Servizio': [
    'Buon appetito!',
    'Va tutto bene?',
    'Desiderate altro?',
    'Volete un dolce o un caffè?',
    'Mi dispiace, è finito.',
    'Arrivo subito.',
  ],
  'Conto': [
    'Ecco il conto.',
    'Pagate insieme o separati?',
    'Accettiamo carte e contanti.',
    'Il servizio è incluso.',
    'Grazie, arrivederci!',
  ],
};
