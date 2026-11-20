// Token list — naye coins kaise add hote hain (Vinay ka sawaal).
//
// SAWAAL: "Naye coins bhi automatic add ho sakte hain?"
// JAWAAB: Nahi — automatic nahi hone chahiye, aur isiliye:
//
//   1. Scam risk: Tron par koi bhi "USDT" naam ka token bana sakta hai.
//      Agar app har naya token automatic list kar de, to user galti se
//      nakli token khareed/bhej sakta hai. Isliye list CURATED hai —
//      sirf wo coins jo tumne khud check karke list me dale hain.
//   2. Naya coin add karna phir bhi bahut easy hai: neeche
//      [curatedTokens] me EK LINE add karo — bas. Koi code change,
//      koi naya screen, koi naya service nahi chahiye. Swap screen
//      aur Home screen isi list se chalte hain.
//   3. User khud bhi coin add kar sakta hai: "Add Custom Token" —
//      contract address dalo, app khud TronGrid se us token ka naam,
//      symbol, decimals aur balance fetch karke dikhata hai
//      ([CustomTokenService.fetchTokenInfo]). Galat/fake contract ho
//      to fetch fail hoga aur token add nahi hoga.
//   4. Future option: list ko server se update karna (jaise ek JSON
//      file jo app startup par download kare). Ye starter me NAHI hai
//      — uske liye server + signing chahiye, warna koi bhi server
//      hack karke scam token list me daal dega. README me note hai.
//
// Ek line kaise add karein (example — naya coin XYZ, TRC20):
//   const TokenInfo(
//     symbol: 'XYZ',
//     name: 'XYZ Token',
//     coinGeckoId: 'xyz-token',   // CoinGecko id, ya '' agar na ho
//     decimals: 6,
//     contractAddress: 'T...',   // Tronscan par verify karke dalo
//     network: 'TRC20',
//   ),
// Phir XYZ Home par dikhega aur USDT<->XYZ swap (rate quote) me
// aayega. On-chain swap execute sirf USDT<->TRX ke liye hai —
// dusre TRC20 pairs ke liye SunSwap pool hona chahiye (README dekho).

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import 'wallet_service.dart';

/// Ek coin/token ki poori pehchan — list me sirf itna hi chahiye.
///
/// NOTE (Vinay): ek hi symbol alag network par ho sakta hai — jaise
/// USDT Tron par bhi hai (TRC20) aur BNB Chain par bhi (BEP20).
/// Isliye har token ka alag [id] hota hai ('USDT-TRC20',
/// 'USDT-BEP20'). Symbol sirf dikhane ke liye hai, pehchan id se hoti hai.
class TokenInfo {
  /// Unique pehchan, jaise 'USDT-TRC20', 'USDT-BEP20', 'TRX', 'BNB'.
  final String id;

  /// Chhota naam, jaise 'USDT', 'TRX', 'ETH', 'BNB', 'SHIB'.
  final String symbol;

  /// Poora naam, jaise 'Tether USD'.
  final String name;

  /// CoinGecko API id (rate ke liye), jaise 'tether', 'tron'.
  /// Khaali ho to rate sirf on-chain quote se aayega (ya nahi aayega).
  final String coinGeckoId;

  /// Token ke decimals: USDT (Tron) 6, USDT (BSC) 18, TRX 6,
  /// ETH 18, BNB 18, BTC 8. (BSC wala USDT 18 decimals ka hota hai —
  /// Tron/Ethereum wale se alag — isliye decimals hamesha list se lo,
  /// andaze se nahi.)
  final int decimals;

  /// TRC20/BEP20 contract address. Native coin (TRX, BNB) ke liye null —
  /// native coin kisi contract ka token nahi hai, wo chain ki khud ki
  /// currency hai.
  final String? contractAddress;

  /// Network label, jaise 'Tron (TRC20)', 'BNB Smart Chain (BEP20)'.
  /// UI me coin ke SAATH network dikhta hai — taaki USDT TRC20 aur
  /// USDT BEP20 kabhi mix na hon.
  final String network;

  /// True = is coin ko is app se dusre network/chain par bhejna nahi hai.
  /// ETH/SHIB/BNB/USDT-BEP20 ke liye true hai: wo dusri chain ke coins
  /// hain, is wallet me sirf unka RATE dikhta hai, swap execute nahi hota.
  final bool quoteOnly;

  /// Quote-only hone ki wajah, UI me dikhane ke liye.
  final String? quoteOnlyReason;

  const TokenInfo({
    required this.id,
    required this.symbol,
    required this.name,
    required this.coinGeckoId,
    required this.decimals,
    this.contractAddress,
    required this.network,
    this.quoteOnly = false,
    this.quoteOnlyReason,
  });

  /// Native coin (TRX, BNB) hai ya token contract hai?
  bool get isNative => contractAddress == null;

  /// Tron par on-chain swap/balance ke liye use ho sakta hai?
  bool get isTronToken =>
      !quoteOnly && (isNative || contractAddress != null);

  Map<String, dynamic> toJson() => {
        'id': id,
        'symbol': symbol,
        'name': name,
        'coinGeckoId': coinGeckoId,
        'decimals': decimals,
        'contractAddress': contractAddress,
        'network': network,
        'quoteOnly': quoteOnly,
        'quoteOnlyReason': quoteOnlyReason,
      };

  factory TokenInfo.fromJson(Map<String, dynamic> json) {
    final symbol = json['symbol']?.toString() ?? '';
    return TokenInfo(
      id: json['id']?.toString() ?? symbol,
      symbol: symbol,
      name: json['name']?.toString() ?? '',
      coinGeckoId: json['coinGeckoId']?.toString() ?? '',
      decimals: json['decimals'] is int ? json['decimals'] as int : 6,
      contractAddress: json['contractAddress']?.toString(),
      network: json['network']?.toString() ?? 'TRC20',
      quoteOnly: json['quoteOnly'] == true,
      quoteOnlyReason: json['quoteOnlyReason']?.toString(),
    );
  }
}

/// Curated list — sirf checked coins. Naya coin = yahan ek line.
///
/// TEENO NETWORKS PEHLE SE LIST HAIN (Vinay):
///   Tron:          USDT (TRC20), TRX — live, swap execute hota hai.
///   Ethereum:      ETH, SHIB, USDT ERC20 — balance/send LIVE hai;
///                  swap (Uniswap) next step, abhi sirf rate.
///   BNB Chain:     BNB, USDT BEP20 — balance/send LIVE hai;
///                  swap (PancakeSwap) next step, abhi sirf rate.
/// Network switcher Home par hai (Tron / Ethereum / BNB Smart Chain).
///
/// NILE TESTNET NOTE: USDT ka Nile contract TXYZ... hai (config dekho).
/// TRX/BNB native hain — unka koi contract nahi. USDT BEP20 ka
/// contract 0x55d398326f99059fF775485246999027B3197955 hai (Binance-Peg
/// USDT, 18 decimals — BscScan/CoinGecko se verify kiya 2026-11-19).
/// Ye Tether ka apna contract nahi hai, Binance-Peg token hai.
const List<TokenInfo> curatedTokens = [
  TokenInfo(
    id: 'USDT-TRC20',
    symbol: 'USDT',
    name: 'Tether USD',
    coinGeckoId: 'tether',
    decimals: 6,
    contractAddress: null, // network ke hisab se config se aata hai
    network: 'Tron (TRC20)',
  ),
  TokenInfo(
    id: 'TRX',
    symbol: 'TRX',
    name: 'Tron',
    coinGeckoId: 'tron',
    decimals: 6,
    contractAddress: null, // native coin — koi contract nahi
    network: 'Tron (native)',
  ),
  TokenInfo(
    id: 'USDT-ERC20',
    symbol: 'USDT',
    name: 'Tether USD (ERC20)',
    coinGeckoId: 'tether',
    decimals: 6,
    contractAddress: '0xdAC17F958D2ee523a2206206994597C13D831ec7',
    network: 'Ethereum (ERC20) — swap quote only',
    quoteOnly: true,
    quoteOnlyReason:
        'USDT ERC20 balance/send works on the Ethereum network. Swap (Uniswap) is not in this starter — only the rate is shown for now, that is the next step.',
  ),
  TokenInfo(
    id: 'BNB',
    symbol: 'BNB',
    name: 'BNB',
    coinGeckoId: 'binancecoin',
    decimals: 18,
    contractAddress: null, // native coin — koi contract nahi
    network: 'BNB Smart Chain (native) — swap quote only',
    quoteOnly: true,
    quoteOnlyReason:
        'BNB balance/send works on the BNB Smart Chain. Swap (PancakeSwap) is not in this starter — only the rate is shown for now, that is the next step.',
  ),
  TokenInfo(
    id: 'USDT-BEP20',
    symbol: 'USDT',
    name: 'Tether USD (BEP20)',
    coinGeckoId: 'tether',
    decimals: 18, // BEP20 wala USDT 18 decimals ka hota hai (TRC20: 6)
    contractAddress: '0x55d398326f99059fF775485246999027B3197955',
    network: 'BNB Smart Chain (BEP20) — swap quote only',
    quoteOnly: true,
    quoteOnlyReason:
        'USDT BEP20 balance/send works on the BNB Smart Chain. Swap (PancakeSwap) is not in this starter — only the rate is shown for now, that is the next step.',
  ),
  TokenInfo(
    id: 'ETH',
    symbol: 'ETH',
    name: 'Ethereum',
    coinGeckoId: 'ethereum',
    decimals: 18,
    network: 'Ethereum (native) — swap quote only',
    quoteOnly: true,
    quoteOnlyReason:
        'ETH balance/send works on the Ethereum network. Swap (Uniswap) is not in this starter — only the rate is shown for now, that is the next step.',
  ),
  TokenInfo(
    id: 'SHIB',
    symbol: 'SHIB',
    name: 'Shiba Inu',
    coinGeckoId: 'shiba-inu',
    decimals: 18,
    network: 'Ethereum (ERC20) — swap quote only',
    quoteOnly: true,
    quoteOnlyReason:
        'SHIB balance/send works on the Ethereum network. Swap (Uniswap) is not in this starter — only the rate is shown for now, that is the next step.',
  ),
  TokenInfo(
    id: 'BTC',
    symbol: 'BTC',
    name: 'Bitcoin',
    coinGeckoId: 'bitcoin',
    decimals: 8,
    network: 'Bitcoin — quote only',
    quoteOnly: true,
    quoteOnlyReason:
        'BTC is a coin of another chain (Bitcoin) — only the rate is shown in this starter, swap is not executed. A bridge/exchange is needed for a cross-chain swap.',
  ),
];

/// USDT ka contract address — network (Nile/mainnet) ke hisab se.
/// Curated list me USDT (TRC20) ka contract null rakha hai taaki ek hi
/// list dono network par chale; asli address yahan se milta hai.
/// USDT BEP20 ka contract list me hi likha hai (0x55d3...7955).
String usdtContractFor(TokenInfo token) {
  if (token.id == 'USDT-TRC20') return TronConfig.usdtContract;
  return token.contractAddress ?? '';
}

/// Kisi id ya symbol ka TokenInfo dhoondho (curated + custom dono me).
/// Id se dhoondhna hamesha sahi hai (USDT TRC20 vs BEP20 alag hain).
/// Symbol se dhoondho to pehla match milta hai — USDT ke liye TRC20
/// wala (default), kyunki wahi is wallet ka main coin hai.
TokenInfo? findToken(String idOrSymbol, List<TokenInfo> customTokens) {
  final all = [...curatedTokens, ...customTokens];
  for (final t in all) {
    if (t.id.toUpperCase() == idOrSymbol.toUpperCase()) return t;
  }
  for (final t in all) {
    if (t.symbol.toUpperCase() == idOrSymbol.toUpperCase()) return t;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Add Custom Token — user contract address dale, app khud details fetch kare
// ---------------------------------------------------------------------------

/// User ke khud add kiye hue tokens — secure storage me JSON list.
/// Ye curated list se ALAG save hote hain, taaki app update par user
/// ke tokens delete na hon.
class CustomTokenService {
  static const _storage = FlutterSecureStorage();
  static const _kCustomTokens = 'usdt_custom_tokens'; // JSON list

  final FlutterSecureStorage _store;

  CustomTokenService({FlutterSecureStorage? storage})
      : _store = storage ?? _storage;

  Future<List<TokenInfo>> getCustomTokens() async {
    final raw = await _store.read(key: _kCustomTokens);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map<String, dynamic>>()
          .map(TokenInfo.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Token add karo — duplicate symbol/contract ho to dobara add nahi hota.
  /// Returns true agar naya token add hua, false agar pehle se tha.
  Future<bool> addCustomToken(TokenInfo token) async {
    final current = await getCustomTokens();
    final exists = current.any(
      (t) =>
          t.symbol.toUpperCase() == token.symbol.toUpperCase() ||
          (t.contractAddress != null &&
              token.contractAddress != null &&
              t.contractAddress!.toLowerCase() ==
                  token.contractAddress!.toLowerCase()),
    );
    if (exists) return false;
    current.add(token);
    await _store.write(
      key: _kCustomTokens,
      value: jsonEncode(current.map((t) => t.toJson()).toList()),
    );
    return true;
  }

  Future<void> removeCustomToken(String contractAddress) async {
    final current = await getCustomTokens();
    current.removeWhere(
      (t) => t.contractAddress?.toLowerCase() ==
          contractAddress.toLowerCase(),
    );
    await _store.write(
      key: _kCustomTokens,
      value: jsonEncode(current.map((t) => t.toJson()).toList()),
    );
  }

  /// Contract address se token ki details fetch karo (TronGrid, read-only).
  /// TRC20 standard functions: name(), symbol(), decimals().
  /// Koi bhi ek call fail ho to Exception — matlab contract galat hai,
  /// ya wo TRC20 token hi nahi hai. Aise token ko add mat karo.
  Future<TokenInfo> fetchTokenInfo(String contractAddress) async {
    final contract = contractAddress.trim();
    if (!WalletService.isValidTronAddress(contract)) {
      throw Exception(
        'This does not look like a valid TRC20 contract address (starts with T, 34 characters).',
      );
    }
    final name = await _callString(contract, 'name()');
    final symbol = await _callString(contract, 'symbol()');
    final decimals = await _callUint(contract, 'decimals()');
    if (symbol.isEmpty) {
      throw Exception(
        'No symbol was found for this contract — it may not be a TRC20 token at all.',
      );
    }
    return TokenInfo(
      id: 'CUSTOM-${symbol.toUpperCase()}',
      symbol: symbol.toUpperCase(),
      name: name.isEmpty ? symbol.toUpperCase() : name,
      coinGeckoId: '',
      decimals: decimals,
      contractAddress: contract,
      network: 'TRC20 (custom)',
    );
  }

  /// Custom token ka balance (owner address ke liye).
  Future<double> getCustomTokenBalance(
    TokenInfo token,
    String ownerAddress,
  ) async {
    final contract = token.contractAddress;
    if (contract == null) return 0;
    final ownerHex = WalletService.tronAddressToHex(ownerAddress);
    final result = await _triggerConstant(
      contract,
      'balanceOf(address)',
      ownerHex.padLeft(64, '0'),
    );
    if (result.isEmpty) return 0;
    final smallest = BigInt.parse(result, radix: 16);
    var divisor = 1.0;
    for (var i = 0; i < token.decimals; i++) {
      divisor *= 10;
    }
    return smallest.toDouble() / divisor;
  }

  // --- TronGrid read-only call helpers ------------------------------------

  Future<String> _callString(String contract, String function) async {
    final hex = await _triggerConstant(contract, function, '');
    return decodeAbiString(hex);
  }

  Future<int> _callUint(String contract, String function) async {
    final hex = await _triggerConstant(contract, function, '');
    if (hex.isEmpty) return 0;
    return int.parse(hex, radix: 16);
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
        'owner_address': 'T9yD14Nj9j7xAB4dbGeiX9h8unkKHxuWwb', // zero address
        'contract_address': contract,
        'function_selector': functionSelector,
        'parameter': parameter,
        'visible': true,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('Token details could not be fetched (HTTP ${res.statusCode}).');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final result = json['result'];
    if (result is Map && result['result'] != true) {
      throw Exception(
        'Contract call failed: ${json['Error'] ?? 'this does not look like a TRC20 token'}.',
      );
    }
    final constantResult = json['constant_result'];
    if (constantResult is! List || constantResult.isEmpty) return '';
    return constantResult.first.toString();
  }

  /// ABI-encoded dynamic string decode karta hai (name()/symbol() ke liye).
  /// Layout: offset (32 bytes) + length (32 bytes) + utf8 bytes (padded).
  /// Pure function hai — test me bina network ke check hota hai.
  static String decodeAbiString(String hex) {
    if (hex.isEmpty) return '';
    final clean = hex.startsWith('0x') ? hex.substring(2) : hex;
    if (clean.length < 128) return '';
    final bytes = _hexToBytes(clean);
    // bytes 32..64 = length
    var length = 0;
    for (var i = 32; i < 64; i++) {
      length = length * 256 + bytes[i];
    }
    if (length <= 0 || 64 + length > bytes.length) return '';
    return utf8.decode(bytes.sublist(64, 64 + length));
  }

  /// ABI-encoded uint256[] decode — getAmountsOut jaise calls ke liye.
  /// Layout: offset + length + values. Aakhri value = amountOut.
  /// Pure function hai — test me bina network ke check hota hai.
  static List<BigInt> decodeAbiUintArray(String hex) {
    if (hex.isEmpty) return [];
    final clean = hex.startsWith('0x') ? hex.substring(2) : hex;
    if (clean.length < 128) return [];
    final bytes = _hexToBytes(clean);
    var length = 0;
    for (var i = 32; i < 64; i++) {
      length = length * 256 + bytes[i];
    }
    final values = <BigInt>[];
    for (var i = 0; i < length; i++) {
      final start = 64 + i * 32;
      if (start + 32 > bytes.length) break;
      values.add(_bytesToBigInt(bytes.sublist(start, start + 32)));
    }
    return values;
  }

  static Uint8List _hexToBytes(String hex) {
    final clean = hex.startsWith('0x') ? hex.substring(2) : hex;
    final out = Uint8List(clean.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  static BigInt _bytesToBigInt(Uint8List bytes) {
    if (bytes.isEmpty) return BigInt.zero;
    final buffer = StringBuffer();
    for (final b in bytes) {
      buffer.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return BigInt.parse(buffer.toString(), radix: 16);
  }
}
