// Monthly wallet fee — $0.01 FLAT per month (Vinay final, 2026-11-20).
//
// PURE calculation — koi network call, koi storage, koi deduction nahi.
//
//   - Fee: $0.01 flat = 0.01 USDT, har mahine. Balance se koi lena-dena
//     nahi — 100 USDT ho ya 10,000 USDT, fee wahi 0.01 USDT.
//   - Kab: har mahine ke aakhri din (month-end), us mahine ki fee.
//   - Kahan: owner fee wallet (SwapConfig.ownerFeeWalletAddress).
//
// HONEST LIMIT — YE SIRF CALCULATE KARTA HAI, KAAT-TA NAHI:
//   Bina server ke app khud user ke on-chain balance se fee nahi kaat
//   sakta. Isliye ye service sirf batati hai ki fee kitni hai aur kab
//   due hai — balance kabhi kam nahi karti, koi fake deduction, fake
//   history ya fake "fee paid" nahi banati. Asli deduction ke liye
//   server/custodial step chahiye hoga, jo abhi app me nahi hai.
import '../config.dart';

class MonthlyFeeService {
  /// Is mahine ki fee — hamesha flat 0.01 USDT.
  /// [usdtBalance] sirf display ke liye liya jata hai, fee us par
  /// depend nahi karti (flat hai).
  static double feeForMonth(double usdtBalance) {
    if (usdtBalance < 0) return MonthlyFeeConfig.monthlyFeeUsdt;
    return MonthlyFeeConfig.monthlyFeeUsdt;
  }

  /// Is mahine ki fee kab due hai — mahine ka aakhri din.
  /// Jaise Nov 2026 -> 30 Nov 2026, Feb 2027 -> 28 Feb 2027.
  static DateTime nextDueDate([DateTime? now]) {
    final d = now ?? DateTime.now();
    // Agle mahine ka day 0 = is mahine ka aakhri din.
    return DateTime(d.year, d.month + 1, 0);
  }

  /// Due date display ke liye: "30/11/2026".
  static String dueDateLabel([DateTime? now]) {
    final d = nextDueDate(now);
    final day = d.day.toString().padLeft(2, '0');
    final month = d.month.toString().padLeft(2, '0');
    return '$day/$month/${d.year}';
  }
}
