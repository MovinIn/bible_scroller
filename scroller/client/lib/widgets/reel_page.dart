import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../state/reels_controller.dart';
import 'auth_gate.dart';
import 'playback_splash_overlay.dart';
import 'reel_action_bar.dart';

class ReelPage extends StatelessWidget {
  const ReelPage({
    super.key,
    required this.reel,
    required this.controller,
    required this.onCommentsTap,
    required this.onTranslationTap,
    required this.onVoiceTap,
    this.onVoiceLongPress,
    this.onBodyTap,
    this.onBookTap,
    this.playbackSplashController,
  });

  final Reel reel;
  final ReelsController controller;
  final VoidCallback onCommentsTap;
  final VoidCallback onTranslationTap;
  final VoidCallback onVoiceTap;
  final VoidCallback? onVoiceLongPress;
  final VoidCallback? onBodyTap;
  final VoidCallback? onBookTap;
  final PlaybackSplashController? playbackSplashController;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Stack(
      fit: StackFit.expand,
      children: [
        CachedNetworkImage(
          imageUrl: reel.imageUrl,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(color: const Color(0xFF111111)),
          errorWidget: (_, __, ___) => Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1F1147), Color(0xFF0B1026)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.15),
                Colors.black.withValues(alpha: 0.2),
                Colors.black.withValues(alpha: 0.75),
              ],
              stops: const [0.0, 0.55, 1.0],
            ),
          ),
        ),
        if (playbackSplashController != null)
          PlaybackSplashOverlay(controller: playbackSplashController!),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 88, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Text(
                    reel.reference,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  controller.verseTextFor(reel),
                  style: textTheme.headlineSmall?.copyWith(color: Colors.white),
                  maxLines: 8,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
        Positioned.fill(
          child: _ReelBodyTapTarget(onTap: onBodyTap),
        ),
        Positioned(
          right: 12,
          top: 0,
          bottom: 0,
          child: SafeArea(
            child: Center(
              child: ReelActionBar(
                reel: reel,
                translationVersion: controller.translationVersion,
                isMuted: controller.isMuted,
                onLike: () async {
                  final ok = await ensureLoggedIn(context);
                  if (!ok || !context.mounted) {
                    return;
                  }
                  await controller.toggleReelLike(reel);
                },
                onCommentsTap: onCommentsTap,
                onTranslationTap: onTranslationTap,
                onVoiceTap: onVoiceTap,
                onVoiceLongPress: onVoiceLongPress,
              ),
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  key: const Key('book_picker_button'),
                  borderRadius: BorderRadius.circular(999),
                  onTap: onBookTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          reel.book,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.expand_more,
                          color: Colors.white70,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Tap target that does not join the gesture arena, so vertical PageView
/// drags/swipes are not competed with by an opaque [GestureDetector].
class _ReelBodyTapTarget extends StatefulWidget {
  const _ReelBodyTapTarget({this.onTap});

  final VoidCallback? onTap;

  @override
  State<_ReelBodyTapTarget> createState() => _ReelBodyTapTargetState();
}

class _ReelBodyTapTargetState extends State<_ReelBodyTapTarget> {
  int? _activePointer;
  Offset? _downPosition;

  void _clear() {
    _activePointer = null;
    _downPosition = null;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      key: const Key('reel_body_tap_target'),
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        if (widget.onTap == null) {
          return;
        }
        _activePointer = event.pointer;
        _downPosition = event.localPosition;
      },
      onPointerMove: (event) {
        if (_activePointer != event.pointer || _downPosition == null) {
          return;
        }
        if ((event.localPosition - _downPosition!).distance > kTouchSlop) {
          _clear();
        }
      },
      onPointerUp: (event) {
        if (_activePointer != event.pointer) {
          return;
        }
        _clear();
        widget.onTap?.call();
      },
      onPointerCancel: (event) {
        if (_activePointer == event.pointer) {
          _clear();
        }
      },
    );
  }
}
