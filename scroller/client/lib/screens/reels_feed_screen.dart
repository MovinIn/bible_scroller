import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/reels_controller.dart';
import '../utils/page_wheel_navigator.dart';
import '../utils/playback_splash_icon.dart';
import '../widgets/book_picker_sheet.dart';
import '../widgets/comments_sheet.dart';
import '../widgets/playback_splash_overlay.dart';
import '../widgets/reel_page.dart';

class ReelsFeedScreen extends StatefulWidget {
  const ReelsFeedScreen({super.key, this.wheelNavigator});

  /// Injectable for tests (e.g. zero cooldown).
  final PageWheelNavigator? wheelNavigator;

  @override
  State<ReelsFeedScreen> createState() => _ReelsFeedScreenState();
}

class _ReelsFeedScreenState extends State<ReelsFeedScreen> {
  late final PageController _pageController;
  late final PageWheelNavigator _wheelNavigator;
  double _dragDistance = 0;
  final Map<int, PlaybackSplashController> _splashControllers = {};

  @override
  void initState() {
    super.initState();
    _wheelNavigator = widget.wheelNavigator ?? PageWheelNavigator();
    _pageController = PageController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ReelsController>().initialize();
    });
  }

  @override
  void dispose() {
    for (final controller in _splashControllers.values) {
      controller.dispose();
    }
    _pageController.dispose();
    super.dispose();
  }

  PlaybackSplashController _splashFor(Reel reel) {
    return _splashControllers.putIfAbsent(reel.id, PlaybackSplashController.new);
  }

  void _flashPlaybackSplash(Reel reel, PlaybackSplashIcon icon) {
    _splashFor(reel).flash(icon);
  }

  void _handlePointerSignal(PointerSignalEvent event, int itemCount) {
    if (event is! PointerScrollEvent) {
      return;
    }

    if (!_pageController.hasClients) {
      return;
    }

    final page = _pageController.page?.round() ?? _pageController.initialPage;
    final controller = context.read<ReelsController>();
    final canGoNext = page < itemCount - 1 || controller.canLoadNext;
    final canGoPrevious = page > 0 || controller.canLoadPrevious;
    final action = _wheelNavigator.resolve(
      event.scrollDelta.dy,
      canGoNext: canGoNext,
      canGoPrevious: canGoPrevious,
    );

    if (action == null) {
      return;
    }
    unawaited(_animateToAction(action, itemCount));
  }

  void _handleVerticalDragStart(DragStartDetails details) {
    _dragDistance = 0;
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    _dragDistance += details.delta.dy;
  }

  void _handleVerticalDragEnd(DragEndDetails details, int itemCount) {
    if (!_pageController.hasClients) {
      return;
    }

    final velocity = details.primaryVelocity ?? 0;
    final distance = _dragDistance;
    _dragDistance = 0;

    // A quick flick (velocity) or a deliberate half-swipe (distance) both
    // count as a page change; direction is up = next, down = previous.
    final double signal;
    if (velocity.abs() >= 150) {
      signal = velocity;
    } else if (distance.abs() >= 60) {
      signal = distance;
    } else {
      return;
    }

    final page = _pageController.page?.round() ?? _pageController.initialPage;
    final controller = context.read<ReelsController>();
    if (signal < 0) {
      unawaited(_animateToAction(PageWheelAction.next, itemCount));
    } else if (signal > 0 && (page > 0 || controller.canLoadPrevious)) {
      unawaited(_animateToAction(PageWheelAction.previous, itemCount));
    }
  }

  Future<void> _animateToAction(PageWheelAction action, int itemCount) async {
    if (!_pageController.hasClients || !mounted) {
      return;
    }

    const duration = Duration(milliseconds: 280);
    const curve = Curves.easeOut;
    final controller = context.read<ReelsController>();
    final page = _pageController.page?.round() ?? _pageController.initialPage;

    if (action == PageWheelAction.next) {
      if (page >= itemCount - 1) {
        final loaded = await controller.ensureNextPageLoaded();
        if (!mounted || !_pageController.hasClients) {
          return;
        }
        itemCount = controller.reels.length;
        if (!loaded || page >= itemCount - 1) {
          return;
        }
      }
      await _pageController.nextPage(duration: duration, curve: curve);
      return;
    }

    if (page > 0) {
      await _pageController.previousPage(duration: duration, curve: curve);
      return;
    }

    final added = await controller.prependPreviousPage();
    if (!mounted || !_pageController.hasClients || added == 0) {
      return;
    }
    _pageController.jumpToPage(added);
    await _pageController.previousPage(duration: duration, curve: curve);
  }

  void _openComments(Reel reel) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CommentsSheet(
        reel: reel,
        controller: context.read<ReelsController>(),
      ),
    );
  }

  Future<void> _openTranslationPicker(ReelsController controller) async {
    await controller.ensureVersionsLoaded();
    if (!mounted) {
      return;
    }
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF121212),
      builder: (context) {
        return SafeArea(
          child: ListView(
            children: [
              const ListTile(title: Text('Choose translation')),
              ...controller.versions.map(
                (version) => ListTile(
                  title: Text(version.name),
                  subtitle: Text(version.versionId.toUpperCase()),
                  trailing: controller.translationVersion == version.versionId
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.pop(context, version.versionId),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (selected != null) {
      await controller.setTranslation(selected);
    }
  }

  Future<void> _openBookPicker(ReelsController controller, Reel reel) async {
    await controller.ensureBooksLoaded();
    if (!mounted) {
      return;
    }
    final books = controller.books.isNotEmpty ? controller.books : [reel.book];
    final selected = await showBookPickerSheet(
      context,
      books: books,
      currentBook: reel.book,
    );
    if (selected == null || selected == reel.book || !mounted) {
      return;
    }

    final index = await controller.jumpToBook(selected);
    if (!mounted) {
      return;
    }
    if (index == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No reels for $selected')));
      return;
    }
    if (_pageController.hasClients) {
      _pageController.jumpToPage(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ReelsController>(
      builder: (context, controller, _) {
        if (controller.loading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (controller.error != null) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wifi_off, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      'Could not load reels',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(controller.error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: controller.refreshFeed,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        if (controller.reels.isEmpty) {
          return const Scaffold(body: Center(child: Text('No reels yet')));
        }

        final itemCount = controller.reels.length;
        return Scaffold(
          body: Listener(
            onPointerSignal: (event) => _handlePointerSignal(event, itemCount),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragStart: _handleVerticalDragStart,
              onVerticalDragUpdate: _handleVerticalDragUpdate,
              onVerticalDragEnd: (details) =>
                  _handleVerticalDragEnd(details, itemCount),
              child: PageView.builder(
                controller: _pageController,
                scrollDirection: Axis.vertical,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: itemCount,
                onPageChanged: (index) => controller.onReelVisible(index),
                itemBuilder: (context, index) {
                  final reel = controller.reels[index];
                  return ReelPage(
                    reel: reel,
                    controller: controller,
                    playbackSplashController: _splashFor(reel),
                    onCommentsTap: () => _openComments(reel),
                    onTranslationTap: () => _openTranslationPicker(controller),
                    onVoiceTap: () => controller.toggleMute(),
                    onBookTap: () => _openBookPicker(controller, reel),
                    onBodyTap: () async {
                      // Flash before awaiting play so failures still show splash.
                      final intended = controller.peekVoiceoverTapAction(reel);
                      _flashPlaybackSplash(
                        reel,
                        playbackSplashIconFor(intended),
                      );
                      try {
                        await controller.toggleVoiceoverPlayback(reel);
                      } catch (_) {
                        // Audio may be unavailable (bad URL / HLS / missing key).
                      }
                    },
                    onVoiceLongPress: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await controller.setAutoplayVoice(
                        !controller.autoplayVoice,
                      );
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            controller.autoplayVoice
                                ? 'Autoplay voice enabled'
                                : 'Autoplay voice disabled',
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
