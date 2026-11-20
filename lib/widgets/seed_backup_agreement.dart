// Seed backup agreement card — wallet creation (aur import) par dikhta hai.
//
// FINAL RULE — text bilkul waisa hi jaisa final hua tha, paraphrase nahi.
// Wording SeedBackupPolicy ke constants se aati hai (single source).
//
// Flow:
//   1. Pehla tick (main agreement) — iske bina dusra tick dikhta hi nahi.
//   2. Pehla tick lagte hi dusra tickmark show hota hai — usme seed-backup
//      note likha hota hai, SEPARATELY aur OPENLY (terms me chhupa nahi):
//      PERMANENT, sirf owner dekh sakta hai, dusre users nahi, delete/skip
//      ka option.
//   3. Aage badhne ke liye (tick 1 + tick 2) ya Skip — Skip ka matlab:
//      NO seed backup, seed server par save NAHI hogi.

import 'package:flutter/material.dart';

import '../services/seed_backup_service.dart';

/// Agreement card. [onChanged] har tick/skip par naya [SeedBackupChoice]
/// deta hai — parent (Create/Import screen) Save button isi se enable karta hai.
class SeedBackupAgreementCard extends StatefulWidget {
  final ValueChanged<SeedBackupChoice> onChanged;

  const SeedBackupAgreementCard({super.key, required this.onChanged});

  @override
  State<SeedBackupAgreementCard> createState() =>
      _SeedBackupAgreementCardState();
}

class _SeedBackupAgreementCardState extends State<SeedBackupAgreementCard> {
  SeedBackupChoice _choice = const SeedBackupChoice();

  void _update(SeedBackupChoice next) {
    setState(() => _choice = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final choice = _choice;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(),
        const Text(
          'Agreement',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        // Tick 1 — main agreement.
        CheckboxListTile(
          value: choice.agreedMain,
          onChanged: (v) => _update(
            choice.copyWith(
              agreedMain: v ?? false,
              // Tick 1 hatate hi tick 2 aur skip dono hat jate hain.
              agreedBackup: false,
              skipped: false,
            ),
          ),
          title: const Text(
            'Main is agreement se sehmat hoon: wallet banega hi seed se, '
            'without Gmail and any other proofs. Apne 12 words ki zimmedari '
            'meri hai — words kho gaye to paise wapas nahi milenge.',
          ),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
        ),
        // Tick 2 — pehle tick ke BAAD hi show hota hai (skip par nahi).
        if (choice.agreedMain && !choice.skipped) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.teal.withValues(alpha: 0.08),
              border: Border.all(color: Colors.teal),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Seed backup note — alag se, khul kar padho:',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                // Final rule — verbatim, SeedBackupPolicy se.
                ...SeedBackupPolicy.ruleLines.map(
                  (line) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('• $line', style: const TextStyle(fontSize: 14)),
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.teal.withValues(alpha: 0.08),
                  child: Text(
                    '"${SeedBackupPolicy.exactNotice}"',
                    style: const TextStyle(
                      fontSize: 14,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Seed backup PERMANENT save rehti hai, sirf tumhari marzi '
                  'se. Backup sirf OWNER dekh sakta hai — dusre users nahi '
                  'dekh sakte. Seed server par encrypted save hoti hai, '
                  'plain text me kabhi nahi. Tum backup delete bhi kar '
                  'sakte ho.',
                  style: TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          CheckboxListTile(
            value: choice.agreedBackup,
            onChanged: (v) =>
                _update(choice.copyWith(agreedBackup: v ?? false)),
            title: const Text(
              'Maine seed-backup note padh liya hai aur main sehmat hoon: '
              'meri seed backup server par PERMANENT save rahegi.',
            ),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
        ],
        // Skip — NO seed backup.
        TextButton(
          onPressed: choice.skipped
              ? null
              : () => _update(
                    const SeedBackupChoice(
                      agreedMain: true,
                      skipped: true,
                    ),
                  ),
          child: Text(
            choice.skipped
                ? 'Skip kiya — seed backup save NAHI hogi'
                : 'Skip karo — bina seed backup ke aage badho',
          ),
        ),
        if (choice.skipped)
          TextButton(
            onPressed: () => _update(const SeedBackupChoice()),
            child: const Text('Skip wapas lo — dobara choose karo'),
          ),
      ],
    );
  }
}
