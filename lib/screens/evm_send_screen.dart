// EVM send screen — Ethereum / BNB Smart Chain par bhejo.
//
// Ek hi screen dono chains ke liye: native coin (ETH/BNB) ya token
// (USDT ERC20 / SHIB / USDT BEP20). Gas fee hamesha native coin me
// lagti hai (ETH chain par ETH, BSC par BNB) — wo screen par dikhti hai.
// Confirm se pehle chhota popup: address, network, amount, gas fee.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../services/evm_service.dart';
import '../services/token_list.dart';
import '../services/wallet_service.dart';

class EvmSendResult {
  final String txHash;
  const EvmSendResult(this.txHash);
}

class EvmSendScreen extends StatefulWidget {
  final EvmChainConfig chain;
  final String fromAddress; // 0x... (ETH aur BNB dono ke liye wahi)
  final double nativeBalance;
  final Map<String, double> tokenBalances; // token id -> balance
  final List<TokenInfo> tokens; // native + tokens, is chain ke

  const EvmSendScreen({
    super.key,
    required this.chain,
    required this.fromAddress,
    required this.nativeBalance,
    required this.tokenBalances,
    required this.tokens,
  });

  @override
  State<EvmSendScreen> createState() => _EvmSendScreenState();
}

class _EvmSendScreenState extends State<EvmSendScreen> {
  late final EvmService _service;
  final _walletService = WalletService();
  final _toController = TextEditingController();
  final _amountController = TextEditingController();

  TokenInfo? _selectedToken;
  String? _amountError;
  String? _sendError;
  String? _gasNote;
  bool _sending = false;

  TokenInfo get _nativeToken => widget.tokens.firstWhere(
        (t) => t.isNative,
        orElse: () => widget.tokens.first,
      );

  @override
  void initState() {
    super.initState();
    _service = EvmService(chain: widget.chain);
    _selectedToken = _nativeToken;
    _loadGasNote();
  }

  Future<void> _loadGasNote() async {
    try {
      final gasPrice = await _service.getGasPriceWei();
      final gwei = gasPrice.toDouble() / 1e9;
      if (mounted) {
        setState(() => _gasNote =
            'Gas price abhi: ${gwei.toStringAsFixed(1)} Gwei. '
            'Native transfer ~21000 gas, token transfer ~60000-100000 gas. '
            'Fee ${widget.chain.gasSymbol} me lagegi.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _gasNote = 'Gas price nahi mil paya — internet check karo.');
      }
    }
  }

  double _balanceOf(TokenInfo token) {
    if (token.isNative) return widget.nativeBalance;
    return widget.tokenBalances[token.id] ?? 0;
  }

  void _onAmountChanged(String value) {
    final token = _selectedToken;
    final amount = double.tryParse(value);
    setState(() {
      if (token == null) {
        _amountError = null;
      } else if (value.isEmpty) {
        _amountError = null;
      } else if (amount == null || amount <= 0) {
        _amountError = 'Sahi amount likho (0 se zyada).';
      } else if (amount > _balanceOf(token)) {
        _amountError =
            'Balance se zyada hai. Tumhare paas ${_balanceOf(token)} ${token.symbol} hai.';
      } else {
        _amountError = null;
      }
    });
  }

  Future<void> _send() async {
    if (_sending) return;
    final token = _selectedToken;
    final toAddress = _toController.text.trim();
    final amount = double.tryParse(_amountController.text);
    if (token == null || toAddress.isEmpty || amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Address aur sahi amount likho.')),
      );
      return;
    }
    if (!toAddress.startsWith('0x') || toAddress.length != 42) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ye sahi EVM address nahi lagta (0x + 40 chars).'),
        ),
      );
      return;
    }
    if (amount > _balanceOf(token)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Amount balance se zyada hai.')),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm karo'),
        content: Text(
          '$toAddress • ${widget.chain.displayName} • '
          '$amount ${token.symbol}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirm & Send'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      final privateKeyHex =
          await _walletService.getEthereumPrivateKeyHex();
      late final String txHash;
      if (token.isNative) {
        txHash = await _service.sendNative(
          fromAddress: widget.fromAddress,
          toAddress: toAddress,
          amount: amount,
          privateKeyHex: privateKeyHex,
        );
      } else {
        txHash = await _service.sendToken(
          contract: token.contractAddress!,
          fromAddress: widget.fromAddress,
          toAddress: toAddress,
          amount: amount,
          decimals: token.decimals,
          privateKeyHex: privateKeyHex,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(EvmSendResult(txHash));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _sendError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  void dispose() {
    _toController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final token = _selectedToken;
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.chain.displayName} par bhejo'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Balance: ${widget.nativeBalance.toStringAsFixed(4)} ${widget.chain.gasSymbol} (gas ke liye)',
              style: const TextStyle(color: Colors.grey),
            ),
            if (_gasNote != null) ...[
              const SizedBox(height: 4),
              Text(_gasNote!,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
            const SizedBox(height: 20),
            const Text('Coin',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButton<TokenInfo>(
                value: token,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                items: widget.tokens.map((t) {
                  return DropdownMenuItem<TokenInfo>(
                    value: t,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(t.symbol,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold)),
                        Text(t.network,
                            style: const TextStyle(
                                fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (t) => setState(() {
                  _selectedToken = t;
                  _amountController.clear();
                  _amountError = null;
                }),
              ),
            ),
            if (token != null) ...[
              const SizedBox(height: 4),
              Text(
                'Balance: ${_balanceOf(token)} ${token.symbol}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
            const SizedBox(height: 20),
            TextField(
              controller: _toController,
              decoration: const InputDecoration(
                labelText: 'Receiver ka address',
                hintText: '0x... se shuru hone wala address',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: InputDecoration(
                labelText: 'Amount (${token?.symbol ?? ''})',
                border: const OutlineInputBorder(),
                suffix: TextButton(
                  onPressed: token == null
                      ? null
                      : () {
                          _amountController.text =
                              _balanceOf(token).toStringAsFixed(4);
                          _onAmountChanged(_amountController.text);
                        },
                  child: const Text('MAX'),
                ),
                errorText: _amountError,
              ),
              onChanged: _onAmountChanged,
            ),
            const SizedBox(height: 8),
            const Text(
              'Pehli baar kisi naye address par bhej rahe ho to pehle chhota test amount bhejo.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            if (_sendError != null) ...[
              Text(_sendError!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
            ],
            ElevatedButton(
              onPressed: _sending ? null : _send,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _sending
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('Send', style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }
}
