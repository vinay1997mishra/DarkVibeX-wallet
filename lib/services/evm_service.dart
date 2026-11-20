// EVM service — Ethereum + BNB Smart Chain (Sepolia / BSC testnet pehle).
//
// Ek hi service dono chains ke liye kaam karti hai, kyunki dono EVM hain:
// sirf chain config (chainId, RPC, explorer, gas symbol) badalta hai.
//   Ethereum: Sepolia testnet, chain 11155111, gas ETH
//   BNB Chain: BSC testnet, chain 97, gas BNB (tBNB)
//
// Kya karta hai:
//   - Native balance (ETH / BNB), ERC20/BEP20 token balance
//   - Gas price + estimate, nonce
//   - Native send + ERC20/BEP20 token send — LEGACY tx (type 0),
//     EIP-155 signing, private key sirf phone par use hoti hai
//   - Transaction status (receipt se)
//   - History (Etherscan / BscScan API — free API key chahiye, config me)
//   - Auto-detect: address ke saare token transfers se naye tokens dhoondho
//
// ⚠️ ETH aur BNB ka address EK HI hota hai (0x..., ek hi seed se).
// Balance/history/gas har chain par ALAG hota hai — network switch
// karte hi address wahi rehta hai, baaki sab badal jata hai.
// Testnet par USDT ERC20 / SHIB / USDT BEP20 ke official contract
// NAHI hain — testnet par sirf native coin (ETH/BNB) test karo.
// Mainnet contracts config me hain (verify kiye hue).

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pointycastle/digests/keccak.dart';

import '../config.dart';
import 'token_list.dart';
import 'wallet_service.dart';

/// Etherscan/BscScan se mili ek transaction (history ke liye).
class EvmTx {
  final String hash;
  final String from;
  final String to;
  final double value; // native coin me (ETH/BNB) — token tx me 0 hota hai
  final String? tokenSymbol; // null = native transfer
  final double? tokenValue; // token amount (decimals ke hisab se)
  final int timestampSec;
  final bool isError; // 1 = fail hui thi

  const EvmTx({
    required this.hash,
    required this.from,
    required this.to,
    required this.value,
    this.tokenSymbol,
    this.tokenValue,
    required this.timestampSec,
    required this.isError,
  });

  bool isOutgoing(String address) =>
      from.toLowerCase() == address.toLowerCase();
}

/// Auto-detect se mila ek naya token (list me ho ya na ho).
class DetectedToken {
  final String contractAddress;
  final String symbol;
  final String name;
  final int decimals;
  final double balance;

  const DetectedToken({
    required this.contractAddress,
    required this.symbol,
    required this.name,
    required this.decimals,
    required this.balance,
  });
}

class EvmService {
  final EvmChainConfig chain;
  final String explorerApiKey;

  EvmService({
    required this.chain,
    String? explorerApiKey,
  }) : explorerApiKey = explorerApiKey ?? '';

  factory EvmService.ethereum() => EvmService(
        chain: EthereumConfig.chain,
        explorerApiKey: EthereumConfig.etherscanApiKey,
      );

  factory EvmService.bsc() => EvmService(
        chain: BscConfig.chain,
        explorerApiKey: BscConfig.bscscanApiKey,
      );

  // ---------------------------------------------------------------------------
  // JSON-RPC (read)
  // ---------------------------------------------------------------------------

  Future<dynamic> _rpc(String method, [List<dynamic> params = const []]) async {
    final res = await http.post(
      Uri.parse(chain.rpcUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'jsonrpc': '2.0',
        'id': 1,
        'method': method,
        'params': params,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('${chain.displayName} RPC error (HTTP ${res.statusCode}).');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json['error'] != null) {
      throw Exception('${chain.displayName} RPC error: ${json['error']['message'] ?? json['error']}');
    }
    return json['result'];
  }

  /// Native balance (ETH / BNB), e.g. 0.5.
  Future<double> getNativeBalance(String address) async {
    final result = await _rpc('eth_getBalance', [address, 'latest']);
    final wei = BigInt.parse(result.toString().substring(2), radix: 16);
    return wei.toDouble() / 1e18;
  }

  /// ERC20/BEP20 token balance (contract + decimals se).
  Future<double> getTokenBalance(
    String contract,
    String address,
    int decimals,
  ) async {
    final data = '0x70a08231' + _abiAddress(address);
    final result = await _rpc('eth_call', [
      {'to': contract, 'data': data},
      'latest',
    ]);
    final raw = (result as String).replaceFirst('0x', '');
    if (raw.isEmpty) return 0;
    final smallest = BigInt.parse(raw, radix: 16);
    var divisor = 1.0;
    for (var i = 0; i < decimals; i++) {
      divisor *= 10;
    }
    return smallest.toDouble() / divisor;
  }

  /// Token ka naam/symbol/decimals (contract se, read-only).
  Future<TokenInfo> getTokenInfo(String contract) async {
    final name = await _callString(contract, '0x06fdde03'); // name()
    final symbol = await _callString(contract, '0x95d89b41'); // symbol()
    final decimalsHex = await _callRaw(contract, '0x313ce567'); // decimals()
    var decimals = 18;
    if (decimalsHex.isNotEmpty) {
      decimals = int.parse(
        decimalsHex.replaceFirst('0x', ''),
        radix: 16,
      );
    }
    if (symbol.isEmpty) {
      throw Exception('Is contract se symbol nahi mila — ERC20 token nahi lagta.');
    }
    return TokenInfo(
      id: 'CUSTOM-${symbol.toUpperCase()}',
      symbol: symbol.toUpperCase(),
      name: name.isEmpty ? symbol.toUpperCase() : name,
      coinGeckoId: '',
      decimals: decimals,
      contractAddress: contract,
      network: '${chain.displayName} (custom)',
    );
  }

  Future<String> _callString(String contract, String selector) async {
    final hex = await _callRaw(contract, selector);
    if (hex.isEmpty) return '';
    return CustomTokenService.decodeAbiString(hex);
  }

  Future<String> _callRaw(String contract, String data) async {
    final result = await _rpc('eth_call', [
      {'to': contract, 'data': data},
      'latest',
    ]);
    return result?.toString() ?? '';
  }

  Future<BigInt> getGasPriceWei() async {
    final result = await _rpc('eth_gasPrice');
    return BigInt.parse(result.toString().substring(2), radix: 16);
  }

  Future<int> getNonce(String address) async {
    final result = await _rpc('eth_getTransactionCount', [address, 'pending']);
    return int.parse(result.toString().substring(2), radix: 16);
  }

  /// Transaction ka status: 'pending' / 'confirmed' / 'failed'.
  Future<String> getTxStatus(String txHash) async {
    try {
      final receipt = await _rpc('eth_getTransactionReceipt', [txHash]);
      if (receipt == null) return 'pending';
      final status = receipt['status']?.toString() ?? '';
      return status == '0x1' ? 'confirmed' : 'failed';
    } catch (_) {
      return 'pending';
    }
  }

  String txExplorerUrl(String txHash) => chain.txExplorerUrl(txHash);

  // ---------------------------------------------------------------------------
  // Send — native + ERC20/BEP20 (legacy tx, EIP-155, local signing)
  // ---------------------------------------------------------------------------

  /// Native coin (ETH / BNB) bhejta hai. Returns transaction hash.
  /// Gas: 21000 (fixed, native transfer ke liye). Fee = 21000 * gasPrice.
  Future<String> sendNative({
    required String fromAddress,
    required String toAddress,
    required double amount,
    required String privateKeyHex,
  }) async {
    if (amount <= 0) throw Exception('Amount 0 se zyada hona chahiye.');
    final gasPrice = await getGasPriceWei();
    final nonce = await getNonce(fromAddress);
    final valueWei = BigInt.from((amount * 1e18).round());
    final tx = _buildLegacyTx(
      nonce: nonce,
      gasPrice: gasPrice,
      gasLimit: BigInt.from(21000),
      to: toAddress,
      valueWei: valueWei,
      data: Uint8List(0),
    );
    return _signAndSend(tx, privateKeyHex);
  }

  /// ERC20/BEP20 token bhejta hai (transfer call). Returns tx hash.
  /// Gas estimate RPC se leta hai (fail ho to 100000 default).
  Future<String> sendToken({
    required String contract,
    required String fromAddress,
    required String toAddress,
    required double amount,
    required int decimals,
    required String privateKeyHex,
  }) async {
    if (amount <= 0) throw Exception('Amount 0 se zyada hona chahiye.');
    var scaled = amount;
    for (var i = 0; i < decimals; i++) {
      scaled *= 10;
    }
    final amountSmallest = BigInt.from(scaled.round());
    // transfer(address,uint256) — selector 0xa9059cbb.
    final dataHex = '0xa9059cbb' +
        _abiAddress(toAddress) +
        amountSmallest.toRadixString(16).padLeft(64, '0');
    final data = _hexToBytes(dataHex);
    final gasPrice = await getGasPriceWei();
    final nonce = await getNonce(fromAddress);
    var gasLimit = BigInt.from(100000);
    try {
      final est = await _rpc('eth_estimateGas', [
        {
          'from': fromAddress,
          'to': contract,
          'data': dataHex,
        },
        'latest',
      ]);
      gasLimit = BigInt.parse(est.toString().substring(2), radix: 16);
      // Estimate par 20% buffer — estimate se kam gas ho to tx fail hoti hai.
      gasLimit = gasLimit * BigInt.from(12) ~/ BigInt.from(10);
    } catch (_) {
      // Estimate fail ho to default 100000 se try karo.
    }
    final tx = _buildLegacyTx(
      nonce: nonce,
      gasPrice: gasPrice,
      gasLimit: gasLimit,
      to: contract,
      valueWei: BigInt.zero,
      data: data,
    );
    return _signAndSend(tx, privateKeyHex);
  }

  /// Ek legacy (type 0) transaction banata hai — unsigned RLP ke liye
  /// 9 fields (chainId, 0, 0 aakhri me — EIP-155 signing ke liye).
  List<dynamic> _buildLegacyTx({
    required int nonce,
    required BigInt gasPrice,
    required BigInt gasLimit,
    required String to,
    required BigInt valueWei,
    required Uint8List data,
  }) {
    return [
      BigInt.from(nonce),
      gasPrice,
      gasLimit,
      _hexToBytes(to),
      valueWei,
      data,
      BigInt.from(chain.chainId),
      BigInt.zero,
      BigInt.zero,
    ];
  }

  /// Unsigned tx ko sign karke broadcast karta hai. Returns tx hash
  /// (keccak of signed RLP).
  Future<String> _signAndSend(
    List<dynamic> unsignedTx,
    String privateKeyHex,
  ) async {
    final signingHash = _keccak256(Rlp.encode(unsignedTx));
    final parts = WalletService.signHashParts(signingHash, privateKeyHex);
    final v = BigInt.from(chain.chainId * 2 + 35 + parts.recId);
    final signed = [
      ...unsignedTx.sublist(0, 6),
      v,
      parts.r,
      parts.s,
    ];
    final rawTx = Rlp.encode(signed);
    final rawHex = '0x${_bytesToHex(rawTx)}';
    final result = await _rpc('eth_sendRawTransaction', [rawHex]);
    if (result == null || result.toString().isEmpty) {
      throw Exception('Broadcast fail — RPC ne tx hash nahi diya.');
    }
    // RPC ka hash hi asli hai (keccak of signed RLP se match karta hai).
    return result.toString();
  }

  // ---------------------------------------------------------------------------
  // History + auto-detect (Etherscan / BscScan API — free key chahiye)
  // ---------------------------------------------------------------------------

  /// Native + token transactions (newest first, max 20).
  /// API key na ho to Exception — caller Home par note dikhata hai.
  Future<List<EvmTx>> getHistory(String address) async {
    if (explorerApiKey.isEmpty) {
      throw Exception(
        'History ke liye ${chain.displayName} explorer API key chahiye — config me dalo (free key).',
      );
    }
    final native = await _explorerCall({
      'module': 'account',
      'action': 'txlist',
      'address': address,
      'startblock': '0',
      'endblock': '99999999',
      'page': '1',
      'offset': '20',
      'sort': 'desc',
    });
    final tokens = await _explorerCall({
      'module': 'account',
      'action': 'tokentx',
      'address': address,
      'startblock': '0',
      'endblock': '99999999',
      'page': '1',
      'offset': '20',
      'sort': 'desc',
    });
    final out = <EvmTx>[];
    for (final item in native) {
      out.add(_evmTxFromJson(item, null));
    }
    for (final item in tokens) {
      out.add(_evmTxFromJson(item, item['tokenSymbol']?.toString()));
    }
    out.sort((a, b) => b.timestampSec.compareTo(a.timestampSec));
    return out.take(20).toList();
  }

  EvmTx _evmTxFromJson(Map<String, dynamic> json, String? tokenSymbol) {
    double tokenValue;
    var decimals = 18;
    if (tokenSymbol != null) {
      decimals = int.tryParse(json['tokenDecimal']?.toString() ?? '18') ?? 18;
      final raw = BigInt.tryParse(json['value']?.toString() ?? '0') ?? BigInt.zero;
      var divisor = 1.0;
      for (var i = 0; i < decimals; i++) {
        divisor *= 10;
      }
      tokenValue = raw.toDouble() / divisor;
    } else {
      tokenValue = 0;
    }
    final valueWei =
        BigInt.tryParse(json['value']?.toString() ?? '0') ?? BigInt.zero;
    return EvmTx(
      hash: json['hash']?.toString() ?? '',
      from: json['from']?.toString() ?? '',
      to: json['to']?.toString() ?? '',
      value: tokenSymbol == null ? valueWei.toDouble() / 1e18 : 0,
      tokenSymbol: tokenSymbol,
      tokenValue: tokenSymbol == null ? null : tokenValue,
      timestampSec:
          int.tryParse(json['timeStamp']?.toString() ?? '0') ?? 0,
      isError: json['isError']?.toString() == '1',
    );
  }

  /// Auto-detect: is address ke saare token transfers se unique tokens
  /// nikaalo, har ek ka balance lo. Curated list me ho ya na ho — jo
  /// token address ke paas hai wo dikhega ("New Tokens" section).
  /// API key na ho to khaali list + caller note dikhata hai.
  Future<List<DetectedToken>> detectTokens(String address) async {
    if (explorerApiKey.isEmpty) return [];
    final tokens = await _explorerCall({
      'module': 'account',
      'action': 'tokentx',
      'address': address,
      'startblock': '0',
      'endblock': '99999999',
      'page': '1',
      'offset': '100',
      'sort': 'desc',
    });
    final contracts = <String>{};
    for (final item in tokens) {
      final c = item['contractAddress']?.toString() ?? '';
      if (c.isNotEmpty) contracts.add(c);
    }
    final out = <DetectedToken>[];
    for (final contract in contracts) {
      try {
        final info = await getTokenInfo(contract);
        final balance =
            await getTokenBalance(contract, address, info.decimals);
        if (balance > 0) {
          out.add(DetectedToken(
            contractAddress: contract,
            symbol: info.symbol,
            name: info.name,
            decimals: info.decimals,
            balance: balance,
          ));
        }
      } catch (_) {
        // Ek token ka data na mile to use chhodo, baaki dikhao.
      }
    }
    return out;
  }

  Future<List<Map<String, dynamic>>> _explorerCall(
    Map<String, String> params,
  ) async {
    final query = {
      ...params,
      'apikey': explorerApiKey,
    };
    final uri = Uri.parse(chain.explorerApiBase)
        .replace(queryParameters: query);
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('Explorer API error (HTTP ${res.statusCode}).');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json['status']?.toString() != '1') {
      // '0' = no transactions found — ye error nahi, khaali list hai.
      return [];
    }
    final result = json['result'];
    if (result is! List) return [];
    return result.whereType<Map<String, dynamic>>().toList();
  }

  // ---------------------------------------------------------------------------
  // Small helpers
  // ---------------------------------------------------------------------------

  /// ABI address: 0x address ko 32-byte slot me (24 zero + 20 bytes).
  static String _abiAddress(String address) {
    final clean = address.toLowerCase().replaceFirst('0x', '');
    return clean.padLeft(64, '0');
  }

  static Uint8List _keccak256(Uint8List input) {
    final digest = KeccakDigest(256);
    digest.update(input, 0, input.length);
    final out = Uint8List(32);
    digest.doFinal(out, 0);
    return out;
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
    final padded = clean.length.isOdd ? '0$clean' : clean;
    final out = Uint8List(padded.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(padded.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }
}

// ---------------------------------------------------------------------------
// RLP encoding — Ethereum transaction signing ke liye (pure, testable)
// ---------------------------------------------------------------------------

/// Recursive Length Prefix — Ethereum ka standard encoding.
///   bytes/string -> length prefix + data
///   list         -> length prefix + har item ka encoding
///   BigInt       -> bina leading zero ke bytes
class Rlp {
  static Uint8List encode(dynamic input) {
    if (input is Uint8List) return _encodeBytes(input);
    if (input is String) {
      return _encodeBytes(Uint8List.fromList(input.codeUnits));
    }
    if (input is BigInt) return _encodeBytes(_bigIntToBytes(input));
    if (input is int) return _encodeBytes(_bigIntToBytes(BigInt.from(input)));
    if (input is List) {
      final encodedItems = <int>[];
      for (final item in input) {
        encodedItems.addAll(encode(item));
      }
      final payload = Uint8List.fromList(encodedItems);
      return Uint8List.fromList([
        ..._lengthPrefix(payload.length, 0xc0),
        ...payload,
      ]);
    }
    throw ArgumentError('RLP encode nahi kar sakte: ${input.runtimeType}');
  }

  static Uint8List _encodeBytes(Uint8List bytes) {
    if (bytes.length == 1 && bytes[0] < 0x80) return bytes;
    return Uint8List.fromList([
      ..._lengthPrefix(bytes.length, 0x80),
      ...bytes,
    ]);
  }

  /// 0-55 bytes: 0x80/0xc0 + length. Usse zyada: 0xb7/0xf7 + length-of-length.
  static List<int> _lengthPrefix(int length, int offset) {
    if (length < 56) return [offset + length];
    final lenBytes = _bigIntToBytes(BigInt.from(length));
    return [offset + 55 + lenBytes.length, ...lenBytes];
  }

  static Uint8List _bigIntToBytes(BigInt value) {
    if (value == BigInt.zero) return Uint8List(0);
    var hex = value.toRadixString(16);
    if (hex.length.isOdd) hex = '0$hex';
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }
}
