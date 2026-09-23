import 'package:flutter/cupertino.dart';

import '../models/bonus_program/point_balance.dart';
import '../models/bonus_program/point_transfer.dart';
import '../models/staff_user.dart';
import '../repositories/bonus_program_repository.dart';
import '../services/api_client.dart';
import '../widgets/app_loading.dart';
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

  TextStyle _sectionHeaderStyle(BuildContext context) => TextStyle(
    color: CupertinoColors.secondaryLabel.resolveFrom(context),
    fontSize: 13,
    fontWeight: FontWeight.w400,
  );

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
          'Переведено ${transfer.points} баллов'
          '${transfer.recipientName != null ? ' — ${transfer.recipientName}' : ''}.'
          '${_balance != null ? '\nОстаток: ${_balance!.points} баллов.' : ''}',
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
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Перевести баллы'),
        backgroundColor: CupertinoColors.systemGroupedBackground,
        border: null,
      ),
      child: DefaultTextStyle(
        style: TextStyle(
          color: CupertinoColors.label.resolveFrom(context),
          decoration: TextDecoration.none,
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              _BalanceChip(
                balance: _balance,
                isLoading: _isLoadingBalance,
                error: _balanceError,
                onRetry: _loadBalance,
              ),
              const SizedBox(height: 16),
              CupertinoListSection.insetGrouped(
                margin: EdgeInsets.zero,
                header: Text('ПОЛУЧАТЕЛЬ', style: _sectionHeaderStyle(context)),
                children: [
                  CupertinoListTile(
                    leading: _recipient != null
                        ? MemberAvatar(
                            displayName: _recipient!.fullName,
                            avatarUrl: _recipient!.avatarUrl,
                            radius: 18,
                          )
                        : Container(
                            width: 36,
                            height: 36,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: CupertinoColors.systemGrey5.resolveFrom(
                                context,
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              CupertinoIcons.person_fill,
                              size: 18,
                              color: CupertinoColors.secondaryLabel.resolveFrom(
                                context,
                              ),
                            ),
                          ),
                    title: Text(_recipient?.fullName ?? 'Выбрать сотрудника'),
                    subtitle: _recipient?.department != null
                        ? Text(_recipient!.department!)
                        : null,
                    trailing: const CupertinoListTileChevron(),
                    onTap: _pickRecipient,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              CupertinoListSection.insetGrouped(
                margin: EdgeInsets.zero,
                header: Text('СУММА', style: _sectionHeaderStyle(context)),
                footer: Text(
                  _amountError ?? _limitsHint,
                  style: _sectionHeaderStyle(context).copyWith(
                    color: _amountError != null
                        ? CupertinoColors.systemRed
                        : CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
                children: [
                  CupertinoTextField(
                    controller: _pointsController,
                    keyboardType: TextInputType.number,
                    placeholder: 'Количество баллов',
                    suffix: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(
                        'баллов',
                        style: TextStyle(
                          color: CupertinoColors.secondaryLabel.resolveFrom(
                            context,
                          ),
                          fontSize: 15,
                        ),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: null,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              CupertinoListSection.insetGrouped(
                margin: EdgeInsets.zero,
                header: Text(
                  'КОММЕНТАРИЙ',
                  style: _sectionHeaderStyle(context),
                ),
                children: [
                  CupertinoTextField(
                    controller: _commentController,
                    placeholder: 'Необязательно',
                    maxLines: 2,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: null,
                  ),
                ],
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: CupertinoColors.systemRed),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: CupertinoButton.filled(
                  onPressed: _canSubmit ? _submit : null,
                  child: _isSubmitting
                      ? const CupertinoActivityIndicator(
                          color: CupertinoColors.white,
                        )
                      : const Text('Перевести'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Компактная плашка текущего баланса — контекст, сколько баллов доступно
/// перевести, прямо на экране перевода.
class _BalanceChip extends StatelessWidget {
  const _BalanceChip({
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
      return const AppSkeletonBox(height: 48, borderRadius: 12);
    }
    if (error != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: CupertinoColors.systemRed.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(
              CupertinoIcons.exclamationmark_triangle,
              color: CupertinoColors.systemRed,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                error!,
                style: const TextStyle(
                  color: CupertinoColors.systemRed,
                  fontSize: 14,
                ),
              ),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              onPressed: onRetry,
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }
    if (balance == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [CupertinoColors.systemIndigo, CupertinoColors.systemPurple],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(
            CupertinoIcons.creditcard,
            color: CupertinoColors.white,
            size: 18,
          ),
          const SizedBox(width: 8),
          const Text(
            'Доступно',
            style: TextStyle(color: CupertinoColors.white, fontSize: 14),
          ),
          const Spacer(),
          Text(
            '${balance!.points} баллов',
            style: const TextStyle(
              color: CupertinoColors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
