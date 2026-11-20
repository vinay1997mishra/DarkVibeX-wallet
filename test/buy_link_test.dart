// Buy deep link tests — shareable link build/parse round-trip.
// Run with: flutter test
// No network, no real money.

import 'package:flutter_test/flutter_test.dart';
import 'package:usdt_wallet_app/services/buy_link.dart';
import 'package:usdt_wallet_app/services/buy_service.dart';

void main() {
  group('BuyLink.build', () {
    test('builds a darkvibex-wallet://buy link with all params', () {
      final link = BuyLink.build(
        country: BuyCountry.byId('IN'),
        fiatAmount: 1100,
        network: BuyNetwork.tron,
        paymentMethod: BuyPaymentMethod.upi,
      );
      expect(link.scheme, 'darkvibex-wallet');
      expect(link.host, 'buy');
      expect(link.queryParameters['country'], 'IN');
      expect(link.queryParameters['fiatCurrency'], 'INR');
      expect(link.queryParameters['fiatAmount'], '1100.00');
      expect(link.queryParameters['network'], 'tron');
      expect(link.queryParameters['paymentMethod'], 'upi');
      // Link me wallet address KABHI nahi hota.
      expect(link.toString().contains('T'), isFalse);
      expect(link.toString().contains('0x'), isFalse);
    });

    test('builds a link without amount when amount is missing', () {
      final link = BuyLink.build(
        country: BuyCountry.byId('US'),
        network: BuyNetwork.tron,
        paymentMethod: BuyPaymentMethod.card,
      );
      expect(link.queryParameters.containsKey('fiatAmount'), isFalse);
      expect(link.queryParameters['country'], 'US');
      expect(link.queryParameters['paymentMethod'], 'card');
    });
  });

  group('BuyLink.parse', () {
    test('round-trip: build -> parse gives the same options', () {
      final link = BuyLink.build(
        country: BuyCountry.byId('IN'),
        fiatAmount: 1100,
        network: BuyNetwork.tron,
        paymentMethod: BuyPaymentMethod.upi,
      );
      final params = BuyLink.parse(link);
      expect(params, isNotNull);
      expect(params!.country.id, 'IN');
      expect(params.fiatAmount, 1100);
      expect(params.network, BuyNetwork.tron);
      expect(params.paymentMethod, BuyPaymentMethod.upi);
    });

    test('USA link parses to USD + Apple Pay', () {
      final params = BuyLink.tryParseString(
        'darkvibex-wallet://buy?country=US&fiatCurrency=USD'
        '&fiatAmount=50&network=ethereum&paymentMethod=applePay',
      );
      expect(params, isNotNull);
      expect(params!.country.id, 'US');
      expect(params.fiatAmount, 50);
      expect(params.network, BuyNetwork.ethereum);
      expect(params.paymentMethod, BuyPaymentMethod.applePay);
    });

    test('country missing ho to fiatCurrency se country nikalta hai', () {
      final params = BuyLink.tryParseString(
        'darkvibex-wallet://buy?fiatCurrency=INR&fiatAmount=110'
        '&network=tron&paymentMethod=upi',
      );
      expect(params, isNotNull);
      expect(params!.country.id, 'IN');
    });

    test('UPI USA link me ho to us country ka pehla method milta hai', () {
      final params = BuyLink.tryParseString(
        'darkvibex-wallet://buy?country=US&fiatCurrency=USD'
        '&network=tron&paymentMethod=upi',
      );
      expect(params, isNotNull);
      // USA me UPI nahi hai — Card (pehla method) default.
      expect(params!.paymentMethod, BuyPaymentMethod.card);
    });

    test('galat network ho to Tron default', () {
      final params = BuyLink.tryParseString(
        'darkvibex-wallet://buy?country=IN&fiatCurrency=INR'
        '&network=wrongchain&paymentMethod=upi',
      );
      expect(params, isNotNull);
      expect(params!.network, BuyNetwork.tron);
    });

    test('amount missing/invalid ho to null (user app me bharega)', () {
      final params = BuyLink.tryParseString(
        'darkvibex-wallet://buy?country=IN&fiatCurrency=INR'
        '&network=tron&paymentMethod=upi',
      );
      expect(params, isNotNull);
      expect(params!.fiatAmount, isNull);
    });

    test('non-buy link returns null', () {
      expect(BuyLink.tryParseString('https://example.com/buy'), isNull);
      expect(BuyLink.tryParseString('darkvibex-wallet://home'), isNull);
      expect(BuyLink.tryParseString('not a link at all'), isNull);
      expect(BuyLink.tryParseString(''), isNull);
    });
  });

  group('Vinay ka set rate — \$1 = ₹110', () {
    test('₹110 me 1 USDT milta hai', () {
      final quote = BuyService.buildInrEstimate(fiatAmount: 110);
      expect(quote.estimatedUsdt, closeTo(1, 0.0001));
      expect(quote.fiatCurrency, 'INR');
      expect(quote.rateSource,
          'Vinay ka set rate — \$1 = ₹110 (1 USDT = ₹110)');
    });

    test('₹1100 me 10 USDT, ₹55 me 0.5 USDT', () {
      expect(BuyService.buildInrEstimate(fiatAmount: 1100).estimatedUsdt,
          closeTo(10, 0.0001));
      expect(BuyService.buildInrEstimate(fiatAmount: 55).estimatedUsdt,
          closeTo(0.5, 0.0001));
    });

    test('fixed rate is exactly 110', () {
      expect(BuyService.fixedInrPerUsdt, 110.0);
    });

    test('getQuote INR par bina network ke fixed rate deta hai', () async {
      final quote = await BuyService().getQuote(
        fiatAmount: 220,
        country: BuyCountry.byId('IN'),
      );
      expect(quote.estimatedUsdt, closeTo(2, 0.0001));
      expect(quote.rateSource, contains('₹110'));
    });

    test('INR estimate zero amount par throw karta hai', () {
      expect(
        () => BuyService.buildInrEstimate(fiatAmount: 0),
        throwsException,
      );
    });
  });
}
