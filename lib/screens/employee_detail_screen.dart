import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/staff_user.dart';

class EmployeeDetailScreen extends StatelessWidget {
  const EmployeeDetailScreen({super.key, required this.user});

  final StaffUser user;

  static Widget? _row(BuildContext context, String label, String? value) {
    final v = value?.trim();
    if (v == null || v.isEmpty) return null;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(v, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final birthdayLabel = user.birthday != null
        ? DateFormat('d MMMM y', 'ru_RU').format(user.birthday!)
        : null;
    final rolesText = user.roles.isEmpty ? null : user.roles.join(', ');

    final hasAvatar = user.avatarUrl != null && user.avatarUrl!.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(user.fullName),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: CircleAvatar(
              radius: 48,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: hasAvatar
                  ? ClipOval(
                      child: Image.network(
                        user.avatarUrl!,
                        width: 96,
                        height: 96,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Text(
                            user.initials,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          );
                        },
                      ),
                    )
                  : Text(
                      user.initials,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: user.isOnline ? const Color(0xFF34C759) : theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  user.isOnline ? 'В сети' : 'Не в сети',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          ...[
            _row(context, 'Электронная почта', user.email),
            _row(context, 'Телефон', user.phone),
            _row(context, 'День рождения', birthdayLabel),
            _row(context, 'Отдел', user.department),
            _row(context, 'Рабочий статус', user.workStatus),
            _row(context, 'Роли', rolesText),
          ].whereType<Widget>(),
        ],
      ),
    );
  }
}
