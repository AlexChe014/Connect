import 'package:flutter/cupertino.dart';

import '../models/mail/mail_folder.dart';

class MailFoldersScreen extends StatelessWidget {
  const MailFoldersScreen({
    super.key,
    required this.folders,
    required this.selected,
  });

  final List<MailFolder> folders;
  final MailFolder? selected;

  static (IconData, CupertinoDynamicColor) _iconFor(MailFolder folder) {
    if (folder.isInbox) {
      return (CupertinoIcons.tray_full, CupertinoColors.systemTeal);
    }
    if (folder.isSent) {
      return (
        CupertinoIcons.paperplane,
        CupertinoColors.secondaryLabel,
      );
    }
    if (folder.isDrafts) {
      return (CupertinoIcons.doc_text, CupertinoColors.secondaryLabel);
    }
    if (folder.isSpam) {
      return (
        CupertinoIcons.hand_thumbsdown,
        CupertinoColors.secondaryLabel,
      );
    }
    if (folder.isTrash) {
      return (CupertinoIcons.trash, CupertinoColors.systemRed);
    }
    if (folder.isArchive) {
      return (CupertinoIcons.archivebox, CupertinoColors.secondaryLabel);
    }
    return (CupertinoIcons.folder, CupertinoColors.activeBlue);
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Папки'),
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
              children: [
                for (final folder in folders)
                  Builder(
                    builder: (tileContext) {
                      final (icon, color) = _iconFor(folder);
                      return CupertinoListTile(
                        leading: Icon(icon, color: color.resolveFrom(tileContext)),
                        title: Text(folder.name),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if ((folder.unreadCount ?? 0) > 0)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Text(
                                  '${folder.unreadCount}',
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: CupertinoColors.secondaryLabel
                                        .resolveFrom(tileContext),
                                  ),
                                ),
                              ),
                            if (selected != null &&
                                selected!.id == folder.id &&
                                selected!.name == folder.name)
                              const Icon(
                                CupertinoIcons.check_mark,
                                color: CupertinoColors.activeBlue,
                                size: 18,
                              ),
                          ],
                        ),
                        onTap: () => Navigator.of(context).pop(folder),
                      );
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
