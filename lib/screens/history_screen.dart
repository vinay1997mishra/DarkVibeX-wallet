// Full transaction history: every transaction shows its status clearly.
//
//   Pending   (orange) — broadcast done, network confirmation ka wait.
//   Confirmed (green)  — on-chain, receipt SUCCESS.
//   Failed    (red)    — on-chain but rejected; money did not move.
//
// Tap any transaction to see its full hash and Tronscan link.
// Pending transactions keep being polled while this screen is open.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../models/transaction_model.dart';
import '../services/trongrid_service.dart';
import '../services/tx_status_service.dart';
import '../utils/format.dart';
import '../widgets/status_chip.dart';

class HistoryScreen extends StatefulWidget {
  final String address;

  const HistoryScreen({super.key, required this.address});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _api = TronGridService();
  final _txStatus = TxStatusService();

  List<Trc20Transfer> _history = [];
  List<Trc20Transfer> _pendingTxs = [];
  bool _loading = true;
  String? _error;

  final Map<String, Timer> _pollTimers = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final timer in _pollTimers.values) {
      timer.cancel();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final history = await _api.getTrc20History(widget.address, limit: 50);
      final pending = await _txStatus.getPendingTxs();
      if (!mounted) return;
      setState(() {
        _history = history;
        _pendingTxs = pending;
        _loading = false;
      });
      for (final tx in pending) {
        _startPolling(tx.txId);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _startPolling(String txId) {
    if (_pollTimers.containsKey(txId)) return;
    _pollTimers[txId] = _txStatus.pollTxStatus(txId, (status) {
      if (!mounted) return;
      _pollTimers.remove(txId);
      if (status != TxStatus.pending) {
        _load(); // status changed -> reload list (balance updates on Home)
      }
    });
  }

  /// Pending first, then on-chain history. A transaction that appears in
  /// both lists is shown once (the history copy wins).
  List<Trc20Transfer> get _merged {
    final seen = <String>{};
    final merged = <Trc20Transfer>[];
    for (final tx in [..._pendingTxs, ..._history]) {
      if (seen.add(tx.txId)) merged.add(tx);
    }
    return merged;
  }

  Future<void> _showDetails(Trc20Transfer tx) async {
    final outgoing = tx.isOutgoing(widget.address);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${outgoing ? '-' : '+'}${formatUsdt(tx.amount)} USDT'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              StatusChip(status: tx.status),
              const SizedBox(height: 16),
              _detailRow('Transaction hash', tx.txId, copyable: true),
              _detailRow('From', tx.from),
              _detailRow('To', tx.to),
              if (tx.isRecoveryRedirect) ...[
                _detailRow(
                  'Recovery redirect',
                  'This money went to the recovery wallet — not to the original address. '
                  'Show the hash to support to claim it back.',
                ),
                if (tx.originalAddress != null)
                  _detailRow('Original address', tx.originalAddress!),
                if (tx.intendedNetwork != null)
                  _detailRow('Intended network', tx.intendedNetwork!),
                if (tx.recoveryReason != null)
                  _detailRow('Reason', tx.recoveryReason!),
              ],
              _detailRow('Date', formatDateTime(tx.timestampMs)),
              const SizedBox(height: 8),
              const Text('Tronscan link',
                  style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 4),
              SelectableText(
                TronConfig.txExplorerUrl(tx.txId),
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: tx.txId));
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Hash copied')),
              );
            },
            child: const Text('Copy hash'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, {bool copyable = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 2),
          SelectableText(value, style: const TextStyle(fontSize: 13)),
          if (copyable)
            TextButton(
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: value)),
              child: const Text('Copy'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _merged;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction history'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!,
                            style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _load,
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
                )
              : items.isEmpty
                  ? const Center(
                      child: Text(
                        'No transactions yet.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final tx = items[index];
                          final outgoing = tx.isOutgoing(widget.address);
                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: (outgoing
                                        ? Colors.red
                                        : Colors.green)
                                    .withOpacity(0.15),
                                child: Icon(
                                  outgoing
                                      ? Icons.arrow_upward
                                      : Icons.arrow_downward,
                                  color:
                                      outgoing ? Colors.red : Colors.green,
                                ),
                              ),
                              title: Text(
                                '${outgoing ? '-' : '+'}${formatUsdt(tx.amount)} USDT',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                '${outgoing ? 'To ' : 'From '}${shortAddress(outgoing ? tx.to : tx.from)}'
                                '${tx.isRecoveryRedirect ? '\nRecovery redirect — the original address is in history' : ''}'
                                '\n${formatDateTime(tx.timestampMs)}'
                                '\nHash: ${shortAddress(tx.txId)}',
                              ),
                              isThreeLine: true,
                              trailing: StatusChip(status: tx.status),
                              onTap: () => _showDetails(tx),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
