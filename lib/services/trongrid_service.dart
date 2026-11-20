// Talks to the Tron blockchain through the free TronGrid API.
//
// What this file does:
//   - USDT balance (TRC20 `balanceOf` call — no API key needed for basic use)
//   - TRX balance (needed to pay network fees)
//   - TRC20 transaction history
//   - Transaction STATUS: Pending / Confirmed / Failed (see getTransactionStatus)
//   - Send USDT: builds the transfer on TronGrid, signs it LOCALLY on the
//     phone (private key never leaves the phone), then broadcasts it.
//
// The private key is NEVER sent to TronGrid or anywhere else. TronGrid only
// ever sees the unsigned transaction and the signature.

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/transaction_model.dart';
import 'wallet_service.dart';

/// Has an address ever been used on-chain before?
///
///   used      -> the address already has transactions. Sending to it is
///                less risky (someone definitely controls it).
///   brandNew  -> no transaction ever. It may be a fresh wallet — or it
///                may be a typo. Warn the user, but do not block: a
///                first-time address is perfectly normal.
///   unknown   -> the check itself failed (no network, API error).
///                We must not block sending because of our own error.
enum AddressUsage { used, brandNew, unknown }

class TronGridService {
  final WalletService _walletService;

  TronGridService({WalletService? walletService})
      : _walletService = walletService ?? WalletService();

  Map<String, String> get _headers {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (TronConfig.tronGridApiKey.isNotEmpty) {
      headers['TRON-PRO-API-KEY'] = TronConfig.tronGridApiKey;
    }
    return headers;
  }

  // ---------------------------------------------------------------------------
  // Balances
  // ---------------------------------------------------------------------------

  /// USDT balance of [address], e.g. 12.5.
  /// Uses a read-only smart-contract call, so it costs nothing.
  Future<double> getUsdtBalance(String address) async {
    final addressHex = WalletService.tronAddressToHex(address);
    final body = {
      'owner_address': address,
      'contract_address': TronConfig.usdtContract,
      'function_selector': 'balanceOf(address)',
      // 32-byte padded hex of the address (41... -> 64 chars).
      'parameter': addressHex.padLeft(64, '0'),
      'visible': true,
    };
    final json = await _post('/wallet/triggerconstantcontract', body);
    final result = json['result'];
    if (result is Map && result['result'] != true) {
      throw Exception('Balance nahi mil paya: ${json['Error'] ?? 'unknown'}');
    }
    final constantResult = json['constant_result'];
    if (constantResult is! List || constantResult.isEmpty) return 0;
    final hex = constantResult.first.toString();
    if (hex.isEmpty) return 0;
    final smallest = BigInt.parse(hex, radix: 16);
    return smallest.toDouble() / _pow10(TronConfig.usdtDecimals);
  }

  /// TRX balance of [address], e.g. 15.2.
  /// You need a little TRX to pay the fee of every USDT transfer.
  Future<double> getTrxBalance(String address) async {
    final json = await _post('/wallet/getaccount', {
      'address': address,
      'visible': true,
    });
    // A brand-new address has no account on-chain yet -> balance is 0.
    final balance = json['balance'];
    if (balance is int) return balance / 1000000;
    if (balance is String) return (int.tryParse(balance) ?? 0) / 1000000;
    return 0;
  }

  // ---------------------------------------------------------------------------
  // History + status
  // ---------------------------------------------------------------------------

  /// Last [limit] USDT transfers for [address], newest first.
  Future<List<Trc20Transfer>> getTrc20History(
    String address, {
    int limit = 20,
  }) async {
    final uri = Uri.parse(
      '${TronConfig.baseUrl}/v1/accounts/$address/transactions/trc20'
      '?limit=$limit&contract_address=${TronConfig.usdtContract}',
    );
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode != 200) {
      throw Exception('History nahi mil payi (HTTP ${res.statusCode}).');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final data = json['data'];
    if (data is! List) return [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(Trc20Transfer.fromJson)
        .toList();
  }

  /// Status of one transaction by its hash.
  ///
  ///   Pending   -> TronGrid does not know this transaction yet, or it has
  ///                no result yet (still in a block being built).
  ///   Confirmed -> on-chain with receipt result SUCCESS.
  ///   Failed    -> on-chain but the receipt result is NOT SUCCESS.
  ///
  /// A network error while checking returns Pending (not a crash) — the
  /// poller simply tries again on the next round.
  Future<TxStatus> getTransactionStatus(String txId) async {
    try {
      final uri = Uri.parse('${TronConfig.baseUrl}/v1/transactions/$txId');
      final res = await http.get(uri, headers: _headers);
      if (res.statusCode != 200) return TxStatus.pending;
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final data = json['data'];
      if (data is! List || data.isEmpty) return TxStatus.pending;
      final tx = data.first;
      if (tx is! Map<String, dynamic>) return TxStatus.pending;
      final ret = tx['ret'];
      if (ret is! List || ret.isEmpty) return TxStatus.pending;
      final first = ret.first;
      if (first is! Map<String, dynamic>) return TxStatus.pending;
      final contractRet = first['contractRet']?.toString() ?? '';
      if (contractRet == 'SUCCESS') return TxStatus.confirmed;
      if (contractRet.isEmpty) return TxStatus.pending;
      return TxStatus.failed;
    } catch (_) {
      return TxStatus.pending;
    }
  }

  /// Is address ke SAAR TRC20 token balances (auto-detect ke liye).
  /// TronGrid account endpoint se aata hai: {contract: balanceString}.
  /// Returns: contract address -> balance (smallest units, raw string).
  /// Curated list me ho ya na ho — jo token address ke paas hai wo
  /// yahan aayega. Home screen isse "New Tokens" section banata hai.
  Future<Map<String, String>> getAllTrc20Balances(String address) async {
    try {
      final json = await _get('/v1/accounts/$address');
      final data = json['data'];
      if (data is! List || data.isEmpty) return {};
      final account = data.first;
      if (account is! Map<String, dynamic>) return {};
      final trc20 = account['trc20'];
      if (trc20 is! List) return {};
      final out = <String, String>{};
      for (final entry in trc20) {
        if (entry is Map<String, dynamic>) {
          for (final e in entry.entries) {
            out[e.key] = e.value.toString();
          }
        }
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  /// Checks whether [address] has ever been used on-chain.
  ///
  /// Looks for ANY past transaction (normal TRX transfers first, then
  /// TRC20 token transfers). A brand-new address has neither.
  /// Returns [AddressUsage.unknown] on any network/API error — the check
  /// failing must never block a send, it only means "we could not verify".
  ///
  /// NOTE (ERC20 later): the same idea works on Ethereum with the
  /// Etherscan API: api.etherscan.io/api?module=account&action=txlist
  /// &address=0x...&page=1&offset=1 — an empty result means brand new.
  Future<AddressUsage> checkAddressUsage(String address) async {
    try {
      // 1) Any normal transaction?
      final normal = await _get(
        '/v1/accounts/$address/transactions?limit=1',
      );
      final normalData = normal['data'];
      if (normalData is List && normalData.isNotEmpty) {
        return AddressUsage.used;
      }
      // 2) Any TRC20 token transfer? (An address can hold tokens
      //    without ever sending a normal TRX transaction.)
      final token = await _get(
        '/v1/accounts/$address/transactions/trc20?limit=1',
      );
      final tokenData = token['data'];
      if (tokenData is List && tokenData.isNotEmpty) {
        return AddressUsage.used;
      }
      return AddressUsage.brandNew;
    } catch (_) {
      return AddressUsage.unknown;
    }
  }

  // ---------------------------------------------------------------------------
  // Send USDT (build -> sign locally -> broadcast)
  // ---------------------------------------------------------------------------

  /// Sends [amountUsdt] USDT from [fromAddress] to [toAddress].
  /// Returns the transaction hash (txID) on success.
  ///
  /// Steps: 1) TronGrid builds the unsigned TRC20 transfer.
  ///        2) The phone signs it locally with the saved private key.
  ///        3) The signed transaction is broadcast to the network.
  /// The returned hash starts as Pending — use TxStatusService to watch it
  /// turn Confirmed (usually in 3-10 seconds on Tron).
  ///
  /// [privateKeyHex]: normally the MAIN wallet signs (default). Pass the
  /// recovery wallet's key only for a "wapas bhejo" send FROM the
  /// recovery wallet — the recovery screen loads it after the owner
  /// unlocks. Never pass any other key here.
  Future<String> sendUsdt({
    required String fromAddress,
    required String toAddress,
    required double amountUsdt,
    String? privateKeyHex,
  }) async {
    if (!WalletService.isValidTronAddress(toAddress)) {
      throw Exception('Receiver ka address galat hai. T se shuru hona chahiye.');
    }
    if (amountUsdt <= 0) throw Exception('Amount 0 se zyada hona chahiye.');

    // 1 USDT = 1,000,000 smallest units.
    final amountSmallest =
        BigInt.from((amountUsdt * _pow10(TronConfig.usdtDecimals)).round());

    // ABI encoding for transfer(address,uint256): both values padded to 64 hex chars.
    final toHex = WalletService.tronAddressToHex(toAddress);
    final parameter =
        '${toHex.padLeft(64, '0')}${amountSmallest.toRadixString(16).padLeft(64, '0')}';

    // Step 1: build the unsigned transaction on TronGrid.
    final buildJson = await _post('/wallet/triggersmartcontract', {
      'owner_address': fromAddress,
      'contract_address': TronConfig.usdtContract,
      'function_selector': 'transfer(address,uint256)',
      'parameter': parameter,
      'fee_limit': TronConfig.feeLimitSun,
      'call_value': 0,
      'visible': true,
    });
    final buildResult = buildJson['result'];
    if (buildResult is Map && buildResult['result'] != true) {
      throw Exception(
        'Transfer ban nahi paya: ${buildJson['Error'] ?? buildResult['message'] ?? 'unknown error'}. '
        'Ho sakta hai TRX kam ho (fee ke liye TRX chahiye) ya address galat ho.',
      );
    }
    final transaction = buildJson['transaction'];
    if (transaction is! Map<String, dynamic>) {
      throw Exception('Transfer ban nahi paya: TronGrid se jawab nahi mila.');
    }
    final txId = transaction['txID']?.toString() ?? '';
    if (txId.isEmpty) throw Exception('Transfer ban nahi paya: txID nahi mila.');

    // Step 2: sign locally. The private key never leaves the phone.
    final signingKeyHex =
        privateKeyHex ?? await _walletService.getPrivateKeyHex();
    final signatureHex = WalletService.signHash(txId, signingKeyHex);
    transaction['signature'] = [signatureHex];

    // Step 3: broadcast the signed transaction.
    final broadcastJson = await _post(
      '/wallet/broadcasttransaction',
      transaction,
    );
    if (broadcastJson['result'] != true) {
      throw Exception(
        'Broadcast fail ho gaya: ${broadcastJson['code'] ?? ''} ${broadcastJson['message'] ?? 'unknown error'}',
      );
    }
    return broadcastJson['txid']?.toString() ?? txId;
  }

  // ---------------------------------------------------------------------------
  // Plain TRX transfer + generic smart-contract call (Swap ke liye)
  // ---------------------------------------------------------------------------

  /// Plain TRX bhejta hai (swap fee collect karne ke liye, jab From = TRX).
  /// Returns the transaction hash. Steps: build -> sign locally -> broadcast.
  Future<String> sendTrx({
    required String fromAddress,
    required String toAddress,
    required double amountTrx,
    String? privateKeyHex,
  }) async {
    if (!WalletService.isValidTronAddress(toAddress)) {
      throw Exception('Receiver ka address galat hai. T se shuru hona chahiye.');
    }
    if (amountTrx <= 0) throw Exception('Amount 0 se zyada hona chahiye.');
    final amountSun = BigInt.from((amountTrx * 1000000).round());
    final buildJson = await _post('/wallet/createtransaction', {
      'owner_address': fromAddress,
      'to_address': toAddress,
      'amount': amountSun.toInt(),
      'visible': true,
    });
    final txId = buildJson['txID']?.toString() ?? '';
    if (txId.isEmpty) {
      throw Exception('TRX transfer ban nahi paya: ${buildJson['Error'] ?? 'unknown'}.');
    }
    final signingKeyHex =
        privateKeyHex ?? await _walletService.getPrivateKeyHex();
    final signatureHex = WalletService.signHash(txId, signingKeyHex);
    final tx = Map<String, dynamic>.from(buildJson);
    tx['signature'] = [signatureHex];
    final broadcastJson = await _post('/wallet/broadcasttransaction', tx);
    if (broadcastJson['result'] != true) {
      throw Exception(
        'Broadcast fail: ${broadcastJson['code'] ?? ''} ${broadcastJson['message'] ?? 'unknown error'}',
      );
    }
    return broadcastJson['txid']?.toString() ?? txId;
  }

  /// Kisi bhi smart contract ko call karta hai: build -> sign locally ->
  /// broadcast. Swap (SunSwap router) iska use karta hai.
  /// [callValueSun]: TRX wale swap ke liye (TRX->USDT), warna 0.
  /// Returns the transaction hash.
  Future<String> callSmartContract({
    required String fromAddress,
    required String contractAddress,
    required String functionSelector,
    required String parameter,
    int callValueSun = 0,
    String? privateKeyHex,
  }) async {
    final buildJson = await _post('/wallet/triggersmartcontract', {
      'owner_address': fromAddress,
      'contract_address': contractAddress,
      'function_selector': functionSelector,
      'parameter': parameter,
      'fee_limit': TronConfig.feeLimitSun,
      'call_value': callValueSun,
      'visible': true,
    });
    final buildResult = buildJson['result'];
    if (buildResult is Map && buildResult['result'] != true) {
      throw Exception(
        'Contract call ban nahi paya: ${buildJson['Error'] ?? buildResult['message'] ?? 'unknown error'}. '
        'Ho sakta hai TRX kam ho ya pool me liquidity na ho.',
      );
    }
    final transaction = buildJson['transaction'];
    if (transaction is! Map<String, dynamic>) {
      throw Exception('Contract call ban nahi paya: TronGrid se jawab nahi mila.');
    }
    final txId = transaction['txID']?.toString() ?? '';
    if (txId.isEmpty) throw Exception('Contract call ban nahi paya: txID nahi mila.');
    final signingKeyHex =
        privateKeyHex ?? await _walletService.getPrivateKeyHex();
    final signatureHex = WalletService.signHash(txId, signingKeyHex);
    transaction['signature'] = [signatureHex];
    final broadcastJson = await _post(
      '/wallet/broadcasttransaction',
      transaction,
    );
    if (broadcastJson['result'] != true) {
      throw Exception(
        'Broadcast fail ho gaya: ${broadcastJson['code'] ?? ''} ${broadcastJson['message'] ?? 'unknown error'}',
      );
    }
    return broadcastJson['txid']?.toString() ?? txId;
  }

  // ---------------------------------------------------------------------------
  // Small HTTP helpers
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final uri = Uri.parse('${TronConfig.baseUrl}$path');
    final res = await http.post(
      uri,
      headers: _headers,
      body: jsonEncode(body),
    );
    if (res.statusCode != 200) {
      throw Exception('TronGrid error (HTTP ${res.statusCode}): ${res.body}');
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('TronGrid se galat jawab mila.');
    }
    return decoded;
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final uri = Uri.parse('${TronConfig.baseUrl}$path');
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode != 200) {
      throw Exception('TronGrid error (HTTP ${res.statusCode}).');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  double _pow10(int n) {
    var result = 1.0;
    for (var i = 0; i < n; i++) {
      result *= 10;
    }
    return result;
  }
}
