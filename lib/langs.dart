// Lingue supportate e testi dell'interfaccia.

class Lang {
  final String code; // es. "it", "ary" (darija)
  final String name; // nome nella propria lingua
  final String nameIt; // nome in italiano
  final String flag;
  final String speech; // locale per il riconoscimento vocale
  final String tts; // locale per la voce
  final bool rtl;
  final String english; // nome in inglese (per l'interprete AI)
  const Lang(this.code, this.name, this.nameIt, this.flag, this.speech,
      this.tts, {this.rtl = false, this.english = ''});
}

/// Lingue principali (anche senza AI: traduzione sul telefono).
const langs = <Lang>[
  Lang('it', 'Italiano', 'Italiano', '🇮🇹', 'it-IT', 'it-IT', english: 'Italian'),
  Lang('en', 'English', 'Inglese', '🇬🇧', 'en-GB', 'en-GB', english: 'English'),
  Lang('es', 'Español', 'Spagnolo', '🇪🇸', 'es-ES', 'es-ES', english: 'Spanish'),
  Lang('ary', 'الدارجة', 'Darija (Marocco)', '🇲🇦', 'ar-MA', 'ar-MA',
      rtl: true, english: 'Moroccan Arabic (Darija)'),
];

/// Altre lingue riconosciute dall'interprete AI.
const moreLangs = <Lang>[
  Lang('fr', 'Français', 'Francese', '🇫🇷', 'fr-FR', 'fr-FR', english: 'French'),
  Lang('de', 'Deutsch', 'Tedesco', '🇩🇪', 'de-DE', 'de-DE', english: 'German'),
  Lang('pt', 'Português', 'Portoghese', '🇵🇹', 'pt-PT', 'pt-PT', english: 'Portuguese'),
  Lang('ar', 'العربية', 'Arabo', '🇸🇦', 'ar-SA', 'ar-SA', rtl: true, english: 'Arabic'),
  Lang('ro', 'Română', 'Rumeno', '🇷🇴', 'ro-RO', 'ro-RO', english: 'Romanian'),
  Lang('sq', 'Shqip', 'Albanese', '🇦🇱', 'sq-AL', 'sq-AL', english: 'Albanian'),
  Lang('uk', 'Українська', 'Ucraino', '🇺🇦', 'uk-UA', 'uk-UA', english: 'Ukrainian'),
  Lang('ru', 'Русский', 'Russo', '🇷🇺', 'ru-RU', 'ru-RU', english: 'Russian'),
  Lang('pl', 'Polski', 'Polacco', '🇵🇱', 'pl-PL', 'pl-PL', english: 'Polish'),
  Lang('nl', 'Nederlands', 'Olandese', '🇳🇱', 'nl-NL', 'nl-NL', english: 'Dutch'),
  Lang('tr', 'Türkçe', 'Turco', '🇹🇷', 'tr-TR', 'tr-TR', english: 'Turkish'),
  Lang('zh', '中文', 'Cinese', '🇨🇳', 'zh-CN', 'zh-CN', english: 'Chinese (Mandarin)'),
  Lang('ja', '日本語', 'Giapponese', '🇯🇵', 'ja-JP', 'ja-JP', english: 'Japanese'),
  Lang('ko', '한국어', 'Coreano', '🇰🇷', 'ko-KR', 'ko-KR', english: 'Korean'),
  Lang('hi', 'हिन्दी', 'Hindi', '🇮🇳', 'hi-IN', 'hi-IN', english: 'Hindi'),
  Lang('ur', 'اردو', 'Urdu', '🇵🇰', 'ur-PK', 'ur-PK', rtl: true, english: 'Urdu'),
  Lang('bn', 'বাংলা', 'Bengalese', '🇧🇩', 'bn-BD', 'bn-IN', english: 'Bengali'),
  Lang('fa', 'فارسی', 'Persiano', '🇮🇷', 'fa-IR', 'fa-IR', rtl: true, english: 'Persian'),
  Lang('el', 'Ελληνικά', 'Greco', '🇬🇷', 'el-GR', 'el-GR', english: 'Greek'),
];

const allLangs = <Lang>[...langs, ...moreLangs];

/// Lingua dal codice; per lingue sconosciute crea una voce generica.
Lang langOf(String code) {
  if (code == 'ar-ma') code = 'ary';
  for (final l in allLangs) {
    if (l.code == code) return l;
  }
  if (RegExp(r'^[a-z]{2,3}$').hasMatch(code) && code != 'xx') {
    return Lang(code, code.toUpperCase(), code.toUpperCase(), '🌐', code, code,
        english: code);
  }
  return langs.first;
}

/// Testi dell'interfaccia mostrati al turista nella sua lingua.
const touristUi = <String, Map<String, String>>{
  'it': {'again': 'Non ho capito, ripeti', 'speak': 'Parla in italiano', 'listening': 'Sto ascoltando…', 'you': 'Hai detto'},
  'en': {'again': 'Sorry, please repeat', 'speak': 'Speak in English', 'listening': 'Listening…', 'you': 'You said'},
  'fr': {'again': 'Pardon, répétez', 'speak': 'Parlez en français', 'listening': 'J\'écoute…', 'you': 'Vous avez dit'},
  'de': {'again': 'Bitte wiederholen', 'speak': 'Bitte auf Deutsch sprechen', 'listening': 'Ich höre zu…', 'you': 'Sie sagten'},
  'es': {'again': 'Perdón, repite', 'speak': 'Habla en español', 'listening': 'Escuchando…', 'you': 'Has dicho'},
  'ar': {'again': 'لم أفهم، أعد من فضلك', 'speak': 'تحدث بالعربية', 'listening': '…أستمع', 'you': 'قلت'},
  'ary': {'again': 'ما فهمتش، عاود عافاك', 'speak': 'هضر بالدارجة', 'listening': '…كنسمع', 'you': 'قلتي'},
};

String ui(String lang, String key) =>
    touristUi[lang]?[key] ?? touristUi['en']![key]!;
