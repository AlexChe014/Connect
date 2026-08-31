import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show ScaffoldMessenger, SnackBar, showModalBottomSheet;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../models/disk/disk_share.dart';
import '../repositories/disk_repository.dart';
import '../services/api_client.dart';
import 'app_loading.dart';
import 'staff_user_picker_sheet.dart';

/// «Поделиться» для файла/папки на «Диске»: публичная ссылка (копируется
/// в буфер обмена) + шаринг конкретному сотруднику (`shares/user`), плюс
/// список активных доступов с возможностью отозвать.
class DiskShareSheet extends StatefulWidget {
  const DiskShareSheet({super.key, required this.path, required this.name});

  final String path;
  final String name;

  static Future<void> show(
    BuildContext context, {
    required String path,
    required String name,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
        context,
      ),
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: DiskShareSheet(path: path, name: name),
      ),
    );
  }

  @override
  State<DiskShareSheet> createState() => _DiskShareSheetState();
}

class _DiskShareSheetState extends State<DiskShareSheet> {
  List<DiskShare> _shares = [];
  bool _isLoading = true;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final shares = await DiskRepository.instance.listShares(widget.path);
      if (!mounted) return;
      setState(() {
        _shares = shares;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _createPublicLink() async {
    setState(() => _isBusy = true);
    try {
      final data = await DiskRepository.instance.createPublicLink(widget.path);
      final url = data['url']?.toString();
      if (!mounted) return;
      if (url != null && url.isNotEmpty) {
        await Clipboard.setData(ClipboardData(text: url));
        if (!mounted) return;
        _showMessage('Ссылка скопирована в буфер обмена');
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      _showMessage(e is ApiException ? e.message : 'Не удалось создать ссылку');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _shareWithColleague() {
    StaffUserPickerSheet.show(
      context,
      selectedIds: const {},
      onUserSelected: (user) async {
        final userId = user.idAsInt;
        if (userId == null) return;

        setState(() => _isBusy = true);
        try {
          await DiskRepository.instance.shareWithUser(widget.path, userId);
          if (!mounted) return;
          _showMessage('Открыт доступ для ${user.fullName}');
          await _load();
        } catch (e) {
          if (!mounted) return;
          _showMessage(
            e is ApiException ? e.message : 'Не удалось поделиться',
          );
        } finally {
          if (mounted) setState(() => _isBusy = false);
        }
      },
    );
  }

  Future<void> _revoke(DiskShare share) async {
    setState(() => _isBusy = true);
    try {
      await DiskRepository.instance.deleteShare(share.id);
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      _showMessage(e is ApiException ? e.message : 'Не удалось отозвать доступ');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text(
              widget.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: CupertinoButton(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    color: CupertinoColors.systemGrey5.resolveFrom(context),
                    onPressed: _isBusy ? null : _createPublicLink,
                    child: const Text('Скопировать ссылку'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CupertinoButton.filled(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    onPressed: _isBusy ? null : _shareWithColleague,
                    child: const Text('Сотруднику'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'АКТИВНЫЕ ДОСТУПЫ',
                style: TextStyle(
                  fontSize: 13,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: _isLoading
                ? const AppPageLoader()
                : _shares.isEmpty
                ? const Center(
                    child: Text(
                      'Нет активных доступов',
                      style: TextStyle(color: CupertinoColors.secondaryLabel),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: _shares.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final share = _shares[index];
                      return Container(
                        decoration: BoxDecoration(
                          color: CupertinoColors
                              .secondarySystemGroupedBackground
                              .resolveFrom(context),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              share.isPublicLink
                                  ? CupertinoIcons.link
                                  : CupertinoIcons.person_fill,
                              color: CupertinoColors.systemBlue,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                share.isPublicLink
                                    ? 'Публичная ссылка'
                                    : 'Доступ открыт сотруднику',
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              onPressed: _isBusy ? null : () => _revoke(share),
                              child: const Icon(
                                CupertinoIcons.xmark_circle_fill,
                                color: CupertinoColors.systemGrey,
                                size: 22,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
