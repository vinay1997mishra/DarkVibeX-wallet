// Hidden owner login — secret tap sequence tests.
//
// Owner login sirf version text par 7 baar tap (5 second ke andar) se
// khulta hai. 6 baar tap par kuch nahi hona chahiye, aur window ke
// bahar ke purane tap gin-ti me nahi aane chahiye.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usdt_wallet_app/widgets/secret_owner_tap.dart';

void main() {
  group('SecretTapCounter (7 taps, 5s window)', () {
    test('7 tez tap par trigger hota hai', () {
      final counter = SecretTapCounter();
      var triggered = false;
      for (var i = 0; i < 6; i++) {
        triggered = counter.registerTap();
        expect(triggered, isFalse, reason: 'tap ${i + 1} par trigger nahi');
      }
      triggered = counter.registerTap();
      expect(triggered, isTrue, reason: '7th tap par trigger hona chahiye');
    });

    test('6 tap par trigger nahi hota', () {
      final counter = SecretTapCounter();
      var triggered = false;
      for (var i = 0; i < 6; i++) {
        triggered = counter.registerTap();
      }
      expect(triggered, isFalse);
    });

    test('trigger ke baad counter reset — phir se 7 tap chahiye', () {
      final counter = SecretTapCounter();
      for (var i = 0; i < 7; i++) {
        counter.registerTap();
      }
      expect(counter.registerTap(), isFalse,
          reason: 'reset ke baad pehla tap trigger nahi');
    });

    test('window ke bahar ke purane tap gin-ti me nahi aate', () {
      final counter = SecretTapCounter(
        window: const Duration(milliseconds: 50),
      );
      for (var i = 0; i < 6; i++) {
        counter.registerTap();
      }
      // Window nikal jaye to purane 6 tap khatam — naye 7 tap chahiye.
      return Future.delayed(const Duration(milliseconds: 80), () {
        var triggered = false;
        for (var i = 0; i < 6; i++) {
          triggered = counter.registerTap();
        }
        expect(triggered, isFalse,
            reason: 'purane tap + naye 6 tap = trigger nahi');
        expect(counter.registerTap(), isTrue,
            reason: 'naye 7 tap par trigger hona chahiye');
      });
    });

    test('default 7 taps hi hai — 5 tap wala purana rule nahi', () {
      expect(SecretTapCounter().tapsToTrigger, 7);
    });
  });

  group('SecretOwnerTapDetector (widget)', () {
    testWidgets('version text dikhta hai, 6 tap par kuch nahi, 7th par trigger',
        (tester) async {
      var triggered = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SecretOwnerTapDetector(
              onTriggered: () => triggered = true,
              child: const Text('Version 0.1.0'),
            ),
          ),
        ),
      );

      // Version text dikhna chahiye — chhupa hua kuch nahi, koi
      // "Owner Login" hint nahi.
      expect(find.text('Version 0.1.0'), findsOneWidget);
      expect(find.textContaining('Owner'), findsNothing);

      final versionFinder = find.text('Version 0.1.0');
      for (var i = 0; i < 6; i++) {
        await tester.tap(versionFinder);
        await tester.pump();
        expect(triggered, isFalse, reason: 'tap ${i + 1} par trigger nahi');
      }
      await tester.tap(versionFinder);
      await tester.pump();
      expect(triggered, isTrue, reason: '7th tap par trigger hona chahiye');
    });
  });
}
