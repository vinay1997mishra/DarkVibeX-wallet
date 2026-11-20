// In-app Recovery Wallet (special wallet) — separate from the main wallet.
//
// Vinay ka final call: recovery wallet BAHAR ka external address NAHI
// hai. Ye app ke andar hi ek alag wallet hai:
//   - Apna 12-word seed, apna Tron address, apni private key.
//   - Main wallet se ALAG secure-storage keys — dono kabhi mix nahi hote.
//   - Sirf OWNER khol sakta hai (owner PIN + biometric, see
//     owner_lock_service.dart + recovery_wallet_screen.dart).
//
// Kaam:
//   - Galat network wale send par user [Recovery wallet me bhejo]
//     dabaye to paise isi wallet ke address par jate hain.
//   - Owner is wallet ko khol kar balance dekhta hai aur "Wapas bhejo"
//     se paise user ke sahi address par wapas bhej sakta hai.
//   - Is wallet ka seed SIRF owner ke paas safe rahe — usi se paise
//     wapas milenge. PIN bhool jao to seed se PIN dobara set hota hai
//     (OwnerLockService.resetPinWithSeed), seed bhi kho gaya to paise
//     hamesha ke liye gaye.

import 'package:bip39/bip39.dart' as bip39;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'wallet_service.dart';

/// Preview shown BEFORE saving: owner must write the words down first.
class RecoveryWalletPreview {
  final String mnemonic;
  final String address;
  const RecoveryWalletPreview({required this.mnemonic, required this.address});
}

class RecoveryWalletService {
  static const _storage = FlutterSecureStorage();

  // Secure-storage keys — recovery wallet ONLY. Main wallet uses
  // usdt_wallet_mnemonic / usdt_wallet_private_key / usdt_wallet_address.
  // Alag keys hone se main aur recovery wallet kabhi mix nahi hote.
  static const String mnemonicKey = 'recovery_wallet_mnemonic';
  static const String privateKeyKey = 'recovery_wallet_private_key';
  static const String addressKey = 'recovery_wallet_address';

  /// Recovery wallet is phone me kab bana/import hua — ISO 8601.
  /// Owner accounts list me creation date ke liye. Purane wallet me
  /// ye key nahi hogi — tab date "pata nahi".
  static const String createdAtKey = 'recovery_wallet_created_at';

  final FlutterSecureStorage _store;

  RecoveryWalletService({FlutterSecureStorage? storage})
      : _store = storage ?? _storage;

  /// True if a recovery wallet already exists in this app.
  Future<bool> hasRecoveryWallet() async {
    final address = await _store.read(key: addressKey);
    return address != null && address.isNotEmpty;
  }

  /// The recovery wallet's Tron address, or null if not created yet.
  /// The ADDRESS alone is not secret — but the screen only shows it
  /// after the owner unlocks, so a normal user never sees it.
  Future<String?> getRecoveryAddress() =>
      _store.read(key: addressKey);

  /// Makes a new 12-word phrase + address. Does NOT save anything —
  /// call [saveWallet] only after the owner wrote the words down.
  RecoveryWalletPreview generatePreview() {
    final mnemonic = bip39.generateMnemonic();
    final derived = WalletService.deriveFromMnemonic(mnemonic);
    return RecoveryWalletPreview(
      mnemonic: mnemonic,
      address: derived.address,
    );
  }

  /// Saves a recovery wallet from its 12-word (or 24-word) phrase.
  /// Throws if the phrase is not a valid BIP39 phrase.
  /// Returns the Tron address.
  Future<String> saveWallet(String mnemonic) async {
    final clean = mnemonic.trim().split(RegExp(r'\s+')).join(' ');
    if (!bip39.validateMnemonic(clean)) {
      throw Exception('This seed phrase is wrong. Check the 12 words again.');
    }
    final derived = WalletService.deriveFromMnemonic(clean);
    await _store.write(key: mnemonicKey, value: clean);
    await _store.write(key: privateKeyKey, value: derived.privateKeyHex);
    await _store.write(key: addressKey, value: derived.address);
    await _store.write(
      key: createdAtKey,
      value: DateTime.now().toIso8601String(),
    );
    return derived.address;
  }

  /// The saved seed phrase. ONLY call after the owner unlocks —
  /// the screen enforces this; this service does not show it itself.
  Future<String?> getMnemonic() => _store.read(key: mnemonicKey);

  /// Private key for signing a "wapas bhejo" send FROM the recovery
  /// wallet. Only TronGridService (via the recovery send flow) calls this.
  Future<String> getPrivateKeyHex() async {
    final key = await _store.read(key: privateKeyKey);
    if (key == null || key.isEmpty) {
      throw Exception('Recovery wallet not found. Create one first.');
    }
    return key;
  }

  /// Deletes the recovery wallet from this phone. Money stays on the
  /// blockchain — the same 12 words can bring it back anywhere.
  /// Only the owner (after unlock) can do this.
  Future<void> deleteWallet() async {
    await _store.delete(key: mnemonicKey);
    await _store.delete(key: privateKeyKey);
    await _store.delete(key: addressKey);
    await _store.delete(key: createdAtKey);
  }
}
