// Monthly wallet fee tests — $0.01 FLAT per month (Vinay final).
//
// Fee balance se independent hai — isliye tests ye pakka karte hain ki
// balance kuch bhi ho, fee hamesha 0.01 USDT rahe, aur due date hamesha
// usi mahine ka aakhri din ho.
import 'package:flutter_test/flutter_test.dart';
import 'package:usdt_wallet_app/config.dart';
import 'package:usdt_wallet_app/services/monthly_fee_service.dart';

void main() {
  group('MonthlyFeeService — \$0.01 flat', () {
    test('config: flat fee 0.01 USDT hai', () {
      expect(MonthlyFeeConfig.monthlyFeeUsdt, 0.01);
      expect(MonthlyFeeConfig.feeCoinSymbol, 'USDT');
    });

    test('fee hamesha 0.01 USDT — balance 100 USDT ho ya 10,000', () {
      expect(MonthlyFeeService.feeForMonth(0), 0.01);
      expect(MonthlyFeeService.feeForMonth(100), 0.01);
      expect(MonthlyFeeService.feeForMonth(10000), 0.01);
      expect(MonthlyFeeService.feeForMonth(0.5), 0.01);
    });

    test('fee percentage nahi hai — 0.001% wala purana rule nahi', () {
      // 0.001% hota to 10,000 USDT par fee 0.1 USDT hoti — flat me 0.01 hai.
      expect(MonthlyFeeService.feeForMonth(10000), isNot(0.1));
      expect(MonthlyFeeService.feeForMonth(10000), 0.01);
    });

    test('due date: Nov 2026 -> 30 Nov 2026 (mahine ka aakhri din)', () {
      final due = MonthlyFeeService.nextDueDate(DateTime(2026, 11, 20));
      expect(due.year, 2026);
      expect(due.month, 11);
      expect(due.day, 30);
    });

    test('due date: Feb 2027 (non-leap) -> 28 Feb 2027', () {
      final due = MonthlyFeeService.nextDueDate(DateTime(2027, 2, 5));
      expect(due.day, 28);
      expect(due.month, 2);
    });

    test('due date: Dec 2026 -> 31 Dec 2026', () {
      final due = MonthlyFeeService.nextDueDate(DateTime(2026, 12, 1));
      expect(due.day, 31);
      expect(due.month, 12);
    });

    test('due date label: 30/11/2026 format', () {
      expect(
        MonthlyFeeService.dueDateLabel(DateTime(2026, 11, 20)),
        '30/11/2026',
      );
    });
  });
}
