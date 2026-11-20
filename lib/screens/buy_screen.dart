// Buy USDT screen — fiat se USDT kharido (Transak on-ramp).
//
// FLOW:
//   1. Country chuno → us country ki currency + payment methods dikhte
//      hain (India: UPI + Card + Bank Transfer; USA/UK/Europe: Card +
//      Apple Pay + Google Pay + Bank Transfer; Other: Card + Apple Pay
//      + Google Pay).
//   2. Amount + network (Tron default) chuno → "Rate dekho" → CoinGecko
//      se ESTIMATE: kitna USDT milega (fee se pehle).
//   3. "Transak par kharido" → Transak widget phone ke browser me khulta
//      hai — payment + KYC wahin hota hai. USDT aate hi Home par balance
//      badhega (30-sec refresh).
//
// HONEST RULES:
//   - App sirf estimate dikhata hai — final rate aur fee Transak
//     checkout me dikhte hain. Kabhi fake "buy ho gaya" nahi.
//   - API key set nahi hai to Buy button disabled rehta hai + setup
//     steps dikhte hain.
//   - Staging (default) = TEST MODE — asli paise nahi lagte. Production
//     = REAL paise, KYC + KYB chahiye.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../services/buy_link.dart';
import '../services/buy_service.dart';

class BuyScreen extends StatefulWidget {
  final String tronAddress; // USDT TRC20 destination (T...)
  final String evmAddress; // USDT ERC20/BEP20 destination (0x...)

  /// Shareable buy link (darkvibex-wallet://buy?...) se aaye options —
  /// screen khulte hi pre-fill ho jate hain.
  final BuyLinkParams? initialParams;

  const BuyScreen({
    super.key,
    required this.tronAddress,
    required this.evmAddress,
    this.initialParams,
  });

  @override
  State<BuyScreen> createState() => _BuyScreenState();
}

class _BuyScreenState extends State<BuyScreen> {
  final _buyService = BuyService();
  final _amountController = TextEditingController();

  BuyCountry _country = BuyCountry.all.first; // India (default)
  BuyPaymentMethod _method = BuyPaymentMethod.upi;
  BuyNetwork _network = BuyNetwork.tron;

  BuyQuote? _quote;
  String? _quoteError;
  bool _loadingQuote = false;
  String? _launchError;

  @override
  void initState() {
    super.initState();
    // Buy link se khula ho to uske options pre-fill karo.
    final initial = widget.initialParams;
    if (initial != null) {
      _country = initial.country;
      _method = initial.paymentMethod;
      _network = initial.network;
      if (initial.fiatAmount != null) {
        _amountController.text = initial.fiatAmount!.toStringAsFixed(2);
      }
    }
  }

  String get _walletAddress =>
      _network == BuyNetwork.tron ? widget.tronAddress : widget.evmAddress;

  List<BuyPaymentMethod> get _methods => _country.paymentMethods;

  void _onCountryChanged(BuyCountry? country) {
    if (country == null) return;
    setState(() {
      _country = country;
      // Country ke methods me pehla method default — India par UPI,
      // baaki par Card. Purana method nayi country me na ho to badlo.
      _method = country.paymentMethods.first;
      _quote = null;
      _quoteError = null;
    });
  }

  Future<void> _getQuote() async {
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      setState(() => _quoteError = 'Sahi amount likho (0 se zyada).');
      return;
    }
    setState(() {
      _loadingQuote = true;
      _quoteError = null;
      _quote = null;
    });
    try {
      // INR: fixed ₹110 rate (Vinay ka set rate — bina network).
      // Baaki currencies: CoinGecko estimate.
      final quote = await _buyService.getQuote(
        fiatAmount: amount,
        country: _country,
      );
      if (!mounted) return;
      setState(() => _quote = quote);
    } catch (e) {
      if (mounted) {
        setState(() =>
            _quoteError = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loadingQuote = false);
    }
  }

  Future<void> _openTransak() async {
    final quote = _quote;
    if (quote == null || !BuyConfig.isConfigured) return;
    setState(() => _launchError = null);
    try {
      final url = BuyService.buildWidgetUrl(
        fiatAmount: quote.fiatAmount,
        country: _country,
        network: _network,
        paymentMethod: _method,
        walletAddress: _walletAddress,
      );
      final ok = await _buyService.launchBuy(url);
      if (!mounted) return;
      if (!ok) {
        setState(() => _launchError =
            'Browser nahi khul paya. Link copy karke browser me kholo:\n$url');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Transak browser me khul gaya. Payment + KYC wahin hoga — '
              'USDT aate hi Home par balance badhega.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(
            () => _launchError = e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  /// Current selections se shareable buy link.
  Uri _currentBuyLink() {
    final amount = double.tryParse(_amountController.text);
    return BuyLink.build(
      country: _country,
      fiatAmount: amount,
      network: _network,
      paymentMethod: _method,
    );
  }

  /// Buy link copy karo — DarkVibeX app / WhatsApp me share karne ke liye.
  Future<void> _shareBuyLink() async {
    final link = _currentBuyLink().toString();
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Buy link copy ho gaya:\n$link'),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final quote = _quote;
    final configured = BuyConfig.isConfigured;
    final isTest = BuyConfig.isTestMode;
    return Scaffold(
      appBar: AppBar(title: const Text('Buy USDT')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ---- Test / real banner ----
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (isTest ? Colors.orange : Colors.red).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: (isTest ? Colors.orange : Colors.red)
                      .withOpacity(0.4),
                ),
              ),
              child: Text(
                isTest
                    ? 'TEST MODE (Transak staging) — asli paise nahi lagenge. '
                        'Test card / test details se test karo.'
                    : 'REAL MODE (Transak production) — asli paise lagenge. '
                        'KYC karni padegi, aur rate + fee checkout me dikhegi.',
                style: const TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(height: 20),

            // ---- Country ----
            const Text('Country',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<BuyCountry>(
              value: _country,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
              ),
              items: BuyCountry.all
                  .map((c) => DropdownMenuItem(
                        value: c,
                        child: Text('${c.name} (${c.fiatCurrency})'),
                      ))
                  .toList(),
              onChanged: _onCountryChanged,
            ),
            const SizedBox(height: 4),
            const Text(
              'Country ke hisaab se currency aur payment methods badalte hain.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 20),

            // ---- Amount ----
            TextField(
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Amount (${_country.fiatSymbol} ${_country.fiatCurrency})',
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() => _quote = null),
            ),
            const SizedBox(height: 20),

            // ---- Payment method (country ke hisaab se) ----
            const Text('Payment method',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _methods.map((m) {
                return ChoiceChip(
                  label: Text(m.label),
                  selected: m == _method,
                  onSelected: (_) => setState(() {
                    _method = m;
                    _quote = null;
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: 4),
            Text(
              '${_country.name} me ye methods hain: ${_methods.map((m) => m.label).join(', ')}. '
              'Final list Transak widget me dikhegi — wahan se bhi chun sakte ho.',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 20),

            // ---- Network ----
            const Text('Network (USDT kahan aayega)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: BuyNetwork.values.map((n) {
                return ChoiceChip(
                  label: Text(n.label),
                  selected: n == _network,
                  onSelected: (_) => setState(() {
                    _network = n;
                    _quote = null;
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _walletAddress.isEmpty
                        ? 'Address nahi mila.'
                        : 'USDT is address par aayega: ${_walletAddress.length > 18 ? '${_walletAddress.substring(0, 10)}...${_walletAddress.substring(_walletAddress.length - 6)}' : _walletAddress}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  tooltip: 'Address copy karo',
                  onPressed: _walletAddress.isEmpty
                      ? null
                      : () {
                          Clipboard.setData(
                              ClipboardData(text: _walletAddress));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Address copy ho gaya')),
                          );
                        },
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ---- Rate dekho ----
            ElevatedButton(
              onPressed: _loadingQuote ? null : _getQuote,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _loadingQuote
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('Rate dekho'),
            ),
            if (_quoteError != null) ...[
              const SizedBox(height: 12),
              Text(_quoteError!, style: const TextStyle(color: Colors.red)),
            ],

            // ---- Quote card (ESTIMATE) ----
            if (quote != null) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.teal.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '1 USDT ≈ ${quote.fiatSymbol}${(1 / quote.usdtPerFiat).toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text('Rate source: ${quote.rateSource}',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.grey)),
                    if (quote.fiatCurrency == 'INR') ...[
                      const SizedBox(height: 4),
                      const Text(
                        '₹110 = 1 USDT — Vinay ka set rate (\$1 = ₹110).',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ],
                    const Divider(),
                    Text(
                      'Tum doge: ${quote.fiatSymbol}${quote.fiatAmount.toStringAsFixed(2)} '
                      '(${quote.fiatCurrency}) • ${_method.label}',
                    ),
                    Text(
                      'Tum paaoge (lagbhag, fee se pehle): '
                      '${quote.estimatedUsdt.toStringAsFixed(4)} USDT '
                      '• ${_network.label}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Ye sirf ESTIMATE hai — Transak ki asli fee aur final '
                      'rate checkout (widget) me dikhega, usse pehle confirm '
                      'mat samjho. Fee method par depend karti hai (card par '
                      'zyada, UPI/bank par alag ho sakti hai).',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: configured ? _openTransak : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: Text(
                  configured
                      ? 'Transak par kharido (${_method.label})'
                      : 'Buy setup nahi hai',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
              if (!configured) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Buy abhi setup nahi hai — Transak API key chahiye:\n'
                    '1. https://dashboard.transak.com par partner account banao\n'
                    '2. Environment: Staging → Developers → API key lo\n'
                    '3. lib/config.dart me BuyConfig.transakApiKey me paste karo\n'
                    'Production key ke liye Transak KYB approve hona chahiye.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ],
            if (_launchError != null) ...[
              const SizedBox(height: 12),
              Text(_launchError!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 16),
            // ---- Shareable buy link ----
            // DarkVibeX app me ye link lagega — user tap kare to wallet
            // app Buy screen par khulega, options pre-filled. Link me
            // wallet address NAHI hota — USDT hamesha kharidne wale ke
            // apne wallet me jayega.
            OutlinedButton.icon(
              onPressed: _shareBuyLink,
              icon: const Icon(Icons.share, size: 18),
              label: const Text('Buy link copy karo'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Link: ${_currentBuyLink()}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            const Text(
              'Buy karne ke liye Transak par KYC karni padegi (ID / PAN jaisi '
              'details) — pehli baar. USDT milne ke baad Home par balance '
              'apne aap badhega. Pehli baar chhota amount se test karo.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
