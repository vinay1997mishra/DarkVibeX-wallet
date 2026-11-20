/// Small display helpers shared by the screens.
library;

String formatUsdt(double amount) {
  final s = amount.toStringAsFixed(6);
  return s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
}

String shortAddress(String address) {
  if (address.length <= 12) return address;
  return '${address.substring(0, 6)}...${address.substring(address.length - 4)}';
}

String formatDateTime(int timestampMs) {
  if (timestampMs <= 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(timestampMs);
  final day = d.day.toString().padLeft(2, '0');
  final month = d.month.toString().padLeft(2, '0');
  final hour = d.hour.toString().padLeft(2, '0');
  final min = d.minute.toString().padLeft(2, '0');
  return '$day/$month/${d.year} $hour:$min';
}
