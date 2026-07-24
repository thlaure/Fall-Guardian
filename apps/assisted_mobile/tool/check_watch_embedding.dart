import 'dart:io';

void main() {
  const projectPath = 'ios/Runner.xcodeproj/project.pbxproj';
  final project = File(projectPath).readAsStringSync();

  final requiredMarkers = <String, String>{
    'watch target': '/* FallGuardian Watch App */ = {\n'
        '\t\t\tisa = PBXNativeTarget;',
    'watch bundle identifier':
        'PRODUCT_BUNDLE_IDENTIFIER = com.fallguardian.app.watchkitapp;',
    'companion bundle identifier':
        'INFOPLIST_KEY_WKCompanionAppBundleIdentifier = '
            'com.fallguardian.app;',
    'watch source group':
        'path = "../../watchos/FallGuardian/FallGuardian Watch App";',
    'embedded watch product':
        'FallGuardian Watch App.app in Embed Watch Content',
    'watch target dependency':
        'target = F6C100242024072400000001 /* FallGuardian Watch App */;',
    'Fall Detection entitlement build setting':
        'CODE_SIGN_ENTITLEMENTS = "../../watchos/FallGuardian/FallGuardian '
            'Watch App/FallGuardian Watch App.entitlements";',
    'Fall Detection usage description':
        'INFOPLIST_KEY_NSFallDetectionUsageDescription = '
            '"Fall Guardian uses Apple Watch fall detection to alert linked '
            'caregivers when a fall occurs.";',
  };

  for (final entry in requiredMarkers.entries) {
    if (!project.contains(entry.value)) {
      stderr.writeln(
        'Missing ${entry.key} in $projectPath. '
        'The assistee build would no longer package its Watch companion.',
      );
      exitCode = 1;
      return;
    }
  }

  final runnerTarget = RegExp(
    r'97C146ED1CF9000F007C117D /\* Runner \*/ = '
    r'\{[\s\S]*?buildPhases = \(([\s\S]*?)\);',
  ).firstMatch(project);
  if (runnerTarget == null) {
    stderr.writeln('Unable to inspect Runner build phases in $projectPath.');
    exitCode = 1;
    return;
  }

  final phases = runnerTarget.group(1)!;
  final embedIndex = phases.indexOf('Embed Watch Content');
  final flutterBuildIndex = phases.indexOf('/* Run Script */');
  if (embedIndex < 0 ||
      flutterBuildIndex < 0 ||
      embedIndex > flutterBuildIndex) {
    stderr.writeln(
      'Embed Watch Content must run before Flutter Run Script to avoid an '
      'Xcode dependency cycle.',
    );
    exitCode = 1;
  }

  final watchApp = File(
    '../watchos/FallGuardian/FallGuardian Watch App/FallGuardianApp.swift',
  ).readAsStringSync();
  final entitlements = File(
    '../watchos/FallGuardian/FallGuardian Watch App/'
    'FallGuardian Watch App.entitlements',
  ).readAsStringSync();
  final standaloneProject = File(
    '../watchos/FallGuardian/FallGuardian.xcodeproj/project.pbxproj',
  ).readAsStringSync();

  final backgroundMarkers = <String, bool>{
    'early extension delegate setup':
        watchApp.contains('@WKApplicationDelegateAdaptor') &&
            watchApp.contains('applicationDidFinishLaunching'),
    'system Fall Detection manager':
        watchApp.contains('CMFallDetectionManager') &&
            watchApp.contains('didDetect event: CMFallDetectionEvent'),
    'Fall Detection entitlement': entitlements.contains(
      '<key>com.apple.developer.health.fall-detection</key>',
    ),
    'standalone Watch entitlement build setting': standaloneProject.contains(
      'CODE_SIGN_ENTITLEMENTS = "FallGuardian Watch App/'
      'FallGuardian Watch App.entitlements";',
    ),
    'standalone Watch usage description': standaloneProject.contains(
      'INFOPLIST_KEY_NSFallDetectionUsageDescription',
    ),
  };

  for (final entry in backgroundMarkers.entries) {
    if (!entry.value) {
      stderr.writeln(
        'Missing ${entry.key}. Background fall detection would regress.',
      );
      exitCode = 1;
    }
  }
}
