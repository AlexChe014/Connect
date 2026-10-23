import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/bookings/bookable_object.dart';
import '../models/staff_user.dart';
import '../repositories/favorites_repository.dart';
import '../services/app_navigation_service.dart';
import '../utils/booking_time_utils.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/app_glass.dart';
import '../widgets/app_loading.dart';
import '../widgets/app_network_image.dart';
import '../widgets/app_title_bar.dart';
import '../widgets/employee_row.dart';
import 'create_booking_screen.dart';
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

class _FavoritesScreenState extends State<FavoritesScreen> with RouteAware {
  _FavoritesSegment _segment = _FavoritesSegment.users;

  bool _isLoading = true;
  List<StaffUser> _users = const [];
  List<BookableObject> _objects = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    AppNavigationService.routeObserver.subscribe(
      this,
      ModalRoute.of(context)! as PageRoute<dynamic>,
    );
  }

  @override
  void dispose() {
    AppNavigationService.routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    // Экран остаётся смонтированным под запушенными поверх него route,
    // поэтому избранное, изменённое там, не подхватится без явной
    // перезагрузки при возврате сюда.
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

  /// Убирает из избранного сразу (оптимистично) и даёт вернуть из
  /// снекбара: звезда стоит под пальцем, промахнуться легко.
  Future<void> _removeUser(StaffUser user) async {
    final id = user.idAsInt;
    if (id == null) return;
    final index = _users.indexOf(user);
    setState(() => _users = _users.where((u) => u.id != user.id).toList());
    try {
      await FavoritesRepository.instance.toggleUser(id);
    } catch (_) {
      if (!mounted) return;
      setState(() => _users = _reinserted(_users, index, user));
      _showSnack('Не удалось убрать из избранного');
      return;
    }
    _showUndo('${user.fullName} — убран из избранного', () async {
      setState(() => _users = _reinserted(_users, index, user));
      try {
        await FavoritesRepository.instance.toggleUser(id);
      } catch (_) {
        if (!mounted) return;
        setState(() => _users = _users.where((u) => u.id != user.id).toList());
        _showSnack('Не удалось вернуть в избранное');
      }
    });
  }

  Future<void> _removeObject(BookableObject object) async {
    final index = _objects.indexOf(object);
    setState(
      () => _objects = _objects.where((o) => o.id != object.id).toList(),
    );
    Future<void> toggle() => FavoritesRepository.instance.toggleObject(
      object.id,
      favoriteTypeId: object.favoriteTypeId,
    );
    try {
      await toggle();
    } catch (_) {
      if (!mounted) return;
      setState(() => _objects = _reinserted(_objects, index, object));
      _showSnack('Не удалось убрать из избранного');
      return;
    }
    _showUndo('${object.name} — убран из избранного', () async {
      setState(() => _objects = _reinserted(_objects, index, object));
      try {
        await toggle();
      } catch (_) {
        if (!mounted) return;
        setState(
          () => _objects = _objects.where((o) => o.id != object.id).toList(),
        );
        _showSnack('Не удалось вернуть в избранное');
      }
    });
  }

  List<T> _reinserted<T>(List<T> list, int index, T item) =>
      [...list]..insert(index.clamp(0, list.length), item);

  void _showSnack(String message) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  void _showUndo(String message, VoidCallback onUndo) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(message, maxLines: 2, overflow: TextOverflow.ellipsis),
        action: SnackBarAction(
          label: 'Вернуть',
          onPressed: () {
            if (mounted) onUndo();
          },
        ),
      ),
    );
  }

  void _openEmployee(StaffUser user) {
    Navigator.of(context).push<void>(
      CupertinoPageRoute<void>(
        builder: (context) => EmployeeDetailScreen(user: user),
      ),
    );
  }

  void _openObject(BookableObject object) {
    final typeId = object.favoriteTypeId;
    if (typeId == null) return;

    final now = DateTime.now();
    final slots = BookingTimeUtils.slotsForDate(now);
    final lastIndex = slots.length - 1;
    final startIndex = BookingTimeUtils.nearestSlotIndex(
      slots,
      now,
      floorToPrevious: false,
    ).clamp(0, (lastIndex - 1).clamp(0, lastIndex));

    Navigator.of(context).push<bool>(
      CupertinoPageRoute<bool>(
        builder: (context) => CreateBookingScreen(
          object: object,
          modelType: typeId,
          modelId: object.id,
          initialStart: slots[startIndex],
          initialEnd: slots[startIndex + 1],
        ),
      ),
    );
  }

  Widget _buildSegmentedControl() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: AppGlass(
        borderRadius: BorderRadius.circular(12),
        shadows: AppGlass.controlShadow,
        child: CupertinoSlidingSegmentedControl<_FavoritesSegment>(
          groupValue: _segment,
          backgroundColor: Colors.transparent,
          thumbColor: CupertinoColors.systemBackground.resolveFrom(context),
          children: const {
            _FavoritesSegment.users: Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Сотрудники'),
            ),
            _FavoritesSegment.objects: Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Объекты'),
            ),
          },
          onValueChanged: (value) {
            if (value == null) return;
            setState(() => _segment = value);
          },
        ),
      ),
    );
  }

  Widget _buildResultsSliver() {
    if (_isLoading) {
      return AppGlassSliverList(
        itemCount: 6,
        itemBuilder: (context, index) => const AppSkeletonListTile(),
      );
    }

    if (_segment == _FavoritesSegment.users) {
      if (_users.isEmpty) {
        return const SliverAppEmptyState(
          icon: CupertinoIcons.star,
          message:
              'Пока нет избранных сотрудников.\n'
              'Отметьте звездой в карточке коллеги.',
        );
      }
      return AppGlassSliverList(
        separatorIndent: EmployeeRow.separatorIndent,
        itemCount: _users.length,
        itemBuilder: (context, index) {
          final user = _users[index];
          return EmployeeRow(
            user: user,
            onTap: () => _openEmployee(user),
            trailing: EmployeeRowButton(
              icon: CupertinoIcons.star_fill,
              onPressed: () => _removeUser(user),
            ),
          );
        },
      );
    }

    if (_objects.isEmpty) {
      return const SliverAppEmptyState(
        icon: CupertinoIcons.star,
        message: 'Пока нет избранных объектов',
      );
    }
    return AppGlassSliverList(
      separatorIndent: EmployeeRow.separatorIndent,
      itemCount: _objects.length,
      itemBuilder: (context, index) {
        final object = _objects[index];
        return _FavoriteObjectRow(
          object: object,
          onTap: () => _openObject(object),
          onRemove: () => _removeObject(object),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppGlassBarBlur(
      builder: (context, blur) => CupertinoPageScaffold(
        backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
          context,
        ),
        child: DefaultTextStyle(
          style: TextStyle(
            fontFamily: '.SF Pro Text',
            decoration: TextDecoration.none,
            color: CupertinoColors.label.resolveFrom(context),
            fontSize: 16,
          ),
          child: Stack(
            children: [
              const AppGlassGlow(),
              SafeArea(
                top: false,
                bottom: false,
                child: RefreshIndicator.adaptive(
                  onRefresh: _load,
                  child: CustomScrollView(
                    slivers: [
                      AppSliverTitleBar(
                        title: const Text('Избранное'),
                        leading: CupertinoButton(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          onPressed: () => Navigator.maybePop(context),
                          child: Icon(
                            CupertinoIcons.back,
                            size: AppSliverTitleBar.iconSize,
                            color: CupertinoColors.label.resolveFrom(context),
                          ),
                        ),
                        blur: blur,
                      ),
                      SliverToBoxAdapter(child: _buildSegmentedControl()),
                      _buildResultsSliver(),
                    ],
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

/// Строка объекта бронирования — та же сетка, что у [EmployeeRow]:
/// превью 44 слева, название и описание, звезда справа.
class _FavoriteObjectRow extends StatelessWidget {
  const _FavoriteObjectRow({
    required this.object,
    required this.onTap,
    required this.onRemove,
  });

  final BookableObject object;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final imageUrl = object.previewImageUrl;
    final description = (object.description ?? '').trim();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
        child: Row(
          children: [
            imageUrl == null
                ? Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: CupertinoColors.tertiarySystemFill.resolveFrom(
                        context,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      CupertinoIcons.location_solid,
                      size: 20,
                      color: CupertinoColors.secondaryLabel.resolveFrom(
                        context,
                      ),
                    ),
                  )
                : AppNetworkImage(
                    url: imageUrl,
                    width: 44,
                    height: 44,
                    borderRadius: 12,
                  ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    object.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: CupertinoColors.label.resolveFrom(context),
                    ),
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: CupertinoColors.secondaryLabel.resolveFrom(
                          context,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            EmployeeRowButton(
              icon: CupertinoIcons.star_fill,
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}
