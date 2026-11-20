// Owner lock for the in-app Recovery Wallet.
//
// SIRF OWNER khol sakta hai — normal user Recovery Wallet screen par
// PIN/biometric ke bina balance, address, seed ya history kuch nahi
// dekh sakta.
//
//   - Owner PIN: 4-6 digit PIN. Pehli baar Recovery Wallet banate waqt
//     set hota hai. PIN kabhi plain text me save nahi hota — sirf uska
//     SHA-256 hash + salt secure storage me rehta hai.
//   - Biometric: fingerprint / Face ID, sirf PIN ke saath optional
//     shortcut hai (local_auth package). Phone me biometric set nahi
//     hai to ye option dikhega hi nahi — PIN se hi khulega.
//   - PIN bhool gaye? App me koi "PIN reset" button nahi hai — jaan
//     boojh kar. Ek hi rasta hai: recovery wallet ke 12 words (seed)
//     se verify karke naya PIN set karo (see resetPinWithSeed).
//     Seed bhi nahi hai to recovery wallet kabhi nahi khul payega —
//     isiliye seed ko kagaz par likh kar safe jagah rakhna hai.
//
// Main wallet aur recovery wallet ke keys secure storage me ALAG-ALAG
// keys se save hote hain (see recovery_wallet_service.dart) — is file
// me sirf owner lock ke keys hain, wallet keys yahan kabhi nahi aate.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:pointycastle/digests/sha256.dart';

import 'recovery_wallet_service.dart';
import 'wallet_service.dart';

class OwnerLockService {
  static const _storage = FlutterSecureStorage();

  // Secure-storage keys — ONLY for the owner lock. Wallet keys live
  // under different keys (usdt_wallet_* and recovery_wallet_*).
  static const String pinHashKey = 'recovery_owner_pin_hash';
  static const String pinSaltKey = 'recovery_owner_pin_salt';
  static const String biometricEnabledKey = 'recovery_biometric_enabled';

  final FlutterSecureStorage _store;
  final LocalAuthentication _auth;

  OwnerLockService({
    FlutterSecureStorage? storage,
    LocalAuthentication? auth,
  })  : _store = storage ?? _storage,
        _auth = auth ?? LocalAuthentication();

  // ---------------------------------------------------------------------------
  // PIN: pure helpers (no storage — safe to unit test)
  // ---------------------------------------------------------------------------

  /// PIN sirf 4-6 digit hona chahiye.
  static bool isValidPin(String pin) =>
      RegExp(r'^[0-9]{4,6}$').hasMatch(pin);

  /// SHA-256(PIN + salt) as hex. Salt har baar alag hota hai, isliye
  /// do users ka same PIN bhi alag hash banta hai.
  static String hashPin(String pin, String salt) {
    final digest = SHA256Digest();
    final bytes = Uint8List.fromList(utf8.encode('$salt:$pin'));
    digest.update(bytes, 0, bytes.length);
    final out = Uint8List(32);
    digest.doFinal(out, 0);
    return out.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static String generateSalt([int length = 16]) {
    final random = Random.secure();
    final bytes = Uint8List.fromList(
      List.generate(length, (_) => random.nextInt(256)),
    );
    return base64Url.encode(bytes);
  }

  // ---------------------------------------------------------------------------
  // PIN: storage
  // ---------------------------------------------------------------------------

  /// True if an owner PIN has ever been set.
  Future<bool> hasPin() async {
    final hash = await _store.read(key: pinHashKey);
    return hash != null && hash.isNotEmpty;
  }

  /// Sets (or replaces) the owner PIN. Throws if the PIN format is wrong.
  /// The plain PIN is never stored — only hash + salt.
  Future<void> setPin(String pin) async {
    if (!isValidPin(pin)) {
      throw Exception('PIN 4-6 digit ka hona chahiye.');
    }
    final salt = generateSalt();
    await _store.write(key: pinSaltKey, value: salt);
    await _store.write(key: pinHashKey, value: hashPin(pin, salt));
  }

  /// True if [pin] matches the saved PIN. Wrong PIN = false, no exception.
  Future<bool> verifyPin(String pin) async {
    final hash = await _store.read(key: pinHashKey);
    final salt = await _store.read(key: pinSaltKey);
    if (hash == null || salt == null) return false;
    return hashPin(pin, salt) == hash;
  }

  /// PIN badlo: pehle purana PIN sahi hona chahiye, phir naya PIN set.
  Future<bool> changePin(String oldPin, String newPin) async {
    if (!await verifyPin(oldPin)) return false;
    await setPin(newPin);
    return true;
  }

  /// Deletes the whole owner lock (PIN + biometric setting). Only used
  /// when the recovery wallet itself is deleted — a fresh recovery
  /// wallet starts with a fresh PIN.
  Future<void> clearLock() async {
    await _store.delete(key: pinHashKey);
    await _store.delete(key: pinSaltKey);
    await _store.delete(key: biometricEnabledKey);
  }

  /// PIN bhool gaye to ek hi rasta: recovery wallet ke 12 words se
  /// verify karo. Seed se bane address ka stored recovery address se
  /// milna zaroori hai — galat seed se PIN reset nahi hoga.
  /// Returns true only if the seed matches the stored recovery wallet.
  Future<bool> resetPinWithSeed(String mnemonic, String newPin) async {
    if (!isValidPin(newPin)) return false;
    final clean = mnemonic.trim().split(RegExp(r'\s+')).join(' ');
    try {
      final derived = WalletService.deriveFromMnemonic(clean);
      final storedAddress =
          await _store.read(key: RecoveryWalletService.addressKey);
      if (storedAddress == null || storedAddress != derived.address) {
        return false;
      }
    } catch (_) {
      return false;
    }
    await setPin(newPin);
    return true;
  }

  // ---------------------------------------------------------------------------
  // Biometric: fingerprint / Face ID (optional shortcut, PIN is the fallback)
  // ---------------------------------------------------------------------------

  /// True if this phone can do biometrics at all (hardware + enrolled).
  Future<bool> canUseBiometric() async {
    try {
      return await _auth.canCheckBiometrics ||
          await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// True if the owner turned the biometric shortcut ON.
  Future<bool> isBiometricEnabled() async {
    final value = await _store.read(key: biometricEnabledKey);
    return value == 'true';
  }

  /// Turns the biometric shortcut on/off. Turning it ON first asks for
  /// a real biometric check, so koi aur tumhare phone se ise on nahi
  /// kar sakta. Turning it OFF needs the PIN (checked by the caller).
  Future<bool> setBiometricEnabled(bool enabled) async {
    if (enabled) {
      if (!await authenticateWithBiometric(
        reason: 'Biometric unlock on karne ke liye verify karo',
      )) {
        return false;
      }
    }
    await _store.write(
      key: biometricEnabledKey,
      value: enabled ? 'true' : 'false',
    );
    return true;
  }

  /// One biometric prompt. Returns true only on success. Any failure,
  /// cancellation or missing hardware returns false — never throws,
  /// so the UI can always fall back to the PIN.
  Future<bool> authenticateWithBiometric({
    String reason = 'Recovery Wallet kholne ke liye verify karo',
  }) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
