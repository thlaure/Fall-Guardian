DateTime? parseApiDateTime(String? value) {
  if (value == null) return null;

  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;

  final hasExplicitTimezone = RegExp(
    r'(Z|z|[+-]\d{2}:?\d{2})$',
  ).hasMatch(trimmed);
  final normalized = hasExplicitTimezone ? trimmed : '${trimmed}Z';

  return DateTime.tryParse(normalized);
}
