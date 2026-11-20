// Seed backup + agreement policy tests (Vinay FINAL, 2026-11-20).
// Run with: flutter test
// NO network (MockClient), NO real server, NO secure storage (memory store),
// NO real transaction. Sirf local logic + widget gating.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:usdt_wallet_app/config.dart';
import 'package:usdt_wallet_app/services/seed_backup_service.dart';
import 'package:usdt_wallet_app/widgets/seed_backup_agreement.dart';

const _testMnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
const _testAddress = 'TTestAddress12345678901234567890123';

void main() {
  group('FINAL RULE — verbatim wording (badli hui wording fail karegi)', () {
    test('exact English wording ek akshar bhi alag nahi', () {
      expect(
        SeedBackupPolicy.exactNotice,
        'Your seed backup is saved. If you forget your seed, prove you are '
        'a real user from your original phone and get your login back within '
        '3 months after logout.',
      );
    });

    test('rule lines bilkul waisi hi jaisi final hui thi', () {
      expect(SeedBackupPolicy.ruleLines, [
        'The wallet is created using only the seed, without Gmail and without any other proof.',
        'The seed stays on the server PERMANENTLY (not for 3 months — permanently).',
        'Verification ONLY by the real original phone the wallet was created on (same device).',
        'The real user will get the seed from the owner only within 3 months AFTER wallet logout (3 months from the logout day, not from the wallet creation day); after that, the owner will not give the seed to anyone, even though the seed stays saved on the server.',
        'The agreement has 2 tickmarks — first the agreement tick, and after that a second tickmark will appear with the seed-backup note written in it.',
      ]);
    });

    test('config: retention PERMANENT, window 3 months after logout', () {
      expect(SeedBackupConfig.retention, 'PERMANENT');
      expect(SeedBackupConfig.recoveryWindowMonths, 3);
      expect(SeedBackupPolicy.recoveryWindowMonths, 3);
      // Server abhi set nahi hai — backup upload nahi hota.
      expect(SeedBackupConfig.backupApiBaseUrl, isEmpty);
    });
  });

  group('Agreement choice gating (2 tickmarks + Skip)', () {
    test('kuch tick nahi to aage nahi badh sakte', () {
      expect(const SeedBackupChoice().canProceed, isFalse);
      expect(const SeedBackupChoice().wantsBackup, isFalse);
    });

    test('sirf pehla tick to aage nahi badh sakte', () {
      const c = SeedBackupChoice(agreedMain: true);
      expect(c.canProceed, isFalse);
      expect(c.wantsBackup, isFalse);
    });

    test('dono tick to backup ke saath aage badh sakte hain', () {
      const c = SeedBackupChoice(agreedMain: true, agreedBackup: true);
      expect(c.canProceed, isTrue);
      expect(c.wantsBackup, isTrue);
    });

    test('Skip = aage badh sakte hain, par NO backup', () {
      const c = SeedBackupChoice(agreedMain: true, skipped: true);
      expect(c.canProceed, isTrue);
      expect(c.wantsBackup, isFalse);
    });

    test('dono tick + skip ek saath ho to backup nahi', () {
      const c = SeedBackupChoice(
        agreedMain: true,
        agreedBackup: true,
        skipped: true,
      );
      expect(c.wantsBackup, isFalse);
    });
  });

  group('3-month recovery window — logout day se, creation day se nahi', () {
    test('logout 20 Nov 2026 -> deadline 20 Feb 2027', () {
      final logout = DateTime(2026, 11, 20, 10, 0);
      final deadline = SeedBackupPolicy.recoveryDeadline(logout);
      expect(deadline.year, 2027);
      expect(deadline.month, 2);
      expect(deadline.day, 20);
    });

    test('month-end clamp: 30 Nov + 3 months = 28 Feb (30 Feb nahi hota)', () {
      final deadline =
          SeedBackupPolicy.recoveryDeadline(DateTime(2026, 11, 30));
      expect(deadline, DateTime(2027, 2, 28));
    });

    test('deadline ke din tak window khuli, agle din band', () {
      final logout = DateTime(2026, 11, 20, 10, 0);
      expect(
        SeedBackupPolicy.isWithinRecoveryWindow(
          logout,
          DateTime(2027, 2, 20, 10, 0),
        ),
        isTrue,
      );
      expect(
        SeedBackupPolicy.isWithinRecoveryWindow(
          logout,
          DateTime(2027, 2, 21, 10, 0),
        ),
        isFalse,
      );
      expect(
        SeedBackupPolicy.isWithinRecoveryWindow(
          logout,
          DateTime(2027, 3, 1),
        ),
        isFalse,
      );
    });

    test('logout se pehle window shuru hi nahi hoti', () {
      final logout = DateTime(2026, 11, 20, 10, 0);
      expect(
        SeedBackupPolicy.isWithinRecoveryWindow(
          logout,
          DateTime(2026, 11, 19),
        ),
        isFalse,
      );
    });

    test('creation day se window nahi chalti — logout day se chalti hai', () {
      // Wallet 1 Jan ko bana, logout 20 Nov ko hua: deadline Feb 2027 hai,
      // April 2026 (creation + 3 months) nahi.
      final logout = DateTime(2026, 11, 20);
      expect(
        SeedBackupPolicy.isWithinRecoveryWindow(logout, DateTime(2026, 4, 1)),
        isFalse,
      );
      expect(
        SeedBackupPolicy.isWithinRecoveryWindow(logout, DateTime(2027, 1, 15)),
        isTrue,
      );
    });
  });

  group('canDiscloseSeed — code enforcement (sirf UI text nahi)', () {
    final now = DateTime(2026, 12, 1);
    final logout = DateTime(2026, 11, 20);

    test('sab shartein poori to allowed', () {
      expect(
        SeedBackupPolicy.canDiscloseSeed(
          backupSaved: true,
          logoutAt: logout,
          isOriginalDevice: true,
          now: now,
        ),
        SeedBackupDisclosure.allowed,
      );
    });

    test('backup save hi nahi hui (skip) to noBackup', () {
      expect(
        SeedBackupPolicy.canDiscloseSeed(
          backupSaved: false,
          logoutAt: logout,
          isOriginalDevice: true,
          now: now,
        ),
        SeedBackupDisclosure.noBackup,
      );
    });

    test('logout hi nahi hua to notLoggedOut', () {
      expect(
        SeedBackupPolicy.canDiscloseSeed(
          backupSaved: true,
          logoutAt: null,
          isOriginalDevice: true,
          now: now,
        ),
        SeedBackupDisclosure.notLoggedOut,
      );
    });

    test('original phone nahi to wrongDevice — seed-only se nahi', () {
      expect(
        SeedBackupPolicy.canDiscloseSeed(
          backupSaved: true,
          logoutAt: logout,
          isOriginalDevice: false,
          now: now,
        ),
        SeedBackupDisclosure.wrongDevice,
      );
    });

    test('3 months ke baad windowExpired — seed saved rehne ke baad bhi', () {
      expect(
        SeedBackupPolicy.canDiscloseSeed(
          backupSaved: true,
          logoutAt: logout,
          isOriginalDevice: true,
          now: DateTime(2027, 3, 1),
        ),
        SeedBackupDisclosure.windowExpired,
      );
    });
  });

  group('Device hash — original phone verification (no phone number)', () {
    test('same device id -> same hash, alag id -> alag hash', () {
      final a = SeedBackupPolicy.deviceHash('device-one');
      final b = SeedBackupPolicy.deviceHash('device-one');
      final c = SeedBackupPolicy.deviceHash('device-two');
      expect(a, b);
      expect(a, isNot(c));
      expect(a.length, 64); // SHA-256 hex
    });

    test('hash me raw device id nahi hota', () {
      final hash = SeedBackupPolicy.deviceHash('my-secret-device-id');
      expect(hash.contains('my-secret-device-id'), isFalse);
    });
  });

  group('Encryption — seed plain text me kahin nahi jati', () {
    test('encrypt -> decrypt round-trip se wahi seed wapas', () {
      final key = SeedBackupCrypto.generateKey();
      final enc = SeedBackupCrypto.encryptSeed(_testMnemonic, key);
      expect(
        SeedBackupCrypto.decryptSeed(enc.ciphertextBase64, enc.ivBase64, key),
        _testMnemonic,
      );
    });

    test('har encryption ka IV alag — same seed, alag ciphertext', () {
      final key = SeedBackupCrypto.generateKey();
      final a = SeedBackupCrypto.encryptSeed(_testMnemonic, key);
      final b = SeedBackupCrypto.encryptSeed(_testMnemonic, key);
      expect(a.ivBase64, isNot(b.ivBase64));
      expect(a.ciphertextBase64, isNot(b.ciphertextBase64));
    });

    test('ciphertext me seed ka ek word bhi nahi hota', () {
      final key = SeedBackupCrypto.generateKey();
      final enc = SeedBackupCrypto.encryptSeed(_testMnemonic, key);
      expect(enc.ciphertextBase64.contains('abandon'), isFalse);
      expect(enc.ciphertextBase64.contains('about'), isFalse);
    });

    test('galat key se decrypt nahi hota', () {
      final key = SeedBackupCrypto.generateKey();
      final otherKey = SeedBackupCrypto.generateKey();
      final enc = SeedBackupCrypto.encryptSeed(_testMnemonic, key);
      expect(
        () => SeedBackupCrypto.decryptSeed(
          enc.ciphertextBase64,
          enc.ivBase64,
          otherKey,
        ),
        throwsStateError,
      );
    });

    test('32-byte se chhoti key reject hoti hai', () {
      expect(
        () => SeedBackupCrypto.encryptSeed(
          _testMnemonic,
          Uint8List.fromList([1, 2, 3]),
        ),
        throwsArgumentError,
      );
    });
  });

  group('SeedBackupService — skip / no-server / upload / recovery / delete', () {
    late MemorySeedBackupStore store;

    setUp(() {
      store = MemorySeedBackupStore();
    });

    test('Skip = status skipped, koi HTTP call nahi, koi key nahi', () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response('{}', 201);
      });
      final service = SeedBackupService(
        store: store,
        httpClient: client,
        backupApiBaseUrl: 'https://example.workers.dev',
      );
      final status = await service.saveBackup(
        mnemonic: _testMnemonic,
        address: _testAddress,
        choice: const SeedBackupChoice(agreedMain: true, skipped: true),
      );
      expect(status, SeedBackupStatus.skipped);
      expect(calls, 0);
      expect(await store.read(SeedBackupService.backupKeyKey), isNull);
      expect((await service.getInfo()).status, SeedBackupStatus.skipped);
    });

    test('server URL set nahi ho to notConfigured — jhootha saved nahi', () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response('{}', 201);
      });
      final service = SeedBackupService(
        store: store,
        httpClient: client,
        backupApiBaseUrl: '',
      );
      final status = await service.saveBackup(
        mnemonic: _testMnemonic,
        address: _testAddress,
        choice: const SeedBackupChoice(agreedMain: true, agreedBackup: true),
      );
      expect(status, SeedBackupStatus.notConfigured);
      expect(calls, 0);
      expect((await service.getInfo()).status, SeedBackupStatus.notConfigured);
    });

    test('upload: body me plain seed nahi, sirf ciphertext + deviceHash', () async {
      Map<String, dynamic>? sentBody;
      final client = MockClient((request) async {
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('{"ok":true}', 201);
      });
      final service = SeedBackupService(
        store: store,
        httpClient: client,
        backupApiBaseUrl: 'https://example.workers.dev',
      );
      final status = await service.saveBackup(
        mnemonic: _testMnemonic,
        address: _testAddress,
        choice: const SeedBackupChoice(agreedMain: true, agreedBackup: true),
      );
      expect(status, SeedBackupStatus.saved);
      expect(sentBody, isNotNull);
      expect(sentBody!['address'], _testAddress);
      expect(sentBody!.containsKey('mnemonic'), isFalse);
      expect(sentBody!.containsKey('seed'), isFalse);
      expect(sentBody!['ciphertext'], isNotEmpty);
      expect(sentBody!['ciphertext'].toString().contains('abandon'), isFalse);
      expect(sentBody!['deviceHash'], isNotEmpty);
      // Backup key phone par hai, request me nahi gayi.
      final storedKey = await store.read(SeedBackupService.backupKeyKey);
      expect(storedKey, isNotNull);
      expect(jsonEncode(sentBody).contains(storedKey!), isFalse);
      // Ciphertext stored key se decrypt hota hai.
      expect(
        SeedBackupCrypto.decryptSeed(
          sentBody!['ciphertext'] as String,
          sentBody!['iv'] as String,
          base64.decode(storedKey),
        ),
        _testMnemonic,
      );
    });

    test('poora recovery flow: logout -> window ke andar allowed, baad me expired', () async {
      final client = MockClient((_) async => http.Response('{"ok":true}', 201));
      final service = SeedBackupService(
        store: store,
        httpClient: client,
        backupApiBaseUrl: 'https://example.workers.dev',
      );
      await service.saveBackup(
        mnemonic: _testMnemonic,
        address: _testAddress,
        choice: const SeedBackupChoice(agreedMain: true, agreedBackup: true),
      );
      final deviceId = await service.ensureDeviceId();
      // Logout se pehle recovery nahi.
      expect(
        await service.checkRecovery(
          presentedDeviceId: deviceId,
          now: DateTime(2026, 11, 19),
        ),
        SeedBackupDisclosure.notLoggedOut,
      );
      // Logout 20 Nov 2026.
      await service.recordLogout(now: DateTime(2026, 11, 20, 10, 0));
      // Original phone, window ke andar -> allowed.
      expect(
        await service.checkRecovery(
          presentedDeviceId: deviceId,
          now: DateTime(2026, 12, 15),
        ),
        SeedBackupDisclosure.allowed,
      );
      // Dusra phone -> wrongDevice.
      expect(
        await service.checkRecovery(
          presentedDeviceId: 'koi-aur-phone',
          now: DateTime(2026, 12, 15),
        ),
        SeedBackupDisclosure.wrongDevice,
      );
      // 3 months ke baad -> windowExpired (seed saved rehne ke baad bhi).
      expect(
        await service.checkRecovery(
          presentedDeviceId: deviceId,
          now: DateTime(2027, 3, 1),
        ),
        SeedBackupDisclosure.windowExpired,
      );
      // Naya wallet save hote hi logout record clear.
      await service.clearLogoutRecord();
      expect((await service.getInfo()).logoutAt, isNull);
    });

    test('deleteBackup: status deleted, key mit jati hai', () async {
      final client = MockClient((_) async => http.Response('{"ok":true}', 201));
      final service = SeedBackupService(
        store: store,
        httpClient: client,
        backupApiBaseUrl: 'https://example.workers.dev',
      );
      await service.saveBackup(
        mnemonic: _testMnemonic,
        address: _testAddress,
        choice: const SeedBackupChoice(agreedMain: true, agreedBackup: true),
      );
      expect(await store.read(SeedBackupService.backupKeyKey), isNotNull);
      final status = await service.deleteBackup(address: _testAddress);
      expect(status, SeedBackupStatus.deleted);
      expect(await store.read(SeedBackupService.backupKeyKey), isNull);
      expect((await service.getInfo()).status, SeedBackupStatus.deleted);
    });
  });

  group('SeedBackupAgreementCard widget — tick 2 pehle tick ke baad hi', () {
    testWidgets('pehle tick ke baad dusra tick + exact notice dikhta hai',
        (tester) async {
      SeedBackupChoice? latest;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SeedBackupAgreementCard(
                onChanged: (c) => latest = c,
              ),
            ),
          ),
        ),
      );
      // Shuru me dusra tick nahi dikhta.
      expect(find.textContaining('I have read the seed-backup note'), findsNothing);
      expect(find.textContaining(SeedBackupPolicy.exactNotice), findsNothing);
      // Pehla tick lagao.
      await tester.ensureVisible(find.byType(Checkbox).first);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();
      // Ab dusra tick + exact notice dikhta hai.
      expect(find.textContaining('I have read the seed-backup note'), findsOneWidget);
      expect(
        find.textContaining(SeedBackupPolicy.exactNotice),
        findsOneWidget,
      );
      // Dusra tick lagao -> dono tick, canProceed true.
      await tester.ensureVisible(find.byType(Checkbox).last);
      await tester.tap(find.byType(Checkbox).last);
      await tester.pump();
      expect(latest, isNotNull);
      expect(latest!.canProceed, isTrue);
      expect(latest!.wantsBackup, isTrue);
    });

    testWidgets('Skip dabane par NO backup, phir bhi aage badh sakte hain',
        (tester) async {
      SeedBackupChoice? latest;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SeedBackupAgreementCard(
                onChanged: (c) => latest = c,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.textContaining('Skip — continue'));
      await tester.pump();
      expect(latest, isNotNull);
      expect(latest!.skipped, isTrue);
      expect(latest!.canProceed, isTrue);
      expect(latest!.wantsBackup, isFalse);
      expect(find.textContaining('seed backup will NOT be saved'), findsOneWidget);
    });
  });
}
