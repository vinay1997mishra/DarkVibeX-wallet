// Swap / Exchange screen — coin badlo, app ke andar hi.
//
// CHAIN SELECTOR: Tron / Ethereum / BNB Smart Chain.
//   Tron:     USDT <-> TRX — LIVE execute (SunSwap V2, testnet pehle).
//   Ethereum: USDT ERC20 / ETH / SHIB — sirf RATE (quote only).
//             Swap (Uniswap) next step hai, abhi execute nahi hota.
//   BNB:      USDT BEP20 / BNB — sirf RATE (quote only).
//             Swap (PancakeSwap) next step hai, abhi execute nahi hota.
//
// Har coin ke SAATH uska network dikhta hai ("USDT • Tron (TRC20)",
// "USDT • BNB Smart Chain (BEP20)") — taaki dono USDT kabhi mix na hon.
//
// Confirm se PEHLE sab dikhta hai: rate, rate ka source, service fee
// (PERMANENT 0.09%, owner profit — USI COIN me kategi jo swap ho raha
// hai, alag coin nahi chahiye), milne wala amount, minimum receive
// (slippage), aur network fee alag se. Quote-only pair ho to Confirm
// disabled rehta hai aur wajah saaf likhi hoti hai — kabhi fake swap nahi.

import 'package:flutter/material.dart';

import '../config.dart';
import '../models/swap_model.dart';
import '../services/evm_service.dart';
import '../services/swap_service.dart';
import '../services/token_list.dart';

enum SwapChain { tron, ethereum, bsc }

class SwapScreen extends StatefulWidget {
  final String fromAddress; // Tron address (T...)
  final String evmAddress; // Ethereum/BNB address (0x...)
  final double usdtBalance;
  final double trxBalance;

  const SwapScreen({
    super.key,
    required this.fromAddress,
    required this.evmAddress,
    required this.usdtBalance,
    required this.trxBalance,
  });

  @override
  State<SwapScreen> createState() => _SwapScreenState();
}

class _SwapScreenState extends State<SwapScreen> {
  final _swapService = SwapService();
  final _amountController = TextEditingController();

  SwapChain _chain = SwapChain.tron;
  List<TokenInfo> _customTokens = [];
  TokenInfo? _from;
  TokenInfo? _to;
  SwapQuote? _quote;
  String? _quoteError;
  bool _loadingQuote = false;
  bool _swapping = false;
  String? _swapError;
  String? _doneTxId;

  // EVM balances (sirf Ethereum/BNB chain par MAX ke liye).
  final Map<String, double> _evmBalances = {};

  List<TokenInfo> get _chainTokens {
    final all = [...curatedTokens, ..._customTokens];
    switch (_chain) {
      case SwapChain.tron:
        return all
            .where((t) => t.id == 'USDT-TRC20' || t.id == 'TRX')
            .toList();
      case SwapChain.ethereum:
        return all
            .where((t) =>
                t.id == 'USDT-ERC20' || t.id == 'ETH' || t.id == 'SHIB')
            .toList();
      case SwapChain.bsc:
        return all
            .where((t) => t.id == 'USDT-BEP20' || t.id == 'BNB')
            .toList();
    }
  }

  String get _chainLabel {
    switch (_chain) {
      case SwapChain.tron:
        return 'Tron';
      case SwapChain.ethereum:
        return 'Ethereum';
      case SwapChain.bsc:
        return 'BNB Smart Chain';
    }
  }

  double _balanceOf(TokenInfo token) {
    if (_chain == SwapChain.tron) {
      if (token.id == 'USDT-TRC20') return widget.usdtBalance;
      if (token.id == 'TRX') return widget.trxBalance;
      return 0;
    }
    return _evmBalances[token.id] ?? 0;
  }

  @override
  void initState() {
    super.initState();
    _loadCustomTokens();
    _resetPair();
  }

  Future<void> _loadCustomTokens() async {
    final custom = await CustomTokenService().getCustomTokens();
    if (mounted) setState(() => _customTokens = custom);
  }

  void _resetPair() {
    final tokens = _chainTokens;
    _from = tokens.isNotEmpty ? tokens.first : null;
    _to = tokens.length > 1 ? tokens[1] : null;
    _quote = null;
    _quoteError = null;
    _doneTxId = null;
  }

  void _onChainChanged(SwapChain chain) {
    setState(() {
      _chain = chain;
      _resetPair();
      _amountController.clear();
    });
    if (chain != SwapChain.tron) _loadEvmBalances();
  }

  Future<void> _loadEvmBalances() async {
    final service = _chain == SwapChain.ethereum
        ? EvmService.ethereum()
        : EvmService.bsc();
    final balances = <String, double>{};
    try {
      balances['native'] =
          await service.getNativeBalance(widget.evmAddress);
    } catch (_) {}
    for (final token in _chainTokens) {
      if (token.contractAddress == null) continue;
      try {
        balances[token.id] = await service.getTokenBalance(
          token.contractAddress!,
          widget.evmAddress,
          token.decimals,
        );
      } catch (_) {
        balances[token.id] = 0;
      }
    }
    if (!mounted) return;
    setState(() {
      _evmBalances.clear();
      // Native balance ko ETH/BNB id se map karo.
      final nativeId = _chain == SwapChain.ethereum ? 'ETH' : 'BNB';
      _evmBalances[nativeId] = balances['native'] ?? 0;
      _evmBalances.addAll(balances);
    });
  }

  void _swapDirection() {
    setState(() {
      final tmp = _from;
      _from = _to;
      _to = tmp;
      _quote = null;
      _quoteError = null;
    });
  }

  Future<void> _getQuote() async {
    final from = _from;
    final to = _to;
    final amount = double.tryParse(_amountController.text);
    if (from == null || to == null) return;
    if (amount == null || amount <= 0) {
      setState(() => _quoteError = 'Sahi amount likho (0 se zyada).');
      return;
    }
    if (amount > _balanceOf(from)) {
      setState(() => _quoteError =
          'Balance se zyada hai. Tumhare paas ${_balanceOf(from)} ${from.symbol} hai.');
      return;
    }
    setState(() {
      _loadingQuote = true;
      _quoteError = null;
      _quote = null;
    });
    try {
      final quote = await _swapService.getQuote(
        from: from,
        to: to,
        amountIn: amount,
      );
      if (mounted) setState(() => _quote = quote);
    } catch (e) {
      if (mounted) {
        setState(() => _quoteError = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loadingQuote = false);
    }
  }

  Future<void> _confirmAndSwap() async {
    final quote = _quote;
    if (quote == null || !quote.isExecutable || _swapping) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Swap confirm karo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${quote.amountIn} ${quote.from.symbol} → '
                '${quote.estimatedOut.toStringAsFixed(6)} ${quote.to.symbol}'),
            const SizedBox(height: 8),
            Text('Rate: 1 ${quote.from.symbol} = '
                '${quote.rate.toStringAsFixed(6)} ${quote.to.symbol} '
                '(${quote.rateSource})'),
            Text(
              'Service fee (${(SwapConfig.swapServiceFeePercent * 100).toStringAsFixed(2)}%): '
              '${quote.serviceFee.toStringAsFixed(6)} ${quote.from.symbol}'),
            Text(
              'Fee ${quote.from.symbol} me kategi — alag coin nahi chahiye.',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            Text('Minimum milega: '
                '${quote.minOut.toStringAsFixed(6)} ${quote.to.symbol}'),
            const Text(
              'Network fee (TRX gas) alag se lagegi.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirm & Swap'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _swapping = true;
      _swapError = null;
    });
    try {
      final result = await _swapService.executeSwap(
        quote: quote,
        fromAddress: widget.fromAddress,
      );
      if (!mounted) return;
      setState(() => _doneTxId = result.txId);
      // Swap ka txId screen par dikhta hai (neeche result card me) aur
      // History me USDT transfer ke roop me aayega (router ko gaya hua).
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Swap bhej diya! Status: Pending — ${result.feeCollected ? 'fee owner ko bhej di.' : 'fee wallet set nahi hai, fee nahi kati.'}',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _swapError = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _swapping = false);
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final from = _from;
    final to = _to;
    final quote = _quote;
    return Scaffold(
      appBar: AppBar(title: const Text('Swap / Exchange')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ---- Chain selector ----
            const Text('Network',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: SwapChain.values.map((chain) {
                final label = chain == SwapChain.tron
                    ? 'Tron'
                    : chain == SwapChain.ethereum
                        ? 'Ethereum'
                        : 'BNB Smart Chain';
                return ChoiceChip(
                  label: Text(label),
                  selected: chain == _chain,
                  onSelected: (_) => _onChainChanged(chain),
                );
              }).toList(),
            ),
            if (_chain != SwapChain.tron) ...[
              const SizedBox(height: 8),
              Text(
                '$_chainLabel par swap abhi sirf rate dikhata hai — '
                'execute next step me aayega (Uniswap / PancakeSwap).',
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ],
            const SizedBox(height: 20),

            // ---- From ----
            _coinDropdown(
              label: 'From (bhejo)',
              value: from,
              onChanged: (t) => setState(() {
                _from = t;
                _quote = null;
              }),
            ),
            if (from != null) ...[
              const SizedBox(height: 4),
              Text(
                '${from.network} • Balance: ${_balanceOf(from).toStringAsFixed(4)} ${from.symbol}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
            const SizedBox(height: 8),
            Center(
              child: IconButton(
                icon: const Icon(Icons.swap_vert, size: 28),
                tooltip: 'Ulta karo',
                onPressed: _swapDirection,
              ),
            ),

            // ---- To ----
            _coinDropdown(
              label: 'To (paao)',
              value: to,
              onChanged: (t) => setState(() {
                _to = t;
                _quote = null;
              }),
            ),
            if (to != null) ...[
              const SizedBox(height: 4),
              Text(
                '${to.network} • Balance: ${_balanceOf(to).toStringAsFixed(4)} ${to.symbol}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
            const SizedBox(height: 20),

            // ---- Amount ----
            TextField(
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Amount (${from?.symbol ?? ''})',
                border: const OutlineInputBorder(),
                suffix: TextButton(
                  onPressed: from == null
                      ? null
                      : () {
                          _amountController.text =
                              _balanceOf(from).toStringAsFixed(4);
                        },
                  child: const Text('MAX'),
                ),
              ),
              onChanged: (_) => setState(() => _quote = null),
            ),
            const SizedBox(height: 16),
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

            // ---- Quote card ----
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
                      '1 ${quote.from.symbol} = '
                      '${quote.rate.toStringAsFixed(6)} ${quote.to.symbol}',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text('Rate source: ${quote.rateSource}',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.grey)),
                    const Divider(),
                    Text('Tum bhejoge: ${quote.amountIn} ${quote.from.symbol}'),
                    Text(
                      'Service fee (${(SwapConfig.swapServiceFeePercent * 100).toStringAsFixed(2)}%): '
                      '${quote.serviceFee.toStringAsFixed(6)} ${quote.from.symbol}',
                    ),
                    Text(
                      'Fee ${quote.from.symbol} me kategi — alag coin '
                      '(BNB ya koi aur) nahi chahiye.',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.grey),
                    ),
                    Text(
                      'Tum paaoge (lagbhag): '
                      '${quote.estimatedOut.toStringAsFixed(6)} ${quote.to.symbol}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Minimum milega: ${quote.minOut.toStringAsFixed(6)} ${quote.to.symbol}',
                    ),
                    if (!quote.isExecutable) ...[
                      const SizedBox(height: 8),
                      Text(
                        quote.quoteOnlyReason ?? 'Sirf rate quote hai.',
                        style: const TextStyle(
                            fontSize: 13, color: Colors.orange),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: quote.isExecutable && !_swapping
                    ? _confirmAndSwap
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _swapping
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : Text(
                        quote.isExecutable
                            ? 'Confirm & Swap'
                            : 'Swap abhi is network par nahi hai',
                        style: const TextStyle(fontSize: 16),
                      ),
              ),
            ],
            if (_swapError != null) ...[
              const SizedBox(height: 12),
              Text(_swapError!, style: const TextStyle(color: Colors.red)),
            ],
            if (_doneTxId != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Swap bhej diya! (Pending)',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('Tx: $_doneTxId',
                        style: const TextStyle(fontSize: 12)),
                    Text(
                      'Tronscan: ${TronConfig.txExplorerUrl(_doneTxId!)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const Text(
                      'Status History screen par Pending se Confirmed hote hue dekho.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'Pehli baar swap kar rahe ho to pehle chhota test amount se karo. '
              'Rate swap karte waqt thoda badal sakta hai — minimum receive se kam mile to swap fail ho jayega.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _coinDropdown({
    required String label,
    required TokenInfo? value,
    required ValueChanged<TokenInfo?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButton<TokenInfo>(
            value: value,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            items: _chainTokens.map((token) {
              return DropdownMenuItem<TokenInfo>(
                value: token,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(token.symbol,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(token.network,
                        style: const TextStyle(
                            fontSize: 11, color: Colors.grey)),
                  ],
                ),
              );
            }).toList(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
