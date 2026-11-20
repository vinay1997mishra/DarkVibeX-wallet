# USDT Wallet App — Flutter Starter

Vinay ke liye banaya gaya starter project: **USDT wallet app**, Flutter me.
Teen networks: **Tron (TRC20), Ethereum (ERC20), BNB Smart Chain (BEP20)**.
Wallet create/import, balance, send, receive, history, transaction status,
**Swap/Exchange**, **Add Custom Token** aur **New Tokens auto-detect** — sab
kuch hai. Home par network switcher hai (Tron / Ethereum / BNB Smart Chain).

> ⚠️ **Ye ek seekhne wala starter hai, production app nahi.**
> Real money dalne se pehle isko testnet par poori tarah test karo, aur
> production me use karne se pehle ek security audit karwana.
> Seed phrase aur private key kabhi kisi ko mat do — na dost ko, na support ko,
> na kisi website/app ko.

---

## 1. Networks: Tron, Ethereum, BNB Smart Chain

| Network | Coin | Fee (lagbhag) | Address | Status |
|---|---|---|---|---|
| **Tron TRC20 (default)** | USDT, TRX | $1–2 | `T...` | Balance, send, receive, history, swap |
| **Ethereum (ERC20)** | ETH, USDT, SHIB | $5–20 (mainnet) | `0x...` | Balance, send, receive, history |
| **BNB Smart Chain (BEP20)** | BNB, USDT | <$1 | `0x...` | Balance, send, receive, history |

- **ETH aur BNB ka address EK HI hota hai** (`0x...`, ek hi seed se banta
  hai — `m/44'/60'/0'/0/0`). Balance, history aur gas fee har chain par
  **alag** hota hai. Tron ka address alag hai (`T...`, `m/44'/195'/0'/0/0`).
- **Sab networks default TESTNET par hain** (`lib/config.dart` me set hai):
  Tron = Nile, Ethereum = Sepolia (chain 11155111), BNB Chain = BSC testnet
  (chain 97). Mainnet ke liye har network ka `isTestnet = false` karo — aur
  tab bhi pehla mainnet transfer **chhota test amount** se karo.
- **Testnet par USDT ERC20 / SHIB / USDT BEP20 ke official contract nahi
  hain** — testnet par sirf native coin (ETH / tBNB) test karo. Mainnet
  contracts config me hain (verify kiye hue): USDT ERC20
  `0xdAC17F958D2ee523a2206206994597C13D831ec7` (6 decimals), SHIB
  `0x95aD61b0a150d79219dCF64E1E6Cc01f0B64C4cE` (18 decimals), USDT BEP20
  `0x55d398326f99059fF775485246999027B3197955` (Binance-Peg, **18 decimals**
  — TRC20 wala USDT 6 decimals ka hota hai, ye alag hai).

### Har network ke liye API key aur testnet steps

| Network | Balance/send | History ke liye | Testnet faucet |
|---|---|---|---|
| Tron (Nile) | TronGrid (free key, `config.dart`) | TronGrid | Nile faucet (nileex.io) — test TRX + test USDT |
| Ethereum (Sepolia) | PublicNode free RPC (no key) — ya apna Infura/Alchemy RPC (`EthereumConfig.rpcUrlOverride`) | **Etherscan free API key** (`EthereumConfig.etherscanApiKey`) — bina key ke history nahi dikhegi | Sepolia faucet (sepoliafaucet.com ya Google Cloud faucet) — test ETH |
| BNB Chain (testnet) | PublicNode free RPC (no key) | **BscScan free API key** (`BscConfig.bscscanApiKey`) — bina key ke history nahi dikhegi | BSC testnet faucet (testnet.bnbchain.org/faucet-smart) — tBNB |

- Etherscan free key: https://etherscan.io/apis (sign up → API Keys).
- BscScan free key: https://bscscan.com/apis
- Gas fee: Ethereum par ETH me, BNB Chain par BNB me lagti hai — send
  screen par gas price dikhta hai. TRX gas ki tarah, gas fee network ko
  jati hai, owner ko nahi.

---

## 2. Chalane ka tareeka (Run)

```bash
cd usdt-wallet-app

# 1) Android/iOS folders banao (starter me sirf Dart code hai)
flutter create .

# 2) Packages download karo
flutter pub get

# 3) Phone/emulator par chalao
flutter run
```

Agar `flutter pub get` me version error aaye to `flutter pub upgrade`
chalao — `pubspec.yaml` me versions 19 Nov 2026 ko pub.dev par check
kiye gaye the (neeche table dekho).

---

## 3. Pehle TESTNET par chalao (Nile) — real money mat dalo

1. **Network Nile hi rehne do** (default). Mainnet tabhi karo jab testnet
   par sab kuch 2–3 baar test kar chuke ho.
2. **Free test TRX + test USDT lo — Nile faucet se:**
   - Nile faucet kholo (nileex.io par "Faucet" dhoondho), apna testnet
     address paste karo. Tumhe test TRX milega (fee ke liye) aur test USDT.
   - Test USDT ka contract: `TXYZopYRdj2D9XRtbG411XZZ3kM5VkAeBf`
   - ⚠️ **Pehle nile.tronscan.org par ye contract verify kar lo.**
     Kuch purane guides me alag address likha hai
     (`TXLAQ63Xg1NAzckPwKHvzw7CSEmLMEqcdj`) — bina verify kiye use mat karo.
3. **Free TronGrid API key lo (2 minute, free):**
   - https://www.trongrid.io par sign up karo → Dashboard → API Keys.
   - Key ko `lib/config.dart` me `tronGridApiKey = '';` ke andar paste karo.
   - Bina key ke bhi app chalta hai, lekin bahut kam requests allowed hain.
     Free key se 100,000 requests/day milte hain.
   - Key ko kabhi public repo me commit mat karo.
4. **Test karo:** wallet banao → faucet se test USDT lo → khud ke dusre
   testnet address par 1 USDT bhejo → status Pending se Confirmed hote
   hue dekho → balance apne aap update hoga.

---

## 4. Kya app khud confirm kar sakta hai? (Vinay ka sawaal)

**Haan — ye sab app khud check karta hai, bhejne se pehle:**

| Check | Kahan | Kya hota hai |
|---|---|---|
| Address format + checksum | Send screen, type karte hi | Tron address T se shuru, 34 chars, sirf Base58 characters, aur sahi checksum. Ek character bhi badla ho to chhoti warning line dikhti hai — Send kabhi block nahi hota. |
| Network mismatch warning | Send screen, prefix se | `T...` = Tron (TRC20), `0x...` = Ethereum (ERC20) / BSC (BEP20). Network galat lage to ek chhoti line: "Network galat lag raha hai, USDT doob sakta hai". Sirf warning — faisla user ka. |
| Address history | Service me ready (`checkAddressUsage`) | TronGrid se check karta hai ki address pehle kabhi use hua hai ya nahi. Send screen par abhi use nahi hota (Vinay ka final call: sirf chhoti warning). Ek line me wapas joda ja sakta hai. |
| Chhota confirm popup | Send dabane par | Ek chhota popup: address, network aur amount ek line me. Network mismatch ho to popup me saaf likha hota hai ki paise Special (Recovery) Wallet me jayenge — Confirm dabate hi AUTOMATIC redirect ho jata hai, galat address par kuch nahi jata. Sahi address ho to normal send hota hai. Koi extra step nahi, koi do-button choice nahi. |

**Lekin ek cheez app KABHI nahi kar sakta — aur ye samajhna sabse important hai:**

> App ye bata sakta hai ki address **sahi format ka hai**.
> App ye **nahi** bata sakta ki address **sahi insaan ka hai**.
>
> Matlab: agar tum galti se kisi **aur ki sahi address** par USDT bhej do
> (format bilkul sahi, checksum bilkul sahi, pehle use bhi hua hua),
> to app use rok nahi sakta — wo address har check pass kar lega.
> **Wo sirf TUM check kar sakte ho** — receiver se pooch kar, ya address
> ko akshar-akshar mila kar.

Isiliye:
- **Blockchain par bheja hua transaction wapas nahi hota.** Na app wapas
  la sakta hai, na Tron, na koi bhi. Galat address = paise gaye.
- **Pehli baar kisi naye address par bhej rahe ho to pehle chhota test
  amount bhejo (jaise 1 USDT).** Jab confirm ho jaye ki sahi insaan ko
  mila, tabhi baaki amount bhejo.
- Bade amount se pehle hamesha receiver se address dobara confirm kar lo.

---

## 5. Transaction status: Pending → Confirmed

Bhejne ke baad transaction ka status dikhta hai:

| Status | Matlab |
|---|---|
| **Pending** (orange) | Broadcast ho gaya, network confirmation ka wait hai. |
| **Confirmed** (green) | Network ne confirm kar diya (receipt SUCCESS). Tron par isme aam taur par 3–10 second lagte hain. |
| **Failed** (red) | Network ne reject kar diya (jaise energy/TRX kam). Paise nahi gaye — sirf try karne ki thodi fee gayi. |

Kaise kaam karta hai:
- Send karte hi transaction hash phone me save ho jata hai (Pending).
- App har 10 second me TronGrid se status check karta hai (polling),
  zyada se zyada ~3 minute tak.
- **Confirm hote hi balance aur history apne aap update ho jate hain** —
  manual refresh ki zaroorat nahi.
- App band karke dobara kholo to bhi pending transaction dobara check
  hota hai (hash secure storage me save rehta hai).
- Home screen par balance har 30 second me apne aap refresh hota hai,
  taaki koi tumhe USDT bheje to wo bhi dikhe. Neeche khinch kar (pull
  to refresh) kabhi bhi turant refresh kar sakte ho.
- History screen me har transaction ka status, hash aur Tronscan link
  dikhta hai. Transaction par tap karo to poora hash + link milega.

---

## 6. Address safety + Special (Recovery) Wallet — FINAL FLOW

Vinay ka final flow, exactly aise:

1. **Chhoti red warning line:** Send screen par address dalte hi, agar
   network galat lag raha hai to field ke neeche ek chhoti red line
   dikhti hai — "Network galat lag raha hai, USDT doob sakta hai".
   **Koi block nahi** — Send button kabhi disable nahi hota.
2. **Automatic redirect:** Warning ke baad bhi user Send dabaye to
   paise us galat address par **NAHI** jayenge — seedha app ke andar
   ke **Special (Recovery) Wallet** me transfer ho jayenge, automatic.
   Send ke baad app saaf dikhata hai: **"Galat network tha, paise
   Special Wallet me gaye hain"** + history me original address aur
   reason note hota hai.
3. **Sahi address + sahi network ho to** paise normal tarike se usi
   address par jayenge — special wallet me nahi, koi redirect nahi.
4. **Do-button choice nahi hai** — flow automatic redirect wala hai.
5. **Fee ke liye TRX:** USDT bhejne par fee TRX me lagti hai. TRX balance
   Send screen par dikhta rehta hai.

### Recovery Wallet kya hai? (in-app special wallet)

- Ye **bahar ka external address nahi hai** — app ke andar hi ek
  alag wallet hai: apna 12-word seed, apna Tron address, apni
  private key. Main wallet se **alag secure-storage keys** se save
  hota hai, dono kabhi mix nahi hote.
- **Sirf OWNER khol sakta hai:** Recovery Wallet screen par owner
  PIN (4-6 digit, pehli baar set karne par) + fingerprint/Face ID
  lock hai. Bina PIN/biometric ke uska balance, address, seed ya
  history **kuch nahi dikhega** — normal user wahan ja hi nahi payega.
- Recovery Wallet banane ke liye: hidden owner login se Owner Accounts
  kholo (Version 0.1.0 par 7 baar tap → PIN/biometric) → **Recovery
  Wallet kholo** → 12 words likh lo → owner PIN set karo. Bas.
- **Paise wapas kaise milenge (claim-back):** user support ko
  transaction hash dega → owner Recovery Wallet khol kar (PIN se)
  hash check karega → **Wapas bhejo** se paise user ke **sahi**
  address par wapas bhej dega.
- **PIN bhool gaye to?** Recovery wallet ke 12 words (seed) se
  verify karke naya PIN set kar sakte ho. **Seed bhi kho gaya to
  recovery wallet kabhi nahi khul payega** — isliye seed ko kagaz
  par likh kar safe jagah rakhna hai, sirf owner ke paas.
- **Ye redirect sirf isliye kaam karta hai kyunki app transaction
  ko SIGN karne se PEHLE destination badal deti hai.** Blockchain
  khud kabhi redirect nahi karta: ek baar sign + broadcast ho gaya,
  to paise usi address par jate hain jo transaction me likha hai.
- Recovery wallet abhi bana hi nahi hai to redirect karne ki jagah
  nahi hai — tab mismatch wale popup me Send button hi nahi aata.
  Pehle Recovery Wallet banao, phir dobara bhejo.

---

## 6a. Login rules — user seed se, owner bina seed ke

- **Normal user: login sirf seed se.** Wallet banana ho to 12-word seed
  milti hai, wapas aana ho to wahi seed dalni padti hai. Bina seed ke
  user login **nahi** hota — PIN/biometric seed login ki jagah nahi lete.
  PIN/biometric sirf app unlock / owner area kholne ke liye hain, seed
  login ke baad.
- **Sirf OWNER bina seed ke login kar sakta hai — hidden owner login:**
  app ki kisi bhi main screen (Welcome, Home) par neeche chhote grey me
  likhe **Version 0.1.0** text par **7 baar tap** karo (5 second ke andar)
  — Owner Login screen khulti hai. Uske baad **PIN ya fingerprint/Face ID**
  se owner area khulta hai. Bina PIN/biometric ke owner login nahi khulta.
- Normal user ko app me kahin bhi \"Owner Login\" ka button, option, hint
  ya text **nahi** dikhta — version par 7 baar tap hone se pehle tap
  karne par kuch nahi hota.
- **Phone/device verification HATA DIYA GAYA hai** — koi phone number
  verification, device fingerprint ya original-phone check ab app me
  nahi hai. Pehle ye feature add hua tha, Vinay ne hatane ko bola, to
  poora remove kar diya gaya (service, screen, tests, `device_info_plus`
  package — sab).
- Koi server nahi — login aur owner lock sab local/on-device hai.

## 6b. Owner accounts — app ke saare accounts, sirf owner ko

Hidden owner login se khulta hai — **Version 0.1.0 par 7 baar tap** →
  PIN/biometric → Owner Accounts screen. Normal user ko iska koi button
  ya menu option nahi dikhta:

- App me stored **sare** wallet accounts ki list — Main Wallet + Recovery
  (Special) Wallet. Import kiya hua wallet Main Wallet ki keys me hi save
  hota hai, isliye wo "Main Wallet" ke roop me aata hai.
- Har account ke liye: address (Tron `T...` + Ethereum/BNB `0x...` — dono
  ek hi seed se), network (Tron / Ethereum / BNB Smart Chain), balance
  (USDT + TRX, ETH, BNB, USDT ERC20/BEP20 — mainnet par), creation date
  (is phone me kab add hua; purane wallet me "pata nahi").
- **Seed / private key sirf owner lock kholne ke baad** dikhte hain —
  per-account "Seed dikhao" button se, default chhupa rehta hai.
- **List bhi lock ke bina nahi khulti** — pehle owner PIN set karo (nahi
  hai to), phir PIN/biometric se kholo. Bina lock ke kuch nahi dikhta.
- Koi server nahi, sab local. **Koi account yahan se delete / change
  nahi hota — sirf view.**

## 6c. Monthly wallet fee — $0.01 FLAT per month

- **Kitni: $0.01 flat per month = 0.01 USDT.** Balance se koi lena-dena
  nahi — 100 USDT ho ya 10,000 USDT, fee wahi 0.01 USDT rahegi.
  (Pehle 0.001% socha tha, Vinay ne flat $0.01 kar diya.)
- **Kab: har mahine ke aakhri din** (month-end), us mahine ki fee.
- **Kis coin me: USDT** (USDT dollar se pegged hai, isliye $0.01 =
  0.01 USDT). Fee **owner fee wallet** me jayegi — wahi address
  (`SwapConfig.ownerFeeWalletAddress`) jahan swap fee jati hai.
  Address khaali ho to fee collect nahi hoti.
- **User ko pehle se saaf dikhta hai:** Home screen par fee card me —
  kitni, kab, kis coin me, kahan jayegi — sab likha hota hai.
- **Honest limit — deduction abhi automatic nahi hota:** bina server ke
  app khud user ke on-chain balance se fee **nahi** kaat sakta
  (blockchain se paise nikalne ke liye signed transaction ya custodial
  server chahiye). Isliye app sirf fee calculate karke dikhata hai —
  balance se kuch kaat-ta nahi, aur koi fake deduction, fake history
  ya fake "fee paid" kabhi nahi dikhata. Asli deduction ke liye
  server/custodial step banega, tab ye section update hoga.
  Calculation: `lib/services/monthly_fee_service.dart`, config:
  `MonthlyFeeConfig` (`lib/config.dart`).

## 6d. Seed backup + agreement policy — FINAL (Vinay, 2026-11-20)

> ⚠️ **Ye text FINAL hai — apne words me badal kar mat likhna.**
> Agreement screen, code comments aur README me yahi wording hai
> (`SeedBackupPolicy` constants — single source).

Final rule:

- Wallet banega hi seed se, without Gmail and any other proofs.
- Seed server par PERMANENT rahegi (3 months tak nahi, permanent).
- Verification ONLY by the real original phone the wallet was created on (same device).
- Real user ko seed owner se sirf 3 months ke andar milegi, AFTER wallet logout (logout day se 3 months, wallet creation day se nahi); uske baad owner kisi ko seed nahi dega, seed server par saved rehne ke baad bhi.
- Agreement me 2 tickmarks — pehla agreement tick, uske baad dusra tickmark show hoga usme seed-backup note likha hoga.
- Exact wording: "Your seed backup is saved. If you forget your seed, prove you are a real user from your original phone and get your login back within 3 months after logout."

### Agreement — 2 tickmarks (wallet create + import, dono par)

1. **Pehla tick (main agreement):** wallet banega hi seed se, without
   Gmail and any other proofs. Iske bina dusra tick dikhta hi nahi.
2. **Dusra tick (seed-backup note):** pehla tick lagte hi show hota hai —
   note SEPARATELY aur OPENLY dikhta hai, terms me chhupa kar nahi.
   Note me likha hota hai: backup PERMANENT save rehti hai, sirf OWNER
   dekh sakta hai (dusre users nahi dekh sakte), seed encrypted save hoti
   hai, aur user backup delete kar sakta hai.
3. **Skip option:** user skip kar sakta hai — Skip ka matlab NO seed
   backup, seed server par save NAHI hoti. Bina (tick 1 + tick 2) ya Skip
   ke wallet create/import nahi hota.

### Seed backup kaise save hoti hai (encrypted, server-side design)

- Seed server par **PLAIN TEXT me kabhi nahi jati** — bhejne se pehle
  phone par **AES-256-CBC (PKCS7, random IV)** se encrypt hoti hai.
  Server par sirf ciphertext + IV + device hash jata hai.
- Backup key (32 random bytes) **sirf is phone ki secure storage** me
  rehti hai — server par kabhi nahi jati, code me kabhi hardcode nahi
  hoti, GitHub par kabhi nahi jati. Key ke bina server par pada
  ciphertext kisi kaam ka nahi.
- **PIN code me kahin store nahi hota** (owner PIN ka hash alag service
  me hai — `lib/services/owner_lock_service.dart`).
- Server config: `SeedBackupConfig.backupApiBaseUrl`
  (`lib/config.dart`) — khaali hai to backup save NAHI hoti, app
  `notConfigured` dikhata hai, kabhi jhootha "saved" nahi.
  Server stub: `server/seed-backup-worker.js` (**STUB — deploy nahi hua**).

### Recovery — logout date + 3-month window + original phone

- **Logout date record hoti hai** — Home se wallet delete/logout karte hi
  (`SeedBackupService.recordLogout`, delete se PEHLE). Naya wallet save
  hote hi purana logout record clear ho jata hai.
- **Window logout day se 3 months hai** — wallet creation day se nahi.
  Deadline = logout date + 3 calendar months (month-end clamp, jaise
  30 Nov → 28 Feb).
- **Verification ONLY by the real original phone the wallet was created on
  (same device)** — device hash match hona chahiye. Seed-only ya koi aur
  proof se recovery NAHI hoti.
- **3 months ke baad owner kisi ko seed nahi dega, seed server par saved
  rehne ke baad bhi.** Ye code me enforce hota hai
  (`SeedBackupPolicy.canDiscloseSeed` / `SeedBackupService.checkRecovery`)
  — sirf UI text nahi hai.
- **Delete:** user backup delete kar sakta hai
  (`SeedBackupService.deleteBackup`) — server DELETE + local key delete.
  Key mitne ke baad server par pada ciphertext kabhi decrypt nahi ho sakta.

### Normal login se farq — dhyaan se padho

- **Normal user login ONLY by seed hota hai.** Phone/device verification
  login flow se HATA DIYA GAYA hai (Vinay: "phone verification wala part
  hta de") — wo wapas nahi aaya hai.
- **Original-phone verification SIRF seed-backup recovery ke liye hai.**
  Login me iska koi role nahi hai.

### Honest limits (seed backup)

- **Server abhi deploy nahi hua hai** — `backupApiBaseUrl` khaali hai, to
  backup server par save NAHI hoti. Vinay ko worker deploy karna hai
  (`server/seed-backup-worker.js` me steps likhe hain: Cloudflare
  Workers + D1/KV, `OWNER_API_TOKEN` secret, phir URL config me dalna).
- **App uninstall ho jaye to backup key bhi mit jati hai** — phir server
  par pada ciphertext decrypt nahi ho sakta. Isliye 12 words kagaz par
  likh kar rakhna abhi bhi sabse safe tareeka hai.
- Recovery ka owner-side check code me hai (`checkRecovery`), par uske
  liye abhi koi owner UI screen nahi hai — owner ko check karke hi seed
  deni hai, aur ye README + code me likha hai.
- Koi real server test nahi hua hai — sirf local unit/widget tests
  (MockClient + memory store), koi real transaction nahi.

## 7. Swap / Exchange (USDT ↔ TRX live, baaki sirf rate)

Home → **Swap** button. Pehle network chuno (Tron / Ethereum / BNB Smart Chain),
phir From coin, To coin, amount — **Rate dekho** dabao, phir Confirm.

- **Tron: USDT ↔ TRX — LIVE execute** (SunSwap V2, testnet pehle).
  TRX isliye chahiye kyunki Tron par gas TRX me lagti hai. Rate pehle
  SunSwap pool se (`getAmountsOut`), fail ho to CoinGecko estimate se —
  rate ka source screen par likha hota hai.
- **Ethereum: USDT ERC20 / ETH / SHIB — sirf RATE (quote only).**
  **BNB Chain: USDT BEP20 / BNB — sirf RATE (quote only).**
  Swap execute (Uniswap / PancakeSwap) next step hai — abhi Confirm
  disabled rehta hai aur wajah screen par likhi hoti hai. **Kabhi fake
  completed swap nahi dikhaya jata.**
- **Fee — Confirm se pehle sab dikhta hai:**
  - Service fee: **0.09% PERMANENT** (`SwapConfig.swapServiceFeePercent`
    = 0.0009 — Vinay final, kabhi badalni nahi hai). Ye owner ka profit
    hai. Fee input amount se kat-ti hai — jaise 100 USDT swap karo to
    0.09 USDT fee, sirf 99.91 USDT swap hota hai.
  - **Fee usi coin me kategi jo swap ho raha hai** — USDT swap karo to
    USDT me, TRX swap karo to TRX me. Alag coin (BNB ya koi aur) me fee
    nahi lagti — user ko fee ke liye alag coin nahi chahiye hoga. Swap
    screen par saaf likha hota hai ki fee kis coin me kategi.
  - Network fee: alag se (Tron par TRX gas; Ethereum par ETH gas,
    BNB Chain par BNB gas). Ye network ko jati hai, owner ko nahi.
  - Milne wala amount + minimum receive (1% slippage) — rate hilne par
    minimum se kam mile to swap fail ho jayega (paise nahi jayenge, sirf
    thodi gas jalegi).
- **Fee kahan jati hai:** `SwapConfig.ownerFeeWalletAddress` me apna TRC20
  address dalo — tab fee swap confirm hote hi us address par bhej di jati
  hai. **Khaali chhoda (default) to fee collect nahi hoti** — fee ka hissa
  user ke wallet me hi rehta hai, aur screen par ye saaf likha hota hai.
  Galat profit dikhane se behtar hai ye sach likhna.
- **Pehla swap chhota test amount se karo** (testnet par bhi). Router
  address (`SwapConfig.sunSwapRouter`) ko Tronscan par verify kar lo:
  SunSwap V2 router mainnet `TNJVzGqKBWkJxJB5XYSqGAwUTV15U24pPq`, Nile
  `TMn1qrmYUMSTXo9babrJLzepKZoPC7M6Sy` (19 Nov 2026 ko sunswapteam repo
  se liye gaye — sources me conflict tha, isliye code me ye address
  configurable hai aur verify-first hai).

## 8. Naye coins: token list, Add Custom Token, auto-detect

Vinay ka sawaal tha: **market me aane wale naye coins automatic add ho
jayenge?** Jawab do hisson me hai — **receive/show automatic hai, swap
list curated hai.**

### (a) Receive / dikhna — AUTOMATIC hai
Home screen wallet apne aap naye tokens detect karta hai:
- **Tron:** TronGrid account se address ke saare TRC20 balances.
- **Ethereum:** Etherscan API se saare token transfers → har token ka balance.
- **BNB Chain:** BscScan API se wahi.
- Jo token curated list me **nahi** hai wo Home par **"New Tokens"**
  section me balance ke saath dikhta hai. Kisi ko bhejna nahi padta —
  koi bhi tumhare address par token bhej de to wo yahan dikhega.
- ⚠️ EVM (Ethereum/BNB) par auto-detect ke liye Etherscan/BscScan free
  API key chahiye (upar section 1 dekho). Bina key ke section khaali rehta
  hai — balance/send phir bhi chalta hai.

### (b) Swap list — CURATED hai (automatic nahi)
- Swap screen ki list `lib/services/token_list.dart` me `curatedTokens`
  hai: contract address, symbol, decimals, network. **Naya coin add
  karna = us list me ek line add karna** — poora code change nahi karna
  padta. Network add karte hi us network ke coins show hone lagte hain
  (ETH/SHIB/BNB/USDT-BEP20 pehle se list the, isliye Ethereum/BNB support
  aate hi wo dikhne lage).
- **Har naya coin automatic list nahi hota — scam token ka risk hai.**
  Koi bhi fake token bana kar asli jaisa naam/symbol rakh sakta hai.
  Isliye swap list sirf owner ki curated list se aati hai.
- **Future option:** list ko server se update karna (ek JSON file server
  par, app start par fetch kare) — abhi implement nahi hai, lekin
  `token_list.dart` ko aise banaya gaya hai ki server list aane par sirf
  ek jagah badalni padegi.

### (c) Add Custom Token — user khud add kare
Home → **Add Custom Token** (abhi Tron/TRC20 ke liye):
1. TRC20 contract address dalo (T... se shuru).
2. App TronGrid se khud fetch karta hai: naam, symbol, decimals + balance.
3. "Add karo" dabate hi token save ho jata hai (secure storage me) aur
   Home par dikhne lagta hai.
- Contract galat ho ya TRC20 token hi na ho to fetch fail hoga aur token
  add nahi hoga. **Hamesha contract address ko Tronscan par verify karo**
  — scam token ka naam/symbol asli jaisa ho sakta hai.
- EVM custom token (ERC20/BEP20) jald aa raha hai — abhi sirf Tron.

## 9. Project structure

```
lib/
  main.dart                        App start, wallet hai ya nahi (gate)
  config.dart                      Network switch + API key (TODO yahan hai)
  models/
    transaction_model.dart         Transfer + TxStatus (Pending/Confirmed/Failed)
  services/
    wallet_service.dart            12 words, Tron address, local signing
    seed_backup_service.dart       Seed backup: AES-256 encrypt, logout date, 3-month window, owner recovery check, delete
    recovery_wallet_service.dart   In-app Recovery Wallet (alag keys)
    owner_lock_service.dart        Owner PIN (hash) + biometric lock
    owner_accounts_service.dart    App ke saare stored accounts ki list (owner only)
    monthly_fee_service.dart       Monthly fee $0.01 flat — sirf calculate, kaat-ta nahi
    trongrid_service.dart          Balance, history, status, send (TronGrid API)
    tx_status_service.dart         Pending save karo + status polling
    address_validator.dart         Tron + Ethereum address checks (EIP-55)
  screens/
    owner_login_screen.dart        Hidden owner login (version 7 taps → PIN/biometric)
    owner_accounts_screen.dart     Saare accounts, owner lock ke baad (address/balance/seed)
    home_screen.dart               Balance + recent + auto-refresh
    history_screen.dart            Poori history, status ke saath
    recovery_wallet_screen.dart    Owner-only: PIN/biometric, balance, wapas bhejo
    create_wallet_screen.dart      Naya wallet (12 words) + 2-tick agreement (seed backup)
    import_wallet_screen.dart      Purana wallet wapas lao + 2-tick agreement (seed backup)
    send_screen.dart               Network select, chhoti warning line, chhota popup, automatic recovery redirect
    receive_screen.dart            QR code + address copy
  utils/format.dart                Amount/date/address dikhane ke helpers
  widgets/status_chip.dart         Pending/Confirmed/Failed badge
  widgets/secret_owner_tap.dart    Version par 7 tez tap = hidden owner login trigger
  widgets/seed_backup_agreement.dart  Agreement card: pehla tick, phir dusra tick (seed-backup note), ya Skip
server/
  seed-backup-worker.js          Seed backup server STUB (Cloudflare Worker) — DEPLOY NAHI HUA
```

---

## 10. Packages (19 Nov 2026 ko pub.dev par check kiye gaye)

| Package | Version | Kaam |
|---|---|---|
| bip39 | ^1.0.6 | 12-word seed phrase |
| flutter_secure_storage | ^11.2.0 | Seed + private key (Keystore/Keychain) |
| http | ^1.6.0 | TronGrid API calls |
| pointycastle | ^4.0.0 | secp256k1 signing, Keccak, BIP32 |
| qr_flutter | ^4.1.0 | Receive QR code |
| local_auth | ^2.3.0 | Fingerprint / Face ID (Recovery Wallet + owner lock) |
| flutter_lints | ^6.0.0 | Code linting |

`tron_wallet` package **jaan-boojh kar use nahi kiya** — wo Dec 2024 se
update nahi hua, sirf 135 pub points hain, aur bhari webview dependency
lata hai. Signing yahan `pointycastle` se khud ki gayi hai.

---

## 11. Abhi bhi Vinay ko ye karna hai

- [ ] `lib/config.dart` me apni **free TronGrid API key** paste karni hai.
- [ ] **Etherscan free API key** (`EthereumConfig.etherscanApiKey`) aur
      **BscScan free API key** (`BscConfig.bscscanApiKey`) — history aur
      auto-detect ke liye. Bina key ke balance/send chalta hai.
- [ ] **Nile testnet** par wallet banao → faucet se test TRX + test USDT lo.
- [ ] **Sepolia testnet** par test karo: Home → Ethereum → faucet se test
      ETH lo → 0.001 ETH ka test transfer karo (gas ETH me dikhega).
- [ ] **BSC testnet** par test karo: Home → BNB Smart Chain → faucet se
      tBNB lo → 0.001 BNB ka test transfer karo.
- [ ] **Swap test karo (Nile):** chhota amount USDT → TRX, Pending →
      Confirmed dekho. Router address Tronscan par verify karo. Swap
      screen par fee **0.09%** dikhe aur fee **USDT me** kati dikhe
      (TRX swap karo to fee TRX me). Fee wallet set ho to fee usi coin
      me owner address par jani chahiye.
- [ ] **Monthly fee card check karo:** Home par fee card dikhna chahiye —
      "$0.01 flat", "0.01 USDT", agli fee ki date (mahine ka aakhri din)
      — aur balance me se kuch kata nahi dikhna chahiye (koi fake
      deduction nahi).
- [ ] **Hidden owner login test karo:** Welcome/Home screen par Version
      0.1.0 par 7 baar tap karo → Owner Login khulna chahiye → PIN set
      karo → owner accounts dikhne chahiye. 6 baar tap par kuch nahi
      hona chahiye, aur app me kahin "Owner Login" ka button/text nahi
      dikhna chahiye.
- [ ] **Owner accounts test karo:** hidden owner login se kholo →
      PIN/biometric ke baad dono accounts (Main + Recovery) address,
      balance aur creation date ke saath dikhne chahiye → bina PIN ke
      kuch nahi dikhna chahiye.
- [ ] **Seed backup agreement test karo:** Naya wallet banao → pehle sirf
      pehla tick dikhna chahiye, dusra tick + seed-backup note pehle tick
      ke baad dikhna chahiye → dono tick ke bina Save disabled rehna
      chahiye → Skip dabane par bina backup ke wallet banna chahiye.
      Note me exact wording honi chahiye: "Your seed backup is saved. If
      you forget your seed, prove you are a real user from your original
      phone and get your login back within 3 months after logout."
- [ ] **Seed backup server abhi set nahi hai:** dono tick laga kar wallet
      banao to "Seed backup server abhi set nahi hai" wala sach dikhna
      chahiye — jhootha "saved" nahi. Worker deploy karne ke baad hi
      `SeedBackupConfig.backupApiBaseUrl` me URL dalna hai (README
      section 6d + `server/seed-backup-worker.js` dekho).
- [ ] **Logout window test karo:** wallet delete karo → logout date record
      honi chahiye → 3 months ke andar original phone se recovery allowed,
      dusre phone se nahi, 3 months ke baad nahi (seed saved rehne ke
      baad bhi).
- [ ] **Auto-detect test karo:** Nile par kisi dusre TRC20 token ko apne
      address par bhejo (ya faucet se lo) → Home par "New Tokens" me dikhe.
- [ ] **Add Custom Token test karo:** kisi TRC20 contract ko dal kar fetch
      karo, phir add karo.
- [ ] **Swap fee wallet set karo:** `SwapConfig.ownerFeeWalletAddress` me
      apna TRC20 address dalo — tabhi swap fee tumhe milegi.
- [ ] Testnet par 1 USDT ka test transfer karo, Pending → Confirmed dekho.
- [ ] **Recovery Wallet test karo (testnet par):** hidden owner login
      se Owner Accounts → Recovery Wallet kholo → 12 words likh lo →
      owner PIN set karo → phir main
      wallet se jaan-boojh kar ek galat-network address (0x...) par
      1 USDT bhejo → dekho paise Special Wallet me gaye, history me
      original address + reason likha hai → Recovery Wallet khol kar
      **Wapas bhejo** se paise sahi address par wapas bhejo.
- [ ] Recovery wallet ke **12 words kagaz par likh kar safe jagah
      rakho** — PIN bhool jao to sirf seed se PIN dobara set hoga.
- [ ] Nile USDT contract (`TXYZopYRdj2D9XRtbG411XZZ3kM5VkAeBf`) ko
      nile.tronscan.org par verify karo.
- [ ] Sab test hone ke baad hi `config.dart` me mainnet karo — aur tab bhi
      pehla mainnet transfer **chhota test amount** se karo.
- [ ] Real money se pehle: main wallet ke liye PIN/biometric lock bhi
      add karo (Recovery Wallet ka owner PIN/biometric lock ab hai),
      aur security audit karwao (ye starter me nahi hai).

## 12. Aage kya add kar sakte ho (next steps)

- PIN / fingerprint lock (app kholte hi)
- USDT price in ₹/$ dikhana (CoinGecko free API)
- QR code scan karke address bharna (mobile_scanner)
- Multiple wallets / multiple addresses
- Swap execute: Ethereum par Uniswap, BNB Chain par PancakeSwap (abhi sirf rate)
- EVM custom token (ERC20/BEP20) — Add Custom Token abhi Tron-only hai
- EVM sends ki Pending → Confirmed tracking (Tron jaisi — abhi sirf tx hash + explorer link milta hai)
- Token list server se update karna (curated list ko JSON se fetch karna)
