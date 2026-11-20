// Send screen — simple, no blocks. (Vinay's final call.)
//
// Bas itna hi:
//   1. Address dalte hi, agar network galat lag raha hai to field ke
//      neeche ek CHHOTI warning line dikhti hai:
//      "The network looks wrong, USDT could be lost"
//      Send button kabhi disable nahi hota — warning sirf warning hai.
//   2. Send dabane par ek CHHOTA popup dikhta hai — address, network
//      aur amount ek line me. Confirm dabate hi bhej diya jata hai.
//      Koi extra confirm step nahi hai.
//   3. Network mismatch ho (TRC20 select, 0x... address) to popup me
//      ye saaf likha hota hai: "The network looks wrong — USDT
//      will not go to this address. If the address is wrong, no
//      refund will be given." Do-button
//      choice NAHI hai — Confirm dabate hi paise AUTOMATIC in-app
//      Special (recovery) Wallet me jate hain, galat address par
//      kabhi nahi. Sahi address + sahi network ho to recovery kabhi
//      nahi aata — paise seedha usi address par jate hain.
//      Recovery wallet bana hi nahi hai to redirect ki jagah nahi hai,
//      isliye popup me Send button hi nahi aata — pehle Recovery
//      Wallet banao.
//
// Address check abhi bhi hota hai (format + checksum + network detect:
// T... = Tron/TRC20, 0x... = Ethereum/ERC20 ya BSC/BEP20), lekin uska
// kaam sirf warning dikhana hai, rokna nahi.
//
// IMPORTANT (honest limit): ye checks sirf ye bata sakte hain ki address
// SAHI FORMAT ka hai aur SAHI NETWORK ka lagta hai. Agar tum kisi AUR ki
// sahi address par bhej do (format sahi, network sahi, lekin galat
// insaan), to app use nahi pehchan sakta — wo sirf TUM check kar sakte
// ho. Isiliye pehli baar chhota test amount bhejo.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/address_validator.dart';
import '../services/recovery_wallet_service.dart';
import '../services/trongrid_service.dart';
import '../utils/format.dart';

/// Returned to Home when a send succeeds.
class SendResult {
  final String txId;

  /// The address the money actually went to — the entered address for a
  /// normal send, the recovery wallet for a recovery redirect.
  final String toAddress;
  final double amount;

  /// True only when this send was redirected to the recovery wallet.
  final bool isRecoveryRedirect;

  /// The address the user originally typed (only for recovery redirects).
  final String? originalAddress;

  /// The network the original address looked like (only for recovery).
  final String? intendedNetwork;

  /// Short reason for the redirect (only for recovery redirects).
  final String? recoveryReason;

  const SendResult({
    required this.txId,
    required this.toAddress,
    required this.amount,
    this.isRecoveryRedirect = false,
    this.originalAddress,
    this.intendedNetwork,
    this.recoveryReason,
  });
}

/// What the user picked in the small send popup.
enum _SendChoice { confirm, cancel }

class SendScreen extends StatefulWidget {
  final String fromAddress;
  final double usdtBalance;
  final double trxBalance;

  /// True only when this send is FROM the recovery wallet itself
  /// ("Wapas bhejo" flow, opened after the owner unlocks). Then the
  /// transaction is signed with the recovery wallet's private key,
  /// not the main wallet's. Normal sends leave this false.
  final bool sendFromRecoveryWallet;

  const SendScreen({
    super.key,
    required this.fromAddress,
    required this.usdtBalance,
    required this.trxBalance,
    this.sendFromRecoveryWallet = false,
  });

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  final _api = TronGridService();
  final _recoveryService = RecoveryWalletService();
  final _toController = TextEditingController();
  final _amountController = TextEditingController();

  /// Selected network. Bhejna aaj sirf TRC20 se hota hai.
  AddressNetwork _selectedNetwork = AddressNetwork.tron;

  AddressValidation? _validation;
  String? _amountError;
  String? _sendError;
  bool _sending = false;

  /// In-app recovery wallet address, loaded from secure storage.
  /// Null = recovery wallet not created yet in this app.
  String? _recoveryAddress;

  @override
  void initState() {
    super.initState();
    _loadRecoveryAddress();
  }

  Future<void> _loadRecoveryAddress() async {
    final address = await _recoveryService.getRecoveryAddress();
    if (mounted) setState(() => _recoveryAddress = address);
  }

  @override
  void dispose() {
    _toController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  static const _networkLabels = {
    AddressNetwork.tron: 'TRC20 (Tron)',
    AddressNetwork.ethereum: 'ERC20 (Ethereum)',
    AddressNetwork.bsc: 'BEP20 (BSC)',
  };

  void _onNetworkSelected(AddressNetwork network) {
    setState(() => _selectedNetwork = network);
    _onAddressChanged(_toController.text);
  }

  /// Runs on every keystroke. Only ever produces a small warning line.
  void _onAddressChanged(String value) {
    if (value.trim().isEmpty) {
      setState(() => _validation = null);
      return;
    }
    setState(() {
      _validation = AddressValidator.validateForSelectedNetwork(
        value,
        _selectedNetwork,
      );
    });
  }

  void _onAmountChanged(String value) {
    final amount = double.tryParse(value);
    setState(() {
      if (value.isEmpty) {
        _amountError = null;
      } else if (amount == null || amount <= 0) {
        _amountError = 'Enter a valid amount (more than 0).';
      } else if (amount > widget.usdtBalance) {
        _amountError =
            'More than your balance. You have ${formatUsdt(widget.usdtBalance)} USDT.';
      } else {
        _amountError = null;
      }
    });
  }

  double? get _amount => double.tryParse(_amountController.text);

  /// The one small warning line under the address field, if any.
  /// Mismatch warning first, then format/checksum problems.
  String? get _warningLine {
    final validation = _validation;
    if (validation == null) return null;
    if (validation.warning != null) return validation.warning;
    if (!validation.isValid) return validation.error;
    return null;
  }

  Future<void> _send() async {
    if (_sending) return;
    final toAddress = _toController.text.trim();
    final amount = _amount;
    if (toAddress.isEmpty || amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter an address and a valid amount.')),
      );
      return;
    }
    if (amount > widget.usdtBalance) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Amount is more than your balance.')),
      );
      return;
    }

    // Network mismatch? Only the small warning + small popup — never a
    // block. Correct address + correct network = normal send, no change.
    final mismatch =
        AddressValidator.isNetworkMismatch(toAddress, _selectedNetwork);
    final detectedNetwork =
        AddressValidator.detectNetworkFromAddress(toAddress);

    // ERC20/BEP20 sends are not supported yet — except when the address
    // is actually a Tron address (user just selected the wrong network
    // in the UI). That case is a mismatch, not an unsupported send:
    // it goes through the popup below and is sent via TRC20.
    if (_selectedNetwork != AddressNetwork.tron &&
        detectedNetwork != AddressNetwork.tron) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sending via ERC20/BEP20 is not available in this starter yet — '
            'you can only send via TRC20.',
          ),
        ),
      );
      return;
    }

    // Small confirm popup: address, network, amount — one line.
    // FINAL FLOW (Vinay): mismatch par do-button choice NAHI hai.
    // Warning ke baad bhi Send dabao to paise galat address par NAHI
    // jate — AUTOMATIC in-app Special (recovery) Wallet me jate hain.
    // Popup me ye saaf likha hota hai, aur ek hi Confirm button hota
    // hai. Sahi address + sahi network ho to normal send hota hai.
    // Recovery wallet abhi bana hi nahi hai to redirect karne ki jagah
    // hi nahi hai — tab popup sirf ye batata hai aur send nahi hota
    // (paise doobne se bachane ke liye); user pehle Recovery Wallet
    // banaye, phir dobara bheje.
    // In-app recovery wallet (secure storage). Null = not created yet.
    final recoveryConfigured = _recoveryAddress != null &&
        _recoveryAddress!.isNotEmpty;
    // Recovery wallet SE wapas bhejte waqt (owner flow) redirect ka
    // matlab nahi hai — destination to khud recovery wallet hi hai.
    // Wahan sirf warning dikhti hai, owner khud faisla karta hai.
    final effectiveMismatch =
        mismatch && !widget.sendFromRecoveryWallet;
    final intendedNetworkLabel = detectedNetwork == null
        ? null
        : AddressValidator.networkLabel(detectedNetwork);
    final recoveryReason = effectiveMismatch
        ? 'Network mismatch: ${_networkLabels[_selectedNetwork]} was selected, '
            'but the address looks like ${intendedNetworkLabel ?? 'another network'}'
        : null;

    final choice = await showDialog<_SendChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$toAddress • ${_networkLabels[_selectedNetwork]} • '
              '${formatUsdt(amount)} USDT',
            ),
            if (effectiveMismatch) ...[
              const SizedBox(height: 8),
              const Text(
                'The network looks wrong — USDT will not go to this address. '
                'If the address is wrong, no refund will be given.',
                style: TextStyle(fontSize: 13, color: Colors.red),
              ),
              if (!recoveryConfigured) ...[
                const SizedBox(height: 4),
                const Text(
                  'This send cannot go through right now — please check the address and network again.',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ],
            ] else if (_warningLine != null) ...[
              const SizedBox(height: 8),
              Text(
                _warningLine!,
                style: const TextStyle(fontSize: 13, color: Colors.orange),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_SendChoice.cancel),
            child: const Text('Cancel'),
          ),
          if (effectiveMismatch && !recoveryConfigured)
            // No safe place to redirect to — no Send button at all.
            const SizedBox.shrink()
          else
            ElevatedButton(
              onPressed: () =>
                  Navigator.of(context).pop(_SendChoice.confirm),
              child: const Text('Confirm & Send'),
            ),
        ],
      ),
    );
    if (choice == null || choice == _SendChoice.cancel || !mounted) return;

    // Destination is decided HERE, before signing — that is the only
    // moment a redirect is possible. Once signed + broadcast, the
    // blockchain sends the money to whatever address is in the
    // transaction and never redirects it.
    // Automatic redirect: mismatch ho to destination hamesha in-app
    // recovery wallet hota hai — galat address par kabhi nahi jata.
    final isRecovery = effectiveMismatch;
    final actualToAddress =
        isRecovery ? _recoveryAddress! : toAddress;

    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      final String? signingKeyHex = widget.sendFromRecoveryWallet
          ? await _recoveryService.getPrivateKeyHex()
          : null;
      final txId = await _api.sendUsdt(
        fromAddress: widget.fromAddress,
        toAddress: actualToAddress,
        amountUsdt: amount,
        privateKeyHex: signingKeyHex,
      );
      if (!mounted) return;
      Navigator.of(context).pop(
        SendResult(
          txId: txId,
          toAddress: actualToAddress,
          amount: amount,
          isRecoveryRedirect: isRecovery,
          originalAddress: isRecovery ? toAddress : null,
          intendedNetwork: isRecovery ? intendedNetworkLabel : null,
          recoveryReason: isRecovery ? recoveryReason : null,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _sendError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.sendFromRecoveryWallet
              ? 'Send back (Recovery Wallet)'
              : 'Send USDT',
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Balance: ${formatUsdt(widget.usdtBalance)} USDT  •  '
              '${widget.trxBalance.toStringAsFixed(2)} TRX (for fees)',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),

            // ---- Network ----
            const Text(
              'Network',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: AddressNetwork.values.map((network) {
                return ChoiceChip(
                  label: Text(_networkLabels[network]!),
                  selected: network == _selectedNetwork,
                  onSelected: (_) => _onNetworkSelected(network),
                );
              }).toList(),
            ),
            if (_selectedNetwork != AddressNetwork.tron) ...[
              const SizedBox(height: 8),
              const Text(
                'Sending via ERC20/BEP20 is not available in this starter yet — '
                'you can only send via TRC20.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ],
            const SizedBox(height: 20),

            // ---- Receiver address + one small warning line ----
            TextField(
              controller: _toController,
              decoration: InputDecoration(
                labelText: "Receiver's address",
                hintText: _selectedNetwork == AddressNetwork.tron
                    ? 'Paste an address starting with T...'
                    : 'Paste an address starting with 0x...',
                border: const OutlineInputBorder(),
              ),
              onChanged: _onAddressChanged,
            ),
            if (_warningLine != null) ...[
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 16, color: Colors.orange),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _warningLine!,
                      style: const TextStyle(
                          fontSize: 13, color: Colors.orange),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),

            // ---- Amount ----
            TextField(
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: InputDecoration(
                labelText: 'Amount (USDT)',
                border: const OutlineInputBorder(),
                suffix: TextButton(
                  onPressed: () {
                    _amountController.text =
                        widget.usdtBalance.toStringAsFixed(2);
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
              'If you are sending to a new address for the first time, first send a small '
              'test amount (like 1 USDT).',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 24),

            if (_sendError != null) ...[
              Text(_sendError!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
            ],

            // Send button is never disabled by a warning — only while
            // a send is already in progress.
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
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Send', style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }
}
