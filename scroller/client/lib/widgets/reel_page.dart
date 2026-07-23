import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../state/reels_controller.dart';
import '../utils/voiceover_presentation.dart';
import 'auth_gate.dart';
import 'playback_splash_overlay.dart';
import 'reel_action_bar.dart';
import 'voice_speed_sheet.dart';
import 'word_definition_sheet.dart';

class ReelPage extends StatelessWidget {
  const ReelPage({
    super.key,
    required this.reel,
    required this.controller,
    required this.onCommentsTap,
    required this.onTranslationTap,
    required this.onVoiceTap,
    this.onDefineTap,
    this.onVoiceLongPress,
    this.onSpeedTap,
    this.onBodyTap,
    this.onBookTap,
    this.playbackSplashController,
  });

  final Reel reel;
  final ReelsController controller;
  final VoidCallback onCommentsTap;
  final VoidCallback onTranslationTap;
  final VoidCallback onVoiceTap;
  final VoidCallback? onDefineTap;
  final VoidCallback? onVoiceLongPress;
  final VoidCallback? onSpeedTap;
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
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 56, 88, 24),
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) {
                final defineMode = controller.defineModeEnabled;
                final study = defineMode ? controller.wordStudyFor(reel) : null;
                final forThisReel = controller.isVoiceoverFor(reel);
                final presentation = forThisReel
                    ? controller.voiceoverPresentation
                    : VoiceoverPresentation.sectionIdle;
                final isActivePlay =
                    presentation == VoiceoverPresentation.playingActiveVerse;
                final text = isActivePlay
                    ? (controller.activeVerseTextFor(reel) ??
                        controller.verseTextFor(reel))
                    : controller.verseTextFor(reel);
                final fadeIn =
                    presentation == VoiceoverPresentation.sectionReveal;

                return Center(
                  child: TweenAnimationBuilder<double>(
                    key: ValueKey(
                      'verse-copy-${defineMode}-${presentation.name}-${controller.activeVerseNumber ?? 0}',
                    ),
                    tween: Tween<double>(
                      begin: fadeIn ? 0 : 1,
                      end: 1,
                    ),
                    duration: Duration(milliseconds: fadeIn ? 450 : 0),
                    builder: (context, opacity, child) {
                      return Opacity(opacity: opacity, child: child);
                    },
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: 520,
                        maxHeight: 420,
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.center,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: Colors.white24),
                                ),
                                child: Text(
                                  reel.reference,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 21,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              if (defineMode && study != null)
                                _WordStudyGroups(
                                  study: study,
                                  textStyle: textTheme.headlineSmall?.copyWith(
                                    color: Colors.white,
                                    fontSize: 28,
                                    height: 1.35,
                                  ),
                                )
                              else
                                Text(
                                  text,
                                  textAlign: TextAlign.center,
                                  style: textTheme.headlineSmall?.copyWith(
                                    color: Colors.white,
                                    fontSize: 28,
                                    height: 1.35,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            if (controller.defineModeEnabled) {
              return const SizedBox.shrink();
            }
            return Positioned.fill(
              child: _ReelBodyTapTarget(onTap: onBodyTap),
            );
          },
        ),
        if (playbackSplashController != null)
          PlaybackSplashOverlay(controller: playbackSplashController!),
        Positioned(
          right: 12,
          top: 0,
          bottom: 0,
          child: SafeArea(
            // Horizontal inset is Positioned(right: 12) only — keep discovery aligned.
            left: false,
            right: false,
            child: Align(
              alignment: Alignment.centerRight,
              child: ListenableBuilder(
                listenable: controller,
                builder: (context, _) {
                  return ReelActionBar(
                    reel: reel,
                    translationVersion: controller.translationVersion,
                    isMuted: controller.isMuted,
                    defineModeEnabled: controller.defineModeEnabled,
                    playbackSpeed: controller.voicePlaybackSpeed,
                    onLike: () async {
                      final ok = await ensureLoggedIn(context);
                      if (!ok || !context.mounted) {
                        return;
                      }
                      await controller.toggleReelLike(reel);
                    },
                    onCommentsTap: onCommentsTap,
                    onTranslationTap: onTranslationTap,
                    onDefineTap: onDefineTap ??
                        () {
                          controller.setDefineMode(!controller.defineModeEnabled);
                        },
                    onVoiceTap: onVoiceTap,
                    onVoiceLongPress: onVoiceLongPress,
                    onSpeedTap: onSpeedTap ??
                        () {
                          VoiceSpeedSheet.show(
                            context,
                            speed: controller.voicePlaybackSpeed,
                            onSpeedChanged: (speed) {
                              controller.setVoicePlaybackSpeed(
                                speed,
                                persist: false,
                              );
                            },
                            onSpeedChangeEnd: (speed) {
                              controller.setVoicePlaybackSpeed(speed);
                            },
                          );
                        },
                  );
                },
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

class _WordStudyGroups extends StatelessWidget {
  const _WordStudyGroups({
    required this.study,
    required this.textStyle,
  });

  final WordStudy study;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final groups = study.allGroups;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 8,
          children: [
            for (final group in groups)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => WordDefinitionSheet.show(context, group),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: Colors.amberAccent.withValues(alpha: 0.85),
                          width: 2,
                        ),
                      ),
                    ),
                    child: Text(
                      group.phrase,
                      textAlign: TextAlign.center,
                      style: textStyle,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'BSB',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
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
