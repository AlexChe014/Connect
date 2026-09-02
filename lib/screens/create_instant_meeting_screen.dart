import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show ScaffoldMessenger, SnackBar;

import '../models/staff_user.dart';
import '../repositories/connector_repository.dart';
import '../services/api_client.dart';
import '../services/connector_invite_service.dart';
import '../utils/connector_launch.dart';
import '../widgets/selected_staff_field.dart';

/// Создание мгновенной видеовстречи с приглашением участников в чат.
class CreateInstantMeetingScreen extends StatefulWidget {
  const CreateInstantMeetingScreen({super.key});

  @override
  State<CreateInstantMeetingScreen> createState() =>
      _CreateInstantMeetingScreenState();
}

class _CreateInstantMeetingScreenState
    extends State<CreateInstantMeetingScreen> {
  final _topicController = TextEditingController(text: 'Видеовстреча');
  List<StaffUser> _invitees = [];
  bool _isSubmitting = false;

  @override
  void dispose() {
    _topicController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _isSubmitting = true);

    try {
      final topic = _topicController.text.trim().isEmpty
          ? 'Видеовстреча'
          : _topicController.text.trim();

      final session = await ConnectorRepository.instance.createInstant(
        topic: topic,
        userIds: _invitees
            .map((u) => u.idAsInt)
            .whereType<int>()
            .toList(),
      );

      var invited = 0;
      if (_invitees.isNotEmpty) {
        invited = await ConnectorInviteService.instance.inviteUsers(
          session: session,
          users: _invitees,
          topic: topic,
        );
      }

      if (!mounted) return;

      if (_invitees.isNotEmpty) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              invited > 0
                  ? 'Приглашения отправлены в чат: $invited'
                  : 'Встреча создана, но приглашения не удалось отправить',
            ),
          ),
        );
      }

      await openConnectorSession(session);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      final message = e is ApiException
          ? e.message
          : 'Не удалось создать видеовстречу';
      showCupertinoDialog<void>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('Ошибка'),
          content: Text(message),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: CupertinoColors.systemGroupedBackground,
        border: null,
        middle: const Text('Новая видеовстреча'),
        trailing: _isSubmitting
            ? const Padding(
                padding: EdgeInsets.only(right: 8),
                child: CupertinoActivityIndicator(),
              )
            : CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _submit,
                child: const Text('Начать'),
              ),
      ),
      child: DefaultTextStyle(
        style: TextStyle(
          fontFamily: '.SF Pro Text',
          decoration: TextDecoration.none,
          color: CupertinoColors.label.resolveFrom(context),
          fontSize: 16,
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              CupertinoFormSection.insetGrouped(
                children: [
                  CupertinoTextFormFieldRow(
                    controller: _topicController,
                    prefix: const Text('Название'),
                    placeholder: 'Видеовстреча',
                    textCapitalization: TextCapitalization.sentences,
                    textAlign: TextAlign.end,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SelectedStaffField(
                  label: 'Пригласить',
                  participants: _invitees,
                  onUserAdded: (user) =>
                      setState(() => _invitees = [..._invitees, user]),
                  onUserRemoved: (user) => setState(
                    () => _invitees =
                        _invitees.where((p) => p.id != user.id).toList(),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Text(
                  'Выбранным пользователям в личный чат придёт ссылка на '
                  'встречу — её можно открыть в приложении или в браузере.',
                  style: TextStyle(
                    fontSize: 13,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
