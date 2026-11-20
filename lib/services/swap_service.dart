// Swap (Exchange) service — USDT <-> TRX on Tron via SunSwap V2.
//
// Kya kaam karta hai:
//   1. RATE: pehle SunSwap pool se on-chain quote (getAmountsOut), agar
//      pool/quote na mile to CoinGecko price se estimate. Rate ka source
//      hamesha quote me likha hota hai — kabhi andaze se rate nahi dikhata.
//   2. EXECUTE (sirf USDT <-> TRX, Tron par): approve + router swap.
//      Private key sirf phone par sign karne ke liye use hoti hai.
//   3. FEE: 0.09% PERMANENT (config, Vinay final) — USI COIN me kat-ti
//      hai jo swap ho raha hai (USDT swap karo to USDT me, TRX swap
//      karo to TRX me). Fee wallet set ho to fee alag se owner ko bhej
//      di jati hai, nahi to fee ka hissa user ke wallet me hi rehta hai
//      (README dekho — koi fake profit nahi).
//   4. ETH / SHIB / BTC: sirf RATE QUOTE (CoinGecko). Ye Ethereum /
//      Bitcoin network ke coins hain — is Tron-first starter me unka
//      swap execute NAHI hota. Confirm button disabled rehta hai.
//
// ⚠️ ROUTER ADDRESS VERIFY KARO: SunSwap V2 router ka address
// lib/config.dart me hai (sunswapteam repo ki deployment table se).
// Pehle swap se pehle Tronscan par verify kar lo. Address galat hua
// to swap fail hoga — paise nahi jayenge, sirf thodi TRX fee jalegi.
// Nile testnet par pool me liquidity kam ho sakti hai — quote fail
// ho to app "pool not available" dikhayega, kabhi fake success nahi.

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pointycastle/digests/keccak.dart';

import '../config.dart';
import '../models/swap_model.dart';
import '../models/transaction_model.dart';
import 'token_list.dart';
import 'trongrid_service.dart';
import 'wallet_service.dart';

class SwapService {
  final TronGridService _api;

  SwapService({TronGridService? api}) : _api = api ?? TronGridService();

  // ---------------------------------------------------------------------------
  // Prices — CoinGecko free API (no key needed, rate-limited)
  // ---------------------------------------------------------------------------

  static const _coinGeckoBase = 'https://api.coingecko.com/api/v3';

  /// USD price har coin ke liye: {'tether': 1.0, 'tron': 0.25, ...}.
  /// CoinGecko ids token_list.dart ke curatedTokens se aate hain.
  Future<Map<String, double>> fetchUsdPrices() async {
    final ids = curatedTokens
        .map((t) => t.coinGeckoId)
        .where((id) => id.isNotEmpty)
        .toSet()
        .join(',');
    final uri = Uri.parse(
      '$_coinGeckoBase/simple/price?ids=$ids&vs_currencies=usd',
    );
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception(
        'Could not fetch the rate (CoinGecko HTTP ${res.statusCode}). Check your internet and try again in a little while.',
      );
    }
    return parseUsdPrices(res.body);
  }

  /// Pure parsing — bina network ke test hota hai.
  static Map<String, double> parseUsdPrices(String body) {
    final json = jsonDecode(body) as Map<String, dynamic>;
    final out = <String, double>{};
    for (final entry in json.entries) {
      final data = entry.value;
      if (data is Map) {
        final usd = data['usd'];
        if (usd is num) out[entry.key] = usd.toDouble();
      }
    }
    return out;
  }

  /// CoinGecko rate: 1 From = kitna To (USD price se).
  static double rateFromUsdPrices(
    TokenInfo from,
    TokenInfo to,
    Map<String, double> prices,
  ) {
    final fromUsd = prices[from.coinGeckoId];
    final toUsd = prices[to.coinGeckoId];
    if (fromUsd == null || toUsd == null || toUsd == 0) {
      throw Exception('Rate not found for this pair (CoinGecko).');
    }
    return fromUsd / toUsd;
  }

  // ---------------------------------------------------------------------------
  // Quote — pehle SunSwap pool, nahi to CoinGecko estimate
  // ---------------------------------------------------------------------------

  /// Dono taraf Tron ke coins hon (USDT/TRX) to on-chain quote try karo.
  /// Pool na ho / quote fail ho to CoinGecko estimate par gir jao.
  /// ETH/SHIB/BTC hamesha CoinGecko quote-only hote hain.
  Future<SwapQuote> getQuote({
    required TokenInfo from,
    required TokenInfo to,
    required double amountIn,
  }) async {
    if (amountIn <= 0) throw Exception('The amount must be more than 0.');
    if (from.symbol == to.symbol) {
      throw Exception('Both sides have the same coin — there is no point in swapping.');
    }

    final isTronPair = from.isTronToken && to.isTronToken;
    if (!isTronPair || from.quoteOnly || to.quoteOnly) {
      // Cross-chain coin (ETH/SHIB/BTC) — sirf rate, execute nahi.
      final prices = await fetchUsdPrices();
      final rate = rateFromUsdPrices(from, to, prices);
      return SwapMath.buildQuote(
        from: from,
        to: to,
        amountIn: amountIn,
        rate: rate,
        rateSource: 'CoinGecko (estimate)',
        feePercent: SwapConfig.swapServiceFeePercent,
        slippagePercent: SwapConfig.swapSlippagePercent,
        mode: SwapMode.quoteOnly,
        quoteOnlyReason: to.quoteOnlyReason ?? from.quoteOnlyReason,
      );
    }

    // Tron pair (USDT <-> TRX): pehle pool se asli quote.
    final fee = SwapConfig.swapServiceFeePercent;
    final slippage = SwapConfig.swapSlippagePercent;
    try {
      final netIn = amountIn * (1 - fee);
      final out = await _routerQuote(from, to, netIn);
      if (out > 0) {
        final rate = out / netIn;
        return SwapMath.buildQuote(
          from: from,
          to: to,
          amountIn: amountIn,
          rate: rate,
          rateSource: 'SunSwap pool (on-chain)',
          feePercent: fee,
          slippagePercent: slippage,
          mode: SwapMode.liveTron,
        );
      }
    } catch (_) {
      // Pool quote nahi mila — neeche CoinGecko estimate par gir jao.
    }
    final prices = await fetchUsdPrices();
    final rate = rateFromUsdPrices(from, to, prices);
    return SwapMath.buildQuote(
      from: from,
      to: to,
      amountIn: amountIn,
      rate: rate,
      rateSource: 'CoinGecko (estimate — pool quote not available)',
      feePercent: fee,
      slippagePercent: slippage,
      mode: SwapMode.liveTron,
    );
  }

  /// SunSwap V2 router getAmountsOut — pool ka asli rate.
  /// Returns amountOut (To coin me). Pool na ho to throw karta hai.
  Future<double> _routerQuote(
    TokenInfo from,
    TokenInfo to,
    double netIn,
  ) async {
    final amountInSmallest = _toSmallest(netIn, from.decimals);
    final path = _swapPath(from, to);
    final parameter = AbiEncoder.encodeGetAmountsOut(amountInSmallest, path);
    final hex = await _triggerConstant(
      SwapConfig.sunSwapRouter,
      'getAmountsOut(uint256,address[])',
      parameter,
    );
    final amounts = CustomTokenService.decodeAbiUintArray(hex);
    if (amounts.length < 2) throw Exception('Pool quote not available.');
    final outSmallest = amounts.last;
    return _fromSmallest(outSmallest, to.decimals);
  }

  // ---------------------------------------------------------------------------
  // Execute — sirf USDT <-> TRX, Tron par, testnet pehle
  // ---------------------------------------------------------------------------

  /// Quote ko execute karta hai. Sirf liveTron mode me chalta hai —
  /// quote-only pair par call karo to Exception (UI Confirm ko disable
  /// rakhta hai, ye doosri line of defence hai).
  /// Returns txId + fee collection ki jaankari.
  Future<SwapResult> executeSwap({
    required SwapQuote quote,
    required String fromAddress,
  }) async {
    if (!quote.isExecutable) {
      throw Exception(
        'This swap cannot be executed — ${quote.quoteOnlyReason ?? 'rate quote only'}.',
      );
    }
    final from = quote.from;
    final to = quote.to;
    final netInSmallest = _toSmallest(quote.netAmountIn, from.decimals);
    final minOutSmallest = _toSmallest(quote.minOut, to.decimals);
    final deadline =
        DateTime.now().millisecondsSinceEpoch ~/ 1000 + 20 * 60;

    late final String txId;
    if (from.symbol == 'USDT' && to.symbol == 'TRX') {
      // 1) Router ko USDT spend karne ki permission (approve).
      final approveParam = AbiEncoder.encodeApprove(
        SwapConfig.sunSwapRouter,
        netInSmallest,
      );
      final approveTxId = await _api.callSmartContract(
        fromAddress: fromAddress,
        contractAddress: TronConfig.usdtContract,
        functionSelector: 'approve(address,uint256)',
        parameter: approveParam,
      );
      // Approve confirm hone ka wait karo — bina confirm hue swap fail hoga.
      await _waitForConfirmation(approveTxId);
      // 2) USDT -> TRX swap.
      final path = _swapPath(from, to);
      final param = AbiEncoder.encodeSwapExactTokensForTrx(
        netInSmallest,
        minOutSmallest,
        path,
        fromAddress,
        deadline,
      );
      txId = await _api.callSmartContract(
        fromAddress: fromAddress,
        contractAddress: SwapConfig.sunSwapRouter,
        functionSelector:
            'swapExactTokensForTRX(uint256,uint256,address[],address,uint256)',
        parameter: param,
      );
    } else if (from.symbol == 'TRX' && to.symbol == 'USDT') {
      // TRX -> USDT: TRX call_value ke saath jata hai, approve nahi chahiye.
      final path = _swapPath(from, to);
      final param = AbiEncoder.encodeSwapExactTrxForTokens(
        minOutSmallest,
        path,
        fromAddress,
        deadline,
      );
      txId = await _api.callSmartContract(
        fromAddress: fromAddress,
        contractAddress: SwapConfig.sunSwapRouter,
        functionSelector:
            'swapExactTRXForTokens(uint256,address[],address,uint256)',
        parameter: param,
        callValueSun: netInSmallest.toInt(),
      );
    } else {
      throw Exception(
        'On-chain swap for this pair is not in this starter (only USDT <-> TRX).',
      );
    }

    // Swap confirm hone ka wait karo, phir fee collect karo.
    await _waitForConfirmation(txId);
    final fee = await _collectFee(quote, fromAddress);
    return SwapResult(
      txId: txId,
      quote: quote,
      feeCollected: fee.collected,
      feeDestination: fee.destination,
      feeNote: fee.note,
    );
  }

  /// Service fee owner ke fee wallet ko bhejta hai (agar set hai).
  /// Fee USI COIN me bhejti hai jo swap hua tha — USDT swap hua to
  /// USDT me, TRX swap hua to TRX me. Alag coin (BNB ya koi aur) me
  /// fee kabhi nahi lagti, user ko fee ke liye alag coin nahi chahiye.
  /// Fee wallet set nahi hai to kuch nahi karta — fee ka hissa user ke
  /// wallet me hi rehta hai (kyunki sirf net amount swap hua tha).
  /// Fee transfer fail ho to swap ko fail nahi karta — note me likhta hai.
  Future<({bool collected, String? destination, String? note})>
      _collectFee(SwapQuote quote, String fromAddress) async {
    final feeWallet = SwapConfig.ownerFeeWalletAddress;
    if (feeWallet.isEmpty) {
      return (
        collected: false,
        destination: null,
        note: 'The fee wallet is not set — the fee was not collected, and the fee amount '
            'stayed in your wallet. To receive the fee, add your '
            'TRC20 address in the config.',
      );
    }
    if (quote.serviceFee <= 0) {
      return (collected: false, destination: null, note: 'The fee is 0.');
    }
    try {
      if (quote.from.symbol == 'USDT') {
        await _api.sendUsdt(
          fromAddress: fromAddress,
          toAddress: feeWallet,
          amountUsdt: quote.serviceFee,
        );
      } else {
        await _api.sendTrx(
          fromAddress: fromAddress,
          toAddress: feeWallet,
          amountTrx: quote.serviceFee,
        );
      }
      return (collected: true, destination: feeWallet, note: null);
    } catch (e) {
      return (
        collected: false,
        destination: null,
        note: 'Fee transfer failed ($e) — the swap is done, and the fee '
            'stayed in your wallet.',
      );
    }
  }

  Future<void> _waitForConfirmation(String txId) async {
    // Zyada se zyada ~60 second wait karo (10 sec x 6 try).
    for (var i = 0; i < 6; i++) {
      await Future.delayed(const Duration(seconds: 10));
      final status = await _api.getTransactionStatus(txId);
      if (status == TxStatus.confirmed) return;
      if (status == TxStatus.failed) {
        throw Exception('The transaction failed (tx: $txId).');
      }
    }
    // Timeout: transaction abhi bhi Pending ho sakti hai — caller
    // History me status dekh sakta hai. Yahan throw nahi karte taaki
    // swap ka txId user ko mil jaye.
  }

  // ---------------------------------------------------------------------------
  // Swap path + amounts
  // ---------------------------------------------------------------------------

  /// Router ke liye token path: USDT->TRX = [USDT, WTRX],
  /// TRX->USDT = [WTRX, USDT]. TRX hamesha WTRX ke roop me jata hai.
  /// Id se pehchante hain (symbol se nahi) — USDT TRC20 aur USDT BEP20
  /// ka symbol ek hai, id alag hai. BEP20 pair yahan kabhi nahi aata
  /// (wo quote-only hai, execute nahi hota).
  List<String> _swapPath(TokenInfo from, TokenInfo to) {
    String addr(TokenInfo t) {
      if (t.symbol == 'TRX') return SwapConfig.wtrxContract;
      if (t.id == 'USDT-TRC20') return TronConfig.usdtContract;
      return usdtContractFor(t);
    }

    return [addr(from), addr(to)];
  }

  BigInt _toSmallest(double amount, int decimals) {
    var scaled = amount;
    for (var i = 0; i < decimals; i++) {
      scaled *= 10;
    }
    return BigInt.from(scaled.round());
  }

  double _fromSmallest(BigInt smallest, int decimals) {
    var divisor = 1.0;
    for (var i = 0; i < decimals; i++) {
      divisor *= 10;
    }
    return smallest.toDouble() / divisor;
  }

  Future<String> _triggerConstant(
    String contract,
    String functionSelector,
    String parameter,
  ) async {
    final uri = Uri.parse(
      '${TronConfig.baseUrl}/wallet/triggerconstantcontract',
    );
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (TronConfig.tronGridApiKey.isNotEmpty) {
      headers['TRON-PRO-API-KEY'] = TronConfig.tronGridApiKey;
    }
    final res = await http.post(
      uri,
      headers: headers,
      body: jsonEncode({
        'owner_address': 'T9yD14Nj9j7xAB4dbGeiX9h8unkKHxuWwb',
        'contract_address': contract,
        'function_selector': functionSelector,
        'parameter': parameter,
        'visible': true,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('Could not fetch the quote (HTTP ${res.statusCode}).');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final result = json['result'];
    if (result is Map && result['result'] != true) {
      throw Exception('Pool quote failed: ${json['Error'] ?? 'unknown'}.');
    }
    final constantResult = json['constant_result'];
    if (constantResult is! List || constantResult.isEmpty) return '';
    return constantResult.first.toString();
  }
}

// ---------------------------------------------------------------------------
// ABI encoding — SunSwap V2 router calls ke liye (pure, testable)
// ---------------------------------------------------------------------------

/// Ethereum/Tron ABI encoding ke chhote helpers.
/// Selector = Keccak-256(signature) ke pehle 4 bytes.
/// Address = 20 bytes (Tron hex '41...' se aakhri 20 bytes).
/// uint256 = 32 bytes big-endian. Dynamic array = offset + length + items.
class AbiEncoder {
  static String functionSelector(String signature) {
    final digest = KeccakDigest(256);
    final input = Uint8List.fromList(signature.codeUnits);
    digest.update(input, 0, input.length);
    final out = Uint8List(32);
    digest.doFinal(out, 0);
    return _bytesToHex(out.sublist(0, 4));
  }

  static String encodeUint256(BigInt value) {
    return value.toRadixString(16).padLeft(64, '0');
  }

  /// Tron address (T... ya 41... hex) -> 32-byte padded ABI address.
  static String encodeAddress(String tronAddress) {
    final hex = tronAddress.startsWith('T')
        ? WalletService.tronAddressToHex(tronAddress)
        : tronAddress.replaceFirst('0x', '');
    // '41' + 20 bytes -> aakhri 40 hex chars = 20 bytes.
    final addressBytes = hex.substring(hex.length - 40);
    return addressBytes.padLeft(64, '0');
  }

  /// address[] dynamic array: offset + length + har address (32 byte slot).
  /// [offset] = array shuru hone tak ke bytes (head se).
  static String encodeAddressArray(List<String> addresses, int offset) {
    final buffer = StringBuffer();
    buffer.write(offset.toRadixString(16).padLeft(64, '0'));
    buffer.write(addresses.length.toRadixString(16).padLeft(64, '0'));
    for (final a in addresses) {
      buffer.write(encodeAddress(a));
    }
    return buffer.toString();
  }

  /// getAmountsOut(uint256 amountIn, address[] path) — quote ke liye.
  static String encodeGetAmountsOut(
    BigInt amountIn,
    List<String> path,
  ) {
    // Head: amountIn (32) + offset (32) = 64 bytes, phir array.
    return encodeUint256(amountIn) + encodeAddressArray(path, 64);
  }

  /// approve(address spender, uint256 amount).
  static String encodeApprove(String spender, BigInt amount) {
    return encodeAddress(spender) + encodeUint256(amount);
  }

  /// swapExactTokensForTRX(amountIn, amountOutMin, path, to, deadline).
  /// Head 5 slots = 160 bytes: amountIn, amountOutMin, offset(160),
  /// to, deadline — phir tail me path array (length + items).
  static String encodeSwapExactTokensForTrx(
    BigInt amountIn,
    BigInt amountOutMin,
    List<String> path,
    String to,
    int deadline,
  ) {
    final head = encodeUint256(amountIn) +
        encodeUint256(amountOutMin) +
        encodeUint256(BigInt.from(160)) +
        encodeAddress(to) +
        encodeUint256(BigInt.from(deadline));
    return head + _addressArrayTail(path);
  }

  /// swapExactTRXForTokens(amountOutMin, path, to, deadline).
  /// Head 4 slots = 128 bytes: amountOutMin, offset(128), to,
  /// deadline — phir tail me path array (length + items).
  static String encodeSwapExactTrxForTokens(
    BigInt amountOutMin,
    List<String> path,
    String to,
    int deadline,
  ) {
    final head = encodeUint256(amountOutMin) +
        encodeUint256(BigInt.from(128)) +
        encodeAddress(to) +
        encodeUint256(BigInt.from(deadline));
    return head + _addressArrayTail(path);
  }

  /// Dynamic array ka tail: length + har address (offset head me hota hai).
  static String _addressArrayTail(List<String> addresses) {
    final buffer = StringBuffer();
    buffer.write(addresses.length.toRadixString(16).padLeft(64, '0'));
    for (final a in addresses) {
      buffer.write(encodeAddress(a));
    }
    return buffer.toString();
  }

  static String _bytesToHex(Uint8List bytes) {
    final buffer = StringBuffer();
    for (final b in bytes) {
      buffer.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}
