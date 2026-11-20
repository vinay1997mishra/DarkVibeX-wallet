import 'package:flutter/material.dart';

import '../models/transaction_model.dart';

/// Small coloured badge for a transaction's status.
/// Pending = orange, Confirmed = green, Failed = red.
class StatusChip extends StatelessWidget {
  final TxStatus status;

  const StatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final IconData icon;
    switch (status) {
      case TxStatus.pending:
        color = Colors.orange;
        icon = Icons.hourglass_top;
        break;
      case TxStatus.confirmed:
        color = Colors.green;
        icon = Icons.check_circle;
        break;
      case TxStatus.failed:
        color = Colors.red;
        icon = Icons.error;
        break;
    }
    return Chip(
      label: Text(status.label),
      avatar: Icon(icon, size: 16, color: color),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.bold),
      side: BorderSide(color: color),
      backgroundColor: color.withOpacity(0.1),
      visualDensity: VisualDensity.compact,
    );
  }
}
