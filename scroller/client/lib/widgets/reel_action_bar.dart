import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../utils/voice_playback_speed.dart';

class ReelActionBar extends StatelessWidget {
  const ReelActionBar({
    super.key,
    required this.reel,
    required this.translationVersion,
    required this.isMuted,
    required this.defineModeEnabled,
    required this.playbackSpeed,
    required this.onLike,
    required this.onCommentsTap,
    required this.onTranslationTap,
    required this.onDefineTap,
    required this.onVoiceTap,
    required this.onSpeedTap,
    this.onVoiceLongPress,
  });

  final Reel reel;
  final String translationVersion;
  final bool isMuted;
  final bool defineModeEnabled;
  final double playbackSpeed;
  final VoidCallback onLike;
  final VoidCallback onCommentsTap;
  final VoidCallback onTranslationTap;
  final VoidCallback onDefineTap;
  final VoidCallback onVoiceTap;
  final VoidCallback onSpeedTap;
  final VoidCallback? onVoiceLongPress;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionButton(
          icon: reel.likedByMe ? Icons.favorite : Icons.favorite_border,
          label: _formatCount(reel.likeCount),
          color: reel.likedByMe ? Colors.redAccent : Colors.white,
          onTap: onLike,
        ),
        const SizedBox(height: 18),
        _ActionButton(
          icon: Icons.mode_comment_outlined,
          label: _formatCount(reel.commentCount),
          onTap: onCommentsTap,
        ),
        const SizedBox(height: 18),
        _ActionButton(
          icon: Icons.translate,
          label: translationVersion.toUpperCase(),
          onTap: onTranslationTap,
        ),
        const SizedBox(height: 18),
        _ActionButton(
          // Full CupertinoIcons font — safe when MaterialIcons tree-shake cache is stale.
          icon: defineModeEnabled
              ? CupertinoIcons.book_solid
              : CupertinoIcons.book,
          label: defineModeEnabled ? 'BSB' : 'Define',
          color: defineModeEnabled ? Colors.amberAccent : Colors.white,
          onTap: onDefineTap,
        ),
        const SizedBox(height: 18),
        _ActionButton(
          icon: isMuted ? Icons.volume_off_outlined : Icons.volume_up_outlined,
          label: isMuted ? 'Muted' : '',
          onTap: onVoiceTap,
          onLongPress: onVoiceLongPress,
        ),
        const SizedBox(height: 18),
        _ActionButton(
          icon: Icons.speed,
          label: formatVoicePlaybackSpeed(playbackSpeed),
          onTap: onSpeedTap,
        ),
      ],
    );
  }

  String _formatCount(int value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    }
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}K';
    }
    return value == 0 ? '' : '$value';
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.onLongPress,
    this.color = Colors.white,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(999),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          if (label.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
