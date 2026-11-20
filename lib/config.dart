// Network settings for the USDT wallet.
//
// HOW TO SWITCH NETWORK:
//   Change ONE line below: `currentNetwork = TronNetwork.mainnet;`
//   That is all. Every screen and service reads from here.
//
// WHY TRON (TRC20) IS THE DEFAULT:
//   - A USDT transfer on Tron costs about $1-2 in fees.
//   - The same transfer on Ethereum (ERC20) usually costs $5-20.
//   - TRC20 is the most used USDT network in India.
//   To add Ethereum later you would need a different stack (web3dart +
//   an Ethereum RPC), so this starter stays Tron-only on purpose.

enum TronNetwork { mainnet, nile }

class TronConfig {
  // *** START HERE: testnet first, mainnet only when you are ready. ***
  static const TronNetwork currentNetwork = TronNetwork.nile;

  static bool get isTestnet => currentNetwork == TronNetwork.nile;

  static String get networkName =>
      isTestnet ? 'Nile Testnet' : 'Mainnet';

  /// TronGrid API address for the current network.
  static String get baseUrl => isTestnet
      ? 'https://nile.trongrid.io'
      : 'https://api.trongrid.io';

  /// USDT token contract on the current network.
  ///
  /// Mainnet address is the official Tether contract (TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t).
  /// Nile testnet address is TXYZopYRdj2D9XRtbG411XZZ3kM5VkAeBf.
  /// WARNING: some older guides list a different Nile address
  /// (TXLAQ63Xg1NAzckPwKHvzw7CSEmLMEqcdj). Always confirm the test
  /// contract on nile.tronscan.org before you send anything.
  static String get usdtContract => isTestnet
      ? 'TXYZopYRdj2D9XRtbG411XZZ3kM5VkAeBf' // USDT on Nile testnet
      : 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t'; // USDT on mainnet (official)

  /// USDT has 6 decimals: 1 USDT = 1,000,000 smallest units.
  static const int usdtDecimals = 6;

  /// Maximum fee the app allows for one transfer, in SUN (1 TRX = 1,000,000 SUN).
  /// 100 TRX is only the limit — a normal TRC20 transfer burns much less
  /// (usually TRX for energy + a little bandwidth). On Nile, faucet TRX pays it.
  static const int feeLimitSun = 100000000;

  // TODO: PASTE YOUR FREE TRONGRID API KEY HERE.
  // How to get one (free, 2 minutes):
  //   1. Go to https://www.trongrid.io and sign up.
  //   2. Open the dashboard -> API Keys -> create a key.
  //   3. Paste it between the quotes below.
  // Without a key the app still works, but TronGrid limits you to very
  // few requests per second. With the free key you get 100,000 requests/day.
  // NEVER commit a real mainnet key to a public repo.
  static const String tronGridApiKey = '';

  // ---------------------------------------------------------------------------
  // RECOVERY WALLET (special wallet) — safety net for wrong-network sends.
  // ---------------------------------------------------------------------------
  // NO external address is pasted here. The recovery wallet lives
  // INSIDE this app (see lib/services/recovery_wallet_service.dart):
  // it has its own 12-word seed, its own Tron address and its own
  // private key, saved in secure storage under DIFFERENT keys from the
  // main wallet — so the two wallets can never get mixed up.
  //
  // Kya karta hai ye?
  //   - Sahi address + sahi network ho to kuch nahi badalta: paise seedha
  //     usi address par jate hain, recovery wallet ko chhua bhi nahi jata.
  //   - Sirf jab network mismatch dikhe (jaise TRC20 select hai lekin
  //     address 0x... ERC20 ka hai), tabhi Send popup me do button
  //     aate hain: [Recovery wallet me bhejo] aur
  //     [Phir bhi usi address par bhejo]. Pehla dabane par paise
  //     in-app recovery wallet par jate hain — galat address par nahi.
  //   - Ye sirf isliye kaam karta hai kyunki app transaction ko SIGN
  //     karne se PEHLE destination badal deti hai. Blockchain khud
  //     kabhi redirect nahi karta: ek baar sign + broadcast ho gaya,
  //     to paise usi address par jate hain jo transaction me likha hai.
  //   - Recovery wallet SIRF OWNER khol sakta hai — owner PIN +
  //     biometric lock (lib/services/owner_lock_service.dart,
  //     lib/screens/recovery_wallet_screen.dart). Bina PIN/biometric
  //     ke uska balance, address, seed ya history kuch nahi dikhta.
  //   - Agar recovery wallet abhi banaya hi nahi gaya, to
  //     [Recovery wallet me bhejo] button disabled rehta hai
  //     ("Recovery wallet set nahi hai") aur user sirf usi address
  //     par bhej sakta hai — ya Cancel kar sakta hai.
  //   - Recovery wallet me aaye paise wapas dene ka tareeka README me
  //     likha hai (user support ko transaction hash dega, owner
  //     recovery wallet khol kar uske sahi address par wapas bhejega).
  //
  // NOTE for the owner: recovery wallet ka seed SIRF tumhare paas safe
  // rahe. Usi seed se paise wapas milenge — PIN bhool jao to seed se
  // PIN dobara set kar sakte ho, lekin seed bhi kho gaya to paise
  // hamesha ke liye gaye.

  /// Link to a transaction on the explorer for the current network.
  static String txExplorerUrl(String txId) => isTestnet
      ? 'https://nile.tronscan.org/#/transaction/$txId'
      : 'https://tronscan.org/#/transaction/$txId';
}

// ---------------------------------------------------------------------------
// SWAP (Exchange) — USDT <-> TRX on Tron via SunSwap V2, testnet first.
// ---------------------------------------------------------------------------
/// Swap / exchange settings. Sab kuch yahin se badalta hai.
///
/// OWNER PROFIT (service fee) — PERMANENT 0.09% (Vinay final, 2026-11-20).
///   Ye fee kabhi badalni nahi hai — na 0.5% wapas, na koi aur rate.
///   Har swap par [swapServiceFeePercent] fee lagti hai (0.09%).
///   Fee USI COIN me kat-ti hai jo swap ho raha hai — jaise 100 USDT
///   swap karo to 0.09 USDT fee, aur sirf 99.91 USDT swap hota hai.
///   TRX swap karo to fee TRX me kategi. Alag coin (BNB ya koi aur)
///   me fee nahi lagti — user ko fee ke liye alag coin nahi chahiye.
///   Fee ka paisa kahan jata hai:
///   - Agar [ownerFeeWalletAddress] set hai (tumhara TRC20 address), to
///     swap confirm hote hi fee alag se us address par bhej di jati hai
///     (usi coin me — USDT ho to USDT, TRX ho to TRX).
///   - Agar khaali hai (default), to fee COLLECT NAHI HOTI — fee ka hissa
///     user ke wallet me hi rehta hai (usne kam swap kiya). UI me ye saaf
///     likha hota hai, taaki koi galat profit na dikhe.
///   Network fee (TRX gas) alag hai — wo Tron ko jata hai, owner ko nahi.
class SwapConfig {
  /// Service fee, fraction me: 0.0009 = 0.09% (PERMANENT — Vinay final).
  /// Screen par % me dikhta hai. Fee usi coin me kategi jo swap ho
  /// raha hai (From coin) — alag coin nahi chahiye.
  static const double swapServiceFeePercent = 0.0009;

  /// Slippage: rate thoda badal jaye to bhi swap chalega, is % tak.
  /// 0.01 = 1%. Min. receive = estimated * (1 - slippage).
  static const double swapSlippagePercent = 0.01;

  /// Owner ka fee wallet (TRC20 address, T... se shuru).
  /// TODO: Apna TRC20 address yahan paste karo — tabhi swap fee tumhe
  /// milegi. Khaali chhoda to fee collect nahi hogi (README dekho).
  /// Ise kabhi public repo me mainnet address ke saath commit mat karo
  /// jab tak tum ye public karna na chaho — ye sirf fee receive karta
  /// hai, isse paise nikaale nahi ja sakte, phir bhi address public
  /// karna tumhari marzi hai.
  static const String ownerFeeWalletAddress = '';

  /// SunSwap V2 router — USDT<->TRX swap execute karne ke liye.
  /// Mainnet / Nile addresses sunswapteam/sunswap2.0-contracts repo ki
  /// deployment table se liye gaye hain (2026-11-19 ko check kiye).
  /// ⚠️ PEHLE SWAP SE PEHLE tronscan.org par VERIFY kar lo — router
  /// address galat hua to swap fail hoga (paise nahi jayenge, sirf
  /// thodi TRX fee jalegi). Ek line yahin badalni hai agar alag ho.
  static String get sunSwapRouter => TronConfig.isTestnet
      ? 'TMn1qrmYUMSTXo9babrJLzepKZoPC7M6Sy' // SunSwap V2 router, Nile
      : 'TNJVzGqKBWkJxJB5XYSqGAwUTV15U24pPq'; // SunSwap V2 router, mainnet

  /// Wrapped TRX (WTRX) — TRX ko swap path me use karne ke liye.
  /// Mainnet / Nile addresses SunSwap V3 docs (DeepWiki) se liye gaye
  /// hain — V2 ke liye bhi WTRX yahi hota hai, phir bhi Tronscan par
  /// verify kar lo (router address wali warning yahan bhi lagu hai).
  static String get wtrxContract => TronConfig.isTestnet
      ? 'TYsbWxNnyTgsZaTFaue9hqpxkU3Fkco94a' // WTRX, Nile
      : 'TNUC9Qb1rRpS5CbWLmNMxXBjyFoydXjWFR'; // WTRX, mainnet

  /// Swap confirm hone ka wait (approve ke baad) — zyada se zyada.
  static const Duration approveWaitTimeout = Duration(seconds: 60);
}

// ---------------------------------------------------------------------------
// MONTHLY WALLET FEE — $0.01 FLAT per month (Vinay final, 2026-11-20).
// Pehle 0.001% socha tha, phir Vinay ne flat $0.01 kar diya.
// ---------------------------------------------------------------------------
/// Monthly wallet fee — har mahine $0.01 FLAT, balance se koi lena-dena
/// nahi (100 USDT ho ya 10,000 USDT, fee wahi $0.01).
///
///   - Kitni: $0.01 per month = **0.01 USDT** (USDT dollar se pegged
///     hai, isliye $0.01 = 0.01 USDT).
///   - Kis par: main wallet ke USDT balance par (Tron USDT).
///   - Kab: har mahine ke **aakhri din** (month-end), us mahine ki fee.
///   - Kahan jayegi: owner fee wallet
///     ([SwapConfig.ownerFeeWalletAddress] — wahi address jahan swap
///     fee jati hai). Address khaali ho to fee collect nahi hoti.
///   - User ko pehle se dikhe: Home screen par fee card me — kitni,
///     kab, kis coin me — sab saaf likha hota hai.
///
/// ⚠️ HONEST LIMIT — DEDUCTION ABHI AUTOMATIC NAHI HOTA:
///   Bina server ke app khud user ke on-chain balance se fee NAHI kaat
///   sakta — blockchain se paise nikalne ke liye ya to user ko signed
///   transaction karni padti hai, ya custodial server chahiye. Isliye
///   app abhi sirf fee CALCULATE karke dikhata hai (kitni + kab) —
///   balance se kuch kaat-ta NAHI hai, aur koi fake deduction, fake
///   history ya fake "fee paid" kabhi nahi dikhata. Asli deduction ke
///   liye server/custodial step banega, tab ye note update hoga.
///   (Calculation: lib/services/monthly_fee_service.dart dekho.)
class MonthlyFeeConfig {
  /// Flat monthly fee, USDT me: 0.01 USDT = $0.01.
  static const double monthlyFeeUsdt = 0.01;

  /// Fee kis coin me: USDT.
  static const String feeCoinSymbol = 'USDT';

  /// Fee kab: har mahine ke aakhri din.
  static const String feeDueRule = 'Har mahine ke aakhri din';
}

// ---------------------------------------------------------------------------
// SEED BACKUP + AGREEMENT POLICY — Vinay FINAL (2026-11-20).
// Final rule, bilkul waisa hi jaisa final hua tha (paraphrase nahi):
//   - Wallet banega hi seed se, without Gmail and any other proofs.
//   - Seed server par PERMANENT rahegi (3 months tak nahi, permanent).
//   - Verification ONLY by the real original phone the wallet was created
//     on (same device).
//   - Real user ko seed owner se sirf 3 months ke andar milegi, AFTER
//     wallet logout (logout day se 3 months, wallet creation day se
//     nahi); uske baad owner kisi ko seed nahi dega, seed server par
//     saved rehne ke baad bhi.
//   - Agreement me 2 tickmarks — pehla agreement tick, uske baad dusra
//     tickmark show hoga usme seed-backup note likha hoga.
//   - "Your seed backup is saved. If you forget your seed, prove you are
//     a real user from your original phone and get your login back within
//     3 months after logout."
// Poora rule + enforcement: lib/services/seed_backup_service.dart
// (SeedBackupPolicy — wahi single source hai, yahan dobara mat likho).
// Server stub: server/seed-backup-worker.js (STUB — deploy nahi hua).
// ---------------------------------------------------------------------------
/// Seed backup server settings. Khaali = server set nahi hai.
///
///   - [backupApiBaseUrl] khaali (default) ho to app seed backup server
///     par save NAHI karta — SeedBackupService `notConfigured` lautata
///     hai aur UI ye sach dikhata hai. Kabhi jhootha "saved" nahi.
///   - URL tabhi dalo jab worker deploy ho gaya ho (README section 6d).
///   - Server par sirf ENCRYPTED seed (ciphertext + IV) jata hai — plain
///     seed kabhi nahi. Backup key sirf phone par rehti hai.
///   - Recovery window: 3 months AFTER wallet logout (logout day se
///     3 months, wallet creation day se nahi). Window ke baad owner
///     kisi ko seed nahi dega, seed server par saved rehne ke baad bhi.
class SeedBackupConfig {
  /// Backup server ka base URL (Cloudflare Worker). Khaali = set nahi hai.
  /// TODO: Worker deploy karne ke baad yahan URL paste karo, jaise
  /// `https://seed-backup.example.workers.dev`.
  /// Real URL / token kabhi public repo me commit mat karo.
  static const String backupApiBaseUrl = '';

  /// Backup endpoint path (POST save, GET recover, DELETE delete).
  static const String backupPath = '/backup';

  /// Seed server par kitne time rehti hai: PERMANENT (3 months tak nahi).
  static const String retention = 'PERMANENT';

  /// Recovery window, logout ke baad: 3 months.
  static const int recoveryWindowMonths = 3;
}

// ---------------------------------------------------------------------------
// EVM NETWORKS — Ethereum (Sepolia testnet pehle) + BNB Smart Chain
// (BSC testnet pehle). Tron ke baad ye doosra aur teesra network hai.
// ---------------------------------------------------------------------------
/// Ek EVM chain ki poori pehchan. ETH aur BNB ka address EK HI hota hai
/// (dono 0x... EVM address hain, ek hi seed se bante hain) — lekin
/// balance, history aur gas har chain par ALAG hota hai. Isliye network
/// switch karte hi address wahi rehta hai, baaki sab badal jata hai.
///
/// TESTNET PEHLE: dono chains testnet par default hain. Mainnet ke liye
/// [isTestnet] ko false karo (neeche ek line) — aur tab bhi pehla
/// transfer chhota test amount se karo.
class EvmChainConfig {
  final String id; // 'ethereum' ya 'bsc'
  final String displayName; // 'Ethereum' / 'BNB Smart Chain'
  final int chainId; // Sepolia 11155111, BSC testnet 97
  final String rpcUrl; // PublicNode free RPC (no key) — rate-limited
  final String explorerBase; // tx link ke liye
  final String explorerApiBase; // history ke liye (Etherscan/BscScan)
  final String gasSymbol; // 'ETH' ya 'BNB'
  final bool isTestnet;

  const EvmChainConfig({
    required this.id,
    required this.displayName,
    required this.chainId,
    required this.rpcUrl,
    required this.explorerBase,
    required this.explorerApiBase,
    required this.gasSymbol,
    required this.isTestnet,
  });

  String txExplorerUrl(String txHash) => '$explorerBase/tx/$txHash';
}

/// Ethereum — default Sepolia TESTNET (chain 11155111).
/// RPC: PublicNode free (https://ethereum-sepolia-rpc.publicnode.com,
/// 2026-11-19 ko verify kiya — eth_chainId 0xaa36a7 deta hai).
/// Apna Infura/Alchemy RPC use karna ho to [rpcUrlOverride] me dalo:
///   Sepolia Infura: https://sepolia.infura.io/v3/<API_KEY>
///   Sepolia Alchemy: https://eth-sepolia.g.alchemy.com/v2/<API_KEY>
class EthereumConfig {
  static const bool isTestnet = true;

  static EvmChainConfig get chain => EvmChainConfig(
        id: 'ethereum',
        displayName: 'Ethereum',
        chainId: isTestnet ? 11155111 : 1,
        rpcUrl: rpcUrlOverride.isNotEmpty
            ? rpcUrlOverride
            : isTestnet
                ? 'https://ethereum-sepolia-rpc.publicnode.com'
                : 'https://ethereum-rpc.publicnode.com',
        explorerBase:
            isTestnet ? 'https://sepolia.etherscan.io' : 'https://etherscan.io',
        explorerApiBase: isTestnet
            ? 'https://api-sepolia.etherscan.io/api'
            : 'https://api.etherscan.io/api',
        gasSymbol: 'ETH',
        isTestnet: isTestnet,
      );

  /// Apna Infura/Alchemy RPC URL yahan dalo (khali = PublicNode free RPC).
  static const String rpcUrlOverride = '';

  /// Etherscan free API key — HISTORY ke liye chahiye (tx list).
  /// Bina key ke balance/send chalta hai, history nahi dikhegi.
  /// Free key: https://etherscan.io/apis (sign up → API Keys).
  static const String etherscanApiKey = '';

  /// USDT ERC20 (Ethereum mainnet) — 0xdAC17F958D2ee523a2206206994597C13D831ec7
  /// (Tether, Etherscan se verify kiya 2026-11-19, 6 decimals).
  /// ⚠️ Sepolia testnet par is contract ka USDT NAHI hai — Sepolia par
  /// sirf ETH balance/send test karo. Mainnet par switch karne par hi
  /// ye contract use hoga (tab bhi pehle chhota test amount).
  static const String usdtErc20Contract =
      '0xdAC17F958D2ee523a2206206994597C13D831ec7';

  /// SHIB ERC20 (Ethereum mainnet) — 0x95aD61b0a150d79219dCF64E1E6Cc01f0B64C4cE
  /// (Etherscan se verify kiya 2026-11-19, 18 decimals). Sepolia par nahi hai.
  static const String shibContract =
      '0x95aD61b0a150d79219dCF64E1E6Cc01f0B64C4cE';
}

/// BNB Smart Chain — default BSC TESTNET (chain 97, tBNB).
/// RPC: PublicNode free (https://bsc-testnet-rpc.publicnode.com,
/// 2026-11-19 ko verify kiya — chain 97, explorer testnet.bscscan.com).
class BscConfig {
  static const bool isTestnet = true;

  static EvmChainConfig get chain => EvmChainConfig(
        id: 'bsc',
        displayName: 'BNB Smart Chain',
        chainId: isTestnet ? 97 : 56,
        rpcUrl: rpcUrlOverride.isNotEmpty
            ? rpcUrlOverride
            : isTestnet
                ? 'https://bsc-testnet-rpc.publicnode.com'
                : 'https://bsc-rpc.publicnode.com',
        explorerBase: isTestnet
            ? 'https://testnet.bscscan.com'
            : 'https://bscscan.com',
        explorerApiBase: isTestnet
            ? 'https://api-testnet.bscscan.com/api'
            : 'https://api.bscscan.com/api',
        gasSymbol: 'BNB',
        isTestnet: isTestnet,
      );

  /// Apna RPC URL yahan dalo (khali = PublicNode free RPC).
  static const String rpcUrlOverride = '';

  /// BscScan free API key — HISTORY ke liye chahiye.
  /// Free key: https://bscscan.com/apis
  static const String bscscanApiKey = '';

  /// USDT BEP20 (BNB mainnet) — Binance-Peg USDT, 18 decimals.
  /// ⚠️ BSC testnet par is contract ka USDT NAHI hai — testnet par
  /// sirf BNB (tBNB) balance/send test karo. Mainnet par switch karne
  /// par hi ye contract use hoga (tab bhi pehle chhota test amount).
  static const String usdtBep20Contract =
      '0x55d398326f99059fF775485246999027B3197955';
}

// ---------------------------------------------------------------------------
// BUY USDT — fiat se USDT kharido (Transak on-ramp, 2026-11-20).
// ---------------------------------------------------------------------------
/// USDT Buy (on-ramp) settings — Transak widget se.
///
///   - Provider: **Transak** — India ke liye UPI deta hai (MoonPay /
///     Banxa / Mercuryo ke comparison me sirf Transak ka UPI tha),
///     aur international: card, Apple Pay, Google Pay, bank transfer.
///   - Payment methods **country ke hisaab se** dikhte hain (Buy screen
///     par country chuno): India = UPI + Card + Bank Transfer; USA/UK/
///     Europe = Card + Apple Pay + Google Pay + Bank Transfer; baaki
///     countries = Card + Apple Pay + Google Pay.
///   - KYC: Transak par pehli baar ID/PAN jaisi details se KYC karni
///     padegi — ye Transak karta hai, app nahi. Bina KYC ke buy nahi hoga.
///   - Fee + final rate: Transak checkout (widget) me dikhte hain — app
///     sirf CoinGecko se ESTIMATE dikhata hai, kabhi final rate nahi.
///   - API KEY: [transakApiKey] khaali (default) ho to Buy button
///     disabled rehta hai aur screen par setup steps dikhte hain — kabhi
///     fake buy nahi. Key Transak Partner Dashboard → Developers se
///     milti hai (staging key pehle, production key KYB ke baad).
///   - ⚠️ DEPRECATED DIRECT URL: Transak ne hosted widget URL me seedha
///     query params dalna deprecated kar diya hai — sahi tareeka backend
///     se Create Widget URL API (api-secret se) hai, jo 5-minute ka
///     single-use widgetUrl deta hai. Is app me abhi koi server/backend
///     nahi hai, isliye app seedha widget URL banata hai (staging test
///     ke liye kaam karta hai). Production me backend session API
///     banana hoga — tab ye section update hoga. API SECRET kabhi app
///     me mat dalo — wo sirf server par rehta hai.
class BuyConfig {
  /// Transak partner API key (public key — code me rakhna safe hai,
  /// Transak ke FAQ ke hisaab se apiKey sensitive nahi hai).
  /// TODO: Transak Partner Dashboard (https://dashboard.transak.com)
  /// → Environment: Staging → Developers → API key yahan paste karo.
  /// Production key tabhi dalo jab KYB approve ho gaya ho.
  /// Khaali = Buy setup nahi hai, button disabled rahega.
  static const String transakApiKey = '';

  /// 'staging' (default, TEST — asli paise nahi lagte) ya 'production'
  /// (REAL — asli paise lagenge, KYC + KYB chahiye).
  /// Staging par Transak ke test card / test PAN se test karo.
  static const String transakEnvironment = 'staging';

  /// Referrer domain (Transak dashboard me allow-listed domain/app).
  /// Staging par enforce nahi hota, phir bhi bharna achha hai.
  /// TODO: apna domain ya app package yahan dalo.
  static const String transakReferrerDomain = '';

  /// Widget base URL — environment ke hisaab se.
  static String get transakWidgetBaseUrl =>
      transakEnvironment == 'production'
          ? 'https://global.transak.com'
          : 'https://global-stg.transak.com';

  /// Buy setup hua ya nahi (key + environment).
  static bool get isConfigured =>
      transakApiKey.isNotEmpty &&
      (transakEnvironment == 'staging' ||
          transakEnvironment == 'production');

  /// Test mode? Staging = test, asli paise nahi lagte.
  static bool get isTestMode => transakEnvironment != 'production';
}
