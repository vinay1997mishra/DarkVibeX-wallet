// Add Custom Token screen — user khud coin add kare.
//
// Kaise kaam karta hai:
//   1. User TRC20 contract address dalta hai (T... se shuru).
//   2. App TronGrid se khud fetch karta hai: naam, symbol, decimals.
//   3. Balance bhi fetch karke dikhata hai (is wallet ke address par).
//   4. "Add karo" dabate hi token save ho jata hai — Home par dikhega.
//
// SAFETY: contract galat ho ya TRC20 token hi na ho to fetch fail
// hoga aur token add nahi hoga. Scam token ka naam/symbol kuch bhi
// ho sakta hai — hamesha contract address ko Tronscan par verify karo.
// Ye screen abhi Tron (TRC20) ke liye hai — EVM custom token
// (ERC20/BEP20) jald aa raha hai.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/token_list.dart';

class AddCustomTokenScreen extends StatefulWidget {
  final String ownerAddress; // Tron address (balance dikhane ke liye)

  const AddCustomTokenScreen({super.key, required this.ownerAddress});

  @override
  State<AddCustomTokenScreen> createState() => _AddCustomTokenScreenState();
}

class _AddCustomTokenScreenState extends State<AddCustomTokenScreen> {
  final _service = CustomTokenService();
  final _contractController = TextEditingController();

  TokenInfo? _found;
  double? _balance;
  String? _error;
  bool _fetching = false;
  bool _adding = false;

  Future<void> _fetch() async {
    final contract = _contractController.text.trim();
    if (contract.isEmpty) return;
    setState(() {
      _fetching = true;
      _error = null;
      _found = null;
      _balance = null;
    });
    try {
      final info = await _service.fetchTokenInfo(contract);
      final balance = await _service.getCustomTokenBalance(
        info,
        widget.ownerAddress,
      );
      if (!mounted) return;
      setState(() {
        _found = info;
        _balance = balance;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  Future<void> _add() async {
    final found = _found;
    if (found == null || _adding) return;
    setState(() => _adding = true);
    final added = await _service.addCustomToken(found);
    if (!mounted) return;
    if (added) {
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${found.symbol} add ho gaya!')),
      );
    } else {
      setState(() {
        _adding = false;
        _error = 'Ye token pehle se add hai.';
      });
    }
  }

  @override
  void dispose() {
    _contractController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final found = _found;
    return Scaffold(
      appBar: AppBar(title: const Text('Add Custom Token')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'TRC20 token ka contract address dalo. App khud uska naam, '
              'symbol aur balance fetch karke dikhayega.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _contractController,
              decoration: const InputDecoration(
                labelText: 'Contract address',
                hintText: 'T... se shuru hone wala address',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {
                _found = null;
                _error = null;
              }),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetching ? null : _fetch,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _fetching
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('Token dhoondho'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            if (found != null) ...[
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
                    Text(found.symbol,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                    Text(found.name),
                    Text('Decimals: ${found.decimals}'),
                    Text(
                      'Tumhara balance: ${_balance?.toStringAsFixed(4) ?? '...'} ${found.symbol}',
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Contract address ko Tronscan par verify kar lo — '
                      'scam token ka naam/symbol asli jaisa ho sakta hai.',
                      style: TextStyle(fontSize: 12, color: Colors.orange),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _adding ? null : _add,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Add karo',
                    style: TextStyle(fontSize: 16)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
