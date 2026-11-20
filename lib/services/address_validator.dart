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
      return AddressValidation.invalid('The address is empty.');
    }

    // The most common costly mistake: pasting an Ethereum address here.
    if (address.startsWith('0x') || address.startsWith('0X')) {
      return AddressValidation.invalid(
        'This is an Ethereum (ERC20) address. From this wallet, send only to a Tron (TRC20) '
        'address — one that starts with T.',
        network: AddressNetwork.ethereum,
      );
    }

    if (!address.startsWith('T')) {
      return AddressValidation.invalid(
        'A Tron address always starts with T.',
      );
    }

    if (address.length != 34) {
      return AddressValidation.invalid(
        'A Tron address is 34 characters long. This one is ${address.length} '
        'characters long — did it get cut off while copying?',
        network: AddressNetwork.tron,
      );
    }

    // Base58 alphabet only: 0, O, I and l are never used.
    if (!RegExp(r'^[1-9A-HJ-NP-Za-km-z]+$').hasMatch(address)) {
      return AddressValidation.invalid(
        'The address has a wrong character. A Tron address never contains 0, O, I or l — '
        'it may have been typed wrong.',
        network: AddressNetwork.tron,
      );
    }

    // Checksum: catches an address that was changed by even one character.
    if (!WalletService.isValidTronAddress(address)) {
      return AddressValidation.invalid(
        'The address checksum is wrong — the address may have changed while copying. '
        'Copy it again and paste it.',
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
      return AddressValidation.invalid('The address is empty.');
    }

    final detected = detectNetworkFromAddress(address);
    if (detected == null) {
      return AddressValidation.invalid(
        'The address was not recognised. A Tron address starts with T, '
        'and an Ethereum/BSC address starts with 0x.',
      );
    }

    // --- Network mismatch: only a small warning, NEVER a block. ---
    if (selected == AddressNetwork.tron && detected != AddressNetwork.tron) {
      return AddressValidation.valid(
        warning:
            'The network looks wrong, USDT could be lost — you selected TRC20 '
            'but this looks like an ERC20 address. '
            'If the address is wrong, no refund will be given.',
        network: detected,
      );
    }
    if (selected == AddressNetwork.ethereum &&
        detected == AddressNetwork.tron) {
      return AddressValidation.valid(
        warning:
            'The network looks wrong, USDT could be lost — you selected ERC20 '
            'but this looks like a TRC20 address. '
            'If the address is wrong, no refund will be given.',
        network: detected,
      );
    }
    if (selected == AddressNetwork.bsc && detected == AddressNetwork.tron) {
      return AddressValidation.valid(
        warning:
            'The network looks wrong, USDT could be lost — you selected BEP20 '
            'but this looks like a TRC20 address. '
            'If the address is wrong, no refund will be given.',
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
      return AddressValidation.invalid('The address is empty.');
    }

    if (!address.startsWith('0x') && !address.startsWith('0X')) {
      return AddressValidation.invalid(
        'An Ethereum address starts with 0x.',
      );
    }

    if (address.length != 42) {
      return AddressValidation.invalid(
        'An Ethereum address is 42 characters long (0x + 40). This one is '
        '${address.length} characters long.',
        network: AddressNetwork.ethereum,
      );
    }

    final hexPart = address.substring(2);
    if (!RegExp(r'^[0-9a-fA-F]{40}$').hasMatch(hexPart)) {
      return AddressValidation.invalid(
        'The address must contain only 0-9 and a-f characters.',
        network: AddressNetwork.ethereum,
      );
    }

    final hasLower = hexPart.contains(RegExp(r'[a-f]'));
    final hasUpper = hexPart.contains(RegExp(r'[A-F]'));

    // Mixed upper + lower case = EIP-55 checksum. Verify it.
    if (hasLower && hasUpper) {
      if (!_isValidEip55Checksum(address)) {
        return AddressValidation.invalid(
          'The address checksum (EIP-55) is wrong — the address looks changed. '
          'Copy it again.',
          network: AddressNetwork.ethereum,
        );
      }
      return AddressValidation.valid(network: AddressNetwork.ethereum);
    }

    // All one case: format is fine, but there is no checksum to verify.
    return AddressValidation.valid(
      network: AddressNetwork.ethereum,
      warning: 'This address has no checksum. Check it carefully once more before sending.',
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
