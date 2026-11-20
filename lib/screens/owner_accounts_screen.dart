// Owner accounts screen — app me bane hue SAARE accounts ki FULL
// details, SIRF owner ko.
//
// List bhi owner lock ke bina nahi khulti:
//   - Owner PIN set nahi hai -> pehle PIN set karo (4-6 digit).
//   - PIN set hai -> PIN dalo ya fingerprint/Face ID (agar on hai).
// Bina lock ke address, balance, seed — KUCH nahi dikhta.
//
// Unlock ke baad har account ke liye:
//   - Address: Tron (T...) + Ethereum/BNB (0x..., ek hi seed se)
//   - Network: Tron (TRC20), Ethereum (ERC20), BNB Smart Chain (BEP20)
//   - Balance: USDT + TRX (Tron), ETH, BNB, USDT ERC20/BEP20
//     (mainnet par; testnet par sirf native coin)
//   - Creation date (is phone me kab add hua — purane wallet me
//     "pata nahi", kyunki tab date save nahi hoti thi)
//   - Seed / private key: per-account "Seed dikhao" button se —
//     default chhupa rehta hai, warning ke saath.
//
// Koi server nahi — sab local secure storage + blockchain APIs se.
// Koi account yahan se delete / change NAHI hota — sirf view.
// Delete karna ho to Home / Recovery Wallet screen se hota hai.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../services/evm_service.dart';
import '../services/owner_accounts_service.dart';
import '../services/owner_lock_service.dart';
import '../services/recovery_wallet_service.dart';
import '../services/trongrid_service.dart';
import '../services/wallet_service.dart';
import '../utils/format.dart';
import 'recovery_wallet_screen.dart';

enum _OwnerAccountsView { setupPin, locked, unlocked }

class _AccountBalances {
  double usdt = 0;
  double trx = 0;
  double eth = 0;
  double bnb = 0;
  double usdtErc20 = 0;
  double usdtBep20 = 0;
  bool loaded = false;
}

class _AccountSecrets {
  final String mnemonic;
  final String tronPrivateKeyHex;
  final String evmPrivateKeyHex;
  const _AccountSecrets({
    required this.mnemonic,
    required this.tronPrivateKeyHex,
    required this.evmPrivateKeyHex,
  });
}

class OwnerAccountsScreen extends StatefulWidget {
  /// Hidden owner login (OwnerLoginScreen) se aaye ho to true — lock
  /// wahan khul chuka hai, yahan dobara PIN nahi maanga jata. Seedha
  /// kholne par (default false) ye screen khud lock maangti hai.
  final bool alreadyUnlocked;

  const OwnerAccountsScreen({super.key, this.alreadyUnlocked = false});

  @override
  State<OwnerAccountsScreen> createState() => _OwnerAccountsScreenState();
}

class _OwnerAccountsScreenState extends State<OwnerAccountsScreen> {
  final _accountsService = OwnerAccountsService();
  final _lock = OwnerLockService();
  final _wallet = WalletService();
  final _recovery = RecoveryWalletService();
  final _tronApi = TronGridService();

  _OwnerAccountsView _view = _OwnerAccountsView.locked;
  bool _loading = true;

  // PIN setup / unlock state
  final _pinController = TextEditingController();
  final _pinConfirmController = TextEditingController();
  final _unlockPinController = TextEditingController();
  String? _lockError;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;

  // Unlocked state
  List<StoredAccount> _accounts = [];
  final Map<StoredAccountKind, _AccountBalances> _balances = {};
  final Set<StoredAccountKind> _revealed = {};
  final Map<StoredAccountKind, _AccountSecrets> _secrets = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _pinController.dispose();
    _pinConfirmController.dispose();
    _unlockPinController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    // Hidden owner login se aaye ho to lock wahan khul chuka hai.
    if (widget.alreadyUnlocked) {
      await _unlock();
      if (mounted) setState(() => _loading = false);
      return;
    }
    final hasPin = await _lock.hasPin();
    if (!mounted) return;
    if (!hasPin) {
      setState(() {
        _view = _OwnerAccountsView.setupPin;
        _loading = false;
      });
      return;
    }
    final biometricEnabled = await _lock.isBiometricEnabled();
    final biometricAvailable = await _lock.canUseBiometric();
    setState(() {
      _view = _OwnerAccountsView.locked;
      _biometricEnabled = biometricEnabled;
      _biometricAvailable = biometricAvailable;
      _loading = false;
    });
    if (biometricEnabled && biometricAvailable) {
      final ok = await _lock.authenticateWithBiometric(
        reason: 'Saare accounts dekhne ke liye verify karo',
      );
      if (ok && mounted) await _unlock();
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _setupPin() async {
    final pin = _pinController.text.trim();
    final confirm = _pinConfirmController.text.trim();
    if (!OwnerLockService.isValidPin(pin)) {
      setState(() => _lockError = 'PIN 4-6 digit ka hona chahiye.');
      return;
    }
    if (pin != confirm) {
      setState(() => _lockError = 'Dono PIN same hone chahiye.');
      return;
    }
    try {
      await _lock.setPin(pin);
    } catch (e) {
      setState(
        () => _lockError = e.toString().replaceFirst('Exception: ', ''),
      );
      return;
    }
    await _unlock();
  }

  Future<void> _tryPin() async {
    final pin = _unlockPinController.text.trim();
    if (!await _lock.verifyPin(pin)) {
      setState(() => _lockError = 'Galat PIN. Dobara try karo.');
      return;
    }
    _unlockPinController.clear();
    await _unlock();
  }

  Future<void> _tryBiometric() async {
    final ok = await _lock.authenticateWithBiometric(
      reason: 'Saare accounts dekhne ke liye verify karo',
    );
    if (ok) {
      await _unlock();
    } else {
      setState(() => _lockError = 'Biometric fail hua — PIN se kholo.');
    }
  }

  Future<void> _unlock() async {
    final accounts = await _accountsService.listAccounts();
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _view = _OwnerAccountsView.unlocked;
      _lockError = null;
    });
    await _refreshBalances();
  }

  Future<void> _refreshBalances() async {
    for (final account in _accounts) {
      final balances = _AccountBalances();
      final tronAddress = account.tronAddress;
      final evmAddress = account.evmAddress;
      if (tronAddress != null) {
        try {
          balances.usdt = await _tronApi.getUsdtBalance(tronAddress);
        } catch (_) {}
        try {
          balances.trx = await _tronApi.getTrxBalance(tronAddress);
        } catch (_) {}
      }
      if (evmAddress != null) {
        try {
          balances.eth =
              await EvmService.ethereum().getNativeBalance(evmAddress);
        } catch (_) {}
        try {
          balances.bnb = await EvmService.bsc().getNativeBalance(evmAddress);
        } catch (_) {}
        if (!EthereumConfig.isTestnet) {
          try {
            balances.usdtErc20 = await EvmService.ethereum().getTokenBalance(
              EthereumConfig.usdtErc20Contract,
              evmAddress,
              6,
            );
          } catch (_) {}
        }
        if (!BscConfig.isTestnet) {
          try {
            balances.usdtBep20 = await EvmService.bsc().getTokenBalance(
              BscConfig.usdtBep20Contract,
              evmAddress,
              18,
            );
          } catch (_) {}
        }
      }
      balances.loaded = true;
      if (!mounted) return;
      setState(() => _balances[account.kind] = balances);
    }
  }

  Future<void> _toggleReveal(StoredAccount account) async {
    if (_revealed.contains(account.kind)) {
      setState(() => _revealed.remove(account.kind));
      return;
    }
    try {
      final _AccountSecrets secrets;
      if (account.kind == StoredAccountKind.main) {
        final mnemonic = await _wallet.getMnemonic();
        secrets = _AccountSecrets(
          mnemonic: mnemonic,
          tronPrivateKeyHex: await _wallet.getPrivateKeyHex(),
          evmPrivateKeyHex: await _wallet.getEthereumPrivateKeyHex(),
        );
      } else {
        final mnemonic = await _recovery.getMnemonic();
        if (mnemonic == null) {
          _snack('Recovery wallet ki seed nahi mili.');
          return;
        }
        secrets = _AccountSecrets(
          mnemonic: mnemonic,
          tronPrivateKeyHex: await _recovery.getPrivateKeyHex(),
          evmPrivateKeyHex:
              WalletService.deriveEthereumFromMnemonic(mnemonic)
                  .privateKeyHex,
        );
      }
      if (!mounted) return;
      setState(() {
        _secrets[account.kind] = secrets;
        _revealed.add(account.kind);
      });
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _copy(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    _snack('$label copy ho gaya');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Saare accounts — Owner only')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : switch (_view) {
              _OwnerAccountsView.setupPin => _buildSetupPinView(),
              _OwnerAccountsView.locked => _buildLockedView(),
              _OwnerAccountsView.unlocked => _buildUnlockedView(),
            },
    );
  }

  Widget _buildSetupPinView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.lock, size: 56, color: Colors.teal),
          const SizedBox(height: 16),
          const Text(
            'Saare accounts sirf owner dekh sakta hai. Pehle owner PIN '
            'set karo — yehi PIN aage se accounts aur Recovery Wallet '
            'kholne ke liye chahiye hoga.',
            style: TextStyle(fontSize: 15),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _pinController,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 6,
            decoration: const InputDecoration(
              labelText: 'Owner PIN (4-6 digit)',
              border: OutlineInputBorder(),
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pinConfirmController,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 6,
            decoration: const InputDecoration(
              labelText: 'PIN dobara likho',
              border: OutlineInputBorder(),
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          if (_lockError != null)
            Text(_lockError!, style: const TextStyle(color: Colors.red)),
          if (_lockError != null) const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _setupPin,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child:
                const Text('PIN set karo', style: TextStyle(fontSize: 18)),
          ),
        ],
      ),
    );
  }

  Widget _buildLockedView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.lock, size: 56, color: Colors.teal),
          const SizedBox(height: 16),
          const Text(
            'Saare accounts dekhne ke liye owner lock kholo. Bina PIN / '
            'biometric ke yahan kuch nahi dikhega — na list, na address, '
            'na balance.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _unlockPinController,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 6,
            decoration: const InputDecoration(
              labelText: 'Owner PIN (4-6 digit)',
              border: OutlineInputBorder(),
              counterText: '',
            ),
            onSubmitted: (_) => _tryPin(),
          ),
          const SizedBox(height: 12),
          if (_lockError != null)
            Text(_lockError!, style: const TextStyle(color: Colors.red)),
          if (_lockError != null) const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _tryPin,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text('Kholdo', style: TextStyle(fontSize: 18)),
          ),
          if (_biometricEnabled && _biometricAvailable) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _tryBiometric,
              icon: const Icon(Icons.fingerprint),
              label: const Text('Fingerprint / Face ID se kholo'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildUnlockedView() {
    if (_accounts.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'App me koi wallet account nahi mila.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: Colors.grey),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refreshBalances,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'App me stored saare accounts — sirf owner ko dikh rahe hain. '
            'Seed / private key kabhi screenshot ya message me mat bhejo.',
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const RecoveryWalletScreen(),
                ),
              );
            },
            icon: const Icon(Icons.lock, size: 18),
            label: const Text('Recovery Wallet kholo'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 12),
          ..._accounts.map(_buildAccountCard),
        ],
      ),
    );
  }

  Widget _buildAccountCard(StoredAccount account) {
    final balances = _balances[account.kind];
    final revealed = _revealed.contains(account.kind);
    final secrets = _secrets[account.kind];
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              account.label,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            _row('Network', account.networks.join(', ')),
            _row(
              'Bana tha',
              account.createdAt == null
                  ? 'Pata nahi (is feature se pehle bana tha)'
                  : formatDateTime(
                      account.createdAt!.millisecondsSinceEpoch,
                    ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Addresses',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            if (account.tronAddress != null)
              _copyRow('Tron (TRC20)', account.tronAddress!),
            if (account.evmAddress != null)
              _copyRow('Ethereum / BNB (0x...)', account.evmAddress!),
            const SizedBox(height: 8),
            const Text(
              'Balance',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            if (balances == null || !balances.loaded)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else ...[
              _row('USDT (Tron)', '${formatUsdt(balances.usdt)} USDT'),
              _row('TRX', balances.trx.toStringAsFixed(2)),
              _row('ETH', balances.eth.toStringAsFixed(4)),
              _row('BNB', balances.bnb.toStringAsFixed(4)),
              if (!EthereumConfig.isTestnet)
                _row(
                  'USDT (ERC20)',
                  '${formatUsdt(balances.usdtErc20)} USDT',
                ),
              if (!BscConfig.isTestnet)
                _row(
                  'USDT (BEP20)',
                  '${formatUsdt(balances.usdtBep20)} USDT',
                ),
              if (EthereumConfig.isTestnet && BscConfig.isTestnet)
                const Text(
                  'Testnet par USDT ERC20 / BEP20 ka official contract '
                  'nahi hai — sirf ETH / BNB dikh raha hai.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _toggleReveal(account),
              icon: Icon(
                revealed ? Icons.visibility_off : Icons.visibility,
              ),
              label: Text(
                revealed ? 'Seed / private key chhupao' : 'Seed dikhao',
              ),
            ),
            if (revealed && secrets != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Ye words aur keys kisi ko mat do — jo inhe jaanta '
                      'hai, wo paise nikaal sakta hai.',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Seed (12 words)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    _copyRow('Seed', secrets.mnemonic),
                    _copyRow(
                      'Private key (Tron)',
                      secrets.tronPrivateKeyHex,
                    ),
                    _copyRow(
                      'Private key (Ethereum / BNB)',
                      secrets.evmPrivateKeyHex,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _copyRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.grey)),
                SelectableText(value, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            tooltip: 'Copy karo',
            onPressed: () => _copy(label, value),
          ),
        ],
      ),
    );
  }
}
