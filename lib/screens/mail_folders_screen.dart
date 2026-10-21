import 'package:flutter/cupertino.dart';

import '../config/app_theme.dart';
import '../models/mail/mail_folder.dart';
import '../widgets/app_glass.dart';
import '../widgets/booking_glass_form.dart';

class MailFoldersScreen extends StatelessWidget {
  const MailFoldersScreen({
    super.key,
    required this.folders,
    required this.selected,
  });

  final List<MailFolder> folders;
  final MailFolder? selected;

  static IconData _iconFor(MailFolder folder) {
    if (folder.isAllInbox || folder.isInbox) return CupertinoIcons.tray_full;
    if (folder.isSent) return CupertinoIcons.paperplane;
    if (folder.isDrafts) return CupertinoIcons.doc_text;
    if (folder.isSpam) return CupertinoIcons.exclamationmark_octagon;
    if (folder.isTrash) return CupertinoIcons.trash;
    if (folder.isArchive) return CupertinoIcons.archivebox;
    return CupertinoIcons.folder;
  }

  @override
  Widget build(BuildContext context) {
    final label = CupertinoColors.label.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);

    return BookingGlassScaffold(
      title: 'Папки',
      children: [
        AppGlassSection(
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          children: [
            for (final folder in folders)
              Builder(
                builder: (context) {
                  final isNested = folder.depth > 0;
                  final isSelected =
                      selected != null &&
                      selected!.id == folder.id &&
                      selected!.name == folder.name;
                  final unread = folder.unreadCount ?? 0;
                  return CupertinoListTile(
                    leading: Padding(
                      padding: EdgeInsetsDirectional.only(
                        start: folder.depth * 20.0,
                      ),
                      child: Icon(
                        _iconFor(folder),
                        size: isNested ? 20 : 23,
                        color: folder.isTrash
                            ? CupertinoColors.systemRed.resolveFrom(context)
                            : label,
                      ),
                    ),
                    title: Text(
                      folder.displayName,
                      style: TextStyle(
                        fontSize: isNested ? 15 : 16,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: label,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!folder.isSent && !folder.isDrafts && unread > 0)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Text(
                              '$unread',
                              style: TextStyle(fontSize: 15, color: secondary),
                            ),
                          ),
                        if (isSelected)
                          const Icon(
                            CupertinoIcons.check_mark,
                            color: AppColors.primary,
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
    );
  }
}
