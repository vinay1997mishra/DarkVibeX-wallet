// Buy deep link — shareable link se Buy screen kholo.
//
// LINK FORMAT (shareable — WhatsApp / DarkVibeX app me daal sakte ho):
//   darkvibex-wallet://buy?country=IN&fiatCurrency=INR&fiatAmount=1100
//       &network=tron&paymentMethod=upi
//
//   - Link me sirf BUY KE OPTIONS hote hain (country, amount, network,
//     payment method) — wallet address NAHI hota. Address hamesha us
//     phone ke wallet se aata hai jis par link khulta hai, taaki USDT
//     hamesha kharidne wale ke apne wallet me jaye.
//   - DarkVibeX app me ye link add karo → user tap kare → wallet app
//     (install ho to) Buy screen par khulta hai, options pre-filled.
//   - App install na ho to link kuch nahi karega — uske liye Play Store
//     link fallback DarkVibeX side par lagana hoga (README dekho).
//
// NATIVE SETUP (abhi baaki — repo me android/ ios/ folder nahi hai,
// `flutter create .` se banta hai, tab ye karna hai):
//   Android (AndroidManifest.xml, MAIN activity ke andar):
//     <intent-filter>
//       <action android:name="android.intent.action.VIEW" />
//       <category android:name="android.intent.category.DEFAULT" />
//       <category android:name="android.intent.category.BROWSABLE" />
//       <data android:scheme="darkvibex-wallet" android:host="buy" />
//     </intent-filter>
//   iOS (Info.plist): CFBundleURLSchemes me "darkvibex-wallet" add karo.
//   Tab tak link sirf app ke andar (copy/share + parse) kaam karta hai.

import 'buy_service.dart';

/// Link se aaye hue buy options — BuyScreen ko pre-fill karne ke liye.
class BuyLinkParams {
  final BuyCountry country;
  final double? fiatAmount;
  final BuyNetwork network;
  final BuyPaymentMethod paymentMethod;

  const BuyLinkParams({
    required this.country,
    required this.fiatAmount,
    required this.network,
    required this.paymentMethod,
  });
}

/// Shareable buy link banata + parse karta hai. Pure functions —
//  bina network ke test hote hain.
class BuyLink {
  static const String scheme = 'darkvibex-wallet';
  static const String host = 'buy';

  /// Current selections se shareable link banao.
  /// [fiatAmount] null ho to link bina amount ke banta hai (user
  /// app me amount khud bharega).
  static Uri build({
    required BuyCountry country,
    double? fiatAmount,
    required BuyNetwork network,
    required BuyPaymentMethod paymentMethod,
  }) {
    final params = <String, String>{
      'country': country.id,
      'fiatCurrency': country.fiatCurrency,
      'network': network.transakNetwork,
      'paymentMethod': paymentMethod.name,
    };
    if (fiatAmount != null && fiatAmount > 0) {
      params['fiatAmount'] = fiatAmount.toStringAsFixed(2);
    }
    return Uri(scheme: scheme, host: host, queryParameters: params);
  }

  /// Link string se params nikalo. Buy link na ho ya tuta ho to null.
  static BuyLinkParams? tryParseString(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null) return null;
    return parse(uri);
  }

  /// Uri se params nikalo. Buy link na ho to null.
  static BuyLinkParams? parse(Uri uri) {
    if (uri.scheme != scheme || uri.host != host) return null;

    // Country: pehle `country` param, nahi to fiatCurrency se.
    BuyCountry country;
    final countryId = uri.queryParameters['country'];
    if (countryId != null && countryId.isNotEmpty) {
      country = BuyCountry.byId(countryId.toUpperCase());
    } else {
      country = _countryForFiat(
        uri.queryParameters['fiatCurrency']?.toUpperCase() ?? '',
      );
    }

    // Network: 'tron' / 'ethereum' / 'bsc' — galat ho to Tron default.
    var network = BuyNetwork.tron;
    final networkRaw = uri.queryParameters['network']?.toLowerCase();
    for (final n in BuyNetwork.values) {
      if (n.transakNetwork == networkRaw) network = n;
    }

    // Payment method: enum name se ('upi', 'card', 'applePay' ...).
    // Country me na ho to us country ka pehla method default.
    var method = country.paymentMethods.first;
    final methodRaw = uri.queryParameters['paymentMethod'];
    if (methodRaw != null && methodRaw.isNotEmpty) {
      for (final m in BuyPaymentMethod.values) {
        if (m.name.toLowerCase() == methodRaw.toLowerCase()) {
          if (country.paymentMethods.contains(m)) method = m;
          break;
        }
      }
    }

    // Amount: number na ho to null (user app me bharega).
    final amountRaw = uri.queryParameters['fiatAmount'];
    final amount = amountRaw == null ? null : double.tryParse(amountRaw);
    final fiatAmount =
        (amount != null && amount > 0) ? amount : null;

    return BuyLinkParams(
      country: country,
      fiatAmount: fiatAmount,
      network: network,
      paymentMethod: method,
    );
  }

  static BuyCountry _countryForFiat(String fiatCurrency) {
    switch (fiatCurrency) {
      case 'INR':
        return BuyCountry.byId('IN');
      case 'GBP':
        return BuyCountry.byId('GB');
      case 'EUR':
        return BuyCountry.byId('EU');
      case 'USD':
        return BuyCountry.byId('US');
      default:
        return BuyCountry.byId('IN');
    }
  }
}
