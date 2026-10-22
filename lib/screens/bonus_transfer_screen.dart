import 'package:flutter/cupertino.dart';

import '../config/app_theme.dart';
import '../models/bonus_program/point_balance.dart';
import '../models/bonus_program/point_transfer.dart';
import '../models/staff_user.dart';
import '../repositories/bonus_program_repository.dart';
import '../services/api_client.dart';
import '../widgets/app_glass.dart';
import '../widgets/app_loading.dart';
import '../widgets/bonus_glass.dart';
import '../widgets/booking_glass_form.dart';
import '../widgets/chat_avatar.dart';
import '../widgets/staff_user_picker_sheet.dart';

const _kMinTransferPoints = 10;

/// Перевод баллов другому сотруднику.
class BonusTransferScreen extends StatefulWidget {
  const BonusTransferScreen({super.key});

  @override
  State<BonusTransferScreen> createState() => _BonusTransferScreenState();
}

class _BonusTransferScreenState extends State<BonusTransferScreen> {
  final _pointsController = TextEditingController();
  final _commentController = TextEditingController();

  StaffUser? _recipient;
  PointBalance? _balance;
  bool _isLoadingBalance = true;
  String? _balanceError;
  bool _isSubmitting = false;
  String? _errorMessage;

  int _minTransferPoints = _kMinTransferPoints;
  int _maxTransferPoints = 0;
  bool _transferEnabled = true;

  @override
  void initState() {
    super.initState();
    _pointsController.addListener(_onFormChanged);
    _loadBalance();
    _loadTransferConfig();
  }

  @override
  void dispose() {
    _pointsController.removeListener(_onFormChanged);
    _pointsController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  void _onFormChanged() => setState(() {});

  Future<void> _loadBalance() async {
    setState(() {
      _isLoadingBalance = true;
      _balanceError = null;
    });
    try {
      final balance = await BonusProgramRepository.instance.getBalance();
      if (!mounted) return;
      setState(() {
        _balance = balance;
        _isLoadingBalance = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingBalance = false;
        _balanceError = 'Не удалось загрузить баланс';
      });
    }
  }

  Future<void> _loadTransferConfig() async {
    try {
      final config = await BonusProgramRepository.instance.getTransferConfig();
      if (!mounted) return;
      setState(() {
        _minTransferPoints = config.minPoints;
        _maxTransferPoints = config.maxPoints;
        _transferEnabled = config.enabled;
      });
    } catch (_) {
      // Оставляем значения по умолчанию, если настройки недоступны.
    }
  }

  int? get _points => int.tryParse(_pointsController.text.trim());

  String? get _amountError {
    final points = _points;
    if (_pointsController.text.trim().isEmpty) return null;
    if (points == null || points < _minTransferPoints) {
      return 'Минимальная сумма перевода — $_minTransferPoints баллов';
    }
    if (_maxTransferPoints > 0 && points > _maxTransferPoints) {
      return 'Максимальная сумма перевода — $_maxTransferPoints баллов';
    }
    final balance = _balance;
    if (balance != null && points > balance.points) {
      return 'Недостаточно баллов на балансе';
    }
    return null;
  }

  String get _limitsHint {
    if (!_transferEnabled) {
      return 'Перевод баллов сейчас отключён в настройках компании.';
    }
    final min = 'Минимальная сумма перевода — $_minTransferPoints баллов.';
    if (_maxTransferPoints > 0) {
      return '$min Максимум — $_maxTransferPoints баллов.';
    }
    return min;
  }

  bool get _canSubmit {
    if (!_transferEnabled) return false;
    if (_isSubmitting || _recipient == null) return false;
    final points = _points;
    if (points == null || points < _minTransferPoints) return false;
    if (_maxTransferPoints > 0 && points > _maxTransferPoints) return false;
    final balance = _balance;
    if (balance != null && points > balance.points) return false;
    return true;
  }

  void _pickRecipient() {
    StaffUserPickerSheet.show(
      context,
      selectedIds: _recipient == null ? const {} : {_recipient!.id},
      onUserSelected: (user) {
        setState(() => _recipient = user);
        Navigator.of(context).pop();
      },
    );
  }

  Future<void> _submit() async {
    final recipient = _recipient;
    final recipientId = recipient?.idAsInt;
    final points = _points;
    if (recipient == null || recipientId == null || points == null) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final transfer = await BonusProgramRepository.instance.transferPoints(
        recipientUserId: recipientId,
        points: points,
        comment: _commentController.text,
      );
      if (!mounted) return;
      final balance = _balance;
      if (balance != null) {
        setState(
          () => _balance = PointBalance(
            userId: balance.userId,
            surname: balance.surname,
            name: balance.name,
            position: balance.position,
            points: balance.points - transfer.points,
            pointsSpentTotal: balance.pointsSpentTotal,
          ),
        );
      }
      await _showSuccess(transfer);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = e is ApiException
            ? e.message
            : 'Не удалось перевести баллы';
      });
    }
  }

  Future<void> _showSuccess(PointTransfer transfer) {
    return showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Готово 🎉'),
        content: Text(
          'Переведено ${formatPoints(transfer.points)}'
          '${transfer.recipientName != null ? ' — ${transfer.recipientName}' : ''}.'
          '${_balance != null ? '\nОстаток: ${formatPoints(_balance!.points)}.' : ''}',
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(context),
            child: const Text('Ок'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final label = CupertinoColors.label.resolveFrom(context);
    final recipient = _recipient;
    return BonusGlassScaffold(
      title: 'Перевести баллы',
      canPop: !_isSubmitting,
      slivers: [
        SliverList.list(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _BalanceCard(
                balance: _balance,
                isLoading: _isLoadingBalance,
                error: _balanceError,
                onRetry: _loadBalance,
              ),
            ),
            const AppGlassSectionLabel('Получатель'),
            AppGlassSection(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                CupertinoListTile(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 14, 10),
                  leadingSize: 40,
                  leading: recipient != null
                      ? MemberAvatar(
                          displayName: recipient.fullName,
                          avatarUrl: recipient.avatarUrl,
                          radius: 20,
                        )
                      : Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            CupertinoIcons.person_fill,
                            size: 20,
                            color: AppColors.primary,
                          ),
                        ),
                  title: Text(
                    recipient?.fullName ?? 'Выбрать сотрудника',
                    style: TextStyle(
                      fontSize: 16,
                      color: recipient != null ? label : AppColors.primary,
                    ),
                  ),
                  subtitle: recipient?.department != null
                      ? Text(recipient!.department!)
                      : null,
                  trailing: const CupertinoListTileChevron(),
                  onTap: _isSubmitting ? null : _pickRecipient,
                ),
              ],
            ),
            const AppGlassSectionLabel('Сумма'),
            AppGlassSection(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                CupertinoTextField(
                  controller: _pointsController,
                  keyboardType: TextInputType.number,
                  placeholder: 'Количество баллов',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: label,
                  ),
                  suffix: Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Text(
                      pointsWord(_points ?? 0),
                      style: TextStyle(color: secondary, fontSize: 15),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                  decoration: const BoxDecoration(),
                ),
              ],
            ),
            BookingFootnote(
              _amountError ?? _limitsHint,
              isError: _amountError != null,
            ),
            const AppGlassSectionLabel('Комментарий'),
            AppGlassSection(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                CupertinoTextField(
                  controller: _commentController,
                  placeholder: 'Необязательно',
                  textCapitalization: TextCapitalization.sentences,
                  minLines: 1,
                  maxLines: 4,
                  style: TextStyle(fontSize: 16, color: label),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: const BoxDecoration(),
                ),
              ],
            ),
            if (_errorMessage != null)
              BookingFootnote(_errorMessage!, isError: true),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
              child: AppPrimaryButton(
                label: 'Перевести',
                isLoading: _isSubmitting,
                onPressed: _canSubmit ? _submit : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Сколько баллов доступно перевести — прямо на экране перевода.
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.balance,
    required this.isLoading,
    this.error,
    this.onRetry,
  });

  final PointBalance? balance;
  final bool isLoading;
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const AppSkeletonBox(height: 64, borderRadius: 22);
    }
    final balance = this.balance;
    if (error == null && balance == null) return const SizedBox.shrink();

    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final tint = error != null
        ? CupertinoColors.systemRed.resolveFrom(context)
        : AppColors.primary;
    return AppGlass(
      borderRadius: BorderRadius.circular(22),
      shadows: AppGlass.controlShadow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: isDark ? 0.24 : 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                error != null
                    ? CupertinoIcons.exclamationmark_triangle_fill
                    : CupertinoIcons.star_fill,
                size: 19,
                color: tint,
              ),
            ),
            const SizedBox(width: 12),
            if (error != null) ...[
              Expanded(
                child: Text(
                  error!,
                  style: TextStyle(fontSize: 15, color: tint),
                ),
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                onPressed: onRetry,
                child: const Text(
                  'Повторить',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ] else ...[
              Expanded(
                child: Text(
                  'Доступно',
                  style: TextStyle(
                    fontSize: 15,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
              ),
              Text(
                formatPoints(balance!.points),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
