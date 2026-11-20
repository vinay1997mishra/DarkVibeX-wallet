import 'package:flutter/material.dart';

import '../services/seed_backup_service.dart';
import '../services/wallet_service.dart';
import '../widgets/seed_backup_agreement.dart';

/// Brings back an existing wallet from its 12-word (or 24-word) phrase.
class ImportWalletScreen extends StatefulWidget {
  const ImportWalletScreen({super.key});

  @override
  State<ImportWalletScreen> createState() => _ImportWalletScreenState();
}

class _ImportWalletScreenState extends State<ImportWalletScreen> {
  final _walletService = WalletService();
  final _seedBackupService = SeedBackupService();
  final _controller = TextEditingController();
  bool _importing = false;
  String? _error;

  /// Agreement ke 2 tickmarks + Skip — create screen jaisa hi.
  SeedBackupChoice _choice = const SeedBackupChoice();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    if (_importing || !_choice.canProceed) return;
    setState(() {
      _importing = true;
      _error = null;
    });
    try {
      final address = await _walletService.saveWallet(_controller.text);
      await _seedBackupService.clearLogoutRecord();
      // Seed backup: sirf tab jab user ne dono tick lagaye hon.
      // Skip = NO backup, seed server par save NAHI hoti.
      final backupStatus = await _seedBackupService.saveBackup(
        mnemonic: _controller.text.trim().split(RegExp(r'\s+')).join(' '),
        address: address,
        choice: _choice,
      );
      if (!mounted) return;
      if (backupStatus == SeedBackupStatus.saved ||
          backupStatus == SeedBackupStatus.skipped) {
        Navigator.of(context).pop(true); // wallet ready -> Home screen
        return;
      }
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Seed backup was not saved'),
          content: Text(
            backupStatus == SeedBackupStatus.notConfigured
                ? 'The seed backup server is not set up yet, so the backup '
                    'was NOT saved on the server. Your wallet has been imported — '
                    'write down your 12 words on paper and keep them in a safe place.'
                : 'The seed backup could not be uploaded (server/network problem). '
                    'Your wallet has been imported — write down your 12 words on paper '
                    'and keep them in a safe place.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('I understand'),
            ),
          ],
        ),
      );
      if (ok == true && mounted) Navigator.of(context).pop(true);
      if (mounted) setState(() => _importing = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _importing = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import wallet')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Enter the 12 words of your old wallet here. If the words are correct, '
              'you will get back the same address and the same balance.',
              style: TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _controller,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: '12 words',
                hintText: 'word1 word2 word3 ...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            // Agreement: pehla tick, phir dusra tick (seed-backup note),
            // ya Skip (NO seed backup). Bina iske Import nahi hota.
            SeedBackupAgreementCard(
              onChanged: (choice) => setState(() => _choice = choice),
            ),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            if (_error != null) const SizedBox(height: 12),
            ElevatedButton(
              onPressed: (_importing || !_choice.canProceed) ? null : _import,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _importing
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Import', style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }
}
