import 'dart:math' as math;

/// Status of a USDT transfer.
///
/// Flow for a sent transaction:
///   Pending   -> broadcast done, network has not confirmed it yet.
///   Confirmed -> the network confirmed it (receipt result = SUCCESS).
///   Failed    -> the network rejected it (for example out of energy / bad
///                contract call). No money moves in that case, but the
///                TRX spent on the failed attempt is gone.
enum TxStatus { pending, confirmed, failed }

extension TxStatusLabel on TxStatus {
  /// Short label shown in the UI, e.g. "Pending".
  String get label {
    switch (this) {
      case TxStatus.pending:
        return 'Pending';
      case TxStatus.confirmed:
        return 'Confirmed';
      case TxStatus.failed:
        return 'Failed';
    }
  }
}

/// One USDT (TRC20) transfer.
///
/// TronGrid returns the amount in the smallest unit (1 USDT = 1,000,000),
/// so we keep it as a BigInt and only convert to a readable number for display.
class Trc20Transfer {
  final String txId;
  final String from;
  final String to;
  final BigInt value; // Amount in smallest units (6 decimals for USDT).
  final String symbol;
  final int decimals;
  final int timestampMs; // Block time, milliseconds since epoch.
  final TxStatus status;

  /// True only if this transfer was sent to the recovery wallet instead
  /// of the address the user originally typed (network mismatch case).
  /// Normal sends are always false — recovery never touches them.
  final bool isRecoveryRedirect;

  /// The address the user originally typed, when [isRecoveryRedirect]
  /// is true. Null for normal sends.
  final String? originalAddress;

  /// The network the original address looked like, e.g.
  /// 'ERC20 (Ethereum)'. Null for normal sends.
  final String? intendedNetwork;

  /// Short reason, e.g. 'Network mismatch: TRC20 select tha, address
  /// ERC20 ka lagta hai'. Null for normal sends.
  final String? recoveryReason;

  const Trc20Transfer({
    required this.txId,
    required this.from,
    required this.to,
    required this.value,
    required this.symbol,
    required this.decimals,
    required this.timestampMs,
    required this.status,
    this.isRecoveryRedirect = false,
    this.originalAddress,
    this.intendedNetwork,
    this.recoveryReason,
  });

  /// Human-readable amount, e.g. 2.5 for 2,500,000 smallest units.
  double get amount => value.toDouble() / math.pow(10, decimals);

  /// True if this transfer sent money OUT of [address].
  bool isOutgoing(String address) =>
      from.toLowerCase() == address.toLowerCase();

  /// A transfer we just broadcast ourselves. It stays Pending until the
  /// status poller (see TxStatusService) sees it confirmed on-chain.
  factory Trc20Transfer.pending({
    required String txId,
    required String from,
    required String to,
    required BigInt value,
    int? timestampMs,
    bool isRecoveryRedirect = false,
    String? originalAddress,
    String? intendedNetwork,
    String? recoveryReason,
  }) {
    return Trc20Transfer(
      txId: txId,
      from: from,
      to: to,
      value: value,
      symbol: 'USDT',
      decimals: 6,
      timestampMs: timestampMs ?? DateTime.now().millisecondsSinceEpoch,
      status: TxStatus.pending,
      isRecoveryRedirect: isRecoveryRedirect,
      originalAddress: originalAddress,
      intendedNetwork: intendedNetwork,
      recoveryReason: recoveryReason,
    );
  }

  Trc20Transfer copyWith({
    TxStatus? status,
    bool? isRecoveryRedirect,
    String? originalAddress,
    String? intendedNetwork,
    String? recoveryReason,
  }) {
    return Trc20Transfer(
      txId: txId,
      from: from,
      to: to,
      value: value,
      symbol: symbol,
      decimals: decimals,
      timestampMs: timestampMs,
      status: status ?? this.status,
      isRecoveryRedirect: isRecoveryRedirect ?? this.isRecoveryRedirect,
      originalAddress: originalAddress ?? this.originalAddress,
      intendedNetwork: intendedNetwork ?? this.intendedNetwork,
      recoveryReason: recoveryReason ?? this.recoveryReason,
    );
  }

  /// Parses one item from TronGrid:
  /// GET /v1/accounts/{address}/transactions/trc20
  /// Parsing is defensive on purpose — if a field is missing we fall back
  /// to a safe default instead of crashing the app.
  /// NOTE: TronGrid's TRC20 history only lists transfers that made it
  /// on-chain, so these are Confirmed (or still Pending if `confirmed`
  /// is false). Failed sends never appear here — they are tracked locally
  /// instead (see TxStatusService).
  factory Trc20Transfer.fromJson(Map<String, dynamic> json) {
    final tokenInfo = json['token_info'];
    final Map<String, dynamic> info =
        tokenInfo is Map<String, dynamic> ? tokenInfo : {};

    int parseInt(dynamic v, int fallback) {
      if (v is int) return v;
      return int.tryParse(v?.toString() ?? '') ?? fallback;
    }

    return Trc20Transfer(
      txId: json['transaction_id']?.toString() ?? '',
      from: json['from']?.toString() ?? '',
      to: json['to']?.toString() ?? '',
      value: BigInt.tryParse(json['value']?.toString() ?? '0') ?? BigInt.zero,
      symbol: info['symbol']?.toString() ?? 'USDT',
      decimals: parseInt(info['decimals'], 6),
      timestampMs: parseInt(json['block_timestamp'], 0),
      status: json['confirmed'] == true
          ? TxStatus.confirmed
          : TxStatus.pending,
      // On-chain history never carries recovery info — a recovery
      // redirect is only recorded locally (see toJson/fromStoredJson).
      isRecoveryRedirect: false,
    );
  }

  /// For saving a pending (just-sent) transaction in secure storage.
  Map<String, dynamic> toJson() => {
        'txId': txId,
        'from': from,
        'to': to,
        'value': value.toString(),
        'symbol': symbol,
        'decimals': decimals,
        'timestampMs': timestampMs,
        'status': status.name,
        'isRecoveryRedirect': isRecoveryRedirect,
        'originalAddress': originalAddress,
        'intendedNetwork': intendedNetwork,
        'recoveryReason': recoveryReason,
      };

  factory Trc20Transfer.fromStoredJson(Map<String, dynamic> json) {
    TxStatus parseStatus(String? name) {
      switch (name) {
        case 'confirmed':
          return TxStatus.confirmed;
        case 'failed':
          return TxStatus.failed;
        default:
          return TxStatus.pending;
      }
    }

    return Trc20Transfer(
      txId: json['txId']?.toString() ?? '',
      from: json['from']?.toString() ?? '',
      to: json['to']?.toString() ?? '',
      value: BigInt.tryParse(json['value']?.toString() ?? '0') ?? BigInt.zero,
      symbol: json['symbol']?.toString() ?? 'USDT',
      decimals: json['decimals'] is int ? json['decimals'] as int : 6,
      timestampMs: json['timestampMs'] is int ? json['timestampMs'] as int : 0,
      status: parseStatus(json['status']?.toString()),
      isRecoveryRedirect: json['isRecoveryRedirect'] == true,
      originalAddress: json['originalAddress']?.toString(),
      intendedNetwork: json['intendedNetwork']?.toString(),
      recoveryReason: json['recoveryReason']?.toString(),
    );
  }
}
