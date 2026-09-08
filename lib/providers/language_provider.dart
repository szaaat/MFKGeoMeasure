import 'package:flutter/material.dart';

class LanguageProvider with ChangeNotifier {
  Locale _currentLocale = const Locale('hu');

  Locale get currentLocale => _currentLocale;

  void changeLanguage(Locale locale) {
    if (!['hu', 'en'].contains(locale.languageCode)) return;
    _currentLocale = locale;
    notifyListeners();
  }
}
