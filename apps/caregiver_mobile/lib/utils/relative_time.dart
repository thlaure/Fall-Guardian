import '../l10n/app_localizations.dart';

/// Short localized "x min ago" label. Future timestamps (phone clock behind
/// the server) are shown as "just now" rather than a negative duration.
String relativeTimeLabel(AppLocalizations l10n, DateTime then, DateTime now) {
  final elapsed = now.difference(then);
  if (elapsed.inMinutes < 1) return l10n.justNow;
  if (elapsed.inHours < 1) return l10n.minutesAgo(elapsed.inMinutes);
  if (elapsed.inDays < 1) return l10n.hoursAgo(elapsed.inHours);
  return l10n.daysAgo(elapsed.inDays);
}
