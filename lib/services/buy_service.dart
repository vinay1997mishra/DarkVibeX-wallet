// Buy USDT — fiat (INR/USD/GBP/EUR) se USDT kharido, Transak on-ramp se.
//
// ROUTE (research, 2026-11-20): Transak — India ke liye UPI deta hai
// (MoonPay/Banxa/Mercuryo comparison me UPI sirf Transak ka tha), aur
// international: card, Apple Pay, Google Pay, bank transfer. Isliye
// provider Transak hai, MoonPay nahi.
//
// PAYMENT METHODS COUNTRY KE HISAAB SE:
//   India  (INR): UPI + Card + Bank Transfer
//   USA    (USD): Card + Apple Pay + Google Pay + Bank Transfer
//   UK     (GBP): Card + Apple Pay + Google Pay + Bank Transfer
//   Europe (EUR): Card + Apple Pay + Google Pay + Bank Transfer (SEPA)
//   Other  (USD): Card + Apple Pay + Google Pay
// Country badalte hi fiat currency + methods badal jate hain.
//
// KYA APP KARTA HAI / KYA NAHI:
//   - App sirf ESTIMATE dikhata hai (CoinGecko USDT rate se) + Transak
//     widget ka URL banata hai (wallet address pre-filled, amount,
//     network, payment method default). Asli payment, KYC, rate aur fee
//     — sab Transak widget (browser) me hota hai, app ke andar nahi.
//   - App kabhi khud paise nahi leta, kabhi fake "buy ho gaya" nahi
//     dikhata. USDT aane par Home par balance apne aap badhega (30-sec
//     refresh) — wahi asli confirmation hai.
//   - API key khaali ho to Buy button disabled rehta hai (setup-needed
//     message ke saath). Key ke bina quote bhi estimate hi rehta hai.
//
// PAYMENT METHOD CODES — dhyaan se:
//   Transak ke docs me verify kiye hue codes: `credit_debit_card`,
//   `apple_pay`, `google_pay`, `gbp_bank_transfer`, `pm_wire`,
//   `pm_open_banking` (docs.transak.com — Get Fiat Currencies).
//   UPI / INR bank transfer / SEPA ke codes Transak ke per-currency
//   fiat-currencies API se aate hain (public docs me list nahi hain) —
//   isliye yahan `upi`, `inr_bank_transfer`, `sepa_bank_transfer`
//   use hote hain. Galat code se buy BLOCK nahi hota: hum method ko
//   LOCK nahi karte (`paymentMethod`), sirf DEFAULT suggest karte hain
//   (`defaultPaymentMethod`) — widget apni supported methods ki list
//   khud dikhata hai, user wahan se chun sakta hai. Phir bhi, production
//   se pehle Transak dashboard se apne account ke supported methods
//   check kar lo.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';

/// Ek payment method — label + Transak widget code.
enum BuyPaymentMethod {
  upi('UPI', 'upi'),
  card('Card', 'credit_debit_card'),
  applePay('Apple Pay', 'apple_pay'),
  googlePay('Google Pay', 'google_pay'),
  bankTransfer('Bank Transfer', null); // Code country ke hisaab se.

  const BuyPaymentMethod(this.label, this.transakCode);

  final String label;

  /// Transak widget code — bank transfer ka code country par depend
  /// karta hai, isliye [transakCodeFor] use karo.
  final String? transakCode;

  /// Is method ka Transak code, country ke hisaab se. Bank transfer:
  /// UK = gbp_bank_transfer (docs me verified), India = inr_bank_transfer,
  /// Europe = sepa_bank_transfer, USA = pm_wire (docs me verified code).
  /// Baaki methods ka code har country me ek hi hai.
  String? transakCodeFor(BuyCountry country) {
    if (this != BuyPaymentMethod.bankTransfer) return transakCode;
    switch (country.id) {
      case 'IN':
        return 'inr_bank_transfer';
      case 'GB':
        return 'gbp_bank_transfer';
      case 'EU':
        return 'sepa_bank_transfer';
      case 'US':
        return 'pm_wire';
      default:
        return null; // Pata nahi — widget khud methods dikhayega.
    }
  }
}

/// Ek country — fiat currency + uske payment methods.
class BuyCountry {
  final String id; // 'IN', 'US', 'GB', 'EU', 'OTHER'
  final String name; // 'India', 'USA', ...
  final String fiatCurrency; // 'INR', 'USD', 'GBP', 'EUR'
  final String fiatSymbol; // '₹', '$', '£', '€'
  final List<BuyPaymentMethod> paymentMethods;

  const BuyCountry({
    required this.id,
    required this.name,
    required this.fiatCurrency,
    required this.fiatSymbol,
    required this.paymentMethods,
  });

  static const List<BuyCountry> all = [
    BuyCountry(
      id: 'IN',
      name: 'India',
      fiatCurrency: 'INR',
      fiatSymbol: '₹',
      paymentMethods: [
        BuyPaymentMethod.upi,
        BuyPaymentMethod.card,
        BuyPaymentMethod.bankTransfer,
      ],
    ),
    BuyCountry(
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
    ),
    BuyCountry(
      id: 'GB',
      name: 'UK',
      fiatCurrency: 'GBP',
      fiatSymbol: '£',
      paymentMethods: [
        BuyPaymentMethod.card,
        BuyPaymentMethod.applePay,
        BuyPaymentMethod.googlePay,
        BuyPaymentMethod.bankTransfer,
      ],
    ),
    BuyCountry(
      id: 'EU',
      name: 'Europe',
      fiatCurrency: 'EUR',
      fiatSymbol: '€',
      paymentMethods: [
        BuyPaymentMethod.card,
        BuyPaymentMethod.applePay,
        BuyPaymentMethod.googlePay,
        BuyPaymentMethod.bankTransfer,
      ],
    ),
    BuyCountry(
      id: 'OTHER',
      name: 'Other countries',
      fiatCurrency: 'USD',
      fiatSymbol: '\$',
      paymentMethods: [
        BuyPaymentMethod.card,
        BuyPaymentMethod.applePay,
        BuyPaymentMethod.googlePay,
      ],
    ),
  ];

  static BuyCountry byId(String id) =>
      all.firstWhere((c) => c.id == id, orElse: () => all.first);
}

/// Buy kis network par: USDT TRC20 (Tron, default) / ERC20 / BEP20.
/// Transak widget ke network naam: 'tron', 'ethereum', 'bsc'.
enum BuyNetwork {
  tron('Tron (TRC20)', 'tron'),
  ethereum('Ethereum (ERC20)', 'ethereum'),
  bsc('BNB Smart Chain (BEP20)', 'bsc');

  const BuyNetwork(this.label, this.transakNetwork);

  final String label;
  final String transakNetwork;
}

/// Estimate quote — CoinGecko rate se. FINAL rate/fee NAHI hai.
class BuyQuote {
  final double fiatAmount;
  final String fiatCurrency;
  final String fiatSymbol;
  final double usdtPerFiat; // 1 fiat unit = kitna USDT (estimate)
  final double estimatedUsdt; // Milega (lagbhag, fee se pehle)
  final String rateSource; // Hamesha 'CoinGecko (estimate)'

  const BuyQuote({
    required this.fiatAmount,
    required this.fiatCurrency,
    required this.fiatSymbol,
    required this.usdtPerFiat,
    required this.estimatedUsdt,
    required this.rateSource,
  });
}

class BuyService {
  final http.Client _client;

  BuyService({http.Client? client}) : _client = client ?? http.Client();

  static const _coinGeckoBase = 'https://api.coingecko.com/api/v3';

  /// Vinay ka SET rate — $1 = ₹110 (2026-11-20, DarkVibeX coin rate
  /// wala hi rate). INR buy ka estimate ISI rate se banta hai:
  ///   1 USDT = ₹110  →  ₹110 me 1 USDT, ₹1100 me 10 USDT, ₹55 me 0.5 USDT.
  /// Ye market rate nahi hai — CoinGecko market rate isse alag ho sakta
  /// hai (~₹88-90). INR par hamesha ye set rate dikhega; USD/GBP/EUR
  /// par CoinGecko estimate chalta hai (neeche getQuote dekho).
  static const double fixedInrPerUsdt = 110.0;

  /// INR estimate — fixed ₹110 rate se, bina network ke.
  static BuyQuote buildInrEstimate({required double fiatAmount}) {
    if (fiatAmount <= 0) throw Exception('Amount 0 se zyada hona chahiye.');
    return BuyQuote(
      fiatAmount: fiatAmount,
      fiatCurrency: 'INR',
      fiatSymbol: '₹',
      usdtPerFiat: 1 / fixedInrPerUsdt,
      estimatedUsdt: fiatAmount / fixedInrPerUsdt,
      rateSource: 'Vinay ka set rate — \$1 = ₹110 (1 USDT = ₹110)',
    );
  }

  /// Quote banao: INR ho to fixed ₹110 rate (bina network), baaki
  /// currencies par CoinGecko se live estimate.
  Future<BuyQuote> getQuote({
    required double fiatAmount,
    required BuyCountry country,
  }) async {
    if (fiatAmount <= 0) throw Exception('Amount 0 se zyada hona chahiye.');
    if (country.fiatCurrency == 'INR') {
      return buildInrEstimate(fiatAmount: fiatAmount);
    }
    final rate = await fetchUsdtFiatRate(country.fiatCurrency);
    return buildEstimate(
      fiatAmount: fiatAmount,
      country: country,
      usdtFiatRate: rate,
    );
  }

  /// CoinGecko se 1 USDT ka fiat rate (jaise 1 USDT = ₹88.50).
  /// Sirf INR/USD/GBP/EUR — country ki currency ke hisaab se.
  Future<double> fetchUsdtFiatRate(String fiatCurrency) async {
    final code = fiatCurrency.toLowerCase();
    final uri = Uri.parse(
      '$_coinGeckoBase/simple/price?ids=tether&vs_currencies=$code',
    );
    final res = await _client.get(uri);
    if (res.statusCode != 200) {
      throw Exception(
        'Rate nahi mil paya (CoinGecko HTTP ${res.statusCode}). Internet check karo, thodi der baad dobara try karo.',
      );
    }
    return parseUsdtFiatRate(res.body, fiatCurrency);
  }

  /// Pure parsing — bina network ke test hota hai.
  /// Body: {"tether":{"inr":88.5}} → 88.5 (1 USDT = ₹88.50).
  static double parseUsdtFiatRate(String body, String fiatCurrency) {
    final json = jsonDecode(body) as Map<String, dynamic>;
    final tether = json['tether'];
    if (tether is! Map) throw Exception('Rate nahi mila (CoinGecko).');
    final rate = tether[fiatCurrency.toLowerCase()];
    if (rate is! num || rate <= 0) {
      throw Exception('Is currency ka rate nahi mila (CoinGecko).');
    }
    return rate.toDouble();
  }

  /// Estimate banao: fiat amount / USDT rate = kitna USDT (fee se pehle).
  /// Fee yahan nahi kat-ti — Transak ki fee checkout me dikhegi.
  static BuyQuote buildEstimate({
    required double fiatAmount,
    required BuyCountry country,
    required double usdtFiatRate,
  }) {
    if (fiatAmount <= 0) throw Exception('Amount 0 se zyada hona chahiye.');
    if (usdtFiatRate <= 0) throw Exception('Rate 0 se zyada hona chahiye.');
    return BuyQuote(
      fiatAmount: fiatAmount,
      fiatCurrency: country.fiatCurrency,
      fiatSymbol: country.fiatSymbol,
      usdtPerFiat: 1 / usdtFiatRate,
      estimatedUsdt: fiatAmount / usdtFiatRate,
      rateSource: 'CoinGecko (estimate)',
    );
  }

  /// Transak widget ka URL banata hai — wallet address pre-filled,
  /// amount + network + payment method default. Method LOCK nahi hoti
  /// (defaultPaymentMethod), taaki galat code se bhi buy block na ho —
  /// widget apni supported methods khud dikhata hai.
  /// API key khaali ho to Exception — UI button ko disabled rakhta hai.
  static Uri buildWidgetUrl({
    required double fiatAmount,
    required BuyCountry country,
    required BuyNetwork network,
    required BuyPaymentMethod paymentMethod,
    required String walletAddress,
  }) {
    if (!BuyConfig.isConfigured) {
      throw Exception(
        'Buy setup nahi hai — Transak API key config me dalo (README dekho).',
      );
    }
    if (walletAddress.isEmpty) {
      throw Exception('Wallet address nahi mila — pehle wallet banao.');
    }
    final params = <String, String>{
      'apiKey': BuyConfig.transakApiKey,
      'productsAvailed': 'BUY',
      'fiatCurrency': country.fiatCurrency,
      'defaultFiatAmount': fiatAmount.toStringAsFixed(2),
      'cryptoCurrencyCode': 'USDT',
      'network': network.transakNetwork,
      'walletAddress': walletAddress,
      'disableWalletAddressForm': 'true',
      'environment': BuyConfig.transakEnvironment.toUpperCase(),
    };
    final methodCode = paymentMethod.transakCodeFor(country);
    if (methodCode != null) {
      params['defaultPaymentMethod'] = methodCode;
    }
    if (BuyConfig.transakReferrerDomain.isNotEmpty) {
      params['referrerDomain'] = BuyConfig.transakReferrerDomain;
    }
    return Uri.parse(BuyConfig.transakWidgetBaseUrl)
        .replace(queryParameters: params);
  }

  /// Widget ko phone ke browser me kholo (KYC me camera chahiye hota
  /// hai, isliye external browser — in-app webview nahi).
  /// Returns false agar browser khul hi nahi paya.
  Future<bool> launchBuy(Uri widgetUrl) async {
    return launchUrl(widgetUrl, mode: LaunchMode.externalApplication);
  }
}
