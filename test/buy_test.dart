// Buy USDT tests — Transak on-ramp: quote maths, widget URL, and
// per-country payment methods (India: UPI + Card; USA/UK/EU: Card +
// Apple Pay + Google Pay + Bank Transfer).
// Run with: flutter test
// No network, no real money — quote parsing + URL building only.
// NOTE: BuyConfig.transakApiKey is empty by default, so widget-URL
// tests set it via... they can't (const). Instead, URL tests assert
// the NOT-configured error, and URL-building is tested through a
// test-only copy of the param logic? No — buildWidgetUrl reads the
// const directly, so with an empty key it must throw. That throw is
// itself tested here. A live widget URL can only be built after Vinay
// pastes a staging key in lib/config.dart.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usdt_wallet_app/config.dart';
import 'package:usdt_wallet_app/screens/buy_screen.dart';
import 'package:usdt_wallet_app/services/buy_link.dart';
import 'package:usdt_wallet_app/services/buy_service.dart';

void main() {
  const india = BuyCountry(
    id: 'IN',
    name: 'India',
    fiatCurrency: 'INR',
    fiatSymbol: '₹',
    paymentMethods: [
      BuyPaymentMethod.upi,
      BuyPaymentMethod.card,
      BuyPaymentMethod.bankTransfer,
    ],
  );
  const usa = BuyCountry(
    id: 'US',
    name: 'USA',
    fiatCurrency: 'USD',
    fiatSymbol: '\$',
    paymentMethods: [
      BuyPaymentMethod.card,
      BuyPaymentMethod.applePay,
      BuyPaymentMethod.googlePay,
      BuyPaymentMethod.bankTransfer,
    ],
  );

  group('Per-country payment methods', () {
    test('India has BOTH UPI and Card (Vinay: dono rakhna hai)', () {
      final methods = BuyCountry.byId('IN').paymentMethods;
      expect(methods, contains(BuyPaymentMethod.upi));
      expect(methods, contains(BuyPaymentMethod.card));
      expect(methods, contains(BuyPaymentMethod.bankTransfer));
    });

    test('USA has Card + Apple Pay + Google Pay + Bank Transfer, no UPI',
        () {
      final methods = BuyCountry.byId('US').paymentMethods;
      expect(methods, contains(BuyPaymentMethod.card));
      expect(methods, contains(BuyPaymentMethod.applePay));
      expect(methods, contains(BuyPaymentMethod.googlePay));
      expect(methods, contains(BuyPaymentMethod.bankTransfer));
      expect(methods, isNot(contains(BuyPaymentMethod.upi)));
    });

    test('UK and Europe have Card + Apple Pay + Google Pay + Bank Transfer',
        () {
      for (final id in ['GB', 'EU']) {
        final methods = BuyCountry.byId(id).paymentMethods;
        expect(methods.length, 4);
        expect(methods, contains(BuyPaymentMethod.card));
        expect(methods, contains(BuyPaymentMethod.applePay));
        expect(methods, contains(BuyPaymentMethod.googlePay));
        expect(methods, contains(BuyPaymentMethod.bankTransfer));
      }
    });

    test('Other countries have Card + Apple Pay + Google Pay', () {
      final methods = BuyCountry.byId('OTHER').paymentMethods;
      expect(methods.length, 3);
      expect(methods, isNot(contains(BuyPaymentMethod.upi)));
      expect(methods, isNot(contains(BuyPaymentMethod.bankTransfer)));
    });

    test('every country has at least Card', () {
      for (final country in BuyCountry.all) {
        expect(country.paymentMethods, contains(BuyPaymentMethod.card),
            reason: '${country.name} me Card hona chahiye');
      }
    });

    test('country change gives the right fiat currency', () {
      expect(BuyCountry.byId('IN').fiatCurrency, 'INR');
      expect(BuyCountry.byId('US').fiatCurrency, 'USD');
      expect(BuyCountry.byId('GB').fiatCurrency, 'GBP');
      expect(BuyCountry.byId('EU').fiatCurrency, 'EUR');
      expect(BuyCountry.byId('OTHER').fiatCurrency, 'USD');
    });
  });

  group('Transak payment method codes', () {
    test('Card code is credit_debit_card (docs-verified)', () {
      expect(BuyPaymentMethod.card.transakCodeFor(india),
          'credit_debit_card');
      expect(
          BuyPaymentMethod.card.transakCodeFor(usa), 'credit_debit_card');
    });

    test('Apple Pay / Google Pay codes are docs-verified', () {
      expect(BuyPaymentMethod.applePay.transakCodeFor(usa), 'apple_pay');
      expect(BuyPaymentMethod.googlePay.transakCodeFor(usa), 'google_pay');
    });

    test('UPI code is upi for India', () {
      expect(BuyPaymentMethod.upi.transakCodeFor(india), 'upi');
    });

    test('Bank Transfer code changes per country', () {
      expect(BuyPaymentMethod.bankTransfer.transakCodeFor(india),
          'inr_bank_transfer');
      expect(BuyPaymentMethod.bankTransfer.transakCodeFor(
          BuyCountry.byId('GB')), 'gbp_bank_transfer');
      expect(BuyPaymentMethod.bankTransfer.transakCodeFor(
          BuyCountry.byId('EU')), 'sepa_bank_transfer');
      expect(BuyPaymentMethod.bankTransfer.transakCodeFor(usa), 'pm_wire');
      // Unknown country: no code — widget shows its own methods.
      expect(BuyPaymentMethod.bankTransfer.transakCodeFor(
          BuyCountry.byId('OTHER')), isNull);
    });
  });

  group('Buy networks', () {
    test('Tron default network code is tron', () {
      expect(BuyNetwork.tron.transakNetwork, 'tron');
      expect(BuyNetwork.ethereum.transakNetwork, 'ethereum');
      expect(BuyNetwork.bsc.transakNetwork, 'bsc');
    });
  });

  group('CoinGecko estimate quote', () {
    test('parses 1 USDT = ₹88.50', () {
      final rate = BuyService.parseUsdtFiatRate(
        '{"tether":{"inr":88.5}}',
        'INR',
      );
      expect(rate, 88.5);
    });

    test('parses USD rate, case-insensitive currency', () {
      final rate = BuyService.parseUsdtFiatRate(
        '{"tether":{"usd":1.0}}',
        'USD',
      );
      expect(rate, 1.0);
    });

    test('throws when the rate is missing', () {
      expect(
        () => BuyService.parseUsdtFiatRate('{"tether":{}}', 'INR'),
        throwsException,
      );
    });

    test('₹8850 estimates ~100 USDT (fee se pehle)', () {
      final quote = BuyService.buildEstimate(
        fiatAmount: 8850,
        country: india,
        usdtFiatRate: 88.5,
      );
      expect(quote.estimatedUsdt, closeTo(100, 0.001));
      expect(quote.rateSource, 'CoinGecko (estimate)');
      expect(quote.fiatCurrency, 'INR');
    });

    test('\$100 estimates ~100 USDT', () {
      final quote = BuyService.buildEstimate(
        fiatAmount: 100,
        country: usa,
        usdtFiatRate: 1.0,
      );
      expect(quote.estimatedUsdt, closeTo(100, 0.001));
    });

    test('zero or negative amount throws', () {
      expect(
        () => BuyService.buildEstimate(
          fiatAmount: 0,
          country: india,
          usdtFiatRate: 88.5,
        ),
        throwsException,
      );
    });
  });

  group('Buy setup / widget URL gating', () {
    test('default config is NOT configured (key empty) and is test mode',
        () {
      expect(BuyConfig.transakApiKey, isEmpty);
      expect(BuyConfig.isConfigured, isFalse);
      expect(BuyConfig.isTestMode, isTrue);
      expect(BuyConfig.transakEnvironment, 'staging');
      expect(BuyConfig.transakWidgetBaseUrl,
          'https://global-stg.transak.com');
    });

    test('widget URL throws without an API key — never a fake buy', () {
      expect(
        () => BuyService.buildWidgetUrl(
          fiatAmount: 1000,
          country: india,
          network: BuyNetwork.tron,
          paymentMethod: BuyPaymentMethod.upi,
          walletAddress: 'TTestAddress12345678901234567890',
        ),
        throwsException,
      );
    });
  });

  group('Buy screen widget', () {
    testWidgets('shows BOTH UPI and Card for India by default',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: BuyScreen(
            tronAddress: 'TTestAddress12345678901234567890',
            evmAddress: '0x0000000000000000000000000000000000000001',
          ),
        ),
      );
      expect(find.text('UPI'), findsOneWidget);
      expect(find.text('Card'), findsOneWidget);
      expect(find.text('Bank Transfer'), findsOneWidget);
      expect(find.text('India (INR)'), findsOneWidget);
      // Setup nahi hai to Buy button disabled + setup steps dikhte hain
      // (quote aane ke baad — pehle rate dekho).
      expect(find.text('TEST MODE (Transak staging) — no real money will be charged. Test with a test card / test details.'),
          findsOneWidget);
    });

    testWidgets('changing country to USA shows Apple Pay + Google Pay',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: BuyScreen(
            tronAddress: 'TTestAddress12345678901234567890',
            evmAddress: '0x0000000000000000000000000000000000000001',
          ),
        ),
      );
      await tester.tap(find.text('India (INR)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('USA (USD)').last);
      await tester.pumpAndSettle();
      expect(find.text('Apple Pay'), findsOneWidget);
      expect(find.text('Google Pay'), findsOneWidget);
      expect(find.text('UPI'), findsNothing);
    });

    testWidgets('INR quote shows Vinay ka set rate ₹110 = 1 USDT',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: BuyScreen(
            tronAddress: 'TTestAddress12345678901234567890',
            evmAddress: '0x0000000000000000000000000000000000000001',
          ),
        ),
      );
      // ₹110 likho → Rate dekho → 1 USDT = ₹110 dikhna chahiye.
      await tester.enterText(
          find.byType(TextField), '110');
      await tester.ensureVisible(find.text('See rate'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('See rate'));
      await tester.pumpAndSettle();
      expect(find.text('₹110 = 1 USDT — Vinay\'s set rate (\$1 = ₹110).'),
          findsOneWidget);
      expect(find.text('Copy buy link'), findsOneWidget);
      expect(find.textContaining('darkvibex-wallet://buy'), findsOneWidget);
    });

    testWidgets('buy link params prefill the screen', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BuyScreen(
            tronAddress: 'TTestAddress12345678901234567890',
            evmAddress: '0x0000000000000000000000000000000000000001',
            initialParams: BuyLinkParams(
              country: BuyCountry.byId('IN'),
              fiatAmount: 1100,
              network: BuyNetwork.tron,
              paymentMethod: BuyPaymentMethod.upi,
            ),
          ),
        ),
      );
      // Amount pre-filled, UPI selected, link me 1100 dikhe.
      expect(find.text('1100.00'), findsOneWidget);
      expect(find.textContaining('fiatAmount=1100.00'), findsOneWidget);
    });
  });
}
