import 'package:flutter/cupertino.dart';

import '../widgets/app_glass.dart';
import '../widgets/app_icon_badge.dart';
import '../widgets/booking_glass_form.dart';
import 'mail_connection_form_screen.dart';

class MailProviderPickerScreen extends StatelessWidget {
  const MailProviderPickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const BookingGlassScaffold(
      title: 'Новый почтовый ящик',
      children: [
        AppGlassSectionLabel(
          'Выберите почтового провайдера',
          padding: EdgeInsets.fromLTRB(20, 4, 20, 6),
        ),
        AppGlassSection(
          margin: EdgeInsets.symmetric(horizontal: 16),
          children: [
            _ProviderTile(
              provider: MailProviderKind.yandex,
              color: CupertinoColors.systemRed,
              icon: CupertinoIcons.mail_solid,
            ),
            _ProviderTile(
              provider: MailProviderKind.mailru,
              color: CupertinoColors.systemBlue,
              icon: CupertinoIcons.at,
            ),
            _ProviderTile(
              provider: MailProviderKind.corporate,
              color: CupertinoColors.systemGrey,
              icon: CupertinoIcons.building_2_fill,
            ),
          ],
        ),
      ],
    );
  }
}

class _ProviderTile extends StatelessWidget {
  const _ProviderTile({
    required this.provider,
    required this.color,
    required this.icon,
  });

  final MailProviderKind provider;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return CupertinoListTile(
      leading: AppIconBadge(icon: icon, color: color),
      title: Text(_titleFor(provider), style: const TextStyle(fontSize: 16)),
      trailing: const CupertinoListTileChevron(),
      onTap: () => Navigator.of(context)
          .push<bool>(
            CupertinoPageRoute<bool>(
              builder: (context) =>
                  MailConnectionFormScreen(provider: provider),
            ),
          )
          .then((created) {
            if (created == true && context.mounted)
              Navigator.of(context).pop(true);
          }),
    );
  }

  String _titleFor(MailProviderKind provider) {
    switch (provider) {
      case MailProviderKind.yandex:
        return 'Яндекс Почта';
      case MailProviderKind.mailru:
        return 'Mail';
      case MailProviderKind.corporate:
        return 'Корпоративная почта компании';
    }
  }
}
