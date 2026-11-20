// Owner accounts — app me stored SAARE wallet accounts ki list,
// SIRF owner ko dikhane ke liye.
//
// Kya dikhta hai: main wallet + recovery/special wallet — jo bhi app
// me stored hai. Import kiya hua wallet main wallet ki keys me hi
// save hota hai, isliye wo "Main Wallet" ke roop me list me aata hai
// (alag account nahi banta — import main wallet ko replace karta hai).
//
// Har account ke liye: address (Tron T... + EVM 0x... — dono ek hi
// seed se bante hain), network (Tron / Ethereum / BNB Smart Chain),
// creation date, aur — owner lock kholne ke BAAD hi — seed/private key.
//
// RULES:
//   - List bhi owner lock ke bina nahi khulti — screen pehle PIN /
//     biometric maangti hai (OwnerLockService, wahi lock jo Recovery
//     Wallet ka hai). Bina lock ke address, balance, seed — kuch nahi.
//   - Koi server nahi — sab kuch local secure storage se padha jata hai.
//   - Koi account delete / change nahi hota — sirf view. Delete
//     karna ho to Home / Recovery Wallet screen se hi hota hai.
//   - Creation date sirf un wallet ki milegi jo is feature ke baad
//     bane/import hue (save karte waqt createdAt likha jata hai).
//     Purane wallet me date nahi hogi — tab "pata nahi" dikhega.

import 'package:bip39/bip39.dart' as bip39;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'recovery_wallet_service.dart';
import 'wallet_service.dart';

/// App me stored account ka type.
enum StoredAccountKind { main, recovery }

/// Ek stored wallet account — seed/private key isme NAHI aati.
/// Seed/private key screen sirf unlock ke baad, alag se, per-account
/// reveal button se padhti hai (WalletService / RecoveryWalletService
/// ke getters se) — ye list sirf pehchan + date deti hai.
class StoredAccount {
  final StoredAccountKind kind;

  /// Screen par dikhane wala naam.
  final String label;

  /// Tron address (T...). Null = is kind ka wallet app me nahi hai.
  final String? tronAddress;

  /// Ethereum/BNB address (0x..., EIP-55) — wahi seed se banta hai.
  /// Seed na ho to null.
  final String? evmAddress;

  /// Wallet is phone me kab add hua (create/import). Null = is feature
  /// se pehle bana tha, date pata nahi.
  final DateTime? createdAt;

  /// Seed stored hai ya nahi (address hone par hamesha true hota hai,
  /// lekin list ye assume nahi karti).
  final bool hasSeed;

  const StoredAccount({
    required this.kind,
    required this.label,
    required this.tronAddress,
    required this.evmAddress,
    required this.createdAt,
    required this.hasSeed,
  });

  /// Is account ke networks — dono addresses ek hi seed se hain.
  List<String> get networks => const [
        'Tron (TRC20)',
        'Ethereum (ERC20)',
        'BNB Smart Chain (BEP20)',
      ];
}

class OwnerAccountsService {
  static const _storage = FlutterSecureStorage();

  final FlutterSecureStorage _store;

  OwnerAccountsService({FlutterSecureStorage? storage})
      : _store = storage ?? _storage;

  /// App me stored saare accounts ki list. Seed/private key isme
  /// kabhi nahi aati — wo sirf unlock ke baad screen alag se padhti hai.
  Future<List<StoredAccount>> listAccounts() async {
    final values = <String, String?>{
      WalletService.mnemonicKey:
          await _store.read(key: WalletService.mnemonicKey),
      WalletService.addressKey:
          await _store.read(key: WalletService.addressKey),
      WalletService.createdAtKey:
          await _store.read(key: WalletService.createdAtKey),
      RecoveryWalletService.mnemonicKey:
          await _store.read(key: RecoveryWalletService.mnemonicKey),
      RecoveryWalletService.addressKey:
          await _store.read(key: RecoveryWalletService.addressKey),
      RecoveryWalletService.createdAtKey:
          await _store.read(key: RecoveryWalletService.createdAtKey),
    };
    return buildAccounts(values);
  }

  // ---------------------------------------------------------------------------
  // Pure builder — stored values se account list. No storage, no network.
  // Tests isi ko check karte hain.
  // ---------------------------------------------------------------------------

  /// [stored] me secure-storage keys -> values. Missing/empty wallet
  /// list me nahi aata. Galat seed ho to EVM address null rehta hai,
  /// Tron address phir bhi dikhta hai.
  static List<StoredAccount> buildAccounts(Map<String, String?> stored) {
    final accounts = <StoredAccount>[];

    final main = _buildOne(
      kind: StoredAccountKind.main,
      label: 'Main Wallet',
      mnemonic: stored[WalletService.mnemonicKey],
      tronAddress: stored[WalletService.addressKey],
      createdAtRaw: stored[WalletService.createdAtKey],
    );
    if (main != null) accounts.add(main);

    final recovery = _buildOne(
      kind: StoredAccountKind.recovery,
      label: 'Recovery Wallet (Special)',
      mnemonic: stored[RecoveryWalletService.mnemonicKey],
      tronAddress: stored[RecoveryWalletService.addressKey],
      createdAtRaw: stored[RecoveryWalletService.createdAtKey],
    );
    if (recovery != null) accounts.add(recovery);

    return accounts;
  }

  static StoredAccount? _buildOne({
    required StoredAccountKind kind,
    required String label,
    required String? mnemonic,
    required String? tronAddress,
    required String? createdAtRaw,
  }) {
    final address = tronAddress?.trim();
    final seed = mnemonic?.trim();
    // Na address na seed — is kind ka wallet app me hai hi nahi.
    if ((address == null || address.isEmpty) &&
        (seed == null || seed.isEmpty)) {
      return null;
    }
    String? evmAddress;
    if (seed != null && seed.isNotEmpty && bip39.validateMnemonic(seed)) {
      try {
        evmAddress =
            WalletService.deriveEthereumFromMnemonic(seed).address;
      } catch (_) {
        evmAddress = null; // Derive fail — Tron address phir bhi dikhega.
      }
    }
    DateTime? createdAt;
    if (createdAtRaw != null && createdAtRaw.isNotEmpty) {
      createdAt = DateTime.tryParse(createdAtRaw);
    }
    return StoredAccount(
      kind: kind,
      label: label,
      tronAddress: address?.isEmpty == true ? null : address,
      evmAddress: evmAddress,
      createdAt: createdAt,
      hasSeed: seed != null && seed.isNotEmpty,
    );
  }
}
