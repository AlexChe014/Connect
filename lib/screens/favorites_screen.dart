import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/bookings/bookable_object.dart';
import '../models/staff_user.dart';
import '../repositories/favorites_repository.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/app_loading.dart';
import '../widgets/app_network_image.dart';
import '../widgets/chat_avatar.dart';
import '../widgets/menu_button.dart';
import 'employee_detail_screen.dart';

/// Избранное: сотрудники и объекты бронирования (переговорки, парковки и
/// любые другие типы `BookableObject`) в одном разделе, переключаемые
/// сегмент-контролом. Источник истины — сервер (`/user/favorites/...`).
class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

enum _FavoritesSegment { users, objects }

class _FavoritesScreenState extends State<FavoritesScreen> {
  _FavoritesSegment _segment = _FavoritesSegment.users;

  bool _isLoading = true;
  List<StaffUser> _users = const [];
  List<BookableObject> _objects = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        FavoritesRepository.instance.getFavoriteUsers(),
        FavoritesRepository.instance.getFavoriteObjects(),
      ]);
      if (!mounted) return;
      setState(() {
        _users = results[0] as List<StaffUser>;
        _objects = results[1] as List<BookableObject>;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Не удалось загрузить избранное')),
      );
    }
  }

  Future<void> _removeUser(StaffUser user) async {
    final id = user.idAsInt;
    if (id == null) return;
    setState(() => _users = _users.where((u) => u.id != user.id).toList());
    try {
      await FavoritesRepository.instance.toggleUser(id);
    } catch (_) {
      if (!mounted) return;
      setState(() => _users = [..._users, user]);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Не удалось убрать из избранного')),
      );
    }
  }

  Future<void> _removeObject(BookableObject object) async {
    setState(
      () => _objects = _objects.where((o) => o.id != object.id).toList(),
    );
    try {
      await FavoritesRepository.instance.toggleObject(object.id);
    } catch (_) {
      if (!mounted) return;
      setState(() => _objects = [..._objects, object]);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Не удалось убрать из избранного')),
      );
    }
  }

  void _openEmployee(StaffUser user) {
    Navigator.of(context).push<void>(
      CupertinoPageRoute<void>(
        builder: (context) => EmployeeDetailScreen(user: user),
      ),
    );
  }

  Widget _buildSegmentedControl() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: CupertinoSlidingSegmentedControl<_FavoritesSegment>(
        groupValue: _segment,
        children: const {
          _FavoritesSegment.users: Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Text('Сотрудники'),
          ),
          _FavoritesSegment.objects: Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Text('Объекты'),
          ),
        },
        onValueChanged: (value) {
          if (value == null) return;
          setState(() => _segment = value);
        },
      ),
    );
  }

  Widget _buildResultsSliver() {
    if (_isLoading) {
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        sliver: SliverList.separated(
          itemCount: 6,
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) => const AppSkeletonCardTile(),
        ),
      );
    }

    if (_segment == _FavoritesSegment.users) {
      if (_users.isEmpty) {
        return const SliverAppEmptyState(
          icon: CupertinoIcons.star,
          message: 'Пока нет избранных сотрудников',
        );
      }
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        sliver: SliverList.separated(
          itemCount: _users.length,
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final user = _users[index];
            return _FavoriteUserTile(
              user: user,
              onTap: () => _openEmployee(user),
              onRemove: () => _removeUser(user),
            );
          },
        ),
      );
    }

    if (_objects.isEmpty) {
      return const SliverAppEmptyState(
        icon: CupertinoIcons.star,
        message: 'Пока нет избранных объектов',
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      sliver: SliverList.separated(
        itemCount: _objects.length,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final object = _objects[index];
          return _FavoriteObjectTile(
            object: object,
            onRemove: () => _removeObject(object),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      child: DefaultTextStyle(
        style: TextStyle(
          fontFamily: '.SF Pro Text',
          decoration: TextDecoration.none,
          color: CupertinoColors.label.resolveFrom(context),
          fontSize: 16,
        ),
        child: SafeArea(
          top: false,
          bottom: false,
          child: RefreshIndicator(
            onRefresh: _load,
            child: CustomScrollView(
              slivers: [
                CupertinoSliverNavigationBar(
                  largeTitle: const Text('Избранное'),
                  leading: const MenuButton(),
                  backgroundColor: CupertinoColors.systemGroupedBackground,
                  border: null,
                ),
                SliverToBoxAdapter(child: _buildSegmentedControl()),
                _buildResultsSliver(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FavoriteUserTile extends StatelessWidget {
  const _FavoriteUserTile({
    required this.user,
    required this.onTap,
    required this.onRemove,
  });

  final StaffUser user;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
          context,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              MemberAvatar(
                displayName: user.fullName,
                avatarUrl: user.avatarUrl,
                radius: 24,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  user.fullName,
                  style: TextStyle(
                    fontFamily: '.SF Pro Text',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: CupertinoColors.label.resolveFrom(context),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                onPressed: onRemove,
                child: const Icon(
                  CupertinoIcons.star_fill,
                  size: 22,
                  color: CupertinoColors.systemYellow,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FavoriteObjectTile extends StatelessWidget {
  const _FavoriteObjectTile({required this.object, required this.onRemove});

  final BookableObject object;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final imageUrl = object.previewImageUrl;
    final description = (object.description ?? '').trim();

    return Container(
      decoration: BoxDecoration(
        color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
          context,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            imageUrl == null
                ? Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      CupertinoIcons.location_solid,
                      color: AppColors.primary,
                      size: 24,
                    ),
                  )
                : AppNetworkImage(
                    url: imageUrl,
                    width: 48,
                    height: 48,
                    borderRadius: 12,
                  ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    object.name,
                    style: TextStyle(
                      fontFamily: '.SF Pro Text',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: CupertinoColors.label.resolveFrom(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 13,
                        color: CupertinoColors.secondaryLabel.resolveFrom(
                          context,
                        ),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              onPressed: onRemove,
              child: const Icon(
                CupertinoIcons.star_fill,
                size: 22,
                color: CupertinoColors.systemYellow,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
