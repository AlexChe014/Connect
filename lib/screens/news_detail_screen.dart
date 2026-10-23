import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../config/app_theme.dart';
import '../models/news_comment.dart';
import '../models/news_item.dart';
import '../repositories/comments_repository.dart';
import '../repositories/news_repository.dart';
import '../services/auth_service.dart';
import '../services/paginated.dart';
import '../utils/app_feedback.dart';
import '../utils/html_text_utils.dart';
import '../widgets/app_glass.dart';
import '../widgets/app_loading.dart';
import '../widgets/app_title_bar.dart';
import '../widgets/chat_avatar.dart';
import '../widgets/chat_message_text.dart';
import '../widgets/news_glass.dart';
import '../widgets/news_people_sheet.dart';
import '../widgets/news_reactions.dart';
import 'news_image_viewer_screen.dart';

class NewsDetailScreen extends StatefulWidget {
  const NewsDetailScreen({super.key, required this.news});

  final NewsItem news;

  @override
  State<NewsDetailScreen> createState() => _NewsDetailScreenState();
}

class _NewsDetailScreenState extends State<NewsDetailScreen> {
  late NewsItem _news;
  final _commentController = TextEditingController();
  final _scrollController = ScrollController();

  List<NewsComment> _comments = [];
  bool _commentsLoading = true;
  bool _commentsLoadingMore = false;
  String? _commentsNextUrl;
  bool _sendingComment = false;
  bool _reactionInFlight = false;
  bool _viewRecordedForOpen = false;
  String? _currentUserId;
  final Set<String> _deletingCommentIds = {};
  bool _isDeletingPost = false;

  @override
  void initState() {
    super.initState();
    _news = widget.news;
    _scrollController.addListener(_onScroll);
    _loadCurrentUserId();
    _loadComments();
    _refreshNews();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _refreshNews() async {
    try {
      final fresh = await NewsRepository.instance.getById(
        _news.id,
        includePeople: true,
      );
      if (!mounted) return;
      setState(() => _news = fresh);
    } catch (_) {
      // оставляем данные из списка
    }
  }

  Future<void> _recordView() async {
    if (_news.id.isEmpty) return;
    try {
      await NewsRepository.instance.addView(_news.id);
      if (!mounted) return;
      setState(() {
        _news = _news.copyWith(
          viewsCount: _news.viewsCount + 1,
          isViewed: true,
        );
      });
    } catch (_) {}
  }

  void _onNewsFullyVisible(VisibilityInfo info) {
    if (info.visibleFraction < 1.0) return;
    if (_viewRecordedForOpen) return;
    _viewRecordedForOpen = true;
    _recordView();
  }

  Future<void> _toggleReaction(String emoji) async {
    if (_reactionInFlight || _news.id.isEmpty) return;
    setState(() => _reactionInFlight = true);
    try {
      await toggleNewsReaction(
        _news,
        emoji,
        onUpdate: (news) {
          if (mounted) setState(() => _news = news);
        },
      );
      // Подтягиваем точные группы реакций и списки пользователей с сервера.
      unawaited(_refreshNews());
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showSnackBar(
        context,
        e,
        fallback: 'Не удалось поставить реакцию',
      );
    } finally {
      if (mounted) setState(() => _reactionInFlight = false);
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_commentsLoading || _commentsLoadingMore) return;
    if (_commentsNextUrl == null) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 240) {
      _loadMoreComments();
    }
  }

  Future<void> _loadComments() async {
    setState(() {
      _commentsLoading = true;
      _commentsNextUrl = null;
      _comments = [];
    });
    try {
      final page = await CommentsRepository.instance.getByNewsPage(
        newsId: _news.id,
      );
      if (!mounted) return;
      setState(() {
        _comments = page.data;
        _commentsNextUrl = page.nextPageUrl;
        _commentsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _commentsLoading = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Не удалось загрузить комментарии')),
      );
    }
  }

  Future<void> _loadMoreComments() async {
    final url = _commentsNextUrl;
    if (url == null || _commentsLoadingMore) return;
    setState(() => _commentsLoadingMore = true);
    try {
      final Paginated<NewsComment> page = await CommentsRepository.instance
          .getByNewsPage(newsId: _news.id, url: url);
      if (!mounted) return;
      setState(() {
        _comments = [..._comments, ...page.data];
        _commentsNextUrl = page.nextPageUrl;
        _commentsLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _commentsLoadingMore = false);
    }
  }

  Future<void> _loadCurrentUserId() async {
    try {
      final user = await AuthService.instance.getStoredUser();
      final id = user?['id'];
      if (!mounted || id == null) return;
      setState(() => _currentUserId = id.toString());
    } catch (_) {}
  }

  bool _canDeleteComment(NewsComment comment) {
    final userId = _currentUserId;
    if (userId == null) return false;
    return comment.author?.id == userId || _news.author?.id == userId;
  }

  bool _canDeletePost() {
    final userId = _currentUserId;
    if (userId == null) return false;
    return _news.author?.id == userId;
  }

  void _showPostActions() {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(context);
              _deletePost();
            },
            child: const Text('Удалить'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
      ),
    );
  }

  Future<void> _deletePost() async {
    if (_isDeletingPost) return;
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Удалить публикацию?'),
        content: const Text(
          'Публикация и все комментарии к ней будут удалены безвозвратно.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isDeletingPost = true);
    try {
      await NewsRepository.instance.delete(newsId: _news.id);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isDeletingPost = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Не удалось удалить публикацию')),
      );
    }
  }

  Future<void> _deleteComment(NewsComment comment) async {
    if (_deletingCommentIds.contains(comment.id)) return;
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Удалить комментарий?'),
        content: const Text('Комментарий будет удалён безвозвратно.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deletingCommentIds.add(comment.id));
    try {
      await CommentsRepository.instance.delete(commentId: comment.id);
      if (!mounted) return;
      setState(() {
        _comments.removeWhere((c) => c.id == comment.id);
        _deletingCommentIds.remove(comment.id);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _deletingCommentIds.remove(comment.id));
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Не удалось удалить комментарий')),
      );
    }
  }

  Future<void> _sendComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty || _sendingComment) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _sendingComment = true);
    try {
      await CommentsRepository.instance.create(newsId: _news.id, text: text);
      if (!mounted) return;
      _commentController.clear();
      await _loadComments();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Не удалось отправить комментарий')),
      );
    } finally {
      if (mounted) setState(() => _sendingComment = false);
    }
  }

  void _openPhotos(List<String> urls, int index) {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).push<void>(
      CupertinoPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) =>
            NewsImageViewerScreen(imageUrls: urls, initialIndex: index),
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildPost(BuildContext context) {
    final photos = _news.imageUrls.isNotEmpty
        ? _news.imageUrls
        : [?_news.imageUrl];
    final body = HtmlTextUtils.compactParagraphs(
      _news.contentHtml.trim().isNotEmpty ? _news.contentHtml : _news.content,
    );

    return AppFlatGlassCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NewsAuthorLine(news: _news, avatarRadius: 20),
          const SizedBox(height: 14),
          Text(
            _news.title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              height: 1.25,
              letterSpacing: -0.3,
            ),
          ),
          if (photos.isNotEmpty) ...[
            const SizedBox(height: 14),
            NewsPhotoGallery(
              urls: photos,
              onOpen: (index) => _openPhotos(photos, index),
            ),
          ],
          if (body.isNotEmpty) ...[
            const SizedBox(height: 14),
            ChatMessageText(
              text: body,
              fontSize: 16,
              paragraphSpacing: 12,
              color: CupertinoColors.label.resolveFrom(context),
            ),
          ],
          if (_news.documents.isNotEmpty) ...[
            const SizedBox(height: 10),
            DecoratedBox(
              decoration: BoxDecoration(
                color: CupertinoColors.tertiarySystemFill.resolveFrom(context),
                borderRadius: BorderRadius.circular(14),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Column(
                  children: [
                    for (final document in _news.documents)
                      NewsDocumentRow(
                        document: document,
                        onError: _showMessage,
                      ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Container(
            height: 0.5,
            color: CupertinoColors.separator.resolveFrom(context),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: NewsReactionsBar(
                  news: _news,
                  isLoading: _reactionInFlight,
                  onToggle: _toggleReaction,
                ),
              ),
              const SizedBox(width: 8),
              NewsStatChip(
                icon: CupertinoIcons.eye,
                label: '${_news.viewsCount}',
                onTap: () => NewsPeopleSheet.show(
                  context,
                  newsId: _news.id,
                  kind: NewsPeopleKind.viewers,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildComments(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 24, 4, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            const Text(
              'Комментарии',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            if (!_commentsLoading && _comments.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(
                '${_comments.length}${_commentsNextUrl != null ? '+' : ''}',
                style: TextStyle(fontSize: 17, color: secondary),
              ),
            ],
          ],
        ),
      ),
      if (_commentsLoading)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: AppLoadingIndicator(),
        )
      else if (_comments.isEmpty)
        AppFlatGlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
          child: Column(
            children: [
              Icon(CupertinoIcons.chat_bubble_2, size: 30, color: secondary),
              const SizedBox(height: 8),
              Text(
                'Пока нет комментариев',
                style: TextStyle(fontSize: 15, color: secondary),
              ),
            ],
          ),
        )
      else
        AppFlatGlassCard(
          child: Column(
            children: [
              for (var i = 0; i < _comments.length; i++) ...[
                if (i > 0)
                  Container(
                    height: 0.5,
                    margin: const EdgeInsets.only(left: 58),
                    color: CupertinoColors.separator.resolveFrom(context),
                  ),
                _CommentTile(
                  comment: _comments[i],
                  isDeleting: _deletingCommentIds.contains(_comments[i].id),
                  canDelete: _canDeleteComment(_comments[i]),
                  onDelete: () => _deleteComment(_comments[i]),
                ),
              ],
            ],
          ),
        ),
      if (_commentsLoadingMore)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: AppLoadingIndicator(size: 20),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final groupedBg = CupertinoColors.systemGroupedBackground.resolveFrom(
      context,
    );
    final label = CupertinoColors.label.resolveFrom(context);

    return AppGlassBarBlur(
      builder: (context, blur) => CupertinoPageScaffold(
        backgroundColor: groupedBg,
        navigationBar: AppTitleBar(
          title: const Text('Новость'),
          blur: blur,
          leading: CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            onPressed: () => Navigator.maybePop(context),
            child: Icon(
              CupertinoIcons.back,
              size: AppTitleBar.iconSize,
              color: label,
            ),
          ),
          trailing: _canDeletePost()
              ? CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  onPressed: _isDeletingPost ? null : _showPostActions,
                  child: _isDeletingPost
                      ? const CupertinoActivityIndicator()
                      : Icon(
                          CupertinoIcons.ellipsis_circle,
                          size: AppTitleBar.iconSize,
                          color: label,
                        ),
                )
              : null,
        ),
        child: DefaultTextStyle(
          style: TextStyle(
            fontFamily: '.SF Pro Text',
            decoration: TextDecoration.none,
            color: label,
            fontSize: 16,
          ),
          child: Stack(
            children: [
              const AppGlassGlow(height: 360),
              Builder(
                // Свой context — под скаффолдом, где в MediaQuery уже учтена
                // высота полупрозрачной шапки.
                builder: (context) => RefreshIndicator.adaptive(
                  edgeOffset: MediaQuery.paddingOf(context).top,
                  onRefresh: () async {
                    await Future.wait([_refreshNews(), _loadComments()]);
                  },
                  child: ListView(
                    controller: _scrollController,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(
                      16,
                      MediaQuery.paddingOf(context).top + 8,
                      16,
                      _CommentComposer.reservedHeight(context) + 16,
                    ),
                    children: [
                      VisibilityDetector(
                        key: Key('news-detail-${_news.id}'),
                        onVisibilityChanged: _onNewsFullyVisible,
                        child: _buildPost(context),
                      ),
                      ..._buildComments(context),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _CommentComposer(
                  controller: _commentController,
                  isSending: _sendingComment,
                  onSend: _sendComment,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Поле комментария — плавающие стеклянные капсулы, как ввод в чате.
class _CommentComposer extends StatelessWidget {
  const _CommentComposer({
    required this.controller,
    required this.isSending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool isSending;
  final VoidCallback onSend;

  /// Сколько места снизу занимает однострочное поле с отступами —
  /// последний комментарий не должен прятаться под стекло.
  static double reservedHeight(BuildContext context) =>
      40 + 14 + _bottomInset(context);

  // Над клавиатурой safe area не нужна: CupertinoPageScaffold уже поднял
  // содержимое, а отступ под «полоску» дал бы зазор над клавишами.
  static double _bottomInset(BuildContext context) =>
      MediaQuery.viewInsetsOf(context).bottom > 0
      ? 8
      : MediaQuery.paddingOf(context).bottom.clamp(8.0, 40.0);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 6, 12, _bottomInset(context)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: AppGlass(
              borderRadius: BorderRadius.circular(20),
              shadows: AppGlass.controlShadow,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 40),
                child: CupertinoTextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 5,
                  enabled: !isSending,
                  textCapitalization: TextCapitalization.sentences,
                  placeholder: 'Комментарий',
                  decoration: const BoxDecoration(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final canSend = controller.text.trim().isNotEmpty && !isSending;
              return GestureDetector(
                onTap: canSend ? onSend : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: canSend
                        ? AppColors.primary
                        : CupertinoColors.tertiarySystemFill.resolveFrom(
                            context,
                          ),
                  ),
                  child: isSending
                      ? const CupertinoActivityIndicator(radius: 9)
                      : Icon(
                          CupertinoIcons.arrow_up,
                          size: 20,
                          color: canSend
                              ? CupertinoColors.white
                              : CupertinoColors.tertiaryLabel.resolveFrom(
                                  context,
                                ),
                        ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Комментарий: аватар, имя и дата в строку, под ними текст.
/// Удалить — долгим нажатием или кнопкой «…».
class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    this.canDelete = false,
    this.isDeleting = false,
    this.onDelete,
  });

  final NewsComment comment;
  final bool canDelete;
  final bool isDeleting;
  final VoidCallback? onDelete;

  void _showActions(BuildContext context) {
    if (!canDelete || isDeleting) return;
    showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(context);
              onDelete?.call();
            },
            child: const Text('Удалить'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final author = comment.author;
    final name = author?.fullName ?? 'Пользователь';
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);

    return Opacity(
      opacity: isDeleting ? 0.4 : 1,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: canDelete ? () => _showActions(context) : null,
        child: Padding(
          padding: EdgeInsets.fromLTRB(14, 12, canDelete ? 4 : 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MemberAvatar(
                displayName: name,
                avatarUrl: author?.avatarUrl,
                radius: 16,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          formatNewsDate(comment.date),
                          style: TextStyle(fontSize: 12, color: secondary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    ChatMessageText(text: comment.text, fontSize: 15),
                  ],
                ),
              ),
              if (canDelete)
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(32, 24),
                  onPressed: isDeleting ? null : () => _showActions(context),
                  child: isDeleting
                      ? const CupertinoActivityIndicator(radius: 8)
                      : Icon(
                          CupertinoIcons.ellipsis,
                          size: 18,
                          color: secondary,
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
