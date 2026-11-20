// Tests: EVM (Ethereum/BNB) derivation + signing, token list, swap maths.
//
// Koi network call nahi — sab local/pure calculations hain, isliye ye
// tests bina internet ke chalte hain.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/digests/keccak.dart';
import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/ecc/curves/secp256k1.dart';
import 'package:pointycastle/signers/ecdsa_signer.dart';
import 'package:usdt_wallet_app/config.dart';
import 'package:usdt_wallet_app/models/swap_model.dart';
import 'package:usdt_wallet_app/services/evm_service.dart';
import 'package:usdt_wallet_app/services/swap_service.dart';
import 'package:usdt_wallet_app/services/token_list.dart';
import 'package:usdt_wallet_app/services/wallet_service.dart';

Uint8List keccak(Uint8List input) {
  final digest = KeccakDigest(256);
  digest.update(input, 0, input.length);
  final out = Uint8List(32);
  digest.doFinal(out, 0);
  return out;
}

String hex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  // Hardhat ka standard test mnemonic — account #0.
  const testMnemonic =
      'test test test test test test test test test test test junk';

  group('Ethereum / BNB derivation (same seed, same 0x address)', () {
    test('Hardhat test vector: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266',
        () {
      final derived =
          WalletService.deriveEthereumFromMnemonic(testMnemonic);
      expect(derived.address, '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266');
      expect(derived.privateKeyHex,
          'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80');
    });

    test('Tron address alag hota hai (T...), ETH address 0x...', () {
      final tron = WalletService.deriveFromMnemonic(testMnemonic);
      final eth = WalletService.deriveEthereumFromMnemonic(testMnemonic);
      expect(tron.address.startsWith('T'), isTrue);
      expect(eth.address.startsWith('0x'), isTrue);
      expect(tron.privateKeyHex == eth.privateKeyHex, isFalse);
    });

    test('EIP-55 checksum: galat case wala address fix hota hai', () {
      expect(
        WalletService.toChecksumAddress(
            '0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266'),
        '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266',
      );
      // All-lowercase USDC-style address bhi checksum hota hai.
      expect(
        WalletService.toChecksumAddress(
            '0xdac17f958d2ee523a2206206994597c13d831ec7'),
        '0xdAC17F958D2ee523a2206206994597C13D831ec7',
      );
    });
  });

  group('RLP encoding (Ethereum transaction signing ke liye)', () {
    test("'dog' -> 0x83646f67 (official RLP example)", () {
      expect(hex(Rlp.encode(Uint8List.fromList('dog'.codeUnits))),
          '83646f67');
    });

    test('empty string -> 0x80, empty list -> 0xc0', () {
      expect(hex(Rlp.encode(Uint8List(0))), '80');
      expect(hex(Rlp.encode([])), 'c0');
    });

    test('single byte < 0x80 khud hi hota hai', () {
      expect(hex(Rlp.encode(Uint8List.fromList([0x01]))), '01');
    });

    test('BigInt 0 -> empty (0x80), BigInt 1024 -> 0x820400', () {
      expect(hex(Rlp.encode(BigInt.zero)), '80');
      expect(hex(Rlp.encode(BigInt.from(1024))), '820400');
    });

    test('list of two strings', () {
      final encoded = Rlp.encode([
        Uint8List.fromList('cat'.codeUnits),
        Uint8List.fromList('dog'.codeUnits),
      ]);
      expect(hex(encoded), 'c88363617483646f67');
    });
  });

  group('EIP-155 legacy tx signing', () {
    test('sign -> verify: signature hash se match karti hai, v sahi hai',
        () {
      final domain = ECCurve_secp256k1();
      final priv = BigInt.parse(
          'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f3ff80',
          radix: 16);
      final pubPoint = (domain.G * priv)!;
      final pubKey = ECPublicKey(pubPoint, domain);

      // Sepolia chainId 11155111, 0.01 ETH transfer.
      final unsigned = [
        BigInt.zero, // nonce
        BigInt.from(1000000000), // gasPrice 1 Gwei
        BigInt.from(21000),
        Uint8List.fromList(List.filled(20, 0x11)),
        BigInt.from(10000000000000000), // 0.01 ETH
        Uint8List(0),
        BigInt.from(11155111), // chainId
        BigInt.zero,
        BigInt.zero,
      ];
      final hash = keccak(Rlp.encode(unsigned));
      final parts = WalletService.signHashParts(hash,
          'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f3ff80');
      // Signature verify hoti hai.
      final verifier = ECDSASigner();
      verifier.init(false, PublicKeyParameter<ECPublicKey>(pubKey));
      expect(
        verifier.verifySignature(
            hash, ECSignature(parts.r, parts.s)),
        isTrue,
      );
      // v = chainId*2 + 35 + recId.
      final v = 11155111 * 2 + 35 + parts.recId;
      expect(v, anyOf(22310257, 22310258));
      // Signed tx ka hash 32 bytes ka hota hai.
      final signed = [
        ...unsigned.sublist(0, 6),
        BigInt.from(v),
        parts.r,
        parts.s,
      ];
      final txHash = keccak(Rlp.encode(signed));
      expect(txHash.length, 32);
    });
  });

  group('Token list — teeno networks, USDT alag-alag', () {
    test('USDT-TRC20 (6 dec) vs USDT-BEP20 (18 dec) — id se alag', () {
      final trc20 = findToken('USDT-TRC20', [])!;
      final bep20 = findToken('USDT-BEP20', [])!;
      expect(trc20.symbol, 'USDT');
      expect(bep20.symbol, 'USDT');
      expect(trc20.decimals, 6);
      expect(bep20.decimals, 18);
      expect(trc20.contractAddress, isNot(bep20.contractAddress));
    });

    test('USDT-ERC20 bhi list me hai (6 decimals)', () {
      final erc20 = findToken('USDT-ERC20', [])!;
      expect(erc20.decimals, 6);
      expect(erc20.contractAddress,
          '0xdAC17F958D2ee523a2206206994597C13D831ec7');
    });

    test("'USDT' likhne par TRC20 milta hai (default Tron)", () {
      expect(findToken('USDT', [])!.id, 'USDT-TRC20');
    });

    test('BNB native hai (koi contract nahi), 18 decimals', () {
      final bnb = findToken('BNB', [])!;
      expect(bnb.isNative, isTrue);
      expect(bnb.decimals, 18);
    });

    test('ETH/SHIB/BNB/USDT-BEP20: balance/send live, swap quote-only', () {
      for (final id in ['ETH', 'SHIB', 'BNB', 'USDT-BEP20', 'USDT-ERC20']) {
        final token = findToken(id, [])!;
        expect(token.quoteOnly, isTrue, reason: id);
        expect(token.quoteOnlyReason, contains('balance/send'));
      }
      // Tron pair execute hota hai.
      expect(findToken('USDT-TRC20', [])!.quoteOnly, isFalse);
      expect(findToken('TRX', [])!.quoteOnly, isFalse);
    });
  });

  group('Swap maths', () {
    test('0.09% fee (PERMANENT) aur 1% slippage: 100 USDT -> 99.91 net, '
        'minOut ~989.109', () {
      final quote = SwapMath.buildQuote(
        from: findToken('USDT-TRC20', [])!,
        to: findToken('TRX', [])!,
        amountIn: 100,
        rate: 10, // 1 USDT = 10 TRX
        rateSource: 'CoinGecko (estimate)',
        feePercent: SwapConfig.swapServiceFeePercent,
        slippagePercent: SwapConfig.swapSlippagePercent,
        mode: SwapMode.liveTron,
      );
      expect(SwapConfig.swapServiceFeePercent, closeTo(0.0009, 0.000001));
      expect(quote.serviceFee, closeTo(0.09, 0.0001));
      expect(quote.estimatedOut, closeTo(999.1, 0.001));
      expect(quote.minOut, closeTo(989.109, 0.001));
      expect(quote.isExecutable, isTrue);
    });

    test('fee usi coin me kategi jo swap ho raha hai (TRX swap -> TRX fee)',
        () {
      final quote = SwapMath.buildQuote(
        from: findToken('TRX', [])!,
        to: findToken('USDT-TRC20', [])!,
        amountIn: 1000,
        rate: 0.1, // 1 TRX = 0.1 USDT
        rateSource: 'CoinGecko (estimate)',
        feePercent: SwapConfig.swapServiceFeePercent,
        slippagePercent: SwapConfig.swapSlippagePercent,
        mode: SwapMode.liveTron,
      );
      // Fee From coin (TRX) me: 1000 * 0.09% = 0.9 TRX.
      expect(quote.from.symbol, 'TRX');
      expect(quote.serviceFee, closeTo(0.9, 0.0001));
      expect(quote.estimatedOut, closeTo(99.91, 0.001));
    });

    test('quote-only pair execute nahi hota', () {
      final quote = SwapMath.buildQuote(
        from: findToken('USDT-TRC20', [])!,
        to: findToken('ETH', [])!,
        amountIn: 10,
        rate: 0.0004,
        rateSource: 'CoinGecko (estimate)',
        feePercent: SwapConfig.swapServiceFeePercent,
        slippagePercent: SwapConfig.swapSlippagePercent,
        mode: SwapMode.quoteOnly,
        quoteOnlyReason: 'ETH swap execute nahi hota — sirf rate.',
      );
      expect(quote.isExecutable, isFalse);
      expect(quote.quoteOnlyReason, isNotEmpty);
    });
  });

  group('SunSwap ABI encoding', () {
    // NOTE: AbiEncoder hex String deta hai (selector caller lagata hai).
    test('approve: spender address + amount = 128 hex chars', () {
      final encoded = AbiEncoder.encodeApprove(
        'TNJVzGqKBWkJxJB5XYSqGAwUTV15U24pPq',
        BigInt.from(1000000),
      );
      expect(encoded.length, 128);
      // Amount word (aakhri 64 chars) = 1000000 = 0xF4240.
      expect(encoded.substring(128 - 5), 'f4240');
      // Selector deterministic hai: 8 hex chars.
      final sel =
          AbiEncoder.functionSelector('approve(address,uint256)');
      expect(sel.length, 8);
      expect(sel, '095ea7b3');
    });

    test('getAmountsOut: amountIn + path offset 64 + path length 2', () {
      final encoded = AbiEncoder.encodeGetAmountsOut(
        BigInt.from(1000000),
        ['TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t', 'TNUC9Qb1rRpS5CbWLmNMxXBjyFoydXjWFR'],
      );
      // 5 words * 64 hex chars = 320.
      expect(encoded.length, 320);
      // Path offset word (chars 64..128) = 64 = 0x40.
      expect(encoded.substring(64, 128).endsWith('40'), isTrue);
      // Path length word (chars 128..192) = 2.
      expect(encoded.substring(128, 192).endsWith('2'), isTrue);
      // Selector deterministic (Keccak se nikla — actual value yahi hai).
      expect(
        AbiEncoder.functionSelector('getAmountsOut(uint256,address[])'),
        'd06ca61f',
      );
    });

    test('swapExactTokensForTRX: head 5 slots, path offset 160 (0xa0)', () {
      final encoded = AbiEncoder.encodeSwapExactTokensForTrx(
        BigInt.from(1000000),
        BigInt.from(900),
        ['TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t', 'TNUC9Qb1rRpS5CbWLmNMxXBjyFoydXjWFR'],
        'TXYZopYRdj2D9XRtbG411XZZ3kM5VkAeBf',
        1700000000,
      );
      // Head 5 words (320) + tail length + 2 addresses (192) = 512.
      expect(encoded.length, 512);
      // Path offset word (3rd word, chars 128..192) = 160 = 0xa0.
      expect(encoded.substring(128, 192).endsWith('a0'), isTrue);
      // amountOutMin word (2nd word) = 900 = 0x384.
      expect(encoded.substring(64, 128).endsWith('384'), isTrue);
    });

    test('decodeAbiString: round-trip — encode karke decode karo', () {
      // "Tether USD" ko ABI string layout me banao, phir decode karo.
      final name = 'Tether USD';
      final nameBytes = Uint8List.fromList(name.codeUnits);
      final paddedLen = ((nameBytes.length + 31) ~/ 32) * 32;
      final data = Uint8List(64 + paddedLen);
      // offset = 32 (first word)
      data[31] = 32;
      // length = name length (second word)
      data[63] = nameBytes.length;
      data.setRange(64, 64 + nameBytes.length, nameBytes);
      final decoded = CustomTokenService.decodeAbiString(
          '0x${hex(data)}');
      expect(decoded, 'Tether USD');
    });
  });
}
