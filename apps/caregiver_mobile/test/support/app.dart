import 'package:caregiver_app/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

Widget testApp(Widget home, {Locale locale = const Locale('en')}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: const [AppLocalizations.delegate],
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );
}
