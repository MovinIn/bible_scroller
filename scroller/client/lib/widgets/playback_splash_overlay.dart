import 'dart:async';

import 'package:flutter/material.dart';

import '../utils/playback_splash_icon.dart';

/// Brief play/pause flash centered over reel imagery (TikTok-style).
class PlaybackSplashController extends ChangeNotifier {
  PlaybackSplashIcon? _icon;
  int _flashId = 0;

  PlaybackSplashIcon? get icon => _icon;
  int get flashId => _flashId;

  void flash(PlaybackSplashIcon icon) {
    _icon = icon;
    _flashId += 1;
    notifyListeners();
  }
}

class PlaybackSplashOverlay extends StatefulWidget {
  const PlaybackSplashOverlay({super.key, required this.controller});

  final PlaybackSplashController controller;

  @override
  State<PlaybackSplashOverlay> createState() => _PlaybackSplashOverlayState();
}

class _PlaybackSplashOverlayState extends State<PlaybackSplashOverlay>
    with SingleTickerProviderStateMixin {
  static const _visibleDuration = Duration(milliseconds: 450);

  late final AnimationController _animationController;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;
  PlaybackSplashIcon? _visibleIcon;
  int _lastFlashId = 0;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );
    _scaleAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );
    widget.controller.addListener(_handleFlash);
  }

  @override
  void didUpdateWidget(covariant PlaybackSplashOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleFlash);
      widget.controller.addListener(_handleFlash);
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    widget.controller.removeListener(_handleFlash);
    _animationController.dispose();
    super.dispose();
  }

  void _handleFlash() {
    if (_lastFlashId == widget.controller.flashId) {
      return;
    }
    _hideTimer?.cancel();
    _lastFlashId = widget.controller.flashId;
    _visibleIcon = widget.controller.icon;
    _animationController.forward(from: 0);
    _hideTimer = Timer(_visibleDuration, () {
      if (!mounted || _lastFlashId != widget.controller.flashId) {
        return;
      }
      _animationController.reverse().whenComplete(() {
        if (mounted && _lastFlashId == widget.controller.flashId) {
          setState(() => _visibleIcon = null);
        }
      });
    });
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_visibleIcon == null) {
      return const SizedBox.shrink(key: Key('playback_splash_hidden'));
    }

    final iconData = _visibleIcon == PlaybackSplashIcon.pause
        ? Icons.pause_rounded
        : Icons.play_arrow_rounded;

    return IgnorePointer(
      child: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Container(
              key: const Key('playback_splash_overlay'),
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                shape: BoxShape.circle,
              ),
              child: Icon(iconData, color: Colors.white, size: 44),
            ),
          ),
        ),
      ),
    );
  }
}
