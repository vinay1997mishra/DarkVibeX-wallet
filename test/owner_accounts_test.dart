// Owner accounts tests — app me stored saare accounts ki list.
// Pure builder test hota hai (buildAccounts): no storage, no network.
// Seed/private key is list me kabhi nahi aati — wo sirf unlock ke
// baad screen alag se padhti hai.

import 'package:flutter_test/flutter_test.dart';
import 'package:usdt_wallet_app/services/owner_accounts_service.dart';
import 'package:usdt_wallet_app/services/recovery_wallet_service.dart';
import 'package:usdt_wallet_app/services/wallet_service.dart';

void main() {
  const testMnemonic =
      'test test test test test test test test test test test junk';
  const otherMnemonic =
      'legal winner thank year wave sausage worth useful legal winner thank yellow';

  final testTronAddress =
      WalletService.deriveFromMnemonic(testMnemonic).address;
  final otherTronAddress =
      WalletService.deriveFromMnemonic(otherMnemonic).address;

  group('OwnerAccountsService.buildAccounts', () {
    test('no stored wallet -> empty list', () {
      expect(OwnerAccountsService.buildAccounts({}), isEmpty);
      expect(
        OwnerAccountsService.buildAccounts({
          WalletService.addressKey: '',
          RecoveryWalletService.addressKey: '',
        }),
        isEmpty,
      );
    });

    test('main wallet only -> 1 account with Tron + EVM address', () {
      final accounts = OwnerAccountsService.buildAccounts({
        WalletService.mnemonicKey: testMnemonic,
        WalletService.addressKey: testTronAddress,
        WalletService.createdAtKey: '2026-11-20T10:00:00.000',
      });
      expect(accounts.length, 1);
      final main = accounts.single;
      expect(main.kind, StoredAccountKind.main);
      expect(main.label, 'Main Wallet');
      expect(main.tronAddress, testTronAddress);
      // Wahi seed se EVM address — Hardhat test vector.
      expect(
        main.evmAddress,
        '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266',
      );
      expect(main.hasSeed, isTrue);
      expect(main.createdAt, DateTime(2026, 11, 20, 10, 0, 0));
      expect(
        main.networks,
        ['Tron (TRC20)', 'Ethereum (ERC20)', 'BNB Smart Chain (BEP20)'],
      );
    });

    test('main + recovery -> 2 accounts, kinds and addresses distinct', () {
      final accounts = OwnerAccountsService.buildAccounts({
        WalletService.mnemonicKey: testMnemonic,
        WalletService.addressKey: testTronAddress,
        WalletService.createdAtKey: '2026-11-20T10:00:00.000',
        RecoveryWalletService.mnemonicKey: otherMnemonic,
        RecoveryWalletService.addressKey: otherTronAddress,
        RecoveryWalletService.createdAtKey: '2026-11-19T09:00:00.000',
      });
      expect(accounts.length, 2);
      expect(
        accounts.map((a) => a.kind).toSet(),
        {StoredAccountKind.main, StoredAccountKind.recovery},
      );
      final recovery =
          accounts.firstWhere((a) => a.kind == StoredAccountKind.recovery);
      expect(recovery.label, contains('Recovery'));
      expect(recovery.tronAddress, otherTronAddress);
      expect(recovery.tronAddress, isNot(testTronAddress));
      expect(recovery.evmAddress, isNot(accounts.first.evmAddress));
      expect(recovery.createdAt, DateTime(2026, 11, 19, 9, 0, 0));
    });

    test('recovery only -> 1 recovery account', () {
      final accounts = OwnerAccountsService.buildAccounts({
        RecoveryWalletService.mnemonicKey: otherMnemonic,
        RecoveryWalletService.addressKey: otherTronAddress,
      });
      expect(accounts.length, 1);
      expect(accounts.single.kind, StoredAccountKind.recovery);
    });

    test('no createdAt (old wallet) -> createdAt is null, not a crash',
        () {
      final accounts = OwnerAccountsService.buildAccounts({
        WalletService.mnemonicKey: testMnemonic,
        WalletService.addressKey: testTronAddress,
      });
      expect(accounts.length, 1);
      expect(accounts.single.createdAt, isNull);
    });

    test('invalid createdAt string -> createdAt is null', () {
      final accounts = OwnerAccountsService.buildAccounts({
        WalletService.mnemonicKey: testMnemonic,
        WalletService.addressKey: testTronAddress,
        WalletService.createdAtKey: 'not-a-date',
      });
      expect(accounts.single.createdAt, isNull);
    });

    test('address only, no seed -> listed, hasSeed false, no EVM address',
        () {
      final accounts = OwnerAccountsService.buildAccounts({
        WalletService.addressKey: testTronAddress,
      });
      expect(accounts.length, 1);
      expect(accounts.single.hasSeed, isFalse);
      expect(accounts.single.evmAddress, isNull);
      expect(accounts.single.tronAddress, testTronAddress);
    });

    test('invalid seed -> Tron address still listed, EVM address null',
        () {
      final accounts = OwnerAccountsService.buildAccounts({
        WalletService.mnemonicKey: 'not a real seed phrase at all',
        WalletService.addressKey: testTronAddress,
      });
      expect(accounts.length, 1);
      expect(accounts.single.tronAddress, testTronAddress);
      expect(accounts.single.evmAddress, isNull);
    });
  });
}
