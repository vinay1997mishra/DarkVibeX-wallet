import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Decodes the base64 launcher-icon files (.b64 / .b64.partNN) stored in
// the repo back into real PNGs before the release build.
//
// The PNGs cannot be pushed to GitHub directly (the connector only takes
// UTF-8 text), so they live in the repo as base64 text. This test runs
// inside `flutter test`, which the Build APK workflow runs before
// `flutter build apk`, so the decoded PNGs are in place when the APK
// is built. If a `.b64` file also has `.b64.partNN` chunks, the chunks
// win (they carry the same data, split for upload).
void main() {
  test('decode base64 launcher icons into PNGs', () {
    final decoded = <String>[];

    for (final root in ['android/app/src/main/res', 'assets']) {
      final dir = Directory(root);
      if (!dir.existsSync()) continue;
      final files = dir
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => f.path)
          .toList();

      // Split files, grouped by their base .b64 path.
      final partGroups = <String, List<String>>{};
      for (final path in files) {
        final match = RegExp(r'^(.*\.b64)\.part(\d+)$').firstMatch(path);
        if (match != null) {
          partGroups.putIfAbsent(match.group(1)!, () => []).add(path);
        }
      }

      for (final entry in partGroups.entries) {
        entry.value.sort();
        final joined = entry.value
            .map((p) => File(p).readAsStringSync().trim())
            .join();
        final target = entry.key.substring(0, entry.key.length - 4);
        File(target)
          ..createSync(recursive: true)
          ..writeAsBytesSync(base64Decode(joined));
        decoded.add(target);
      }

      // Whole .b64 files (only when no part chunks exist for them).
      for (final path in files) {
        if (!path.endsWith('.b64') || partGroups.containsKey(path)) continue;
        final target = path.substring(0, path.length - 4);
        final bytes =
            base64Decode(File(path).readAsStringSync().trim());
        File(target)
          ..createSync(recursive: true)
          ..writeAsBytesSync(bytes);
        decoded.add(target);
      }
    }

    expect(decoded, isNotEmpty, reason: 'no .b64 icon files found');
    // Every decoded file must be a real PNG.
    const pngMagic = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    for (final target in decoded) {
      final bytes = File(target).readAsBytesSync();
      expect(bytes.length, greaterThan(100), reason: '$target too small');
      expect(bytes.sublist(0, 8), pngMagic, reason: '$target is not a PNG');
    }
  });
}
