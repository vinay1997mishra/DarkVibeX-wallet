// Address safety: galat address par USDT na jaye.
//
// Ek galat address par bheja hua crypto WAPAS NAHI AATA — blockchain par
// transaction irreversible hota hai. Isliye galat lagne par Send screen
// par ek chhoti warning line dikhayi jati hai. App kabhi Send ko block
// nahi karta — aakhri faisla hamesha user ka hota hai.
//
// Main network TRC20 hai, lekin Ethereum (ERC20) ki validation bhi yahan
// ready hai — agar baad me ERC20 support add karna ho to sirf
// [validateEthereum] ko Send screen se jodna hai, naya code likhna nahi.

import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/digests/keccak.dart';

import 'wallet_service.dart';

enum AddressNetwork { tron, ethereum, bsc }

/// Result of checking one address typed by the user.
class AddressValidation {
  /// True only if the address is safe to send to on the expected network.
  final bool isValid;

  /// Red warning shown under the address field when [isValid] is false.
  final String? error;

  /// Yellow note shown even when the address is valid
  /// (for example: address has no checksum, double-check it).
  final String? warning;

  /// Which network the address belongs to (null if we cannot tell).
  final AddressNetwork? network;

  const AddressValidation({
    required this.isValid,
    this.error,
    this.warning,
    this.network,
  });

  factory AddressValidation.valid({
    AddressNetwork? network,
    String? warning,
  }) {
    return AddressValidation(isValid: true, network: network, warning: warning);
  }

  factory AddressValidation.invalid(String error, {AddressNetwork? network}) {
    return AddressValidation(isValid: false, error: error, network: network);
  }
}

class AddressValidator {
  // ---------------------------------------------------------------------------
  // Tron (TRC20) — this wallet's main network
  // ---------------------------------------------------------------------------

  /// Checks an address the user wants to send USDT to on Tron.
  /// Rules: starts with T, exactly 34 characters, only Base58 characters
  /// (0, O, I, l are never in a Tron address), and a correct checksum.
  static AddressValidation validateForTron(String rawAddress) {
    final address = rawAddress.trim();

    if (address.isEmpty) {
      return AddressValidation.invalid('Address khaali hai.');
    }

    // The most common costly mistake: pasting an Ethereum address here.
    if (address.startsWith('0x') || address.startsWith('0X')) {
      return AddressValidation.invalid(
        'Ye Ethereum (ERC20) address hai. Is wallet se sirf Tron (TRC20) '
        'address par bhejo — jo T se shuru hota hai.',
        network: AddressNetwork.ethereum,
      );
    }

    if (!address.startsWith('T')) {
      return AddressValidation.invalid(
        'Tron address hamesha T se shuru hota hai.',
      );
    }

    if (address.length != 34) {
      return AddressValidation.invalid(
        'Tron address 34 characters ka hota hai. Ye ${address.length} '
        'characters ka hai — copy karte waqt kahin cut to nahi gaya?',
        network: AddressNetwork.tron,
      );
    }

    // Base58 alphabet only: 0, O, I and l are never used.
    if (!RegExp(r'^[1-9A-HJ-NP-Za-km-z]+$').hasMatch(address)) {
      return AddressValidation.invalid(
        'Address me galat character hai. Tron address me 0, O, I, l kabhi '
        'nahi hote — shayad galat type ho gaya hai.',
        network: AddressNetwork.tron,
      );
    }

    // Checksum: catches an address that was changed by even one character.
    if (!WalletService.isValidTronAddress(address)) {
      return AddressValidation.invalid(
        'Address ka checksum galat hai — address copy karte waqt badal gaya '
        'ho sakta hai. Dobara copy karke paste karo.',
        network: AddressNetwork.tron,
      );
    }

    return AddressValidation.valid(network: AddressNetwork.tron);
  }

  // ---------------------------------------------------------------------------
  // Network cross-check — the core safety feature
  // ---------------------------------------------------------------------------

  /// Detects the network from the address prefix alone.
  ///   T...  = Tron (TRC20)
  ///   0x... = Ethereum-style address. ERC20 (Ethereum) and BEP20 (BSC)
  ///           use the exact same address format, so the prefix alone
  ///           cannot tell them apart — the app ASKS the user which one.
  /// Returns null if the prefix matches neither.
  static AddressNetwork? detectNetworkFromAddress(String rawAddress) {
    final address = rawAddress.trim();
    if (address.startsWith('T')) return AddressNetwork.tron;
    if (address.startsWith('0x') || address.startsWith('0X')) {
      return AddressNetwork.ethereum; // same format as BEP20 — ask user
    }
    return null;
  }

  /// True only when the address looks like a DIFFERENT network than the
  /// one the user selected. Used by the Send screen to decide whether
  /// to offer the recovery-wallet choice. Correct address + correct
  /// network always returns false — recovery never touches those sends.
  /// Note: ERC20 and BEP20 share the 0x... format, so a 0x address is
  /// only a mismatch against Tron, never against Ethereum/BSC.
  static bool isNetworkMismatch(
    String rawAddress,
    AddressNetwork selected,
  ) {
    final detected = detectNetworkFromAddress(rawAddress);
    if (detected == null) return false;
    if (selected == AddressNetwork.tron) {
      return detected != AddressNetwork.tron;
    }
    if (selected == AddressNetwork.ethereum) {
      return detected == AddressNetwork.tron;
    }
    // BSC selected: only a Tron address is a mismatch.
    return detected == AddressNetwork.tron;
  }

  /// Human label for a detected network, e.g. 'ERC20 (Ethereum)'.
  static String networkLabel(AddressNetwork network) {
    switch (network) {
      case AddressNetwork.tron:
        return 'TRC20 (Tron)';
      case AddressNetwork.ethereum:
        return 'ERC20 (Ethereum)';
      case AddressNetwork.bsc:
        return 'BEP20 (BSC)';
    }
  }

  /// Validates [rawAddress] against the network the user SELECTED.
  /// A mismatch is ONLY a small warning — the app never blocks Send.
  /// The user sees the warning line and decides.
  ///
  ///   TRC20 selected + 0x... address  -> warning, not blocked.
  ///   ERC20 selected + T... address   -> warning, not blocked.
  ///   BEP20 selected + T... address   -> warning, not blocked.
  ///
  /// The full format is checked only after the prefix matches.
  static AddressValidation validateForSelectedNetwork(
    String rawAddress,
    AddressNetwork selected,
  ) {
    final address = rawAddress.trim();
    if (address.isEmpty) {
      return AddressValidation.invalid('Address khaali hai.');
    }

    final detected = detectNetworkFromAddress(address);
    if (detected == null) {
      return AddressValidation.invalid(
        'Address pehchana nahi gaya. Tron address T se shuru hota hai, '
        'Ethereum/BSC address 0x se.',
      );
    }

    // --- Network mismatch: only a small warning, NEVER a block. ---
    if (selected == AddressNetwork.tron && detected != AddressNetwork.tron) {
      return AddressValidation.valid(
        warning:
            'Network galat lag raha hai, USDT doob sakta hai — tumne TRC20 '
            'select kiya hai lekin ye address ERC20 ka lagta hai.',
        network: detected,
      );
    }
    if (selected == AddressNetwork.ethereum &&
        detected == AddressNetwork.tron) {
      return AddressValidation.valid(
        warning:
            'Network galat lag raha hai, USDT doob sakta hai — tumne ERC20 '
            'select kiya hai lekin ye address TRC20 ka lagta hai.',
        network: detected,
      );
    }
    if (selected == AddressNetwork.bsc && detected == AddressNetwork.tron) {
      return AddressValidation.valid(
        warning:
            'Network galat lag raha hai, USDT doob sakta hai — tumne BEP20 '
            'select kiya hai lekin ye address TRC20 ka lagta hai.',
        network: detected,
      );
    }

    // Prefix matches the selected network — now check the full format.
    switch (selected) {
      case AddressNetwork.tron:
        return validateForTron(address);
      case AddressNetwork.ethereum:
        return validateEthereum(address);
      case AddressNetwork.bsc:
        // BEP20 uses the exact same address format as ERC20.
        final result = validateEthereum(address);
        if (!result.isValid) return result;
        return AddressValidation.valid(
          network: AddressNetwork.bsc,
          warning: result.warning,
        );
    }
  }

  // ---------------------------------------------------------------------------
  // Ethereum (ERC20) — NOT used by Send yet, kept ready for later
  // ---------------------------------------------------------------------------

  /// Checks an Ethereum address, including the EIP-55 checksum.
  /// Use this when ERC20 support is added — do not use it for Tron sends.
  static AddressValidation validateEthereum(String rawAddress) {
    final address = rawAddress.trim();

    if (address.isEmpty) {
      return AddressValidation.invalid('Address khaali hai.');
    }

    if (!address.startsWith('0x') && !address.startsWith('0X')) {
      return AddressValidation.invalid(
        'Ethereum address 0x se shuru hota hai.',
      );
    }

    if (address.length != 42) {
      return AddressValidation.invalid(
        'Ethereum address 42 characters ka hota hai (0x + 40). Ye '
        '${address.length} characters ka hai.',
        network: AddressNetwork.ethereum,
      );
    }

    final hexPart = address.substring(2);
    if (!RegExp(r'^[0-9a-fA-F]{40}$').hasMatch(hexPart)) {
      return AddressValidation.invalid(
        'Address me sirf 0-9 aur a-f characters hone chahiye.',
        network: AddressNetwork.ethereum,
      );
    }

    final hasLower = hexPart.contains(RegExp(r'[a-f]'));
    final hasUpper = hexPart.contains(RegExp(r'[A-F]'));

    // Mixed upper + lower case = EIP-55 checksum. Verify it.
    if (hasLower && hasUpper) {
      if (!_isValidEip55Checksum(address)) {
        return AddressValidation.invalid(
          'Address ka checksum (EIP-55) galat hai — address badla hua lagta '
          'hai. Dobara copy karo.',
          network: AddressNetwork.ethereum,
        );
      }
      return AddressValidation.valid(network: AddressNetwork.ethereum);
    }

    // All one case: format is fine, but there is no checksum to verify.
    return AddressValidation.valid(
      network: AddressNetwork.ethereum,
      warning: 'Ye address checksum ke bina hai. Bhejne se pehle isko ek '
          'baar aur dhyaan se check kar lo.',
    );
  }

  /// EIP-55: hash the lowercase address with Keccak-256. For every letter,
  /// if the matching hash digit is 8 or more the letter must be uppercase.
  static bool _isValidEip55Checksum(String address) {
    final lower = address.substring(2).toLowerCase();
    final hashHex = _bytesToHex(_keccak256(utf8.encode(lower)));
    for (var i = 0; i < 40; i++) {
      final ch = lower[i];
      if (ch.codeUnitAt(0) >= 'a'.codeUnitAt(0) &&
          ch.codeUnitAt(0) <= 'f'.codeUnitAt(0)) {
        final hashDigit = int.parse(hashHex[i], radix: 16);
        final actual = address[2 + i];
        if (hashDigit >= 8) {
          if (actual != actual.toUpperCase()) return false;
        } else {
          if (actual != actual.toLowerCase()) return false;
        }
      }
    }
    return true;
  }

  static Uint8List _keccak256(List<int> input) {
    final digest = KeccakDigest(256);
    final bytes = Uint8List.fromList(input);
    digest.update(bytes, 0, bytes.length);
    final out = Uint8List(32);
    digest.doFinal(out, 0);
    return out;
  }

  static String _bytesToHex(Uint8List bytes) {
    final buffer = StringBuffer();
    for (final b in bytes) {
      buffer.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}
