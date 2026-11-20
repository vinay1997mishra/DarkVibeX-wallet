// Recovery Wallet screen — OWNER ONLY.
//
// Ye screen kholte hi pehle owner lock aata hai:
//   - Recovery wallet abhi bana nahi hai  -> setup: 12 words dikhao,
//     likhne ki confirmation, phir owner PIN set karo.
//   - PIN set hai -> PIN dalo (ya fingerprint/Face ID, agar on hai).
//     Bina PIN/biometric ke balance, address, seed ya history KUCH
//     NAHI dikhta — normal user yahan se aage ja hi nahi sakta.
//   - PIN bhool gaye -> 12 words (seed) se verify karke naya PIN set
//     karo. Seed bhi nahi hai to wallet kabhi nahi khul payega.
//
// Unlocked hone par owner dekh sakta hai:
//   - Recovery wallet ka address + USDT/TRX balance
//   - Uski history (kaun se galat-network sends yahan aaye)
//   - Seed words (dobara dekhne ke liye, warning ke saath)
//   - "Wapas bhejo" — paise user ke SAHI address par wapas bhejna.
//     Ye send recovery wallet ki key se sign hota hai.
//   - PIN badlo, biometric on/off, wallet delete karo.
//
// Main wallet aur recovery wallet ki keys secure storage me ALAG-ALAG
// keys se save hoti hain — dono kabhi mix nahi hote.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/transaction_model.dart';
import '../services/owner_lock_service.dart';
import '../services/recovery_wallet_service.dart';
import '../services/trongrid_service.dart';
import '../services/tx_status_service.dart';
import '../utils/format.dart';
import '../widgets/status_chip.dart';
import 'send_screen.dart';

enum _RecoveryView { setupSeed, setupPin, locked, forgotPin, unlocked }

class RecoveryWalletScreen extends StatefulWidget {
  const RecoveryWalletScreen({super.key});

  @override
  State<RecoveryWalletScreen> createState() => _RecoveryWalletScreenState();
}

class _RecoveryWalletScreenState extends State<RecoveryWalletScreen> {
  final _recovery = RecoveryWalletService();
  final _lock = OwnerLockService();
  final _api = TronGridService();
  final _txStatus = TxStatusService();

  _RecoveryView _view = _RecoveryView.locked;
  bool _loading = true;

  // Setup state
  RecoveryWalletPreview? _preview;
  bool _seedWritten = false;
  final _pinController = TextEditingController();
  final _pinConfirmController = TextEditingController();
  final _importController = TextEditingController();
  bool _showImport = false;

  // Lock state
  final _unlockPinController = TextEditingController();
  String? _lockError;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;

  // Forgot-PIN state
  final _forgotSeedController = TextEditingController();
  final _forgotPinController = TextEditingController();
  final _forgotPinConfirmController = TextEditingController();

  // Unlocked state
  String? _address;
  double _usdtBalance = 0;
  double _trxBalance = 0;
  List<Trc20Transfer> _history = [];
  String? _mnemonic;
  bool _showSeed = false;
  bool _changingPin = false;
  final _oldPinController = TextEditingController();
  final _newPinController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _pinController.dispose();
    _pinConfirmController.dispose();
    _importController.dispose();
    _unlockPinController.dispose();
    _forgotSeedController.dispose();
    _forgotPinController.dispose();
    _forgotPinConfirmController.dispose();
    _oldPinController.dispose();
    _newPinController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final hasWallet = await _recovery.hasRecoveryWallet();
    final hasPin = await _lock.hasPin();
    if (!mounted) return;
    if (!hasWallet) {
      setState(() {
        _view = _RecoveryView.setupSeed;
        _loading = false;
      });
      return;
    }
    final biometricEnabled = await _lock.isBiometricEnabled();
    final biometricAvailable = await _lock.canUseBiometric();
    setState(() {
      _view = _RecoveryView.locked;
      _biometricEnabled = biometricEnabled;
      _biometricAvailable = biometricAvailable;
      _loading = false;
    });
    // Biometric shortcut on hai to turant try karo — fail ho to PIN
    // se khulega, koi error nahi dikhate.
    if (biometricEnabled && biometricAvailable && hasPin) {
      final ok = await _lock.authenticateWithBiometric();
      if (ok && mounted) await _unlock();
    }
  }

  // ---------------------------------------------------------------------------
  // Setup: create a new in-app recovery wallet + owner PIN
  // ---------------------------------------------------------------------------

  void _startSetup() {
    setState(() {
      _preview = _recovery.generatePreview();
      _seedWritten = false;
      _showImport = false;
    });
  }

  Future<void> _finishSetup() async {
    final pin = _pinController.text.trim();
    final confirm = _pinConfirmController.text.trim();
    if (!OwnerLockService.isValidPin(pin)) {
      _snack('PIN must be 4-6 digits.');
      return;
    }
    if (pin != confirm) {
      _snack('Both PINs must match.');
      return;
    }
    try {
      final mnemonic = _showImport
          ? _importController.text.trim()
          : _preview!.mnemonic;
      final address = await _recovery.saveWallet(mnemonic);
      await _lock.setPin(pin);
      if (!mounted) return;
      setState(() => _address = address);
      await _unlock();
      _snack('Recovery Wallet created — keep your seed in a safe place!');
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  // ---------------------------------------------------------------------------
  // Unlock: PIN or biometric
  // ---------------------------------------------------------------------------

  Future<void> _unlock() async {
    final address = await _recovery.getRecoveryAddress();
    if (address == null || !mounted) return;
    setState(() {
      _address = address;
      _view = _RecoveryView.unlocked;
      _lockError = null;
    });
    await _refresh();
  }

  Future<void> _tryPin() async {
    final pin = _unlockPinController.text.trim();
    if (!await _lock.verifyPin(pin)) {
      setState(() => _lockError = 'Wrong PIN. Try again.');
      return;
    }
    _unlockPinController.clear();
    await _unlock();
  }

  Future<void> _tryBiometric() async {
    final ok = await _lock.authenticateWithBiometric();
    if (ok) {
      await _unlock();
    } else {
      setState(
        () => _lockError = 'Biometric failed — open with PIN.',
      );
    }
  }

  Future<void> _resetPinWithSeed() async {
    final seed = _forgotSeedController.text.trim();
    final pin = _forgotPinController.text.trim();
    final confirm = _forgotPinConfirmController.text.trim();
    if (pin != confirm) {
      _snack('Both PINs must match.');
      return;
    }
    final ok = await _lock.resetPinWithSeed(seed, pin);
    if (!ok) {
      _snack('The seed is wrong or the PIN is in the wrong format.');
      return;
    }
    if (!mounted) return;
    setState(() => _view = _RecoveryView.locked);
    _snack('New PIN set — now open with your PIN.');
  }

  // ---------------------------------------------------------------------------
  // Unlocked: balances, history, send back, PIN/biometric settings
  // ---------------------------------------------------------------------------

  Future<void> _refresh() async {
    final address = _address;
    if (address == null) return;
    try {
      final usdt = await _api.getUsdtBalance(address);
      final trx = await _api.getTrxBalance(address);
      final history = await _api.getTrc20History(address, limit: 20);
      if (!mounted) return;
      setState(() {
        _usdtBalance = usdt;
        _trxBalance = trx;
        _history = history;
      });
    } catch (e) {
      if (mounted) _snack(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _openSendBack() async {
    final address = _address;
    if (address == null) return;
    final result = await Navigator.of(context).push<SendResult>(
      MaterialPageRoute(
        builder: (_) => SendScreen(
          fromAddress: address,
          usdtBalance: _usdtBalance,
          trxBalance: _trxBalance,
          sendFromRecoveryWallet: true,
        ),
      ),
    );
    if (result == null || !mounted) return;
    final pending = Trc20Transfer.pending(
      txId: result.txId,
      from: address,
      to: result.toAddress,
      value: BigInt.from((result.amount * 1000000).round()),
    );
    await _txStatus.savePendingTx(pending);
    _txStatus.pollTxStatus(result.txId, (status) {
      if (status != TxStatus.pending && mounted) _refresh();
    });
    _snack('Sent back! Status: Pending.');
    await _refresh();
  }

  Future<void> _changePin() async {
    final ok = await _lock.changePin(
      _oldPinController.text.trim(),
      _newPinController.text.trim(),
    );
    if (!ok) {
      _snack('The old PIN is wrong or the new PIN is not 4-6 digits.');
      return;
    }
    if (!mounted) return;
    setState(() => _changingPin = false);
    _oldPinController.clear();
    _newPinController.clear();
    _snack('PIN changed.');
  }

  Future<void> _toggleBiometric(bool value) async {
    final ok = await _lock.setBiometricEnabled(value);
    if (!ok) {
      _snack('Biometric could not be turned on — try again.');
      return;
    }
    if (mounted) setState(() => _biometricEnabled = value);
  }

  Future<void> _deleteWallet() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Recovery Wallet?'),
        content: const Text(
          'This wallet will be deleted from this phone and the owner PIN will also '
          'be removed. Your funds will stay on the blockchain — you can recover them with the 12 words. '
          'Without the 12 words, your funds will be lost '
          'forever.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await _recovery.deleteWallet();
    await _lock.clearLock();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recovery Wallet — Owner only')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: switch (_view) {
                _RecoveryView.setupSeed => _setupSeedView(),
                _RecoveryView.setupPin => _setupPinView(),
                _RecoveryView.locked => _lockedView(),
                _RecoveryView.forgotPin => _forgotPinView(),
                _RecoveryView.unlocked => _unlockedView(),
              },
            ),
    );
  }

  Widget _setupSeedView() {
    final preview = _preview;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Create Recovery Wallet',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'This is a separate wallet inside the app — different from the main wallet. '
          'Funds from sends on the wrong network will arrive here. Only you '
          '(the owner) can open it.',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 20),
        if (!_showImport) ...[
          if (preview == null)
            ElevatedButton(
              onPressed: _startSetup,
              child: const Text('Create a new Recovery Wallet'),
            )
          else ...[
            const Text(
              '12 words — write them down on paper, do not take a screenshot:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: preview.mnemonic.split(' ').asMap().entries.map((
                entry,
              ) {
                return Chip(
                  label: Text('${entry.key + 1}. ${entry.value}'),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Text(
              'Address: ${preview.address}',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Checkbox(
                  value: _seedWritten,
                  onChanged: (value) =>
                      setState(() => _seedWritten = value ?? false),
                ),
                const Expanded(
                  child: Text('I have written down the 12 words in a safe place.'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _seedWritten
                  ? () => setState(() => _view = _RecoveryView.setupPin)
                  : null,
              child: const Text('Continue — set PIN'),
            ),
          ],
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => setState(() => _showImport = true),
            child: const Text('Already have a recovery wallet? Restore it with your seed'),
          ),
        ] else ...[
          const Text(
            "Enter your recovery wallet's 12 words here:",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _importController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: '12 words',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => setState(() => _view = _RecoveryView.setupPin),
            child: const Text('Continue — set PIN'),
          ),
          TextButton(
            onPressed: () => setState(() => _showImport = false),
            child: const Text('Back — create a new wallet'),
          ),
        ],
      ],
    );
  }

  Widget _setupPinView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Set owner PIN',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Only you should know this PIN. Without the PIN, no one can open the recovery '
          'wallet — not even a normal user.',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _pinController,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(
            labelText: 'PIN (4-6 digits)',
            border: OutlineInputBorder(),
            counterText: '',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pinConfirmController,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(
            labelText: 'Enter PIN again',
            border: OutlineInputBorder(),
            counterText: '',
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _finishSetup,
          child: const Text('Save Recovery Wallet'),
        ),
        TextButton(
          onPressed: () => setState(() => _view = _RecoveryView.setupSeed),
          child: const Text('Back'),
        ),
      ],
    );
  }

  Widget _lockedView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.lock, size: 48, color: Colors.teal),
        const SizedBox(height: 12),
        const Text(
          'Owner lock',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Only the owner can open the Recovery Wallet. Without PIN or '
          'biometric, nothing will be shown here — no balance, address, '
          'seed, history, nothing.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _unlockPinController,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(
            labelText: 'Owner PIN',
            border: OutlineInputBorder(),
            counterText: '',
          ),
          onSubmitted: (_) => _tryPin(),
        ),
        if (_lockError != null) ...[
          const SizedBox(height: 8),
          Text(_lockError!, style: const TextStyle(color: Colors.red)),
        ],
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _tryPin,
          child: const Text('Open with PIN'),
        ),
        if (_biometricEnabled && _biometricAvailable) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _tryBiometric,
            icon: const Icon(Icons.fingerprint),
            label: const Text('Open with Fingerprint / Face ID'),
          ),
        ],
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => setState(() => _view = _RecoveryView.forgotPin),
          child: const Text('Forgot your PIN? Set a new PIN with your seed'),
        ),
      ],
    );
  }

  Widget _forgotPinView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Forgot your PIN?',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          "Verify with your recovery wallet's 12 words to set a new PIN. "
          'If you do not have the seed either, the wallet can never be opened.',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _forgotSeedController,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: '12 words (seed)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _forgotPinController,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(
            labelText: 'New PIN (4-6 digits)',
            border: OutlineInputBorder(),
            counterText: '',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _forgotPinConfirmController,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(
            labelText: 'Enter new PIN again',
            border: OutlineInputBorder(),
            counterText: '',
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _resetPinWithSeed,
          child: const Text('Set new PIN'),
        ),
        TextButton(
          onPressed: () => setState(() => _view = _RecoveryView.locked),
          child: const Text('Back — open with PIN'),
        ),
      ],
    );
  }

  Widget _unlockedView() {
    final address = _address ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.verified_user, color: Colors.green),
            const SizedBox(width: 8),
            const Text(
              'Owner unlocked',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: _refresh,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.teal.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Recovery Wallet Balance',
                  style: TextStyle(fontSize: 14)),
              Text(
                '${formatUsdt(_usdtBalance)} USDT',
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'TRX: ${_trxBalance.toStringAsFixed(2)} (for fees)',
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      shortAddress(address),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: address));
                      _snack('Address copied');
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _usdtBalance > 0 ? _openSendBack : null,
          icon: const Icon(Icons.arrow_upward),
          label: const Text("Send back (to the user's correct address)"),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.teal,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () async {
            final mnemonic = await _recovery.getMnemonic();
            if (mounted) {
              setState(() {
                _mnemonic = mnemonic;
                _showSeed = !_showSeed;
              });
            }
          },
          child: Text(_showSeed ? 'Hide seed' : 'Show seed words'),
        ),
        if (_showSeed && _mnemonic != null) ...[
          const SizedBox(height: 12),
          const Text(
            'This seed is only for you — do not give it to anyone, do not take a screenshot:',
            style: TextStyle(color: Colors.red, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _mnemonic!.split(' ').asMap().entries.map((entry) {
              return Chip(label: Text('${entry.key + 1}. ${entry.value}'));
            }).toList(),
          ),
        ],
        const SizedBox(height: 24),
        const Text(
          'History of this wallet',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (_history.isEmpty)
          const Text(
            'No transactions yet.',
            style: TextStyle(color: Colors.grey),
          )
        else
          ..._history.take(10).map((tx) {
            final incoming = tx.to.toLowerCase() == address.toLowerCase();
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: (incoming ? Colors.green : Colors.red)
                      .withOpacity(0.15),
                  child: Icon(
                    incoming ? Icons.arrow_downward : Icons.arrow_upward,
                    color: incoming ? Colors.green : Colors.red,
                  ),
                ),
                title: Text(
                  '${incoming ? '+' : '-'}${formatUsdt(tx.amount)} USDT',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  '${incoming ? 'From ' : 'To '}'
                  '${shortAddress(incoming ? tx.from : tx.to)}'
                  '${tx.isRecoveryRedirect ? '\nRecovery redirect' : ''}'
                  '\n${formatDateTime(tx.timestampMs)}',
                ),
                isThreeLine: true,
                trailing: StatusChip(status: tx.status),
              ),
            );
          }),
        const SizedBox(height: 24),
        const Text(
          'Owner settings',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
        SwitchListTile(
          title: const Text('Biometric unlock (fingerprint / Face ID)'),
          subtitle: Text(
            _biometricAvailable
                ? 'When turned on, it will open without a PIN'
                : 'Biometric is not available on this phone',
          ),
          value: _biometricEnabled,
          onChanged: _biometricAvailable ? _toggleBiometric : null,
        ),
        if (!_changingPin)
          OutlinedButton(
            onPressed: () => setState(() => _changingPin = true),
            child: const Text('Change PIN'),
          )
        else ...[
          TextField(
            controller: _oldPinController,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: const InputDecoration(
              labelText: 'Old PIN',
              border: OutlineInputBorder(),
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _newPinController,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: const InputDecoration(
              labelText: 'New PIN (4-6 digits)',
              border: OutlineInputBorder(),
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _changePin,
            child: const Text('Change PIN'),
          ),
        ],
        const SizedBox(height: 12),
        TextButton(
          onPressed: _deleteWallet,
          child: const Text(
            'Delete Recovery Wallet',
            style: TextStyle(color: Colors.red),
          ),
        ),
      ],
    );
  }
}
