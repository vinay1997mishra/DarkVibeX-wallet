// Seed backup + agreement policy — Vinay FINAL (2026-11-20).
//
// FINAL RULE — bilkul waisa hi likha hai jaisa final hua tha, apne words
// me badal kar NAHI likha gaya. Agreement screen, README aur code comments
// me yahi wording use hoti hai (neeche ke constants se — kahin haath se
// dobara type mat karo, taaki wording kabhi alag na ho):
//
//   - Wallet banega hi seed se, without Gmail and any other proofs.
//   - Seed server par PERMANENT rahegi (3 months tak nahi, permanent).
//   - Verification ONLY by the real original phone the wallet was created
//     on (same device).
//   - Real user ko seed owner se sirf 3 months ke andar milegi, AFTER
//     wallet logout (logout day se 3 months, wallet creation day se
//     nahi); uske baad owner kisi ko seed nahi dega, seed server par
//     saved rehne ke baad bhi.
//   - Agreement me 2 tickmarks — pehla agreement tick, uske baad dusra
//     tickmark show hoga usme seed-backup note likha hoga.
//   - "Your seed backup is saved. If you forget your seed, prove you are
//     a real user from your original phone and get your login back within
//     3 months after logout."
//
// SEPARATE OPEN NOTICE (terms me chhupa kar nahi — agreement screen par
// alag se khul kar dikhta hai):
//   - Seed backup PERMANENT save rehti hai, sirf user ki marzi se.
//   - Backup sirf OWNER dekh sakta hai — dusre users nahi dekh sakte.
//   - User backup SKIP kar sakta hai (tab seed server par save NAHI hoti)
//     aur baad me backup DELETE bhi kar sakta hai.
//
// ENCRYPTION (app side):
//   - Seed server par PLAIN TEXT me kabhi nahi jati, kabhi save nahi hoti.
//   - Bhejne se pehle seed AES-256-CBC (PKCS7) se encrypt hoti hai, random
//     IV ke saath. Server par sirf ciphertext + IV jata hai.
//   - Backup key (32 random bytes) SIRF is phone ki secure storage me
//     rehti hai — server par kabhi nahi jati, code me kabhi hardcode nahi
//     hoti, GitHub par kabhi nahi jati. Key ke bina server par pada
//     ciphertext kisi kaam ka nahi.
//   - PIN code me kahin store nahi hota (owner PIN ka hash alag service
//     me hai — lib/services/owner_lock_service.dart).
//
// RECOVERY (seed wapas pane ka flow):
//   - Logout date record hoti hai (wallet delete/logout karte hi).
//   - 3-month window LOGOUT day se shuru hoti hai, wallet creation day
//     se nahi. Window ke andar hi owner seed de sakta hai.
//   - Verification ONLY by the real original phone the wallet was created
//     on (same device) — device hash match hona chahiye. Seed-only ya
//     koi aur proof se recovery NAHI hoti.
//   - 3 months ke baad owner kisi ko seed nahi dega, seed server par
//     saved rehne ke baad bhi. Ye rule code me enforce hota hai
//     (SeedBackupPolicy.canDiscloseSeed) — sirf UI text nahi hai.
//
// HONEST LIMITS:
//   - Ye rule NORMAL LOGIN par lagu NAHI hota: normal user login ONLY by
//     seed hota hai (Vinay: phone verification wala part login se hata
//     diya gaya). Original-phone verification SIRF seed-backup recovery
//     ke liye hai.
//   - Server abhi DEPLOY nahi hua hai (SeedBackupConfig.backupApiBaseUrl
//     khaali hai) — tab tak upload `notConfigured` lautata hai aur backup
//     server par save NAHI hoti. App kabhi jhootha "saved" nahi dikhata.
//     Server stub: server/seed-backup-worker.js (STUB — deploy karna
//     Vinay ko hai, README dekho).
//   - Agar app uninstall ho jaye to backup key bhi mit jati hai — phir
//     server par pada ciphertext decrypt nahi ho sakta. Isliye 12 words
//     kagaz par likh kar rakhna abhi bhi sabse safe tareeka hai.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/cbc.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/padded_block_cipher/padded_block_cipher_impl.dart';
import 'package:pointycastle/paddings/pkcs7.dart';

import '../config.dart';

// ---------------------------------------------------------------------------
// FINAL RULE — constants. Yahi single source hai: agreement screen
// aur har jagah yahi constants use hote hain, taaki wording ek hi rahe.
// ---------------------------------------------------------------------------

class SeedBackupPolicy {
  /// Exact English wording (Vinay final — ek akshar bhi mat badlo).
  static const String exactNotice =
      'Your seed backup is saved. If you forget your seed, prove you are '
      'a real user from your original phone and get your login back within '
      '3 months after logout.';

  /// Final rule — same meaning as finalised; translated to English
  /// per Vinay's 100%-English order (2026-11-21).
  static const List<String> ruleLines = [
    'The wallet is created using only the seed, without Gmail and without any other proof.',
    'The seed stays on the server PERMANENTLY (not for 3 months — permanently).',
    'Verification ONLY by the real original phone the wallet was created on (same device).',
    'The real user will get the seed from the owner only within 3 months AFTER wallet logout (3 months from the logout day, not from the wallet creation day); after that, the owner will not give the seed to anyone, even though the seed stays saved on the server.',
    'The agreement has 2 tickmarks — first the agreement tick, and after that a second tickmark will appear with the seed-backup note written in it.',
  ];

  /// Recovery window: 3 months AFTER wallet logout.
  static const int recoveryWindowMonths = 3;

  /// Logout date se 3 calendar months baad — recovery ki aakhri date.
  /// Month-end clamp: jaise 30 Nov + 3 months = 28 Feb (30 Feb nahi hota).
  static DateTime recoveryDeadline(DateTime logoutAt) {
    final totalMonths = logoutAt.month - 1 + recoveryWindowMonths;
    final year = logoutAt.year + totalMonths ~/ 12;
    final month = totalMonths % 12 + 1;
    final lastDayOfMonth = DateTime(year, month + 1, 0).day;
    final day =
        logoutAt.day > lastDayOfMonth ? lastDayOfMonth : logoutAt.day;
    return DateTime(
      year,
      month,
      day,
      logoutAt.hour,
      logoutAt.minute,
      logoutAt.second,
    );
  }

  /// True sirf tab jab [now] logout ke baad aur deadline ke andar ho.
  /// Logout se pehle (wallet abhi phone me hai) owner recovery ki
  /// zaroorat hi nahi — user ke paas seed phone me hai.
  static bool isWithinRecoveryWindow(DateTime logoutAt, DateTime now) {
    if (now.isBefore(logoutAt)) return false;
    return !now.isAfter(recoveryDeadline(logoutAt));
  }

  /// Device id ka SHA-256 hash (hex). Raw device id kabhi server par
  /// nahi jata — sirf hash jata hai, taaki hash match se original phone
  /// verify ho sake.
  static String deviceHash(String deviceId) {
    final digest = SHA256Digest();
    final bytes = Uint8List.fromList(utf8.encode(deviceId));
    digest.update(bytes, 0, bytes.length);
    final out = Uint8List(32);
    digest.doFinal(out, 0);
    return out.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Seed kab owner de sakta hai — code-level enforcement, sirf UI nahi.
  static SeedBackupDisclosure canDiscloseSeed({
    required bool backupSaved,
    required DateTime? logoutAt,
    required bool isOriginalDevice,
    required DateTime now,
  }) {
    if (!backupSaved) return SeedBackupDisclosure.noBackup;
    if (logoutAt == null) return SeedBackupDisclosure.notLoggedOut;
    if (!isOriginalDevice) return SeedBackupDisclosure.wrongDevice;
    if (!isWithinRecoveryWindow(logoutAt, now)) {
      return SeedBackupDisclosure.windowExpired;
    }
    return SeedBackupDisclosure.allowed;
  }
}

/// Owner seed de sakta hai ya nahi — aur agar nahi to kyun.
enum SeedBackupDisclosure {
  /// Sab shartein poori — owner seed de sakta hai.
  allowed,

  /// Backup save hi nahi hui thi (user ne skip kiya tha / server set nahi).
  noBackup,

  /// Wallet abhi logout hi nahi hua — recovery window shuru hi nahi hui.
  notLoggedOut,

  /// Verification ONLY by the real original phone the wallet was created
  /// on (same device) — ye phone wo nahi hai.
  wrongDevice,

  /// 3 months ke baad owner kisi ko seed nahi dega, seed server par
  /// saved rehne ke baad bhi.
  windowExpired,
}

/// Agreement ke 2 tickmarks + Skip — pure state, UI is par hi chalti hai.
///
///   - Tick 1 (main agreement) ke bina tick 2 dikhta hi nahi.
///   - Aage badhne ke liye (tick 1 + tick 2) ya Skip — dono me se ek
///     chahiye. Skip ka matlab: NO seed backup, seed server par save
///     NAHI hogi.
class SeedBackupChoice {
  final bool agreedMain;
  final bool agreedBackup;
  final bool skipped;

  const SeedBackupChoice({
    this.agreedMain = false,
    this.agreedBackup = false,
    this.skipped = false,
  });

  /// Dono tick lage hon aur skip na kiya ho — tabhi backup save hogi.
  bool get wantsBackup => agreedMain && agreedBackup && !skipped;

  /// Aage badh sakte hain: (tick 1 + tick 2) ya Skip.
  bool get canProceed => (agreedMain && agreedBackup) || skipped;

  SeedBackupChoice copyWith({
    bool? agreedMain,
    bool? agreedBackup,
    bool? skipped,
  }) {
    return SeedBackupChoice(
      agreedMain: agreedMain ?? this.agreedMain,
      agreedBackup: agreedBackup ?? this.agreedBackup,
      skipped: skipped ?? this.skipped,
    );
  }
}

/// Seed backup ki local state.
enum SeedBackupStatus {
  /// Abhi koi choice record nahi (purana wallet / pehli baar).
  none,

  /// Ciphertext server par save ho gaya.
  saved,

  /// User ne skip kiya — seed server par save NAHI hui.
  skipped,

  /// Server URL set nahi hai — backup save NAHI hui (jhootha "saved" nahi).
  notConfigured,

  /// Upload try hua par server ne mana kar diya / network fail.
  uploadFailed,

  /// User ne backup delete kar di.
  deleted,
}

/// Ek backup ka record (local metadata — seed isme kabhi nahi hoti).
class SeedBackupInfo {
  final SeedBackupStatus status;
  final String? address;
  final DateTime? savedAt;
  final DateTime? logoutAt;

  const SeedBackupInfo({
    this.status = SeedBackupStatus.none,
    this.address,
    this.savedAt,
    this.logoutAt,
  });
}

// ---------------------------------------------------------------------------
// Encryption — AES-256-CBC (PKCS7), pointycastle. Seed plain text me kabhi
// server par nahi jati. Key phone se bahar kabhi nahi jati.
// ---------------------------------------------------------------------------

class SeedBackupCrypto {
  static const int _keyBytes = 32; // AES-256
  static const int _ivBytes = 16; // AES block size

  /// 32 random bytes — ek backup ki key. Secure storage me rehti hai,
  /// server par kabhi nahi jati, code me kabhi hardcode nahi hoti.
  static Uint8List generateKey() {
    final random = Random.secure();
    return Uint8List.fromList(
      List.generate(_keyBytes, (_) => random.nextInt(256)),
    );
  }

  /// 16 random bytes — har encryption ke liye naya IV.
  static Uint8List generateIv() {
    final random = Random.secure();
    return Uint8List.fromList(
      List.generate(_ivBytes, (_) => random.nextInt(256)),
    );
  }

  /// Seed -> (ciphertextBase64, ivBase64). Plain seed kahin save nahi hoti.
  static ({String ciphertextBase64, String ivBase64}) encryptSeed(
    String mnemonic,
    Uint8List key, {
    Uint8List? iv,
  }) {
    if (key.length != _keyBytes) {
      throw ArgumentError('The backup key must be 32 bytes (AES-256).');
    }
    final usedIv = iv ?? generateIv();
    final cipher = PaddedBlockCipherImpl(
      PKCS7Padding(),
      CBCBlockCipher(AESEngine()),
    );
    cipher.init(
      true,
      PaddedBlockCipherParameters(
        ParametersWithIV<KeyParameter>(KeyParameter(key), usedIv),
        null,
      ),
    );
    final plain = Uint8List.fromList(utf8.encode(mnemonic));
    final encrypted = cipher.process(plain);
    return (
      ciphertextBase64: base64.encode(encrypted),
      ivBase64: base64.encode(usedIv),
    );
  }

  /// (ciphertextBase64, ivBase64) -> seed. Galat key ya kharab data par
  /// throw karta hai — kabhi galat seed wapas nahi deta.
  static String decryptSeed(
    String ciphertextBase64,
    String ivBase64,
    Uint8List key,
  ) {
    if (key.length != _keyBytes) {
      throw ArgumentError('The backup key must be 32 bytes (AES-256).');
    }
    try {
      final cipher = PaddedBlockCipherImpl(
        PKCS7Padding(),
        CBCBlockCipher(AESEngine()),
      );
      cipher.init(
        false,
        PaddedBlockCipherParameters(
          ParametersWithIV<KeyParameter>(
            KeyParameter(key),
            base64.decode(ivBase64),
          ),
          null,
        ),
      );
      final decrypted = cipher.process(base64.decode(ciphertextBase64));
      return utf8.decode(decrypted);
    } catch (_) {
      throw StateError('The backup could not be decrypted — wrong key or corrupted data.');
    }
  }
}

// ---------------------------------------------------------------------------
// Storage abstraction — real: FlutterSecureStorage; tests: memory store.
// Seed backup ki keys wallet keys se ALAG hain (kabhi mix nahi hoti).
// ---------------------------------------------------------------------------

abstract class SeedBackupStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureStorageSeedBackupStore implements SeedBackupStore {
  final FlutterSecureStorage _storage;
  SecureStorageSeedBackupStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Tests ke liye in-memory store — phone storage ko chhoota hi nahi.
class MemorySeedBackupStore implements SeedBackupStore {
  final Map<String, String> values = {};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

// ---------------------------------------------------------------------------
// Service — backup save / logout record / recovery check / delete.
// ---------------------------------------------------------------------------

class SeedBackupService {
  static const String statusKey = 'seed_backup_status';
  static const String addressKey = 'seed_backup_address';
  static const String savedAtKey = 'seed_backup_saved_at';
  static const String logoutAtKey = 'seed_backup_logout_at';
  static const String deviceIdKey = 'seed_backup_device_id';
  static const String backupKeyKey = 'seed_backup_key';

  final SeedBackupStore _store;
  final http.Client _http;

  /// [backupApiBaseUrl] sirf tests ke liye hai — production me hamesha
  /// SeedBackupConfig.backupApiBaseUrl use hota hai.
  final String _baseUrl;

  SeedBackupService({
    SeedBackupStore? store,
    http.Client? httpClient,
    String? backupApiBaseUrl,
  })  : _store = store ?? SecureStorageSeedBackupStore(),
        _http = httpClient ?? http.Client(),
        _baseUrl = backupApiBaseUrl ?? SeedBackupConfig.backupApiBaseUrl;

  // --- status ---------------------------------------------------------------

  Future<SeedBackupInfo> getInfo() async {
    final statusRaw = await _store.read(statusKey);
    final status = SeedBackupStatus.values.firstWhere(
      (s) => s.name == statusRaw,
      orElse: () => SeedBackupStatus.none,
    );
    final address = await _store.read(addressKey);
    final savedAt = _parseDate(await _store.read(savedAtKey));
    final logoutAt = _parseDate(await _store.read(logoutAtKey));
    return SeedBackupInfo(
      status: status,
      address: address,
      savedAt: savedAt,
      logoutAt: logoutAt,
    );
  }

  static DateTime? _parseDate(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  // --- original device ------------------------------------------------------
  // Device id: ek random id, pehli baar wallet banate hi generate hoti hai
  // aur is phone ki secure storage me rehti hai (wallet delete hone par
  // bhi — taaki logout ke baad bhi original phone verify ho sake).
  // Server par sirf iska SHA-256 hash jata hai, raw id kabhi nahi.

  Future<String> ensureDeviceId() async {
    final existing = await _store.read(deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final bytes = Uint8List.fromList(
      List.generate(32, (_) => Random.secure().nextInt(256)),
    );
    final id = base64Url.encode(bytes);
    await _store.write(deviceIdKey, id);
    return id;
  }

  Future<String> currentDeviceHash() async {
    final id = await ensureDeviceId();
    return SeedBackupPolicy.deviceHash(id);
  }

  // --- backup save ----------------------------------------------------------

  /// Wallet save hone ke baad call karo (create/import).
  /// [choice] skip ho to kuch upload nahi hota — status `skipped`.
  /// Server URL set nahi ho to status `notConfigured` — backup save NAHI
  /// hui, aur UI ko ye sach dikhana chahiye.
  Future<SeedBackupStatus> saveBackup({
    required String mnemonic,
    required String address,
    required SeedBackupChoice choice,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    if (!choice.wantsBackup) {
      await _store.write(statusKey, SeedBackupStatus.skipped.name);
      await _store.write(addressKey, address);
      return SeedBackupStatus.skipped;
    }
    final baseUrl = _baseUrl;
    if (baseUrl.isEmpty) {
      await _store.write(statusKey, SeedBackupStatus.notConfigured.name);
      await _store.write(addressKey, address);
      return SeedBackupStatus.notConfigured;
    }
    // Encrypt pehle, phir bhejo — plain seed kabhi request me nahi jati.
    final key = SeedBackupCrypto.generateKey();
    final encrypted = SeedBackupCrypto.encryptSeed(mnemonic, key);
    final deviceHash = await currentDeviceHash();
    final payload = {
      'address': address,
      'ciphertext': encrypted.ciphertextBase64,
      'iv': encrypted.ivBase64,
      'deviceHash': deviceHash,
      'savedAt': at.toIso8601String(),
    };
    try {
      final response = await _http.post(
        Uri.parse('$baseUrl${SeedBackupConfig.backupPath}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      if (response.statusCode != 200 && response.statusCode != 201) {
        await _store.write(statusKey, SeedBackupStatus.uploadFailed.name);
        await _store.write(addressKey, address);
        return SeedBackupStatus.uploadFailed;
      }
    } catch (_) {
      await _store.write(statusKey, SeedBackupStatus.uploadFailed.name);
      await _store.write(addressKey, address);
      return SeedBackupStatus.uploadFailed;
    }
    // Key SIRF phone par rehti hai — server par kabhi nahi jati.
    await _store.write(backupKeyKey, base64.encode(key));
    await _store.write(statusKey, SeedBackupStatus.saved.name);
    await _store.write(addressKey, address);
    await _store.write(savedAtKey, at.toIso8601String());
    return SeedBackupStatus.saved;
  }

  // --- logout ---------------------------------------------------------------
  // Logout = wallet is phone se delete/logout. Isi din se 3 months ki
  // window shuru hoti hai (wallet creation day se nahi).

  /// Wallet delete/logout karte hi — deleteWallet() se PEHLE call karo.
  Future<void> recordLogout({DateTime? now}) async {
    final at = now ?? DateTime.now();
    await _store.write(logoutAtKey, at.toIso8601String());
  }

  /// Naya wallet save hote hi purana logout record khatam (nayi window
  /// tabhi shuru hogi jab ye wallet dobara logout hoga).
  Future<void> clearLogoutRecord() async {
    await _store.delete(logoutAtKey);
  }

  // --- recovery check (owner ke liye) ---------------------------------------
  // Owner seed dene se PEHLE ye check chalata hai. Koi bhi shart poori
  // na ho to seed NAHI milti — code ye enforce karta hai.

  Future<SeedBackupDisclosure> checkRecovery({
    required String presentedDeviceId,
    DateTime? now,
  }) async {
    final info = await getInfo();
    final storedId = await _store.read(deviceIdKey);
    final isOriginal = storedId != null &&
        storedId.isNotEmpty &&
        SeedBackupPolicy.deviceHash(presentedDeviceId) ==
            SeedBackupPolicy.deviceHash(storedId);
    return SeedBackupPolicy.canDiscloseSeed(
      backupSaved: info.status == SeedBackupStatus.saved,
      logoutAt: info.logoutAt,
      isOriginalDevice: isOriginal,
      now: now ?? DateTime.now(),
    );
  }

  /// Recovery ke liye server se ciphertext lao aur is phone ki key se
  /// decrypt karo. Sirf tab jab [checkRecovery] `allowed` de.
  /// (Server abhi set nahi ho to null — backup server par hai hi nahi.)
  Future<String?> recoverSeed({
    required String address,
    required String presentedDeviceId,
    DateTime? now,
  }) async {
    final disclosure = await checkRecovery(
      presentedDeviceId: presentedDeviceId,
      now: now,
    );
    if (disclosure != SeedBackupDisclosure.allowed) return null;
    final baseUrl = _baseUrl;
    if (baseUrl.isEmpty) return null;
    final keyRaw = await _store.read(backupKeyKey);
    if (keyRaw == null || keyRaw.isEmpty) return null;
    final deviceHash = SeedBackupPolicy.deviceHash(presentedDeviceId);
    final response = await _http.get(
      Uri.parse(
        '$baseUrl${SeedBackupConfig.backupPath}/${Uri.encodeComponent(address)}'
        '?deviceHash=${Uri.encodeComponent(deviceHash)}',
      ),
    );
    if (response.statusCode != 200) return null;
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final ciphertext = body['ciphertext'] as String?;
    final iv = body['iv'] as String?;
    if (ciphertext == null || iv == null) return null;
    return SeedBackupCrypto.decryptSeed(
      ciphertext,
      iv,
      base64.decode(keyRaw),
    );
  }

  // --- delete backup --------------------------------------------------------
  // User backup delete kar sakta hai: server se DELETE + local key/status
  // delete. Key mitne ke baad server par pada ciphertext kabhi decrypt
  // nahi ho sakta — delete asal me delete hai.

  Future<SeedBackupStatus> deleteBackup({required String address}) async {
    final baseUrl = _baseUrl;
    if (baseUrl.isNotEmpty) {
      try {
        await _http.delete(
          Uri.parse(
            '$baseUrl${SeedBackupConfig.backupPath}/${Uri.encodeComponent(address)}',
          ),
        );
      } catch (_) {
        // Server unreachable ho to bhi local delete hota hai — key mitne
        // ke baad server copy bekaar hai. Status `deleted` hi rehta hai.
      }
    }
    await _store.delete(backupKeyKey);
    await _store.delete(savedAtKey);
    await _store.write(statusKey, SeedBackupStatus.deleted.name);
    return SeedBackupStatus.deleted;
  }
}
