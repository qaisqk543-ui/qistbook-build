/// App Lock PIN screen: 4-digit PIN entry.
/// Do mode: "set" (naya PIN do dafa) aur "verify" (khulne par check).
/// PIN bhool jao → logout karke password se dobara login (wahi reset hai).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_lock_service.dart';
import '../theme/app_theme.dart';

enum PinMode { set, verify, change }

class AppLockScreen extends StatefulWidget {
  final String uid;
  final PinMode mode;

  /// Verify mode me sahi PIN par chalta hai. Set mode me null bhi aa sakta hai (cancel).
  final ValueChanged<bool> onDone;

  /// "PIN bhool gaye" par chalta hai (logout → login).
  final VoidCallback? onForgot;

  const AppLockScreen({
    super.key,
    required this.uid,
    required this.mode,
    required this.onDone,
    this.onForgot,
  });

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  String _pin = '';
  String? _first; // set mode: pehli entry
  String? _err;
  bool _busy = false;

  String get _title {
    switch (widget.mode) {
      case PinMode.set:
        return _first == null ? 'Naya PIN banao' : 'PIN dobara likhen';
      case PinMode.verify:
        return 'PIN likhen';
      case PinMode.change:
        return _first == null
            ? 'Naya PIN banao'
            : 'Naya PIN dobara likhen';
    }
  }

  void _onKey(String k) {
    if (_busy) return;
    setState(() {
      _err = null;
      if (k == 'back') {
        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
      } else if (_pin.length < 4) {
        _pin += k;
      }
    });
    if (_pin.length == 4) _submit();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      if (widget.mode == PinMode.verify) {
        final ok = await AppLockService.verify(widget.uid, _pin);
        if (!mounted) return;
        if (ok) {
          widget.onDone(true);
        } else {
          setState(() {
            _err = 'Ghalat PIN — dobara koshish karein';
            _pin = '';
            _busy = false;
          });
        }
        return;
      }
      // set / change mode
      if (_first == null) {
        setState(() {
          _first = _pin;
          _pin = '';
          _busy = false;
        });
        return;
      }
      if (_pin != _first) {
        setState(() {
          _err = 'Dono PIN same nahi — dobara shuru karein';
          _first = null;
          _pin = '';
          _busy = false;
        });
        return;
      }
      await AppLockService.setPin(widget.uid, _pin);
      if (!mounted) return;
      widget.onDone(true);
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.mode == PinMode.verify
          ? null
          : AppBar(title: const Text('App Lock')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.xl),
          child: Column(
            children: [
              const SizedBox(height: AppSpace.l),
              Container(
                width: 104,
                height: 104,
                decoration: const BoxDecoration(
                  color: AppColors.tintTeal,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock_rounded,
                    size: 52, color: AppColors.primaryDark),
              ),
              const SizedBox(height: AppSpace.m),
              Text(_title,
                  textAlign: TextAlign.center, style: AppText.h1),
              const SizedBox(height: AppSpace.s),
              const Text('4-digit PIN',
                  style: AppText.label),
              const SizedBox(height: AppSpace.l),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  4,
                  (i) => Container(
                    width: 26,
                    height: 26,
                    margin: const EdgeInsets.symmetric(
                        horizontal: 10),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < _pin.length
                          ? AppColors.primary
                          : AppColors.divider,
                    ),
                  ),
                ),
              ),
              if (_err != null) ...[
                const SizedBox(height: AppSpace.m),
                Text(_err!,
                    textAlign: TextAlign.center,
                    style: AppText.body.copyWith(
                        color: AppColors.dueRed)),
              ],
              const Spacer(),
              _keypad(),
              const SizedBox(height: AppSpace.m),
              if (widget.mode == PinMode.verify &&
                  widget.onForgot != null)
                TextButton(
                  onPressed: widget.onForgot,
                  child: const Text('PIN bhool gaye?'),
                ),
              if (widget.mode != PinMode.verify)
                TextButton(
                  onPressed: () => widget.onDone(false),
                  child: const Text('Cancel'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _keypad() {
    const keys = [
      '1', '2', '3',
      '4', '5', '6',
      '7', '8', '9',
      '', '0', 'back',
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate:
          const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 1.6,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: keys.length,
      itemBuilder: (ctx, i) {
        final k = keys[i];
        if (k.isEmpty) return const SizedBox.shrink();
        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            HapticFeedback.lightImpact();
            _onKey(k);
          },
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border:
                  Border.all(color: AppColors.divider),
            ),
            child: Center(
              child: k == 'back'
                  ? const Icon(Icons.backspace_rounded,
                      size: 32, color: AppColors.grey)
                  : Text(k,
                      style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink)),
            ),
          ),
        );
      },
    );
  }
}
