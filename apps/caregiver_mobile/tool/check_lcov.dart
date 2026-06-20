import 'dart:io';

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln(
      'Usage: dart run tool/check_lcov.dart <lcov.info> <minimum> [excluded-path-substring ...]',
    );
    exit(64);
  }

  final file = File(args[0]);
  final minimum = double.parse(args[1]);
  final excludedPathParts = args.skip(2).toList();
  if (!file.existsSync()) {
    stderr.writeln('Coverage file not found: ${file.path}');
    exit(66);
  }

  var found = 0;
  var hit = 0;
  var excluded = false;
  for (final line in file.readAsLinesSync()) {
    if (line.startsWith('SF:')) {
      final sourceFile = line.substring(3);
      excluded = excludedPathParts.any(sourceFile.contains);
    } else if (!excluded && line.startsWith('LF:')) {
      found += int.parse(line.substring(3));
    } else if (!excluded && line.startsWith('LH:')) {
      hit += int.parse(line.substring(3));
    }
  }

  final coverage = found == 0 ? 0.0 : hit * 100 / found;
  stdout.writeln('Line coverage: ${coverage.toStringAsFixed(2)}%');
  if (coverage < minimum) {
    stderr.writeln(
      'Coverage ${coverage.toStringAsFixed(2)}% is below ${minimum.toStringAsFixed(2)}%.',
    );
    exit(1);
  }
}
