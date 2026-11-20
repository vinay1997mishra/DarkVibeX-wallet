// USDT Wallet — starter app for Vinay.
// USDT (TRC20) on Tron. Default network: Nile testnet (see lib/config.dart).

import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import 'screens/buy_screen.dart';
import 'screens/create_wallet_screen.dart';
import 'screens/home_screen.dart';
import 'screens/import_wallet_screen.dart';
import 'screens/owner_login_screen.dart';
import 'services/buy_link.dart';
import 'services/wallet_service.dart';
import 'widgets/secret_owner_tap.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // Navigator key — WalletGate buy link se BuyScreen khol sake.
  static final navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'USDT Wallet',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF26A17B), // Tether green
        ),
        useMaterial3: true,
      ),
      home: const WalletGate(),
    );
  }
}

/// Decides the first screen: Home if a wallet is saved, otherwise
/// a welcome screen with Create / Import.
class WalletGate extends StatefulWidget {
  const WalletGate({super.key});

  @override
  State<WalletGate> createState() => _WalletGateState();
}

class _WalletGateState extends State<WalletGate> {
  final _walletService = WalletService();
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;
  bool? _hasWallet;

  /// Buy link se aaye options — wallet banne se pehle link aaye to
  /// yahan save rehta hai, wallet ready hote hi Buy screen khulti hai.
  BuyLinkParams? _pendingBuyParams;

  @override
  void initState() {
    super.initState();
    _checkWallet();
    _listenBuyLinks();
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  /// Shareable buy link suno: darkvibex-wallet://buy?country=IN&...
  /// (app khula ho ya link se khula ho — dono). Native intent-filter
  /// (AndroidManifest / Info.plist) lagne ke baad hi link app tak
  /// pahunchega — README me snippet hai.
  Future<void> _listenBuyLinks() async {
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _handleBuyLink(initial);
    } catch (_) {
      // Deep link support na ho to app normal khulta hai.
    }
    _linkSubscription = _appLinks.uriLinkStream.listen(
      _handleBuyLink,
      onError: (_) {},
    );
  }

  void _handleBuyLink(Uri uri) {
    final params = BuyLink.parse(uri);
    if (params == null) return;
    if (_hasWallet == true) {
      _openBuy(params);
    } else {
      // Wallet abhi nahi hai — pehle wallet banao/import karo, phir
      // Buy screen khud khul jayegi.
      _pendingBuyParams = params;
    }
  }

  Future<void> _openBuy(BuyLinkParams params) async {
    final tronAddress = await _walletService.getAddress();
    final evmAddress = await _walletService.getEthereumAddress();
    final navigator = MyApp.navigatorKey.currentState;
    if (tronAddress == null ||
        tronAddress.isEmpty ||
        evmAddress.isEmpty ||
        navigator == null) {
      return;
    }
    navigator.push(
      MaterialPageRoute(
        builder: (_) => BuyScreen(
          tronAddress: tronAddress,
          evmAddress: evmAddress,
          initialParams: params,
        ),
      ),
    );
  }

  Future<void> _checkWallet() async {
    final hasWallet = await _walletService.hasWallet();
    if (!mounted) return;
    setState(() {
      _hasWallet = hasWallet;
    });
    // Wallet ready + buy link pending ho to Buy screen kholo.
    final pending = _pendingBuyParams;
    if (hasWallet && pending != null) {
      _pendingBuyParams = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _openBuy(pending));
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasWallet = _hasWallet;
    if (hasWallet == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (hasWallet) {
      // Wallet saved hai to seedha Home — user login sirf seed se
      // hota hai (create/import). Bina seed ke user login nahi hota.
      // Sirf OWNER bina seed ke login kar sakta hai: version text par
      // 7 baar tap se hidden owner login khulta hai, phir PIN/biometric
      // se owner area khulta hai (OwnerLoginScreen dekho).
      return HomeScreen(onWalletDeleted: _checkWallet);
    }
    return WelcomeScreen(onWalletReady: _checkWallet);
  }
}

class WelcomeScreen extends StatelessWidget {
  final VoidCallback onWalletReady;

  const WelcomeScreen({super.key, required this.onWalletReady});

  Future<void> _open(BuildContext context, Widget screen) async {
    final ready = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => screen),
    );
    if (ready == true) onWalletReady();
  }

  void _openOwnerLogin(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const OwnerLoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.account_balance_wallet,
                  size: 72, color: Colors.teal),
              const SizedBox(height: 16),
              const Text(
                'USDT Wallet',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'USDT (TRC20) bhejo aur receive karo.\nPehle testnet par seekho, phir real money.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.grey),
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: () => _open(context, const CreateWalletScreen()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Naya wallet banao',
                    style: TextStyle(fontSize: 18)),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => _open(context, const ImportWalletScreen()),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Purana wallet import karo',
                    style: TextStyle(fontSize: 18)),
              ),
              const SizedBox(height: 40),
              // Version — chhota grey text. Owner login ka secret
              // trigger: is par 7 baar tap karo (5 second ke andar).
              Center(
                child: SecretOwnerTapDetector(
                  onTriggered: () => _openOwnerLogin(context),
                  child: const Text(
                    'Version 0.1.0',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
