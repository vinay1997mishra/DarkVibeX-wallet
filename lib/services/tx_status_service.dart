// Watches sent transactions until they turn Confirmed (or Failed).
//
// How it works:
//   1. When you send USDT, the transaction hash is saved in secure storage
//      as "pending". The Home screen shows it as Pending straight away.
//   2. A timer checks the status on TronGrid every 10 seconds
//      (see [pollInterval]). Tron usually confirms in 3-10 seconds.
//   3. As soon as the status is Confirmed, the timer stops, the pending
//      entry is deleted, and the caller refreshes the balance + history.
//      That is how the balance auto-updates after a payment arrives.
//   4. If the app is closed and opened again, pending transactions are
//      still in storage, so Home re-checks them on start.
//
// A failed transaction also stops the timer — the money never moved,
// only the small TRX fee for the attempt is gone.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/transaction_model.dart';
import 'trongrid_service.dart';

class TxStatusService {
  final TronGridService _api;

  TxStatusService({TronGridService? api}) : _api = api ?? TronGridService();

  /// Check status every 10 seconds.
  static const Duration pollInterval = Duration(seconds: 10);

  /// Stop polling after ~3 minutes. After that the user can pull to refresh
  /// on the History screen — the transaction is still tracked in storage.
  static const int maxPollAttempts = 18;

  static const _storage = FlutterSecureStorage();
  static const _kPendingTxs = 'usdt_pending_txs'; // JSON list of transfers

  // ---------------------------------------------------------------------------
  // Pending transactions saved on the phone
  // ---------------------------------------------------------------------------

  Future<List<Trc20Transfer>> getPendingTxs() async {
    final raw = await _storage.read(key: _kPendingTxs);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map<String, dynamic>>()
          .map(Trc20Transfer.fromStoredJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> savePendingTx(Trc20Transfer tx) async {
    final current = await getPendingTxs();
    if (current.any((t) => t.txId == tx.txId)) return; // already saved
    current.add(tx);
    await _storage.write(
      key: _kPendingTxs,
      value: jsonEncode(current.map((t) => t.toJson()).toList()),
    );
  }

  Future<void> removePendingTx(String txId) async {
    final current = await getPendingTxs();
    current.removeWhere((t) => t.txId == txId);
    await _storage.write(
      key: _kPendingTxs,
      value: jsonEncode(current.map((t) => t.toJson()).toList()),
    );
  }

  // ---------------------------------------------------------------------------
  // Status check + polling
  // ---------------------------------------------------------------------------

  /// One status check for [txId] (Pending / Confirmed / Failed).
  Future<TxStatus> fetchStatus(String txId) => _api.getTransactionStatus(txId);

  /// Polls [txId] every [pollInterval] and calls [onUpdate] on every check.
  /// Stops by itself when the status becomes Confirmed/Failed, or after
  /// [maxPollAttempts] tries. Returns the Timer — cancel it when the
  /// screen is closed (see HomeScreen.dispose).
  Timer pollTxStatus(String txId, void Function(TxStatus status) onUpdate) {
    var attempts = 0;
    var checking = false;
    return Timer.periodic(pollInterval, (timer) async {
      if (checking) return; // never run two checks at the same time
      checking = true;
      try {
        attempts++;
        final status = await fetchStatus(txId);
        onUpdate(status);
        if (status != TxStatus.pending || attempts >= maxPollAttempts) {
          await removePendingTx(txId);
          timer.cancel();
        }
      } finally {
        checking = false;
      }
    });
  }
}
