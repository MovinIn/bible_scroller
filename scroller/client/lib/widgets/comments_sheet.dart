import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/auth_controller.dart';
import '../state/reels_controller.dart';
import 'auth_gate.dart';
import 'auth_sheet.dart';

class CommentsSheet extends StatefulWidget {
  const CommentsSheet({
    super.key,
    required this.reel,
    required this.controller,
  });

  final Reel reel;
  final ReelsController controller;

  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  final _textController = TextEditingController();
  List<Comment> _comments = const [];
  bool _loading = true;
  String? _error;
  Comment? _replyTo;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final comments = await widget.controller.loadComments(widget.reel.id);
      setState(() {
        _comments = comments;
        _loading = false;
      });
    } catch (err) {
      setState(() {
        _error = err.toString();
        _loading = false;
      });
    }
  }

  Future<void> _submit() async {
    final body = _textController.text.trim();
    if (body.isEmpty) {
      return;
    }

    final ok = await ensureLoggedIn(context);
    if (!ok || !mounted) {
      return;
    }

    final parentId = _replyTo?.id;
    _textController.clear();
    setState(() => _replyTo = null);

    await widget.controller.addComment(widget.reel.id, body, parentId: parentId);
    await _load();
  }

  void _startReply(Comment comment) {
    setState(() => _replyTo = comment);
  }

  void _cancelReply() {
    setState(() => _replyTo = null);
  }

  List<_CommentNode> _buildThread() {
    final byParent = <int?, List<Comment>>{};
    for (final comment in _comments) {
      byParent.putIfAbsent(comment.parentId, () => []).add(comment);
    }

    void appendChildren(int? parentId, int depth, List<_CommentNode> output) {
      final children = byParent[parentId] ?? const [];
      for (final comment in children) {
        output.add(_CommentNode(comment: comment, depth: depth));
        appendChildren(comment.id, depth + 1, output);
      }
    }

    final nodes = <_CommentNode>[];
    appendChildren(null, 0, nodes);
    return nodes;
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Widget _buildComposerFooter(bool isLoggedIn) {
    if (!isLoggedIn) {
      final bodyStyle = Theme.of(context).textTheme.bodyMedium;
      final linkStyle = bodyStyle?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        decoration: TextDecoration.underline,
      );
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Center(
            child: GestureDetector(
              key: const Key('sign_in_to_comment'),
              onTap: () => AuthSheet.show(context),
              child: Text.rich(
                TextSpan(
                  style: bodyStyle,
                  children: [
                    TextSpan(text: 'Sign in', style: linkStyle),
                    const TextSpan(text: ' to comment'),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _textController,
                decoration: InputDecoration(
                  hintText: _replyTo == null ? 'Add a comment…' : 'Write a reply…',
                  filled: true,
                  fillColor: const Color(0xFF1E1E1E),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _submit,
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final thread = _buildThread();
    final isLoggedIn = context.watch<AuthController>().isLoggedIn;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.45,
        maxChildSize: 0.92,
        builder: (context, scrollController) {
          return Material(
            color: const Color(0xFF121212),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Text(
                        '${widget.reel.commentCount} comments',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? Center(child: Text(_error!))
                          : ListView.builder(
                              controller: scrollController,
                              itemCount: thread.length,
                              itemBuilder: (context, index) {
                                final node = thread[index];
                                final comment = node.comment;
                                return Padding(
                                  padding: EdgeInsets.only(left: 16 + (node.depth * 20)),
                                  child: ListTile(
                                    title: Text(comment.authorName),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(comment.body),
                                        TextButton(
                                          onPressed: () async {
                                            final ok = await ensureLoggedIn(context);
                                            if (!ok || !mounted) {
                                              return;
                                            }
                                            _startReply(comment);
                                          },
                                          child: const Text('Reply'),
                                        ),
                                      ],
                                    ),
                                    trailing: IconButton(
                                      onPressed: () async {
                                        final ok = await ensureLoggedIn(context);
                                        if (!ok || !mounted) {
                                          return;
                                        }
                                        await widget.controller.toggleCommentLike(comment);
                                        await _load();
                                      },
                                      icon: Icon(
                                        comment.likedByMe
                                            ? Icons.favorite
                                            : Icons.favorite_border,
                                        color: comment.likedByMe
                                            ? Colors.redAccent
                                            : Colors.white70,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                ),
                if (isLoggedIn && _replyTo != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Replying to ${_replyTo!.authorName}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        TextButton(onPressed: _cancelReply, child: const Text('Cancel')),
                      ],
                    ),
                  ),
                _buildComposerFooter(isLoggedIn),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CommentNode {
  const _CommentNode({required this.comment, required this.depth});

  final Comment comment;
  final int depth;
}
