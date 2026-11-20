// Hidden owner login trigger — secret tap sequence.
//
// Normal user ko app me kahin bhi "Owner Login" ka button, option,
// hint ya text NAHI dikhna chahiye. Owner login sirf is tareeke se
// khulta hai: app ke VERSION text par 7 baar tap karo, 5 second ke
// andar. Uske baad owner PIN/biometric screen aati hai — bina
// PIN/biometric ke owner area kabhi nahi khulta.
//
// Version text har main screen par chhota sa grey me dikhta hai
// (Welcome, Home) — ye aam apps me bhi hota hai, isse
// owner login ka koi hint nahi milta. 7 baar tap hone se pehle tap
// karne par kuch nahi hota — koi popup, koi hint nahi.
//
// Ye widget version text ko wrap kar deta hai — dikhne me kuch nahi
// badalta, sirf 7 tez tap par [onTriggered] chalata hai. Koi server
// nahi, sab local hai.

import 'package:flutter/material.dart';

/// Pure tap counter — unit test karne ke liye UI se alag hai.
/// [tapsToTrigger] baar tap [window] ke andar ho to true deta hai,
/// phir counter reset ho jata hai. Window ke bahar ke purane tap
/// gin-ti me nahi aate.
class SecretTapCounter {
  final int tapsToTrigger;
  final Duration window;

  final List<DateTime> _taps = [];

  SecretTapCounter({
    this.tapsToTrigger = 7,
    this.window = const Duration(seconds: 5),
  });

  /// Ek tap register karo. True = sequence poori hui (trigger karo).
  /// [now] test ke liye diya ja sakta hai — warna abhi ka time.
  bool registerTap([DateTime? now]) {
    final t = now ?? DateTime.now();
    _taps.add(t);
    // Window se purane tap hatao.
    _taps.removeWhere((tap) => t.difference(tap) > window);
    if (_taps.length >= tapsToTrigger) {
      _taps.clear();
      return true;
    }
    return false;
  }

  /// Abhi window me kitne tap gin-ti me hain (tests ke liye).
  int get tapCount => _taps.length;
}

/// Version text ko secret owner-login trigger bana do.
/// Dikhne me child jaisa hi rehta hai — 7 tez tap par onTriggered.
class SecretOwnerTapDetector extends StatefulWidget {
  final Widget child;
  final VoidCallback onTriggered;

  /// Kitni baar tap karna hai (default 7 — version par 7 baar tap).
  final int tapsToTrigger;

  const SecretOwnerTapDetector({
    super.key,
    required this.child,
    required this.onTriggered,
    this.tapsToTrigger = 7,
  });

  @override
  State<SecretOwnerTapDetector> createState() =>
      _SecretOwnerTapDetectorState();
}

class _SecretOwnerTapDetectorState extends State<SecretOwnerTapDetector> {
  late final SecretTapCounter _counter;

  @override
  void initState() {
    super.initState();
    _counter = SecretTapCounter(tapsToTrigger: widget.tapsToTrigger);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (_counter.registerTap(DateTime.now())) {
          widget.onTriggered();
        }
      },
      child: widget.child,
    );
  }
}
