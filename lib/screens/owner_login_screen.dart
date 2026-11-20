// Hidden owner login screen — sirf secret tap sequence se khulti hai
// (version text par 7 baar tap, 5 second ke andar — SecretOwnerTapDetector).
// Normal user ko is screen ka app me kahin koi button, hint ya text
// nahi dikhta.
//
//   - Owner PIN set nahi hai -> pehle PIN set karo (4-6 digit).
//   - PIN set hai -> PIN dalo ya fingerprint/Face ID (agar on hai).
// Bina PIN/biometric ke owner area kabhi nahi khulta — is screen se
// aage badhne ka koi aur rasta nahi hai.
//
// Unlock hone par Owner Accounts screen khulti hai (already unlocked,
// dobara PIN nahi maanga jata). Wahan se Recovery Wallet bhi khulta hai.
// Koi server nahi — lock poora local hai (OwnerLockService).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/owner_lock_service.dart';
import 'owner_accounts_screen.dart';

class OwnerLoginScreen extends StatefulWidget {
  const OwnerLoginScreen({super.key});

  @override
  State<OwnerLoginScreen> createState() => _OwnerLoginScreenState();
}

class _OwnerLoginScreenState extends State<OwnerLoginScreen> {
  final _lock = OwnerLockService();

  final _pinController = TextEditingController();
  final _pinConfirmController = TextEditingController();
  final _unlockPinController = TextEditingController();

  bool? _hasPin;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  bool _busy = false;
  String? _error;

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
    final hasPin = await _lock.hasPin();
    final biometricEnabled = hasPin && await _lock.isBiometricEnabled();
    final biometricAvailable = hasPin && await _lock.canUseBiometric();
    if (!mounted) return;
    setState(() {
      _hasPin = hasPin;
      _biometricEnabled = biometricEnabled;
      _biometricAvailable = biometricAvailable;
    });
    if (biometricEnabled && biometricAvailable) {
      await _unlockWithBiometric();
    }
  }

  Future<void> _setupPin() async {
    final pin = _pinController.text.trim();
    final confirm = _pinConfirmController.text.trim();
    if (!OwnerLockService.isValidPin(pin)) {
      setState(() => _error = 'PIN 4-6 digit ka hona chahiye.');
      return;
    }
    if (pin != confirm) {
      setState(() => _error = 'Dono PIN same hone chahiye.');
      return;
    }
    try {
      await _lock.setPin(pin);
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _error = e.toString().replaceFirst('Exception: ', ''),
      );
      return;
    }
    _openOwnerAccounts();
  }

  Future<void> _unlockWithPin() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await _lock.verifyPin(_unlockPinController.text.trim());
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      _openOwnerAccounts();
    } else {
      setState(() => _error = 'Galat PIN. Dobara try karo.');
    }
  }

  Future<void> _unlockWithBiometric() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await _lock.authenticateWithBiometric(
      reason: 'Owner login ke liye verify karo',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      _openOwnerAccounts();
    } else {
      setState(() => _error = 'Biometric fail hua — PIN se login karo.');
    }
  }

  void _openOwnerAccounts() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => const OwnerAccountsScreen(alreadyUnlocked: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasPin = _hasPin;
    return Scaffold(
      appBar: AppBar(title: const Text('Owner Login')),
      body: hasPin == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.lock, size: 56, color: Colors.teal),
                  const SizedBox(height: 16),
                  Text(
                    hasPin
                        ? 'Owner login ke liye PIN dalo ya biometric se verify karo.'
                        : 'Pehli baar owner login — owner PIN set karo. '
                            'Yehi PIN aage se owner area kholne ke liye '
                            'chahiye hoga.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15),
                  ),
                  const SizedBox(height: 20),
                  if (!hasPin) ...[
                    TextField(
                      controller: _pinController,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
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
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      maxLength: 6,
                      decoration: const InputDecoration(
                        labelText: 'PIN dobara likho',
                        border: OutlineInputBorder(),
                        counterText: '',
                      ),
                    ),
                  ] else ...[
                    TextField(
                      controller: _unlockPinController,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      maxLength: 6,
                      decoration: const InputDecoration(
                        labelText: 'Owner PIN (4-6 digit)',
                        border: OutlineInputBorder(),
                        counterText: '',
                      ),
                      onSubmitted: (_) => _unlockWithPin(),
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (_error != null)
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  if (_error != null) const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _busy
                        ? null
                        : (hasPin ? _unlockWithPin : _setupPin),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: Text(
                      hasPin ? 'Login karo' : 'PIN set karo',
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
                  if (hasPin &&
                      _biometricEnabled &&
                      _biometricAvailable) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _unlockWithBiometric,
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('Fingerprint / Face ID se login karo'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
