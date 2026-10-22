import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';

import '../config/app_theme.dart';
import '../models/surveys/survey_invitation.dart';
import '../repositories/surveys_repository.dart';
import '../services/survey_pending_service.dart';
import '../utils/app_feedback.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/app_glass.dart';
import '../widgets/app_icon_badge.dart';
import '../widgets/app_loading.dart';
import 'survey_form_screen.dart';

/// «Мои опросы»: приглашения, ожидающие ответа, и уже пройденные.
class SurveysScreen extends StatefulWidget {
  const SurveysScreen({super.key});

  /// Открывает форму приглашения: отмечает открытие на портале (для
  /// воронки кампании) и после закрытия формы обновляет бейдж.
  static Future<void> openInvitation(
    BuildContext context,
    SurveyInvitation invitation,
  ) async {
    final pending = SurveyPendingService.instance;
    pending.markOpened(invitation.token);
    if (invitation.id > 0) {
      unawaited(
        SurveysRepository.instance
            .markPortalOpen(invitation.id)
            .catchError((_) {}),
      );
    }
    await Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) =>
            SurveyFormScreen(token: invitation.token, title: invitation.title),
      ),
    );
    unawaited(pending.refreshQuietly());
  }

  @override
  State<SurveysScreen> createState() => _SurveysScreenState();
}

class _SurveysScreenState extends State<SurveysScreen> {
  final _pending = SurveyPendingService.instance;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _pending.addListener(_onChanged);
    _load(showLoader: !_pending.isLoaded);
  }

  @override
  void dispose() {
    _pending.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load({bool showLoader = false}) async {
    if (showLoader) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    try {
      await _pending.refresh();
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = AppFeedback.messageOf(
          e,
          fallback: 'Не удалось получить список опросов',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppGlassBarBlur(
      threshold: AppGlassBarBlur.largeTitleThreshold,
      builder: (context, blur) => CupertinoPageScaffold(
        backgroundColor: CupertinoColors.systemGroupedBackground,
        child: DefaultTextStyle(
          style: TextStyle(
            fontFamily: '.SF Pro Text',
            color: CupertinoColors.label.resolveFrom(context),
            decoration: TextDecoration.none,
            fontSize: 16,
          ),
          child: Stack(
            children: [
              const AppGlassGlow(),
              SafeArea(
                top: false,
                bottom: false,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    CupertinoSliverNavigationBar(
                      largeTitle: const Text('Опросы'),
                      leading: CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        onPressed: () => Navigator.maybePop(context),
                        child: Icon(
                          CupertinoIcons.back,
                          size: 26,
                          color: CupertinoColors.label.resolveFrom(context),
                        ),
                      ),
                      // Прозрачная: заливка дала бы на цветном пятне видимую границу.
                      // Размытие — только при прокрутке (AppGlassBarBlur).
                      backgroundColor: CupertinoColors.systemGroupedBackground
                          .resolveFrom(context)
                          .withValues(alpha: 0),
                      automaticBackgroundVisibility: false,
                      enableBackgroundFilterBlur: blur,
                      border: null,
                    ),
                    CupertinoSliverRefreshControl(onRefresh: _load),
                    ..._buildBody(),
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: MediaQuery.paddingOf(context).bottom + 24,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildBody() {
    if (_isLoading) {
      return [
        AppGlassSliverList(
          itemCount: 5,
          itemBuilder: (context, index) => const AppSkeletonListTile(),
        ),
      ];
    }

    final now = DateTime.now();
    final invitations = _pending.invitations;
    if (invitations.isEmpty && _error != null) {
      return [
        SliverAppEmptyState(
          icon: CupertinoIcons.exclamationmark_triangle,
          message: _error!,
          onRetry: () => _load(showLoader: true),
        ),
      ];
    }
    if (invitations.isEmpty) {
      return const [
        SliverAppEmptyState(
          icon: CupertinoIcons.checkmark_seal,
          message:
              'Опросов пока нет. Когда вас пригласят пройти опрос, '
              'он появится здесь.',
        ),
      ];
    }

    final active = invitations.where((i) => i.isPending(now)).toList()
      ..sort(_byDeadline);
    final past = invitations.where((i) => !i.isPending(now)).toList()
      ..sort(
        (a, b) => (b.completedAt ?? b.closesAt ?? DateTime(0)).compareTo(
          a.completedAt ?? a.closesAt ?? DateTime(0),
        ),
      );

    return [
      if (active.isNotEmpty)
        ..._section('Ожидают ответа', active, now)
      else
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 8, 32, 4),
            child: Text(
              'Все опросы пройдены — спасибо!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
          ),
        ),
      if (past.isNotEmpty) ..._section('Завершённые', past, now),
    ];
  }

  static int _byDeadline(SurveyInvitation a, SurveyInvitation b) {
    final ac = a.closesAt;
    final bc = b.closesAt;
    if (ac == null && bc == null) return b.id.compareTo(a.id);
    if (ac == null) return 1;
    if (bc == null) return -1;
    return ac.compareTo(bc);
  }

  List<Widget> _section(
    String title,
    List<SurveyInvitation> items,
    DateTime now,
  ) {
    return [
      SliverToBoxAdapter(child: AppGlassSectionLabel(title)),
      SliverToBoxAdapter(
        child: AppGlassSection(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            for (final item in items)
              _SurveyTile(
                invitation: item,
                now: now,
                onTap: item.isPending(now)
                    ? () => SurveysScreen.openInvitation(context, item)
                    : null,
              ),
          ],
        ),
      ),
    ];
  }
}

class _SurveyTile extends StatelessWidget {
  const _SurveyTile({
    required this.invitation,
    required this.now,
    required this.onTap,
  });

  final SurveyInvitation invitation;
  final DateTime now;
  final VoidCallback? onTap;

  static final _dateFormat = DateFormat('d MMMM, HH:mm', 'ru_RU');

  IconData get _icon => switch (invitation.surveyType) {
    'nps' => CupertinoIcons.gauge,
    'form' => CupertinoIcons.doc_text_fill,
    _ => CupertinoIcons.chart_bar_square_fill,
  };

  String? get _subtitle {
    if (invitation.isCompleted) {
      final at = invitation.completedAt;
      return at == null ? 'Пройден' : 'Пройден ${_dateFormat.format(at)}';
    }
    final closes = invitation.closesAt;
    if (invitation.isPending(now)) {
      if (invitation.status == SurveyRecipientStatus.started) {
        return closes == null
            ? 'Начат, не завершён'
            : 'Начат · до ${_dateFormat.format(closes)}';
      }
      return closes == null ? null : 'До ${_dateFormat.format(closes)}';
    }
    return 'Приём ответов завершён';
  }

  @override
  Widget build(BuildContext context) {
    final pending = invitation.isPending(now);
    final isNew = invitation.isNew(now);
    final color = invitation.isCompleted
        ? CupertinoColors.systemGreen
        : pending
        ? CupertinoColors.systemPurple
        : CupertinoColors.systemGrey;
    final subtitle = _subtitle;
    return CupertinoListTile(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 14, 12),
      leading: AppIconBadge(
        icon: invitation.isCompleted ? CupertinoIcons.checkmark_alt : _icon,
        color: color,
      ),
      title: Text(
        invitation.title.isEmpty ? 'Опрос' : invitation.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: isNew ? FontWeight.w600 : FontWeight.w400,
          color: pending
              ? CupertinoColors.label.resolveFrom(context)
              : CupertinoColors.secondaryLabel.resolveFrom(context),
        ),
      ),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: pending
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isNew)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Новый',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: CupertinoColors.white,
                      ),
                    ),
                  ),
                const SizedBox(width: 6),
                const CupertinoListTileChevron(),
              ],
            )
          : null,
      onTap: onTap,
    );
  }
}
