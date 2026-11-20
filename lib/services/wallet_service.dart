// Wallet keys: create, import, store, and sign.
//
// SECURITY RULES (read this before you change anything here):
//   1. The 12-word seed phrase and the private key live ONLY in
//      FlutterSecureStorage (Android Keystore / iOS Keychain).
//   2. They are NEVER sent to any server, NEVER saved in SharedPreferences,
//      NEVER written to a file, and NEVER printed in a log.
//   3. The private key leaves this file only inside sendUsdt(), where it
//      signs a transaction LOCALLY on the phone.
//
// How a Tron address is made from a seed phrase (standard, same as TronLink):
//   seed phrase -> BIP39 seed -> BIP32 path m/44'/195'/0'/0/0
//   (195 = Tron's coin type) -> secp256k1 private key -> public key
//   -> Keccak-256 -> last 20 bytes -> add 0x41 prefix -> Base58Check.
//   Result: an address starting with "T", e.g. TQrY...9z.

import 'dart:convert';
import 'dart:typed_data';

import 'package:bip39/bip39.dart' as bip39;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/digests/keccak.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/digests/sha512.dart';
import 'package:pointycastle/ecc/api.dart';
// Provides ECCurve_secp256k1(), used directly to build the domain
// parameters (no string lookup, no registration timing to worry about).
import 'package:pointycastle/ecc/curves/secp256k1.dart';
import 'package:pointycastle/macs/hmac.dart';
import 'package:pointycastle/signers/ecdsa_signer.dart';

/// A brand-new wallet, shown to the user BEFORE it is saved.
/// The user must write the words down first — only then do we save.
class NewWalletPreview {
  final String mnemonic;
  final String address;
  const NewWalletPreview({required this.mnemonic, required this.address});
}

class WalletService {
  // Keys inside secure storage. Only these values are ever stored.
  static const _kMnemonic = 'usdt_wallet_mnemonic';
  static const _kPrivateKey = 'usdt_wallet_private_key';
  static const _kAddress = 'usdt_wallet_address';

  /// Public key names — OwnerAccountsService inhe padh kar app me
  /// stored saare accounts ki list banata hai (koi naya key nahi).
  static const String mnemonicKey = _kMnemonic;
  static const String privateKeyKey = _kPrivateKey;
  static const String addressKey = _kAddress;

  /// Wallet is phone me kab add hua (create ya import) — ISO 8601.
  /// Owner accounts list me creation date dikhane ke liye. Is feature
  /// se pehle bane wallet me ye key nahi hogi — tab date "pata nahi".
  static const String createdAtKey = 'usdt_wallet_created_at';

  static const _storage = FlutterSecureStorage();

  // Tron derivation path. 44' = BIP44, 195' = Tron coin type (same as TronLink).
  static const List<int> _derivationPath = [
    44 + 0x80000000,
    195 + 0x80000000,
    0 + 0x80000000,
    0,
    0,
  ];

  // Ethereum / BNB Smart Chain derivation path (EVM, coin type 60).
  // ETH aur BNB ka address EK HI hota hai — dono chains EVM hain aur
  // ek hi seed + ek hi path (m/44'/60'/0'/0/0) se bante hain. Balance
  // aur history har chain par alag hota hai, address wahi rehta hai.
  static const List<int> _ethDerivationPath = [
    44 + 0x80000000,
    60 + 0x80000000,
    0 + 0x80000000,
    0,
    0,
  ];

  static const String _base58Alphabet =
      '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

  // secp256k1 field prime (public constant, same for every secp256k1 wallet).
  static final BigInt _secp256k1P = BigInt.parse(
    'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F',
    radix: 16,
  );

  static ECDomainParameters get _domain => ECCurve_secp256k1();

  // ---------------------------------------------------------------------------
  // Create / import / delete
  // ---------------------------------------------------------------------------

  /// Makes a new 12-word phrase + its Tron address. Does NOT save anything.
  /// Call [saveWallet] only after the user wrote the words down.
  NewWalletPreview generatePreview() {
    final mnemonic = bip39.generateMnemonic();
    final derived = deriveFromMnemonic(mnemonic);
    return NewWalletPreview(mnemonic: mnemonic, address: derived.address);
  }

  /// Saves a wallet from its 12-word (or 24-word) phrase.
  /// Throws if the phrase is not a valid BIP39 phrase.
  /// Returns the Tron address.
  Future<String> saveWallet(String mnemonic) async {
    final clean = mnemonic.trim().split(RegExp(r'\s+')).join(' ');
    if (!bip39.validateMnemonic(clean)) {
      throw Exception('This seed phrase is wrong. Check the 12 words again.');
    }
    final derived = deriveFromMnemonic(clean);
    await _storage.write(key: _kMnemonic, value: clean);
    await _storage.write(key: _kPrivateKey, value: derived.privateKeyHex);
    await _storage.write(key: _kAddress, value: derived.address);
    // Wallet is phone me kab add hua — owner accounts list ke liye.
    await _storage.write(
      key: createdAtKey,
      value: DateTime.now().toIso8601String(),
    );
    return derived.address;
  }

  /// True if a wallet is already saved on this phone.
  Future<bool> hasWallet() async {
    final address = await _storage.read(key: _kAddress);
    return address != null && address.isNotEmpty;
  }

  /// The saved Tron address, or null if no wallet exists yet.
  Future<String?> getAddress() => _storage.read(key: _kAddress);

  /// Deletes the wallet from this phone. The money is NOT deleted from the
  /// blockchain — the same 12 words can bring it back on any wallet app.
  /// Creation date bhi mit jati hai.
  Future<void> deleteWallet() async {
    await _storage.delete(key: _kMnemonic);
    await _storage.delete(key: _kPrivateKey);
    await _storage.delete(key: _kAddress);
    await _storage.delete(key: createdAtKey);
  }

  // ---------------------------------------------------------------------------
  // Private key (used ONLY for local signing, never shown in the UI)
  // ---------------------------------------------------------------------------

  /// Returns the private key so a transaction can be signed LOCALLY.
  /// Only [TronGridService.sendUsdt] should call this.
  Future<String> getPrivateKeyHex() async {
    final key = await _storage.read(key: _kPrivateKey);
    if (key == null || key.isEmpty) {
      throw Exception('No wallet found. Create or import a wallet first.');
    }
    return key;
  }

  /// The saved seed phrase (needed to derive the Ethereum/BNB address
  /// from the SAME seed). Only EVM code calls this — seed kabhi UI me
  /// ya server par nahi jata.
  Future<String> getMnemonic() async {
    final mnemonic = await _storage.read(key: _kMnemonic);
    if (mnemonic == null || mnemonic.isEmpty) {
      throw Exception('No wallet found. Create or import a wallet first.');
    }
    return mnemonic;
  }

  // ---------------------------------------------------------------------------
  // Ethereum / BNB Smart Chain (EVM) — same seed, different path
  // ---------------------------------------------------------------------------

  /// Ethereum/BNB address (0x..., EIP-55 checksum) from the saved seed.
  /// Yehi address Ethereum aur BNB Chain dono par use hota hai.
  Future<String> getEthereumAddress() async {
    final mnemonic = await getMnemonic();
    return deriveEthereumFromMnemonic(mnemonic).address;
  }

  /// Ethereum/BNB private key (hex) from the saved seed — local signing
  /// ke liye. Only EvmService calls this.
  Future<String> getEthereumPrivateKeyHex() async {
    final mnemonic = await getMnemonic();
    return deriveEthereumFromMnemonic(mnemonic).privateKeyHex;
  }

  /// Pure derivation: seed -> m/44'/60'/0'/0/0 -> ETH/BNB keys.
  /// Test vector: 'abandon' x11 + 'about' -> 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
  /// (Hardhat account #0 — standard test vector).
  static ({String privateKeyHex, String address}) deriveEthereumFromMnemonic(
    String mnemonic,
  ) {
    final derived = deriveFromMnemonic(mnemonic, path: _ethDerivationPath);
    final address = _evmAddressFromPrivateKey(
      BigInt.parse(derived.privateKeyHex, radix: 16),
    );
    return (privateKeyHex: derived.privateKeyHex, address: address);
  }

  /// EVM address from a private key: Keccak(public key)[12:] + EIP-55.
  static String _evmAddressFromPrivateKey(BigInt priv) {
    final domain = _domain;
    final pubPoint = (domain.G * priv)!;
    final uncompressed = pubPoint.getEncoded(false);
    final hash = _keccak256(uncompressed.sublist(1));
    final raw = _bytesToHex(hash.sublist(12));
    return toChecksumAddress('0x$raw');
  }

  /// EIP-55 checksum: Keccak(lowercase address) ke hisab se letters ko
  /// upper/lower karo. Pure function — test me check hota hai.
  static String toChecksumAddress(String address) {
    final lower = address.toLowerCase().replaceFirst('0x', '');
    final hashHex = _bytesToHex(_keccak256(Uint8List.fromList(lower.codeUnits)));
    final out = StringBuffer('0x');
    for (var i = 0; i < 40; i++) {
      final ch = lower[i];
      if (ch.codeUnitAt(0) >= 'a'.codeUnitAt(0) &&
          ch.codeUnitAt(0) <= 'f'.codeUnitAt(0)) {
        final hashDigit = int.parse(hashHex[i], radix: 16);
        out.write(hashDigit >= 8 ? ch.toUpperCase() : ch);
      } else {
        out.write(ch);
      }
    }
    return out.toString();
  }

  /// Recovery id (0-3) for an ECDSA signature — EVM (EIP-155) signing
  /// ke liye. [WalletService.signHash] ke andar wala private logic
  /// yahan public hai taaki EvmService use kar sake.
  static int recoveryIdFor(
    BigInt priv,
    Uint8List hash,
    BigInt r,
    BigInt s,
  ) {
    final domain = ECCurve_secp256k1();
    return _findRecoveryId(domain, priv, hash, r, s);
  }

  /// Signs a 32-byte hash and returns (r, s, recId) — EVM signing ke liye.
  /// Low-S rule yahan bhi lagu hota hai (jaise signHash me).
  static ({BigInt r, BigInt s, int recId}) signHashParts(
    Uint8List hash,
    String privateKeyHex,
  ) {
    final domain = ECCurve_secp256k1();
    final priv = BigInt.parse(privateKeyHex, radix: 16);
    final signer = ECDSASigner(null, HMac(SHA256Digest(), 64));
    signer.init(true, PrivateKeyParameter(ECPrivateKey(priv, domain)));
    final sig = signer.generateSignature(hash) as ECSignature;
    var s = sig.s;
    var recId = _findRecoveryId(domain, priv, hash, sig.r, s);
    if (s > domain.n ~/ BigInt.two) {
      s = domain.n - s;
      recId ^= 1;
    }
    return (r: sig.r, s: s, recId: recId);
  }

  // ---------------------------------------------------------------------------
  // Address helpers (pure functions — safe to test and reuse anywhere)
  // ---------------------------------------------------------------------------

  /// Checks a Tron address: starts with T, 34 chars, correct checksum.
  static bool isValidTronAddress(String address) {
    if (address.length != 34 || !address.startsWith('T')) return false;
    try {
      final payload = _base58CheckDecode(address);
      return payload.length == 21 && payload[0] == 0x41;
    } catch (_) {
      return false;
    }
  }

  /// "T..." address -> hex form "41..." (used inside API calls).
  static String tronAddressToHex(String address) {
    final payload = _base58CheckDecode(address);
    return _bytesToHex(payload);
  }

  /// Hex form "41..." -> "T..." address.
  static String hexToTronAddress(String hex) {
    final bytes = _hexToBytes(hex);
    if (bytes.length != 21 || bytes[0] != 0x41) {
      throw FormatException('This is not a Tron address hex: $hex');
    }
    return _base58CheckEncode(bytes);
  }

  // ---------------------------------------------------------------------------
  // Signing (local only — the private key never leaves the phone)
  // ---------------------------------------------------------------------------

  /// Signs a 32-byte transaction hash (the txID) and returns a 65-byte
  /// signature as hex: r (32) + s (32) + v (1).
  /// Used by TronGridService after it builds an unsigned TRC20 transfer.
  static String signHash(String txIdHex, String privateKeyHex) {
    final domain = ECCurve_secp256k1();
    final priv = BigInt.parse(privateKeyHex, radix: 16);
    final hash = _hexToBytes(txIdHex);

    // Deterministic ECDSA (RFC 6979) over the already-hashed txID.
    final signer = ECDSASigner(null, HMac(SHA256Digest(), 64));
    signer.init(true, PrivateKeyParameter(ECPrivateKey(priv, domain)));
    final sig = signer.generateSignature(hash) as ECSignature;

    // Low-S rule: if s is in the top half, flip it (and the recovery bit).
    var s = sig.s;
    var recId = _findRecoveryId(domain, priv, hash, sig.r, s);
    if (s > domain.n ~/ BigInt.two) {
      s = domain.n - s;
      recId ^= 1;
    }
    final v = recId + 27;

    final out = Uint8List.fromList([
      ..._bigIntTo32Bytes(sig.r),
      ..._bigIntTo32Bytes(s),
      v,
    ]);
    return _bytesToHex(out);
  }

  /// Tries recovery ids 0-3 and returns the one that recovers our public key.
  /// Falls back to 0 if recovery fails — in that case the broadcast will
  /// simply fail with a signature error (no money moves), see README.
  static int _findRecoveryId(
    ECDomainParameters domain,
    BigInt priv,
    Uint8List hash,
    BigInt r,
    BigInt s,
  ) {
    final pubHex = _bytesToHex((domain.G * priv)!.getEncoded(false));
    for (var recId = 0; recId < 4; recId++) {
      try {
        final q = _recoverPublicKey(domain, recId, r, s, hash);
        if (q != null && _bytesToHex(q.getEncoded(false)) == pubHex) {
          return recId;
        }
      } catch (_) {
        // Try the next recovery id.
      }
    }
    return 0;
  }

  /// Recovers the public key from (r, s) and a recovery id (SEC1 method).
  static ECPoint? _recoverPublicKey(
    ECDomainParameters domain,
    int recId,
    BigInt r,
    BigInt s,
    Uint8List hash,
  ) {
    final n = domain.n;
    final x = r + BigInt.from(recId ~/ 2) * n;
    if (x >= _secp256k1P) return null;

    // Throws for an invalid point — the caller tries the next recovery id.
    final rPoint = domain.curve.decompressPoint(recId & 1, x);
    final nR = rPoint * n;
    if (nR == null || !nR.isInfinity) return null;

    final e = _bytesToBigInt(hash);
    final rInv = r.modInverse(n);
    final u1 = (-e * rInv) % n;
    final u2 = (s * rInv) % n;
    final p1 = domain.G * u1;
    final p2 = rPoint * u2;
    if (p1 == null || p2 == null) return null;
    return p1 + p2;
  }

  // ---------------------------------------------------------------------------
  // Key derivation (BIP39 seed -> BIP32 path m/44'/195'/0'/0/0 -> Tron keys)
  // ---------------------------------------------------------------------------

  /// Pure derivation, no storage. Useful for tests and for checking an
  /// address from a phrase without saving anything.
  /// [path]: default Tron path m/44'/195'/0'/0/0. Ethereum/BNB ke liye
  /// m/44'/60'/0'/0/0 pass karo (deriveEthereumFromMnemonic dekho).
  /// NOTE: Tron ke liye ye address deta hai (T...); Ethereum ke liye
  /// [deriveEthereumFromMnemonic] use karo (wo EIP-55 0x... deta hai).
  static ({String privateKeyHex, String address}) deriveFromMnemonic(
    String mnemonic, {
    List<int>? path,
  }) {
    final seed = bip39.mnemonicToSeed(mnemonic);
    var node = _masterKey(seed);
    for (final index in path ?? _derivationPath) {
      node = _deriveChild(node, index);
    }
    final privateKeyHex = _bytesToHex(_bigIntTo32Bytes(node.priv));
    final address = _addressFromPrivateKey(node.priv);
    return (privateKeyHex: privateKeyHex, address: address);
  }

  static ({BigInt priv, Uint8List chain}) _masterKey(Uint8List seed) {
    final i = _hmacSha512(
      Uint8List.fromList(utf8.encode('Bitcoin seed')),
      seed,
    );
    return (
      priv: _bytesToBigInt(i.sublist(0, 32)),
      chain: Uint8List.fromList(i.sublist(32)),
    );
  }

  static ({BigInt priv, Uint8List chain}) _deriveChild(
    ({BigInt priv, Uint8List chain}) parent,
    int index,
  ) {
    final domain = _domain;
    final isHardened = index >= 0x80000000;
    final data = BytesBuilder();
    if (isHardened) {
      data.addByte(0);
      data.add(_bigIntTo32Bytes(parent.priv));
    } else {
      final pub = domain.G * parent.priv;
      data.add(pub!.getEncoded(true)); // 33-byte compressed public key
    }
    final indexBytes = Uint8List(4)
      ..buffer.asByteData().setUint32(0, index);
    data.add(indexBytes);

    final i = _hmacSha512(parent.chain, data.toBytes());
    final childPriv =
        (_bytesToBigInt(i.sublist(0, 32)) + parent.priv) % domain.n;
    return (
      priv: childPriv,
      chain: Uint8List.fromList(i.sublist(32)),
    );
  }

  static String _addressFromPrivateKey(BigInt priv) {
    final domain = _domain;
    final pubPoint = (domain.G * priv)!;
    final uncompressed = pubPoint.getEncoded(false); // 65 bytes, starts 0x04
    final hash = _keccak256(uncompressed.sublist(1));
    final raw = Uint8List(21);
    raw[0] = 0x41; // Tron address prefix
    raw.setRange(1, 21, hash.sublist(12)); // last 20 bytes of the hash
    return _base58CheckEncode(raw);
  }

  // ---------------------------------------------------------------------------
  // Small crypto helpers
  // ---------------------------------------------------------------------------

  static Uint8List _hmacSha512(Uint8List key, Uint8List data) {
    final mac = HMac(SHA512Digest(), 128);
    mac.init(KeyParameter(key));
    mac.update(data, 0, data.length);
    final out = Uint8List(64);
    mac.doFinal(out, 0);
    return out;
  }

  static Uint8List _keccak256(Uint8List input) {
    final digest = KeccakDigest(256);
    digest.update(input, 0, input.length);
    final out = Uint8List(32);
    digest.doFinal(out, 0);
    return out;
  }

  static Uint8List _sha256(Uint8List input) {
    final digest = SHA256Digest();
    digest.update(input, 0, input.length);
    final out = Uint8List(32);
    digest.doFinal(out, 0);
    return out;
  }

  static String _base58CheckEncode(Uint8List payload) {
    final checksum = _sha256(_sha256(payload)).sublist(0, 4);
    final bytes = Uint8List.fromList([...payload, ...checksum]);
    var leadingZeros = 0;
    while (leadingZeros < bytes.length && bytes[leadingZeros] == 0) {
      leadingZeros++;
    }
    var num = _bytesToBigInt(bytes);
    final chars = <String>[];
    final base = BigInt.from(58);
    while (num > BigInt.zero) {
      chars.add(_base58Alphabet[(num % base).toInt()]);
      num ~/= base;
    }
    return '${'1' * leadingZeros}${chars.reversed.join()}';
  }

  static Uint8List _base58CheckDecode(String address) {
    var num = BigInt.zero;
    final base = BigInt.from(58);
    for (final ch in address.split('')) {
      final digit = _base58Alphabet.indexOf(ch);
      if (digit < 0) throw const FormatException('Invalid Base58 character');
      num = num * base + BigInt.from(digit);
    }
    final reversed = <int>[];
    var n = num;
    while (n > BigInt.zero) {
      reversed.add((n & BigInt.from(0xff)).toInt());
      n >>= 8;
    }
    var leadingOnes = 0;
    while (leadingOnes < address.length && address[leadingOnes] == '1') {
      leadingOnes++;
    }
    final full = Uint8List.fromList([
      ...List.filled(leadingOnes, 0),
      ...reversed.reversed,
    ]);
    if (full.length < 5) throw const FormatException('Address too short');
    final payload = full.sublist(0, full.length - 4);
    final checksum = full.sublist(full.length - 4);
    final expected = _sha256(_sha256(payload)).sublist(0, 4);
    for (var i = 0; i < 4; i++) {
      if (checksum[i] != expected[i]) {
        throw const FormatException('Bad address checksum');
      }
    }
    return payload;
  }

  static String _bytesToHex(Uint8List bytes) {
    final buffer = StringBuffer();
    for (final b in bytes) {
      buffer.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  static Uint8List _hexToBytes(String hex) {
    final clean = hex.startsWith('0x') ? hex.substring(2) : hex;
    if (clean.length.isOdd) throw const FormatException('Odd-length hex');
    final out = Uint8List(clean.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  static BigInt _bytesToBigInt(Uint8List bytes) {
    if (bytes.isEmpty) return BigInt.zero;
    return BigInt.parse(_bytesToHex(bytes), radix: 16);
  }

  static Uint8List _bigIntTo32Bytes(BigInt value) {
    final hex = value.toRadixString(16).padLeft(64, '0');
    return _hexToBytes(hex);
  }
}
