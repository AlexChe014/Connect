import 'package:flutter/cupertino.dart';

import 'mail_connection_form_screen.dart';

class MailProviderPickerScreen extends StatelessWidget {
  const MailProviderPickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Новый почтовый ящик'),
        backgroundColor: CupertinoColors.systemGroupedBackground,
        border: null,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          onPressed: () => Navigator.pop(context),
          child: const Icon(CupertinoIcons.back, size: 26),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            CupertinoListSection.insetGrouped(
              margin: EdgeInsets.zero,
              header: const Text('ВЫБЕРИТЕ ПОЧТОВОГО ПРОВАЙДЕРА'),
              children: [
                _ProviderTile(
                  provider: MailProviderKind.yandex,
                  color: CupertinoColors.systemRed,
                  icon: CupertinoIcons.mail_solid,
                ),
                _ProviderTile(
                  provider: MailProviderKind.mailru,
                  color: CupertinoColors.activeBlue,
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
        ),
      ),
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
      leading: Container(
        width: 29,
        height: 29,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Icon(icon, size: 16, color: CupertinoColors.white),
      ),
      title: Text(_titleFor(provider)),
      trailing: const CupertinoListTileChevron(),
      onTap: () => Navigator.of(context).push<bool>(
        CupertinoPageRoute<bool>(
          builder: (context) => MailConnectionFormScreen(provider: provider),
        ),
      ).then((created) {
        if (created == true && context.mounted) Navigator.of(context).pop(true);
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
