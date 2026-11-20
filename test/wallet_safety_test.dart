// Safety tests: key derivation, signing, and the network cross-check.
// Run with: flutter test
// These tests use NO network and NO secure storage — everything is local.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/ecc/curves/secp256k1.dart';
import 'package:pointycastle/signers/ecdsa_signer.dart';
import 'package:usdt_wallet_app/models/transaction_model.dart';
import 'package:usdt_wallet_app/services/address_validator.dart';
import 'package:usdt_wallet_app/services/owner_lock_service.dart';
import 'package:usdt_wallet_app/services/recovery_wallet_service.dart';
import 'package:usdt_wallet_app/services/wallet_service.dart';

Uint8List hexToBytes(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

void main() {
  const testMnemonic =
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
  const otherMnemonic =
      'legal winner thank year wave sausage worth useful legal winner thank yellow';

  group('Tron key derivation', () {
    test('generates a valid 12-word wallet with a T... address', () {
      final preview = WalletService().generatePreview();
      expect(preview.mnemonic.split(' ').length, 12);
      expect(preview.address.startsWith('T'), isTrue);
      expect(preview.address.length, 34);
      expect(WalletService.isValidTronAddress(preview.address), isTrue);
      // Hex round-trip: T... -> 41... -> T...
      final hex = WalletService.tronAddressToHex(preview.address);
      expect(hex.startsWith('41'), isTrue);
      expect(WalletService.hexToTronAddress(hex), preview.address);
    });

    test('same mnemonic always gives the same address', () {
      final a = WalletService.deriveFromMnemonic(testMnemonic);
      final b = WalletService.deriveFromMnemonic(testMnemonic);
      expect(a.address, b.address);
      expect(a.privateKeyHex, b.privateKeyHex);
    });

    test('different mnemonic gives a different address', () {
      final a = WalletService.deriveFromMnemonic(testMnemonic);
      final b = WalletService.deriveFromMnemonic(otherMnemonic);
      expect(a.address, isNot(b.address));
    });
  });

  group('Local signing', () {
    test('signHash verifies against the derived public key', () {
      final derived = WalletService.deriveFromMnemonic(testMnemonic);
      final priv = BigInt.parse(derived.privateKeyHex, radix: 16);
      final domain = ECCurve_secp256k1();

      // A fake 32-byte transaction hash (64 hex chars).
      const txIdHex =
          '5f3e2d1c0b9a876543210fedcba9876543210fedcba9876543210fedcba98765';
      final sigHex = WalletService.signHash(txIdHex, derived.privateKeyHex);

      // 65 bytes: r (32) + s (32) + v (1).
      expect(sigHex.length, 130);
      final r = BigInt.parse(sigHex.substring(0, 64), radix: 16);
      final s = BigInt.parse(sigHex.substring(64, 128), radix: 16);
      final v = int.parse(sigHex.substring(128, 130), radix: 16);
      expect(v >= 27 && v <= 30, isTrue);

      final pubPoint = (domain.G * priv)!;
      // pointycastle 3.x has no separate verifier class — the signer
      // verifies too (init with `false` = verify mode).
      final verifier = ECDSASigner();
      verifier.init(
        false,
        PublicKeyParameter(ECPublicKey(pubPoint, domain)),
      );
      expect(
        verifier.verifySignature(
          hexToBytes(txIdHex),
          ECSignature(r, s),
        ),
        isTrue,
      );
    });
  });

  group('Address validation + network cross-check', () {
    late final String tronAddress;
    const ethAddress = '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed';

    setUpAll(() {
      tronAddress = WalletService.deriveFromMnemonic(testMnemonic).address;
    });

    test('valid Tron address passes on TRC20', () {
      final result = AddressValidator.validateForSelectedNetwork(
        tronAddress,
        AddressNetwork.tron,
      );
      expect(result.isValid, isTrue);
      expect(result.network, AddressNetwork.tron);
    });

    test('TRC20 selected + 0x address = small warning, never blocked', () {
      final result = AddressValidator.validateForSelectedNetwork(
        ethAddress,
        AddressNetwork.tron,
      );
      expect(result.isValid, isTrue); // Vinay: no hard block, ever
      expect(result.warning, contains('Network galat lag raha hai'));
      expect(result.warning, contains('doob sakta hai'));
    });

    test('ERC20 selected + T address = small warning, never blocked', () {
      final result = AddressValidator.validateForSelectedNetwork(
        tronAddress,
        AddressNetwork.ethereum,
      );
      expect(result.isValid, isTrue);
      expect(result.warning, contains('Network galat lag raha hai'));
    });

    test('BEP20 selected + T address = small warning, never blocked', () {
      final result = AddressValidator.validateForSelectedNetwork(
        tronAddress,
        AddressNetwork.bsc,
      );
      expect(result.isValid, isTrue);
      expect(result.warning, contains('Network galat lag raha hai'));
    });

    test('Tron address with a broken checksum is rejected', () {
      final last = tronAddress[tronAddress.length - 1];
      final replacement = last == '1' ? '2' : '1';
      final broken =
          '${tronAddress.substring(0, tronAddress.length - 1)}$replacement';
      final result = AddressValidator.validateForTron(broken);
      expect(result.isValid, isFalse);
      expect(result.error, contains('checksum'));
    });

    test('network is detected from the prefix', () {
      expect(
        AddressValidator.detectNetworkFromAddress(tronAddress),
        AddressNetwork.tron,
      );
      expect(
        AddressValidator.detectNetworkFromAddress(ethAddress),
        AddressNetwork.ethereum,
      );
      expect(AddressValidator.detectNetworkFromAddress('xyz'), isNull);
    });

    test('EIP-55 checksummed Ethereum address passes', () {
      final result = AddressValidator.validateEthereum(ethAddress);
      expect(result.isValid, isTrue);
    });

    test('lowercase Ethereum address passes with a warning', () {
      final result =
          AddressValidator.validateEthereum(ethAddress.toLowerCase());
      expect(result.isValid, isTrue);
      expect(result.warning, isNotNull);
    });

    test('Ethereum address with a broken EIP-55 checksum is rejected', () {
      // Last letter 'd' flipped to 'D' breaks the checksum.
      const broken = '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAeD';
      final result = AddressValidator.validateEthereum(broken);
      expect(result.isValid, isFalse);
    });
  });

  group('Network mismatch detection (automatic recovery redirect)', () {
    late final String tronAddress;
    const ethAddress = '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed';

    setUpAll(() {
      tronAddress = WalletService.deriveFromMnemonic(testMnemonic).address;
    });

    test('TRC20 selected + 0x address = mismatch', () {
      expect(
        AddressValidator.isNetworkMismatch(ethAddress, AddressNetwork.tron),
        isTrue,
      );
    });

    test('ERC20 selected + T address = mismatch', () {
      expect(
        AddressValidator.isNetworkMismatch(
          tronAddress,
          AddressNetwork.ethereum,
        ),
        isTrue,
      );
    });

    test('correct address + correct network = no mismatch, no redirect', () {
      expect(
        AddressValidator.isNetworkMismatch(
          tronAddress,
          AddressNetwork.tron,
        ),
        isFalse,
      );
      expect(
        AddressValidator.isNetworkMismatch(
          ethAddress,
          AddressNetwork.ethereum,
        ),
        isFalse,
      );
    });

    test('recovery redirect is recorded with original address + reason', () {
      final tx = Trc20Transfer.pending(
        txId: 'abc123',
        from: tronAddress,
        to: 'TRecoveryWalletAddressForTest0000000',
        value: BigInt.from(1000000),
        isRecoveryRedirect: true,
        originalAddress: ethAddress,
        intendedNetwork: 'ERC20 (Ethereum)',
        recoveryReason: 'Network mismatch',
      );
      expect(tx.isRecoveryRedirect, isTrue);
      expect(tx.originalAddress, ethAddress);
      expect(tx.intendedNetwork, 'ERC20 (Ethereum)');

      // Round-trip through secure-storage JSON keeps the record.
      final restored =
          Trc20Transfer.fromStoredJson(tx.toJson());
      expect(restored.isRecoveryRedirect, isTrue);
      expect(restored.originalAddress, ethAddress);
      expect(restored.intendedNetwork, 'ERC20 (Ethereum)');
      expect(restored.recoveryReason, 'Network mismatch');
    });

    test('normal transfer is never a recovery redirect', () {
      final tx = Trc20Transfer.pending(
        txId: 'abc124',
        from: tronAddress,
        to: tronAddress,
        value: BigInt.from(2000000),
      );
      expect(tx.isRecoveryRedirect, isFalse);
      expect(tx.originalAddress, isNull);
      final restored =
          Trc20Transfer.fromStoredJson(tx.toJson());
      expect(restored.isRecoveryRedirect, isFalse);
    });
  });

  group('Owner lock (PIN) + recovery wallet key separation', () {
    test('PIN must be 4-6 digits only', () {
      expect(OwnerLockService.isValidPin('1234'), isTrue);
      expect(OwnerLockService.isValidPin('123456'), isTrue);
      expect(OwnerLockService.isValidPin('123'), isFalse);
      expect(OwnerLockService.isValidPin('1234567'), isFalse);
      expect(OwnerLockService.isValidPin('12ab'), isFalse);
      expect(OwnerLockService.isValidPin(''), isFalse);
    });

    test('PIN hash is deterministic for same salt, different for other salt',
        () {
      final a = OwnerLockService.hashPin('1234', 'salt-one');
      final b = OwnerLockService.hashPin('1234', 'salt-one');
      final c = OwnerLockService.hashPin('1234', 'salt-two');
      final d = OwnerLockService.hashPin('4321', 'salt-one');
      expect(a, b);
      expect(a, isNot(c));
      expect(a, isNot(d));
      // The plain PIN is never in the hash output.
      expect(a.contains('1234'), isFalse);
    });

    test('recovery wallet uses DIFFERENT storage keys than the main wallet',
        () {
      expect(
        RecoveryWalletService.mnemonicKey,
        isNot('usdt_wallet_mnemonic'),
      );
      expect(
        RecoveryWalletService.privateKeyKey,
        isNot('usdt_wallet_private_key'),
      );
      expect(
        RecoveryWalletService.addressKey,
        isNot('usdt_wallet_address'),
      );
      expect(RecoveryWalletService.mnemonicKey,
          contains('recovery_wallet'));
      expect(RecoveryWalletService.addressKey,
          contains('recovery_wallet'));
    });

    test('recovery wallet derives a valid Tron address from its seed', () {
      final preview =
          RecoveryWalletService().generatePreview();
      expect(preview.mnemonic.split(' ').length, 12);
      expect(preview.address.startsWith('T'), isTrue);
      expect(preview.address.length, 34);
      expect(WalletService.isValidTronAddress(preview.address), isTrue);
    });
  });
}
