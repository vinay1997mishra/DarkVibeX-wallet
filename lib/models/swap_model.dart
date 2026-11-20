// Swap (Exchange) models — pure data + fee/quote maths (no network here).
//
// Fee ka hisaab (ek hi jagah, taaki UI aur service kabhi alag na dikhayein):
//   fee        = amountIn * swapServiceFeePercent   (PERMANENT 0.09%)
//   netIn      = amountIn - fee                     (yehi swap hota hai)
//   Fee USI COIN me kategi jo swap ho raha hai (From coin) — USDT swap
//   karo to USDT me, TRX swap karo to TRX me. Alag coin (BNB ya koi aur)
//   me fee nahi lagti, user ko fee ke liye alag coin nahi chahiye.
//   netIn      = amountIn - fee                     (yehi swap hota hai)
//   grossOut   = netIn * rate                       (rate = 1 From = ? To)
//   minOut     = grossOut * (1 - slippage)         (rate hilne par bhi
//                isse kam mile to swap fail ho jayega — user ko isse kam
//                kabhi nahi milega, isse zyada mil sakta hai)
// Network fee (TRX gas) isme nahi hai — wo alag dikhti hai.

import '../services/token_list.dart';

/// Swap kaise hoga — live on-chain ya sirf rate quote?
enum SwapMode {
  /// SunSwap V2 se Tron par execute hoga (USDT <-> TRX).
  liveTron,

  /// Sirf rate dikhega — execute nahi hoga (ETH/BTC: dusri chain).
  quoteOnly,
}

/// Ek swap ka quote — Confirm dabane se PEHLE user ko yehi dikhta hai.
class SwapQuote {
  final TokenInfo from;
  final TokenInfo to;

  /// User ne kitna dala (From coin me).
  final double amountIn;

  /// Service fee (From coin me — usi coin me kategi jo swap ho raha
  /// hai) — owner profit, config se (PERMANENT 0.09%).
  final double serviceFee;

  /// Swap hone wala amount = amountIn - serviceFee.
  final double netAmountIn;

  /// 1 From = kitna To (jaise 1 USDT = ~3.5 TRX).
  final double rate;

  /// Rate kahan se aaya: 'SunSwap pool' ya 'CoinGecko (estimate)'.
  final String rateSource;

  /// Milne wala estimated amount (To coin me, fee katne ke baad).
  final double estimatedOut;

  /// Isse kam mile to swap fail — slippage ke baad ka minimum.
  final double minOut;

  final SwapMode mode;

  /// Quote-only hone ki wajah (ETH/BTC ke liye), UI me dikhane ke liye.
  final String? quoteOnlyReason;

  const SwapQuote({
    required this.from,
    required this.to,
    required this.amountIn,
    required this.serviceFee,
    required this.netAmountIn,
    required this.rate,
    required this.rateSource,
    required this.estimatedOut,
    required this.minOut,
    required this.mode,
    this.quoteOnlyReason,
  });

  bool get isExecutable => mode == SwapMode.liveTron;
}

/// Pure maths — bina network ke test hota hai.
class SwapMath {
  /// Fee + net input + estimated out + min out — ek hi jagah se.
  static SwapQuote buildQuote({
    required TokenInfo from,
    required TokenInfo to,
    required double amountIn,
    required double rate,
    required String rateSource,
    required double feePercent,
    required double slippagePercent,
    required SwapMode mode,
    String? quoteOnlyReason,
  }) {
    final fee = amountIn * feePercent;
    final netIn = amountIn - fee;
    final estimatedOut = netIn * rate;
    final minOut = estimatedOut * (1 - slippagePercent);
    return SwapQuote(
      from: from,
      to: to,
      amountIn: amountIn,
      serviceFee: fee,
      netAmountIn: netIn,
      rate: rate,
      rateSource: rateSource,
      estimatedOut: estimatedOut,
      minOut: minOut,
      mode: mode,
      quoteOnlyReason: quoteOnlyReason,
    );
  }
}

/// Swap execute hone ke baad ka result.
class SwapResult {
  final String txId;
  final SwapQuote quote;

  /// Fee owner ke fee wallet ko bheji gayi ya nahi.
  final bool feeCollected;

  /// Fee kahan gayi (fee wallet address) — null = collect nahi hui.
  final String? feeDestination;

  /// Fee collect na hone ki wajah (fee wallet set nahi hai, etc).
  final String? feeNote;

  const SwapResult({
    required this.txId,
    required this.quote,
    required this.feeCollected,
    this.feeDestination,
    this.feeNote,
  });
}
