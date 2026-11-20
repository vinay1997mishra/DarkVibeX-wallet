import 'package:flutter/material.dart';

import '../services/seed_backup_service.dart';
import '../services/wallet_service.dart';
import '../widgets/seed_backup_agreement.dart';

/// Step 1: show the new 12 words. Step 2: user writes them down.
/// Step 3: only then the wallet is saved.
/// The words are NEVER saved before the user confirms writing them down.
class CreateWalletScreen extends StatefulWidget {
  const CreateWalletScreen({super.key});

  @override
  State<CreateWalletScreen> createState() => _CreateWalletScreenState();
}

class _CreateWalletScreenState extends State<CreateWalletScreen> {
  final _walletService = WalletService();
  final _seedBackupService = SeedBackupService();
  NewWalletPreview? _preview;
  bool _wroteDown = false;
  bool _saving = false;
  String? _error;

  /// Agreement ke 2 tickmarks + Skip (SeedBackupAgreementCard se).
  /// Bina (tick 1 + tick 2) ya Skip ke Save nahi hota.
  SeedBackupChoice _choice = const SeedBackupChoice();

  void _generate() {
    setState(() {
      _preview = _walletService.generatePreview();
      _wroteDown = false;
      _error = null;
    });
  }

  Future<void> _save() async {
    final preview = _preview;
    if (preview == null || !_wroteDown || !_choice.canProceed || _saving) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final address = await _walletService.saveWallet(preview.mnemonic);
      // Naya wallet = purana logout record khatam.
      await _seedBackupService.clearLogoutRecord();
      // Seed backup: sirf tab jab user ne dono tick lagaye hon.
      // Skip = NO backup, seed server par save NAHI hoti.
      final backupStatus = await _seedBackupService.saveBackup(
        mnemonic: preview.mnemonic,
        address: address,
        choice: _choice,
      );
      if (!mounted) return;
      if (backupStatus == SeedBackupStatus.saved ||
          backupStatus == SeedBackupStatus.skipped) {
        Navigator.of(context).pop(true); // wallet ready -> Home screen
        return;
      }
      // Server set nahi / upload fail — wallet ban gaya hai, lekin backup
      // save NAHI hui. Ye sach user ko dikhaye bina aage mat badho.
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Seed backup was not saved'),
          content: Text(
            backupStatus == SeedBackupStatus.notConfigured
                ? 'The seed backup server is not set up yet, so the backup '
                    'was NOT saved on the server. Your wallet has been created — '
                    'write down your 12 words on paper and keep them in a safe place.'
                : 'The seed backup could not be uploaded (server/network problem). '
                    'Your wallet has been created — write down your 12 words on paper '
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
      if (mounted) setState(() => _saving = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return Scaffold(
      appBar: AppBar(title: const Text('Create a new wallet')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'These 12 words are the key to your wallet. Write them down on paper '
              'and keep them in a safe place. Anyone who knows these words '
              'can take your money.',
              style: TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 8),
            const Text(
              'Do not send these words in a screenshot or in a message to anyone.',
              style:
                  TextStyle(fontSize: 14, color: Colors.red, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            if (preview == null)
              ElevatedButton(
                onPressed: _generate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Generate 12 words', style: TextStyle(fontSize: 18)),
              )
            else ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: preview.mnemonic
                    .split(' ')
                    .asMap()
                    .entries
                    .map(
                      (e) => Chip(
                        label: Text('${e.key + 1}. ${e.value}'),
                        backgroundColor: Colors.teal.withOpacity(0.1),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 16),
              SelectableText(
                'Address: ${preview.address}',
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                value: _wroteDown,
                onChanged: (v) => setState(() => _wroteDown = v ?? false),
                title: const Text('I have written down the 12 words on paper.'),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              // Agreement: pehla tick, phir dusra tick (seed-backup note),
              // ya Skip (NO seed backup). Bina iske Save nahi hota.
              SeedBackupAgreementCard(
                onChanged: (choice) => setState(() => _choice = choice),
              ),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: Colors.red)),
              if (_error != null) const SizedBox(height: 8),
              ElevatedButton(
                onPressed: (_wroteDown && _choice.canProceed && !_saving)
                    ? _save
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text('Save and get started',
                        style: TextStyle(fontSize: 18)),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _generate,
                child: const Text('Generate new words'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
