// Home screen: balance, pending transactions, recent history.
//
// NETWORK SWITCHER (Tron / Ethereum / BNB Smart Chain):
//   Har network ka apna address, balance aur history dikhta hai.
//   - Tron: address T... se, USDT (TRC20) + TRX.
//   - Ethereum: address 0x... se, ETH + USDT ERC20 + SHIB (mainnet par).
//   - BNB Chain: address 0x... se, BNB + USDT BEP20 (mainnet par).
//   ETH aur BNB ka address EK HI hota hai (ek hi seed se) — balance
//   aur history har chain par alag hota hai.
//
// BALANCE AUTO-UPDATE (Tron):
//   1. After YOU send USDT: TxStatusService watches it turn Confirmed.
//   2. When SOMEONE sends you USDT: 30-second refresh.
// EVM chains par bhi 30-second refresh hai.
//
// NEW TOKENS (auto-detect):
//   Home wallet apne aap naye tokens detect karta hai — TronGrid /
//   Etherscan / BscScan se address ke saare token balances fetch karke.
//   Jo token curated list me NAHI hai wo "New Tokens" section me
//   balance ke saath dikhta hai. Swap list me naya coin automatic
//   NAHI aata (scam risk) — wo curated list se aata hai (README dekho).
//
// Pending transactions (just sent, not confirmed yet) are saved on the
// phone, so they survive closing and reopening the app.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../models/transaction_model.dart';
import '../services/evm_service.dart';
import '../services/monthly_fee_service.dart';
import '../services/seed_backup_service.dart';
import '../services/token_list.dart';
import '../services/trongrid_service.dart';
import '../services/tx_status_service.dart';
import '../services/wallet_service.dart';
import '../utils/format.dart';
import '../widgets/status_chip.dart';
import 'add_custom_token_screen.dart';
import 'buy_screen.dart';
import 'evm_send_screen.dart';
import 'history_screen.dart';
import 'owner_login_screen.dart';
import 'receive_screen.dart';
import 'send_screen.dart';
import 'swap_screen.dart';
import '../widgets/secret_owner_tap.dart';

enum AppChain { tron, ethereum, bsc }

class HomeScreen extends StatefulWidget {
  final VoidCallback onWalletDeleted;

  const HomeScreen({super.key, required this.onWalletDeleted});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _walletService = WalletService();
  final _seedBackupService = SeedBackupService();
  final _api = TronGridService();
  final _txStatus = TxStatusService();
  final _customTokenService = CustomTokenService();

  AppChain _chain = AppChain.tron;

  // Tron state
  String? _address;
  double _usdtBalance = 0;
  double _trxBalance = 0;
  List<Trc20Transfer> _history = [];
  List<Trc20Transfer> _pendingTxs = [];
  bool _loading = true;
  String? _error;

  // EVM state (Ethereum + BNB — address dono ka ek hi 0x... hai)
  String? _evmAddress;
  double _evmNativeBalance = 0;
  Map<String, double> _evmTokenBalances = {};
  List<EvmTx> _evmHistory = [];
  String? _evmHistoryNote;

  // Tokens: curated list se bahar ke, auto-detect + user ke custom.
  List<DetectedToken> _detectedTokens = [];
  List<TokenInfo> _customTokens = [];
  Map<String, double> _customTokenBalances = {};

  /// Refreshes balance + history every 30s so incoming payments appear.
  Timer? _balanceTimer;

  /// One polling timer per pending transaction (cancelled on dispose).
  final Map<String, Timer> _pollTimers = {};

  EvmChainConfig get _evmChainConfig =>
      _chain == AppChain.ethereum ? EthereumConfig.chain : BscConfig.chain;

  EvmService get _evmService => _chain == AppChain.ethereum
      ? EvmService.ethereum()
      : EvmService.bsc();

  List<TokenInfo> get _evmTokens {
    if (_chain == AppChain.ethereum) {
      return curatedTokens
          .where((t) =>
              t.id == 'ETH' || t.id == 'USDT-ERC20' || t.id == 'SHIB')
          .toList();
    }
    return curatedTokens
        .where((t) => t.id == 'BNB' || t.id == 'USDT-BEP20')
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _loadAll();
    _balanceTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshBalancesQuietly(),
    );
  }

  @override
  void dispose() {
    _balanceTimer?.cancel();
    for (final timer in _pollTimers.values) {
      timer.cancel();
    }
    super.dispose();
  }

  Future<void> _loadAll() async {
    final address = await _walletService.getAddress();
    final evmAddress = await _walletService.getEthereumAddress();
    if (!mounted) return;
    setState(() {
      _address = address;
      _evmAddress = evmAddress;
      _loading = true;
      _error = null;
    });
    try {
      await _refreshForChain();
      if (_chain == AppChain.tron) await _recheckPendingTxs();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshForChain() async {
    if (_chain == AppChain.tron) {
      await _refreshTron();
    } else {
      await _refreshEvm();
    }
    await _refreshDetectedTokens();
  }

  Future<void> _refreshTron() async {
    final address = _address;
    if (address == null) return;
    final usdt = await _api.getUsdtBalance(address);
    final trx = await _api.getTrxBalance(address);
    final history = await _api.getTrc20History(address);
    final pending = await _txStatus.getPendingTxs();
    final custom = await _customTokenService.getCustomTokens();
    final customBalances = <String, double>{};
    for (final token in custom) {
      try {
        customBalances[token.id] = await _customTokenService
            .getCustomTokenBalance(token, address);
      } catch (_) {
        customBalances[token.id] = 0;
      }
    }
    if (!mounted) return;
    setState(() {
      _usdtBalance = usdt;
      _trxBalance = trx;
      _history = history;
      _pendingTxs = pending;
      _customTokens = custom;
      _customTokenBalances = customBalances;
    });
  }

  Future<void> _refreshEvm() async {
    final address = _evmAddress;
    if (address == null) return;
    final service = _evmService;
    double native = 0;
    final tokenBalances = <String, double>{};
    try {
      native = await service.getNativeBalance(address);
    } catch (_) {}
    for (final token in _evmTokens) {
      if (token.contractAddress == null) continue;
      try {
        tokenBalances[token.id] = await service.getTokenBalance(
          token.contractAddress!,
          address,
          token.decimals,
        );
      } catch (_) {
        tokenBalances[token.id] = 0;
      }
    }
    List<EvmTx> history = [];
    String? historyNote;
    try {
      history = await service.getHistory(address);
    } catch (e) {
      historyNote = e.toString().replaceFirst('Exception: ', '');
    }
    if (!mounted) return;
    setState(() {
      _evmNativeBalance = native;
      _evmTokenBalances = tokenBalances;
      _evmHistory = history;
      _evmHistoryNote = historyNote;
    });
  }

  /// Auto-detect: address ke saare tokens dhoondho — curated list me
  /// ho ya na ho. Tron par TronGrid account se, EVM par explorer API se.
  Future<void> _refreshDetectedTokens() async {
    final detected = <DetectedToken>[];
    try {
      if (_chain == AppChain.tron && _address != null) {
        final all = await _api.getAllTrc20Balances(_address!);
        final knownContracts = {
          TronConfig.usdtContract.toLowerCase(),
          ..._customTokens
              .map((t) => t.contractAddress?.toLowerCase() ?? '')
              .where((c) => c.isNotEmpty),
        };
        for (final entry in all.entries) {
          if (knownContracts.contains(entry.key.toLowerCase())) continue;
          final raw = BigInt.tryParse(entry.value) ?? BigInt.zero;
          if (raw == BigInt.zero) continue;
          try {
            final info =
                await _customTokenService.fetchTokenInfo(entry.key);
            var divisor = 1.0;
            for (var i = 0; i < info.decimals; i++) {
              divisor *= 10;
            }
            detected.add(DetectedToken(
              contractAddress: entry.key,
              symbol: info.symbol,
              name: info.name,
              decimals: info.decimals,
              balance: raw.toDouble() / divisor,
            ));
          } catch (_) {
            // Naam na mile to token chhodo — galat naam dikhane se behtar.
          }
        }
      } else if (_chain != AppChain.tron && _evmAddress != null) {
        final found = await _evmService.detectTokens(_evmAddress!);
        for (final token in found) {
          // Curated tokens ko alag se balance card me dikhate hain.
          final isKnown = curatedTokens.any((t) =>
              t.contractAddress?.toLowerCase() ==
              token.contractAddress.toLowerCase());
          if (!isKnown) detected.add(token);
        }
      }
    } catch (_) {
      // Auto-detect fail ho to Home khaali nahi hota — section chhup jata hai.
    }
    if (mounted) setState(() => _detectedTokens = detected);
  }

  /// Quiet refresh for the 30-second timer: never shows an error banner,
  /// a failed background refresh simply tries again next round.
  Future<void> _refreshBalancesQuietly() async {
    if (_loading) return;
    try {
      await _refreshForChain();
    } catch (_) {
      // Ignore — next round will try again.
    }
  }

  /// Re-checks pending transactions saved from earlier (for example the
  /// app was closed while a send was still Pending). Confirmed ones
  /// refresh the balance; still-pending ones start polling again.
  Future<void> _recheckPendingTxs() async {
    var changed = false;
    for (final tx in List<Trc20Transfer>.from(_pendingTxs)) {
      final status = await _txStatus.fetchStatus(tx.txId);
      if (!mounted) return;
      if (status == TxStatus.confirmed) {
        await _txStatus.removePendingTx(tx.txId);
        changed = true;
      } else if (status == TxStatus.failed) {
        await _txStatus.removePendingTx(tx.txId);
        changed = true;
      } else {
        _startPolling(tx.txId);
      }
    }
    if (changed && mounted) {
      await _refreshTron(); // balance auto-update after confirmations
    }
  }

  void _startPolling(String txId) {
    if (_pollTimers.containsKey(txId)) return;
    _pollTimers[txId] = _txStatus.pollTxStatus(txId, (status) {
      if (!mounted) return;
      _pollTimers.remove(txId);
      if (status == TxStatus.confirmed) {
        _onTxSettled(txId, true);
      } else if (status == TxStatus.failed) {
        _onTxSettled(txId, false);
      }
    });
  }

  Future<void> _onTxSettled(String txId, bool confirmed) async {
    setState(() {
      _pendingTxs.removeWhere((t) => t.txId == txId);
    });
    await _refreshTron(); // balance + history update themselves
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          confirmed
              ? 'Transaction confirmed! Balance updated.'
              : 'Transaction failed. No money was sent (only a small fee was charged).',
        ),
        backgroundColor: confirmed ? Colors.green : Colors.red,
      ),
    );
  }

  Future<void> _openSend() async {
    if (_chain == AppChain.tron) {
      final address = _address;
      if (address == null) return;
      final result = await Navigator.of(context).push<SendResult>(
        MaterialPageRoute(
          builder: (_) => SendScreen(
            fromAddress: address,
            usdtBalance: _usdtBalance,
            trxBalance: _trxBalance,
          ),
        ),
      );
      if (result == null || !mounted) return;
      final pending = Trc20Transfer.pending(
        txId: result.txId,
        from: address,
        to: result.toAddress,
        value: BigInt.from((result.amount * 1000000).round()),
        isRecoveryRedirect: result.isRecoveryRedirect,
        originalAddress: result.originalAddress,
        intendedNetwork: result.intendedNetwork,
        recoveryReason: result.recoveryReason,
      );
      await _txStatus.savePendingTx(pending);
      setState(() => _pendingTxs.insert(0, pending));
      _startPolling(result.txId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.isRecoveryRedirect
                ? 'Sent to the recovery wallet! Status: Pending — '
                    'The original address is recorded in history.'
                : 'Sent! Status: Pending — your balance will update automatically once it is confirmed.',
          ),
        ),
      );
    } else {
      // Ethereum / BNB: EVM send screen.
      final address = _evmAddress;
      if (address == null) return;
      final result = await Navigator.of(context).push<EvmSendResult>(
        MaterialPageRoute(
          builder: (_) => EvmSendScreen(
            chain: _evmChainConfig,
            fromAddress: address,
            nativeBalance: _evmNativeBalance,
            tokenBalances: _evmTokenBalances,
            tokens: _evmTokens,
          ),
        ),
      );
      if (result == null || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sent! Tx: ${result.txHash}'),
        ),
      );
      await _refreshForChain();
    }
  }

  Future<void> _openSwap() async {
    final address = _address;
    final evmAddress = _evmAddress;
    if (address == null || evmAddress == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SwapScreen(
          fromAddress: address,
          evmAddress: evmAddress,
          usdtBalance: _usdtBalance,
          trxBalance: _trxBalance,
        ),
      ),
    );
    if (mounted) await _refreshForChain();
  }

  Future<void> _openBuy() async {
    final address = _address;
    final evmAddress = _evmAddress;
    if (address == null || evmAddress == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BuyScreen(
          tronAddress: address,
          evmAddress: evmAddress,
        ),
      ),
    );
    if (mounted) await _refreshForChain();
  }

  Future<void> _openAddCustomToken() async {
    final address = _address;
    if (address == null) return;
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddCustomTokenScreen(ownerAddress: address),
      ),
    );
    if (added == true && mounted) await _refreshForChain();
  }

  Future<void> _confirmDeleteWallet() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete wallet?'),
        content: const Text(
          'This wallet will be deleted from this phone. Your money stays '
          'on the blockchain — you can restore it with your 12 words. '
          'Without the 12 words, your money will be lost forever.\n\n'
          'The real user can get the seed from the owner only within '
          '3 months AFTER wallet logout (3 months from the logout day, '
          'not from the wallet creation day); after that the owner will '
          'not give the seed to anyone, even if the seed is still saved '
          'on the server.\n\n'
          'Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (yes == true) {
      // Logout date record karo — deleteWallet() se PEHLE. Isi din se
      // seed-backup recovery ki 3-month window shuru hoti hai
      // (logout day se 3 months, wallet creation day se nahi).
      await _seedBackupService.recordLogout();
      await _walletService.deleteWallet();
      widget.onWalletDeleted();
    }
  }

  /// Pending first, then on-chain history. If a pending transaction
  /// already appears in history, the history copy wins.
  List<Trc20Transfer> get _mergedRecent {
    final seen = <String>{};
    final merged = <Trc20Transfer>[];
    for (final tx in [..._pendingTxs, ..._history]) {
      if (seen.add(tx.txId)) merged.add(tx);
    }
    return merged;
  }

  String get _currentAddress =>
      _chain == AppChain.tron ? (_address ?? '') : (_evmAddress ?? '');

  String get _networkBadge {
    switch (_chain) {
      case AppChain.tron:
        return TronConfig.networkName;
      case AppChain.ethereum:
        return EthereumConfig.isTestnet
            ? 'Ethereum Sepolia Testnet'
            : 'Ethereum Mainnet';
      case AppChain.bsc:
        return BscConfig.isTestnet
            ? 'BNB Chain Testnet'
            : 'BNB Smart Chain Mainnet';
    }
  }

  void _onChainChanged(AppChain chain) {
    setState(() {
      _chain = chain;
      _loading = true;
      _error = null;
    });
    _loadAll();
  }

  @override
  Widget build(BuildContext context) {
    final address = _currentAddress;
    final isTron = _chain == AppChain.tron;
    return Scaffold(
      appBar: AppBar(
        title: const Text('DarkVibeX Wallet'),
        actions: [
          if (isTron)
            IconButton(
              icon: const Icon(Icons.history),
              tooltip: 'All history',
              onPressed: _address == null
                  ? null
                  : () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => HistoryScreen(address: _address!),
                        ),
                      );
                    },
            ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'delete') _confirmDeleteWallet();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'delete',
                child: Text('Delete wallet',
                    style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAll,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ---- Network switcher: Tron / Ethereum / BNB Chain ----
                  const Text('Network',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: AppChain.values.map((chain) {
                      final label = chain == AppChain.tron
                          ? 'Tron'
                          : chain == AppChain.ethereum
                              ? 'Ethereum'
                              : 'BNB Smart Chain';
                      return ChoiceChip(
                        label: Text(label),
                        selected: chain == _chain,
                        onSelected: (_) => _onChainChanged(chain),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Chip(
                      label: Text(_networkBadge),
                      backgroundColor: (TronConfig.isTestnet ||
                                  _chain != AppChain.tron)
                              ? Colors.orange.withOpacity(0.15)
                              : Colors.green.withOpacity(0.15),
                      side: BorderSide(
                        color: Colors.orange,
                      ),
                    ),
                  ),
                  if (!isTron) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'ETH and BNB share the same address (0x..., from the same seed). '
                      'Balance and history are different on each chain.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                  const SizedBox(height: 12),

                  // ---- Balance card ----
                  if (isTron) _tronBalanceCard() else _evmBalanceCard(),
                  const SizedBox(height: 16),

                  // ---- Monthly fee ($0.01 flat) — user ko pehle se saaf
                  // dikhe: kitni, kab, kis coin me. App khud fee nahi
                  // kaat-ta (bina server ke possible nahi) — sirf
                  // calculate karke dikhata hai, koi fake deduction nahi.
                  _monthlyFeeCard(),
                  const SizedBox(height: 16),

                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(_error!,
                          style: const TextStyle(color: Colors.red)),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ---- Send / Receive / Swap / Buy ----
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _openSend,
                          icon: const Icon(Icons.arrow_upward),
                          label: const Text('Send'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: address.isEmpty
                              ? null
                              : () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          ReceiveScreen(address: address),
                                    ),
                                  );
                                },
                          icon: const Icon(Icons.arrow_downward),
                          label: const Text('Receive'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _openSwap,
                          icon: const Icon(Icons.swap_horiz),
                          label: const Text('Swap'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _openBuy,
                          icon: const Icon(Icons.add_shopping_cart),
                          label: const Text('Buy'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed:
                        isTron ? _openAddCustomToken : null,
                    icon: const Icon(Icons.add_circle_outline, size: 18),
                    label: const Text('Add Custom Token'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                  if (!isTron)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'Add Custom Token is available for Tron (TRC20) for now — '
                        'EVM custom tokens are coming soon.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                  const SizedBox(height: 24),

                  // ---- New Tokens (auto-detect) ----
                  if (_detectedTokens.isNotEmpty) ...[
                    const Text(
                      'New Tokens (auto-detect)',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                    const Text(
                      'These tokens were found at your address — whether or not they are in the curated list. '
                      'They do not appear in the swap list automatically (scam risk).',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    ..._detectedTokens.map((token) => Card(
                          child: ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.token, size: 18),
                            ),
                            title: Text(token.symbol,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            subtitle: Text(
                              '${token.name} • ${shortAddress(token.contractAddress)}',
                            ),
                            trailing: Text(
                              token.balance.toStringAsFixed(4),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        )),
                    const SizedBox(height: 24),
                  ],

                  // ---- Custom tokens (user ne khud add kiye) ----
                  if (isTron && _customTokens.isNotEmpty) ...[
                    const Text(
                      'Your custom tokens',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    ..._customTokens.map((token) => Card(
                          child: ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.token, size: 18),
                            ),
                            title: Text(token.symbol,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            subtitle: Text(token.network),
                            trailing: Text(
                              (_customTokenBalances[token.id] ?? 0)
                                  .toStringAsFixed(4),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        )),
                    const SizedBox(height: 24),
                  ],

                  // ---- Recent transactions ----
                  const Text(
                    'Recent transactions',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (isTron) ...[
                    if (_mergedRecent.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'No transactions yet.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    else
                      ..._mergedRecent
                          .take(5)
                          .map((tx) => _txTile(tx, _address)),
                  ] else ...[
                    if (_evmHistoryNote != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'History: $_evmHistoryNote',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey),
                        ),
                      ),
                    if (_evmHistory.isEmpty && _evmHistoryNote == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'No transactions yet.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    else
                      ..._evmHistory.take(5).map((tx) => _evmTxTile(tx)),
                  ],

                  // ---- Version (chhota grey text — owner login ka
                  // secret trigger: is par 7 baar tap karo) ----
                  const SizedBox(height: 32),
                  Center(
                    child: SecretOwnerTapDetector(
                      onTriggered: _openOwnerLogin,
                      child: const Text(
                        'Version 0.1.0',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
    );
  }

  void _openOwnerLogin() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const OwnerLoginScreen()),
    );
  }

  /// Monthly wallet fee card — $0.01 FLAT per month (Vinay final).
  /// User ko pehle se saaf dikhe: kitni (0.01 USDT), kab (mahine ke
  /// aakhri din), kis coin me (USDT), kahan jayegi (owner fee wallet).
  /// Fee balance par depend nahi karti — flat hai.
  /// Note: app khud balance se fee NAHI kaat-ta — bina server ke
  /// on-chain deduction possible nahi hai. Isliye yahan sirf fee
  /// calculate karke dikhayi jati hai; balance me se kuch kata nahi
  /// dikhega, koi fake "fee paid" nahi banega.
  Widget _monthlyFeeCard() {
    final due = MonthlyFeeService.dueDateLabel();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: Colors.amber),
              SizedBox(width: 6),
              Text(
                'Monthly fee — \$0.01 flat',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'A fee of 0.01 USDT will be charged every month — whatever your balance is, '
            'the fee stays the same.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            'Next fee: $due (last day of the month) • The fee is in USDT and '
            'goes to the owner wallet.',
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 4),
          const Text(
            'Note: the app does not deduct the fee from your balance itself — '
            'a server is needed for the deduction, which is not available yet.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _tronBalanceCard() {
    final address = _address;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.teal.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('USDT Balance', style: TextStyle(fontSize: 14)),
          Text(
            '${formatUsdt(_usdtBalance)} USDT',
            style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
          ),
          Text(
            'TRX: ${_trxBalance.toStringAsFixed(2)} (for fees)',
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 8),
          if (address != null) _addressRow(address),
        ],
      ),
    );
  }

  Widget _evmBalanceCard() {
    final address = _evmAddress;
    final gasSymbol = _evmChainConfig.gasSymbol;
    final isTestnet = _evmChainConfig.isTestnet;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.teal.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$gasSymbol Balance', style: const TextStyle(fontSize: 14)),
          Text(
            '${_evmNativeBalance.toStringAsFixed(4)} $gasSymbol',
            style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
          ),
          ..._evmTokens.where((t) => !t.isNative).map((token) {
            final balance = _evmTokenBalances[token.id] ?? 0;
            return Text(
              '${token.symbol} (${token.network}): ${balance.toStringAsFixed(4)}',
              style: const TextStyle(color: Colors.grey),
            );
          }),
          if (isTestnet) ...[
            const SizedBox(height: 8),
            Text(
              'There is no official contract for ${gasSymbol == 'ETH' ? 'USDT ERC20 / SHIB' : 'USDT BEP20'} on testnet — here, test only $gasSymbol. These tokens will appear on mainnet.',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
          const SizedBox(height: 8),
          if (address != null) _addressRow(address),
        ],
      ),
    );
  }

  Widget _addressRow(String address) {
    return Row(
      children: [
        Expanded(
          child: Text(
            shortAddress(address),
            style: const TextStyle(fontSize: 13),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.copy, size: 18),
          tooltip: 'Copy address',
          onPressed: () {
            Clipboard.setData(ClipboardData(text: address));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Address copied')),
            );
          },
        ),
      ],
    );
  }

  Widget _txTile(Trc20Transfer tx, String? address) {
    final outgoing = address != null && tx.isOutgoing(address);
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              (outgoing ? Colors.red : Colors.green).withOpacity(0.15),
          child: Icon(
            outgoing ? Icons.arrow_upward : Icons.arrow_downward,
            color: outgoing ? Colors.red : Colors.green,
          ),
        ),
        title: Text(
          '${outgoing ? '-' : '+'}${formatUsdt(tx.amount)} USDT',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${outgoing ? 'To ' : 'From '}${shortAddress(outgoing ? tx.to : tx.from)}'
          '${tx.isRecoveryRedirect ? ' • Recovery redirect' : ''}'
          ' • ${formatDateTime(tx.timestampMs)}',
        ),
        trailing: StatusChip(status: tx.status),
      ),
    );
  }

  Widget _evmTxTile(EvmTx tx) {
    final address = _evmAddress;
    final outgoing = address != null && tx.isOutgoing(address);
    final isToken = tx.tokenSymbol != null;
    final amountText = isToken
        ? '${tx.tokenValue?.toStringAsFixed(4) ?? '0'} ${tx.tokenSymbol}'
        : '${tx.value.toStringAsFixed(4)} ${_evmChainConfig.gasSymbol}';
    final date = tx.timestampSec > 0
        ? formatDateTime(tx.timestampSec * 1000)
        : '';
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              (outgoing ? Colors.red : Colors.green).withOpacity(0.15),
          child: Icon(
            outgoing ? Icons.arrow_upward : Icons.arrow_downward,
            color: outgoing ? Colors.red : Colors.green,
          ),
        ),
        title: Text(
          '${outgoing ? '-' : '+'}$amountText',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${outgoing ? 'To ' : 'From '}${shortAddress(outgoing ? tx.to : tx.from)}'
          '${tx.isError ? ' • Failed' : ''} • $date',
        ),
        trailing: Icon(
          tx.isError ? Icons.error_outline : Icons.check_circle_outline,
          color: tx.isError ? Colors.red : Colors.green,
        ),
      ),
    );
  }
}
