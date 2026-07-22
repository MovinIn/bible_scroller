import 'package:flutter/material.dart';

import '../services/storage_service.dart';
import '../utils/voice_playback_speed.dart';

class VoiceSpeedSheet extends StatefulWidget {
  const VoiceSpeedSheet({
    super.key,
    required this.speed,
    required this.onSpeedChanged,
    required this.onSpeedChangeEnd,
  });

  final double speed;
  final ValueChanged<double> onSpeedChanged;
  final ValueChanged<double> onSpeedChangeEnd;

  static Future<void> show(
    BuildContext context, {
    required double speed,
    required ValueChanged<double> onSpeedChanged,
    required ValueChanged<double> onSpeedChangeEnd,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => VoiceSpeedSheet(
        speed: speed,
        onSpeedChanged: onSpeedChanged,
        onSpeedChangeEnd: onSpeedChangeEnd,
      ),
    );
  }

  @override
  State<VoiceSpeedSheet> createState() => _VoiceSpeedSheetState();
}

class _VoiceSpeedSheetState extends State<VoiceSpeedSheet> {
  late double _speed;

  @override
  void initState() {
    super.initState();
    _speed = StorageService.clampVoicePlaybackSpeed(widget.speed);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Playback speed',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              formatVoicePlaybackSpeed(_speed),
              key: const Key('voice_speed_label'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.amberAccent,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            Slider(
              key: const Key('voice_speed_slider'),
              value: _speed,
              min: StorageService.minVoicePlaybackSpeed,
              max: StorageService.maxVoicePlaybackSpeed,
              divisions: 6,
              label: formatVoicePlaybackSpeed(_speed),
              onChanged: (value) {
                setState(() => _speed = value);
                widget.onSpeedChanged(value);
              },
              onChangeEnd: widget.onSpeedChangeEnd,
            ),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('0.5x', style: TextStyle(color: Colors.white54)),
                Text('2x', style: TextStyle(color: Colors.white54)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
