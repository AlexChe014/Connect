import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show ScaffoldMessenger, SnackBar;

import '../models/staff_user.dart';
import '../repositories/connector_repository.dart';
import '../services/api_client.dart';
import '../services/connector_invite_service.dart';
import '../utils/connector_launch.dart';
import '../widgets/booking_glass_form.dart';
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
  final _topicController = TextEditingController();
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
        userIds: _invitees.map((u) => u.idAsInt).whereType<int>().toList(),
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
    return BookingGlassScaffold(
      title: 'Новая видеовстреча',
      canPop: !_isSubmitting,
      trailing: BookingNavAction(
        label: 'Начать',
        isLoading: _isSubmitting,
        onPressed: _submit,
      ),
      children: [
        BookingTitleCard(
          themeController: _topicController,
          themePlaceholder: 'Видеовстреча',
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
              () =>
                  _invitees = _invitees.where((p) => p.id != user.id).toList(),
            ),
          ),
        ),
        const BookingFootnote(
          'Выбранным пользователям в личный чат придёт ссылка на '
          'встречу — её можно открыть в приложении или в браузере.',
        ),
      ],
    );
  }
}
