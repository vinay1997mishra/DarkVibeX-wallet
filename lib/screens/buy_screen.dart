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
      setState(() => _quoteError = 'Enter a valid amount (more than 0).');
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
            'The browser could not be opened. Copy the link and open it in your browser:\n$url');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Transak has opened in your browser. Payment and KYC will happen there — '
              'your balance on Home will increase as soon as the USDT arrives.',
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
        content: Text('Buy link copied:\n$link'),
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
                    ? 'TEST MODE (Transak staging) — no real money will be charged. '
                        'Test with a test card / test details.'
                    : 'REAL MODE (Transak production) — real money will be charged. '
                        'You will need to complete KYC, and the rate and fee will be shown at checkout.',
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
              'Currency and payment methods change based on the country.',
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
              'In ${_country.name} these methods are available: ${_methods.map((m) => m.label).join(', ')}. '
              'The final list will be shown in the Transak widget — you can also choose from there.',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 20),

            // ---- Network ----
            const Text('Network (where the USDT will arrive)',
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
                        ? 'Address not found.'
                        : 'USDT will arrive at this address: ${_walletAddress.length > 18 ? '${_walletAddress.substring(0, 10)}...${_walletAddress.substring(_walletAddress.length - 6)}' : _walletAddress}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  tooltip: 'Copy address',
                  onPressed: _walletAddress.isEmpty
                      ? null
                      : () {
                          Clipboard.setData(
                              ClipboardData(text: _walletAddress));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Address copied')),
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
                  : const Text('See rate'),
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
                        "₹110 = 1 USDT — Vinay's set rate (\$1 = ₹110).",
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ],
                    const Divider(),
                    Text(
                      'You will pay: ${quote.fiatSymbol}${quote.fiatAmount.toStringAsFixed(2)} '
                      '(${quote.fiatCurrency}) • ${_method.label}',
                    ),
                    Text(
                      'You will receive (approx., before fee): '
                      '${quote.estimatedUsdt.toStringAsFixed(4)} USDT '
                      '• ${_network.label}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "This is only an ESTIMATE — Transak's actual fee and final "
                      'rate will be shown at checkout (in the widget); do not treat it as confirmed '
                      'before that. The fee depends on the method (higher on card, '
                      'may differ on UPI/bank).',
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
                      ? 'Buy on Transak (${_method.label})'
                      : 'Buy is not set up',
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
                    'Buy is not set up yet — a Transak API key is needed:\n'
                    '1. Create a partner account at https://dashboard.transak.com\n'
                    '2. Environment: Staging → Developers → get the API key\n'
                    '3. Paste it in lib/config.dart under BuyConfig.transakApiKey\n'
                    'Transak KYB must be approved for a production key.',
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
              label: const Text('Copy buy link'),
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
              'To buy, you will need to complete KYC on Transak (details like ID / PAN) '
              '— the first time. After you receive USDT, your balance on Home '
              'will increase automatically. The first time, test with a small amount.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
