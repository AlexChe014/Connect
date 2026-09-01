import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:connect/models/bookings/bookable_object.dart';
import 'package:connect/models/infrastructure/booking_object_type.dart';
import 'package:connect/models/infrastructure/building.dart';
import 'package:connect/models/infrastructure/equipment.dart';
import 'package:connect/models/infrastructure/space.dart';
import 'package:connect/repositories/bookings_repository.dart';
import 'package:connect/repositories/favorites_repository.dart';
import 'package:connect/repositories/infrastructure_repository.dart';
import 'package:connect/screens/create_booking_screen.dart';
import 'package:connect/utils/booking_time_utils.dart';
import 'package:connect/widgets/app_empty_state.dart';
import 'package:connect/widgets/app_loading.dart';
import 'package:connect/widgets/app_network_image.dart';
import 'package:connect/widgets/booking_pickers.dart';

class BookingsScreen extends StatefulWidget {
  const BookingsScreen({super.key, this.showAppBar = true, this.initialDate});

  final bool showAppBar;

  /// Дата, с которой открыть фильтры (например, при переходе из Календаря).
  /// Если задана, фильтры сразу разворачиваются, чтобы пользователь
  /// не тратил лишний тап на их раскрытие.
  final DateTime? initialDate;

  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen> {
  bool _isBootLoading = true;
  bool _isResultsLoading = false;
  String? _bootError;
  String? _resultsError;

  late bool _filtersExpanded = widget.initialDate != null;

  List<Building> _buildings = const [];
  List<Space> _spaces = const [];
  List<BookingObjectType> _types = const [];
  List<Equipment> _equipment = const [];

  Building? _selectedBuilding;
  Space? _selectedSpace;
  BookingObjectType? _selectedType;
  final Set<int> _selectedEquipmentIds = <int>{};

  DateTime _selectedDate = DateTime.now();
  int _startSlotIndex = 0;
  int _endSlotIndex = 0;
  final TextEditingController _capacityController = TextEditingController();

  List<BookableObject> _results = const [];

  /// Индекс получасового слота на 09:00 — стартовое время по умолчанию
  /// для дат, отличных от сегодняшней (когда "ближайший слот" не применим).
  static const _defaultWorkdayStartIndex = 18;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _capacityController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _isBootLoading = true;
      _bootError = null;
    });

    try {
      final buildings = await InfrastructureRepository.instance
          .getActiveBuildings();
      if (buildings.isEmpty) {
        throw Exception('Нет активных офисов для бронирования');
      }

      final selectedBuilding = buildings.first;
      final spacesAndTypes = await InfrastructureRepository.instance
          .getActiveSpacesAndTypes(selectedBuilding.id);

      if (spacesAndTypes.spaces.isEmpty) {
        throw Exception(
          'В выбранном офисе нет активных этажей для бронирования',
        );
      }

      final initialSpace = spacesAndTypes.spaces.first;
      final initialTypes = initialSpace.types;

      if (initialTypes.isEmpty) {
        throw Exception(
          'В выбранном офисе нет доступных типов объектов для бронирования',
        );
      }

      final equipment = await InfrastructureRepository.instance
          .getActiveEquipment(selectedBuilding.id);

      final now = DateTime.now();
      _selectedDate = widget.initialDate ?? now;
      final slots = BookingTimeUtils.slotsForDate(_selectedDate);
      final lastIndex = slots.length - 1;
      final isToday = BookingTimeUtils.isSameDay(_selectedDate, now);
      final rawStartIndex = isToday
          ? BookingTimeUtils.nearestSlotIndex(
              slots,
              now,
              floorToPrevious: false,
            )
          : _defaultWorkdayStartIndex;
      _startSlotIndex = rawStartIndex.clamp(
        0,
        (lastIndex - 1).clamp(0, lastIndex),
      );
      _endSlotIndex = _startSlotIndex + 1;

      if (!mounted) return;
      setState(() {
        _buildings = buildings;
        _selectedBuilding = selectedBuilding;
        _spaces = spacesAndTypes.spaces;
        _selectedSpace = initialSpace;
        _types = initialTypes;
        _selectedType = initialTypes.first;
        _equipment = equipment;
        _isBootLoading = false;
      });

      await _loadResults();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bootError = e.toString();
        _isBootLoading = false;
      });
    }
  }

  DateTime _startDateTime() => BookingTimeUtils.slotAt(
    BookingTimeUtils.slotsForDate(_selectedDate),
    _startSlotIndex,
  );

  DateTime _endDateTime() => BookingTimeUtils.slotAt(
    BookingTimeUtils.slotsForDate(_selectedDate),
    _endSlotIndex,
  );

  bool get _isTimeRangeValid {
    return _endDateTime().isAfter(_startDateTime());
  }

  int? get _capacityValueOrNull {
    final raw = _capacityController.text.trim();
    if (raw.isEmpty) return null;
    final parsed = int.tryParse(raw);
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  Future<void> _loadSpacesTypesAndEquipmentForBuilding(
    Building building,
  ) async {
    setState(() {
      _isBootLoading = true;
      _bootError = null;
    });
    try {
      final spacesAndTypes = await InfrastructureRepository.instance
          .getActiveSpacesAndTypes(building.id);
      if (spacesAndTypes.spaces.isEmpty) {
        throw Exception(
          'В выбранном офисе нет активных этажей для бронирования',
        );
      }

      final initialSpace = spacesAndTypes.spaces.first;
      final initialTypes = initialSpace.types;

      if (initialTypes.isEmpty) {
        throw Exception(
          'В выбранном офисе нет доступных типов объектов для бронирования',
        );
      }

      final equipment = await InfrastructureRepository.instance
          .getActiveEquipment(building.id);

      if (!mounted) return;
      setState(() {
        _selectedBuilding = building;
        _spaces = spacesAndTypes.spaces;
        _selectedSpace = initialSpace;
        _types = initialTypes;
        _selectedType = initialTypes.first;
        _equipment = equipment;
        _selectedEquipmentIds.clear();
        _isBootLoading = false;
      });

      await _loadResults();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bootError = e.toString();
        _isBootLoading = false;
      });
    }
  }

  Future<void> _loadResults() async {
    final type = _selectedType;
    final space = _selectedSpace;
    if (type == null || space == null) return;

    if (!_isTimeRangeValid) {
      setState(() {
        _resultsError = 'Дата/время окончания должно быть строго позже начала';
        _results = const [];
      });

      return;
    }

    final start = _startDateTime();
    final end = _endDateTime();
    final startSeconds = start.millisecondsSinceEpoch ~/ 1000;
    final endSeconds = end.millisecondsSinceEpoch ~/ 1000;

    setState(() {
      _isResultsLoading = true;
      _resultsError = null;
    });

    try {
      final items = await BookingsRepository.instance.getFreeObjects(
        modelType: type.typeId,
        datetimeStartSeconds: startSeconds,
        datetimeEndSeconds: endSeconds,
        spaceId: space.id,
        capacity: _capacityValueOrNull,
        equipmentIds: _selectedEquipmentIds.toList()..sort(),
      );
      if (!mounted) return;
      setState(() {
        _results = items
            .map((o) => o.withFavoriteTypeId(type.typeId))
            .toList();
        _isResultsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _resultsError = e.toString();
        _results = const [];
        _isResultsLoading = false;
      });
    }
  }

  Future<void> _openCreateBooking(BookableObject object) async {
    final type = _selectedType;
    if (type == null) return;

    if (!_isTimeRangeValid) {
      _showMessage('Сначала выберите корректный интервал в фильтрах');
      return;
    }

    final created = await Navigator.of(context).push<bool>(
      CupertinoPageRoute(
        builder: (context) => CreateBookingScreen(
          object: object,
          modelType: type.typeId,
          initialStart: _startDateTime(),
          initialEnd: _endDateTime(),
        ),
      ),
    );

    if (created == true && mounted) {
      await _loadResults();
      if (!mounted) return;
      _showMessage('Бронирование создано');
    }
  }

  void _showMessage(String message) {
    showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('Ок'),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildContentSlivers(BuildContext context) {
    if (_isBootLoading) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: AppPageLoader(),
        ),
      ];
    }

    if (_bootError != null) {
      return [
        SliverFillRemaining(
          child: AppEmptyState(
            icon: CupertinoIcons.exclamationmark_triangle,
            message: _bootError!,
            onRetry: _bootstrap,
          ),
        ),
      ];
    }

    final selectedBuilding = _selectedBuilding;
    final selectedSpace = _selectedSpace;
    final selectedType = _selectedType;
    if (selectedBuilding == null ||
        selectedSpace == null ||
        selectedType == null) {
      return [
        SliverFillRemaining(
          child: AppEmptyState(
            icon: CupertinoIcons.exclamationmark_triangle,
            message: 'Не удалось инициализировать фильтры бронирования',
            onRetry: _bootstrap,
          ),
        ),
      ];
    }

    final slots = BookingTimeUtils.slotsForDate(_selectedDate);
    final lastIndex = slots.length - 1;
    final minStartIndex = BookingTimeUtils.minStartIndex(
      slots,
      _selectedDate,
    ).clamp(0, (lastIndex - 1).clamp(0, lastIndex));

    final startIndex = _startSlotIndex.clamp(
      minStartIndex,
      (lastIndex - 1).clamp(0, lastIndex),
    );
    final minEndIndex = startIndex + 1;
    final endIndex = _endSlotIndex.clamp(minEndIndex, lastIndex);

    if (startIndex != _startSlotIndex || endIndex != _endSlotIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _startSlotIndex = startIndex;
          _endSlotIndex = endIndex;
        });
      });
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        sliver: SliverToBoxAdapter(
          child: Column(
            children: [
              _FiltersDisclosure(
                isExpanded: _filtersExpanded,
                summary:
                    '${selectedBuilding.name} • ${selectedSpace.name} • ${selectedType.name}\n'
                    '${BookingTimeUtils.formatDateShort(_selectedDate)} • ${BookingTimeUtils.formatHm(slots[_startSlotIndex])}'
                    '—${BookingTimeUtils.formatHm(slots[_endSlotIndex])}'
                    '${_capacityController.text.trim().isEmpty ? '' : ' • ${_capacityController.text.trim()} чел.'}'
                    '${_selectedEquipmentIds.isEmpty ? '' : ' • Оборуд.: ${_selectedEquipmentIds.length}'}',
                onTap: () =>
                    setState(() => _filtersExpanded = !_filtersExpanded),
              ),
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _FiltersCard(
                    buildings: _buildings,
                    spaces: _spaces,
                    types: _types,
                    equipment: _equipment,
                    selectedBuilding: selectedBuilding,
                    selectedSpace: selectedSpace,
                    selectedType: selectedType,
                    selectedDate: _selectedDate,
                    slots: slots,
                    minStartIndex: minStartIndex,
                    startIndex: _startSlotIndex,
                    endIndex: _endSlotIndex,
                    capacityController: _capacityController,
                    selectedEquipmentIds: _selectedEquipmentIds,
                    onBuildingChanged: (b) =>
                        _loadSpacesTypesAndEquipmentForBuilding(b),
                    onSpaceChanged: (s) async {
                      setState(() {
                        _selectedSpace = s;
                        _types = s.types;
                        _selectedType = s.types.isNotEmpty
                            ? s.types.first
                            : null;
                      });
                      await _loadResults();
                    },
                    onTypeChanged: (t) async {
                      setState(() => _selectedType = t);
                      await _loadResults();
                    },
                    onDateChanged: (d) async {
                      setState(() {
                        _selectedDate = d;
                        final newSlots = BookingTimeUtils.slotsForDate(d);
                        final lastIndex = newSlots.length - 1;
                        final minStartIndex = BookingTimeUtils.minStartIndex(
                          newSlots,
                          d,
                        ).clamp(0, (lastIndex - 1).clamp(0, lastIndex));
                        _startSlotIndex = _startSlotIndex.clamp(
                          minStartIndex,
                          (lastIndex - 1).clamp(0, lastIndex),
                        );
                        _endSlotIndex = _startSlotIndex + 1;
                      });
                      await _loadResults();
                    },
                    onStartTimeChanged: (i) async {
                      setState(() {
                        final lastIndex = slots.length - 1;
                        _startSlotIndex = i.clamp(
                          0,
                          (lastIndex - 1).clamp(0, lastIndex),
                        );
                        if (_endSlotIndex <= _startSlotIndex) {
                          _endSlotIndex = _startSlotIndex + 1;
                        }
                      });
                      await _loadResults();
                    },
                    onEndTimeChanged: (i) async {
                      setState(() => _endSlotIndex = i);
                      await _loadResults();
                    },
                    onEquipmentTap: () async {
                      final updated = await showModalBottomSheet<Set<int>>(
                        context: context,
                        isScrollControlled: true,
                        showDragHandle: true,
                        backgroundColor: CupertinoColors.systemGroupedBackground
                            .resolveFrom(context),
                        builder: (context) {
                          return _EquipmentPickerSheet(
                            equipment: _equipment,
                            selectedIds: _selectedEquipmentIds,
                          );
                        },
                      );
                      if (updated != null && mounted) {
                        setState(() {
                          _selectedEquipmentIds
                            ..clear()
                            ..addAll(updated);
                        });
                        await _loadResults();
                      }
                    },
                    onCapacitySubmitted: (_) => _loadResults(),
                    onApplyPressed: () async {
                      await _loadResults();
                      if (mounted) setState(() => _filtersExpanded = false);
                    },
                  ),
                ),
                crossFadeState: _filtersExpanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 220),
                sizeCurve: Curves.easeOutCubic,
              ),
            ],
          ),
        ),
      ),
      if (_resultsError != null)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          sliver: SliverToBoxAdapter(
            child: Text(
              _resultsError!,
              style: const TextStyle(
                color: CupertinoColors.systemRed,
                fontSize: 14,
              ),
            ),
          ),
        ),
      if (_isResultsLoading)
        const SliverPadding(
          padding: EdgeInsets.symmetric(vertical: 20),
          sliver: SliverToBoxAdapter(
            child: Center(child: CupertinoActivityIndicator()),
          ),
        ),
      if (!_isResultsLoading && _resultsError == null && _results.isEmpty)
        const SliverFillRemaining(
          child: AppEmptyState(
            icon: CupertinoIcons.search,
            message: 'Нет доступных объектов по выбранным параметрам',
          ),
        ),
      if (_results.isNotEmpty)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.78,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => _BookableObjectTile(
                object: _results[index],
                onTap: () => _openCreateBooking(_results[index]),
              ),
              childCount: _results.length,
            ),
          ),
        ),
    ];
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
            onRefresh: _isBootLoading ? _bootstrap : _loadResults,
            child: CustomScrollView(
              slivers: [
                const CupertinoSliverNavigationBar(
                  largeTitle: Text('Бронирование'),
                  backgroundColor: CupertinoColors.systemGroupedBackground,
                  border: null,
                ),
                ..._buildContentSlivers(context),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget _iconBadge(IconData icon, Color color) {
  return Container(
    width: 29,
    height: 29,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(7),
    ),
    child: Icon(icon, size: 17, color: CupertinoColors.white),
  );
}

class _FiltersCard extends StatelessWidget {
  final List<Building> buildings;
  final List<Space> spaces;
  final List<BookingObjectType> types;
  final List<Equipment> equipment;
  final Building selectedBuilding;
  final Space selectedSpace;
  final BookingObjectType selectedType;
  final DateTime selectedDate;
  final List<DateTime> slots;
  final int minStartIndex;
  final int startIndex;
  final int endIndex;
  final TextEditingController capacityController;
  final Set<int> selectedEquipmentIds;

  final ValueChanged<Building> onBuildingChanged;
  final ValueChanged<Space> onSpaceChanged;
  final ValueChanged<BookingObjectType> onTypeChanged;
  final ValueChanged<DateTime> onDateChanged;
  final ValueChanged<int> onStartTimeChanged;
  final ValueChanged<int> onEndTimeChanged;
  final VoidCallback onEquipmentTap;
  final ValueChanged<String> onCapacitySubmitted;
  final Future<void> Function() onApplyPressed;

  const _FiltersCard({
    required this.buildings,
    required this.spaces,
    required this.types,
    required this.equipment,
    required this.selectedBuilding,
    required this.selectedSpace,
    required this.selectedType,
    required this.selectedDate,
    required this.slots,
    required this.minStartIndex,
    required this.startIndex,
    required this.endIndex,
    required this.capacityController,
    required this.selectedEquipmentIds,
    required this.onBuildingChanged,
    required this.onSpaceChanged,
    required this.onTypeChanged,
    required this.onDateChanged,
    required this.onStartTimeChanged,
    required this.onEndTimeChanged,
    required this.onEquipmentTap,
    required this.onCapacitySubmitted,
    required this.onApplyPressed,
  });

  String _formatDate(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd.$mm.${d.year}';
  }

  Widget _pickerRow({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return CupertinoListTile(
      leading: _iconBadge(icon, color),
      title: Text(label),
      additionalInfo: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 150),
        child: Text(
          value,
          textAlign: TextAlign.right,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: CupertinoColors.secondaryLabel),
        ),
      ),
      trailing: const CupertinoListTileChevron(),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final endMinIndex = (startIndex + 1).clamp(0, slots.length - 1);
    final now = DateTime.now();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CupertinoListSection.insetGrouped(
          margin: EdgeInsets.zero,
          children: [
            _pickerRow(
              icon: CupertinoIcons.building_2_fill,
              color: CupertinoColors.systemBlue,
              label: 'Офис',
              value: selectedBuilding.name,
              onTap: () async {
                final picked = await showBookingOptionSheet<Building>(
                  context: context,
                  title: 'Офис',
                  options: buildings,
                  current: selectedBuilding,
                  labelOf: (b) => b.name,
                );
                if (picked != null && picked.id != selectedBuilding.id) {
                  onBuildingChanged(picked);
                }
              },
            ),
            _pickerRow(
              icon: CupertinoIcons.square_stack_3d_up_fill,
              color: CupertinoColors.systemIndigo,
              label: 'Этаж',
              value: selectedSpace.name,
              onTap: () async {
                final picked = await showBookingOptionSheet<Space>(
                  context: context,
                  title: 'Этаж',
                  options: spaces,
                  current: selectedSpace,
                  labelOf: (s) => s.name,
                );
                if (picked != null && picked.id != selectedSpace.id) {
                  onSpaceChanged(picked);
                }
              },
            ),
            _pickerRow(
              icon: CupertinoIcons.cube_box_fill,
              color: CupertinoColors.systemTeal,
              label: 'Объект бронирования',
              value: selectedType.name,
              onTap: () async {
                final picked = await showBookingOptionSheet<BookingObjectType>(
                  context: context,
                  title: 'Объект бронирования',
                  options: types,
                  current: selectedType,
                  labelOf: (t) => t.name,
                );
                if (picked != null && picked.id != selectedType.id) {
                  onTypeChanged(picked);
                }
              },
            ),
          ],
        ),
        CupertinoListSection.insetGrouped(
          margin: const EdgeInsets.only(top: 12),
          children: [
            _pickerRow(
              icon: CupertinoIcons.calendar,
              color: CupertinoColors.systemOrange,
              label: 'Дата',
              value: _formatDate(selectedDate),
              onTap: () async {
                final picked = await showBookingDateSheet(
                  context: context,
                  initial: selectedDate,
                  firstDate: DateTime(now.year, now.month, now.day),
                  lastDate: DateTime(now.year + 1),
                );
                if (picked != null) onDateChanged(picked);
              },
            ),
            _pickerRow(
              icon: CupertinoIcons.clock_fill,
              color: CupertinoColors.systemOrange,
              label: 'Начало',
              value: BookingTimeUtils.formatHm(
                slots[startIndex.clamp(minStartIndex, slots.length - 1)],
              ),
              onTap: () async {
                final picked = await showBookingTimeSheet(
                  context: context,
                  title: 'Начало',
                  slots: slots,
                  minIndex: minStartIndex,
                  currentIndex: startIndex,
                );
                if (picked != null) onStartTimeChanged(picked);
              },
            ),
            _pickerRow(
              icon: CupertinoIcons.clock_fill,
              color: CupertinoColors.systemOrange,
              label: 'Окончание',
              value: BookingTimeUtils.formatHm(
                slots[endIndex.clamp(endMinIndex, slots.length - 1)],
              ),
              onTap: () async {
                final picked = await showBookingTimeSheet(
                  context: context,
                  title: 'Окончание',
                  slots: slots,
                  minIndex: endMinIndex,
                  currentIndex: endIndex,
                );
                if (picked != null) onEndTimeChanged(picked);
              },
            ),
          ],
        ),
        CupertinoListSection.insetGrouped(
          margin: const EdgeInsets.only(top: 12),
          children: [
            CupertinoListTile(
              leading: _iconBadge(
                CupertinoIcons.person_2_fill,
                CupertinoColors.systemGreen,
              ),
              title: const Text('Вместимость'),
              additionalInfo: ClipRect(
                child: SizedBox(
                  width: 80,
                  child: CupertinoTextField(
                    controller: capacityController,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.search,
                    textAlign: TextAlign.right,
                    placeholder: 'Напр. 8',
                    decoration: const BoxDecoration(),
                    padding: EdgeInsets.zero,
                    onSubmitted: onCapacitySubmitted,
                  ),
                ),
              ),
            ),
            CupertinoListTile(
              leading: _iconBadge(
                CupertinoIcons.slider_horizontal_3,
                CupertinoColors.systemPurple,
              ),
              title: const Text('Оборудование'),
              subtitle: selectedEquipmentIds.isEmpty
                  ? null
                  : Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: equipment
                            .where((e) => selectedEquipmentIds.contains(e.id))
                            .map((e) => _EquipmentChip(name: e.name))
                            .toList(),
                      ),
                    ),
              additionalInfo: selectedEquipmentIds.isEmpty
                  ? Text(
                      equipment.isEmpty ? 'Нет' : 'Выбрать',
                      style: const TextStyle(
                        color: CupertinoColors.secondaryLabel,
                      ),
                    )
                  : null,
              trailing: const CupertinoListTileChevron(),
              onTap: onEquipmentTap,
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SizedBox(
            width: double.infinity,
            child: CupertinoButton.filled(
              onPressed: () => onApplyPressed(),
              child: const Text('Показать доступные'),
            ),
          ),
        ),
      ],
    );
  }
}

class _EquipmentChip extends StatelessWidget {
  const _EquipmentChip({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: CupertinoColors.systemGrey5.resolveFrom(context),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        name,
        style: const TextStyle(fontSize: 12, color: CupertinoColors.label),
      ),
    );
  }
}

class _FiltersDisclosure extends StatelessWidget {
  final bool isExpanded;
  final String summary;
  final VoidCallback onTap;

  const _FiltersDisclosure({
    required this.isExpanded,
    required this.summary,
    required this.onTap,
  });

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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _iconBadge(
                CupertinoIcons.slider_horizontal_3,
                CupertinoColors.systemBlue,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Фильтры',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: CupertinoColors.label,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      summary,
                      maxLines: isExpanded ? 4 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: CupertinoColors.secondaryLabel,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                isExpanded
                    ? CupertinoIcons.chevron_up
                    : CupertinoIcons.chevron_down,
                size: 18,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BookableObjectTile extends StatefulWidget {
  final BookableObject object;
  final VoidCallback onTap;

  const _BookableObjectTile({required this.object, required this.onTap});

  @override
  State<_BookableObjectTile> createState() => _BookableObjectTileState();
}

class _BookableObjectTileState extends State<_BookableObjectTile> {
  late bool _isFavorite = widget.object.isFavorite;
  bool _isToggling = false;

  Future<void> _toggleFavorite() async {
    if (_isToggling) return;
    setState(() {
      _isToggling = true;
      _isFavorite = !_isFavorite;
    });
    try {
      await FavoritesRepository.instance.toggleObject(
        widget.object.id,
        favoriteTypeId: widget.object.favoriteTypeId,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isFavorite = !_isFavorite);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Не удалось изменить избранное')),
      );
    } finally {
      if (mounted) setState(() => _isToggling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final object = widget.object;
    final imageUrl = object.previewImageUrl;
    final description = (object.description ?? '').trim();

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: CupertinoColors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (imageUrl == null)
                Container(
                  color: CupertinoColors.systemBlue.withValues(alpha: 0.12),
                  child: const Icon(
                    CupertinoIcons.location_solid,
                    color: CupertinoColors.systemBlue,
                    size: 40,
                  ),
                )
              else
                AppNetworkImage(url: imageUrl, fit: BoxFit.cover),
              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleFavorite,
                  child: Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.35),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isFavorite
                          ? CupertinoIcons.star_fill
                          : CupertinoIcons.star,
                      size: 17,
                      color: _isFavorite
                          ? CupertinoColors.systemYellow
                          : CupertinoColors.white,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.75),
                      ],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 28, 10, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          object.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: CupertinoColors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        if (description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.92),
                              height: 1.2,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
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

class _EquipmentPickerSheet extends StatefulWidget {
  final List<Equipment> equipment;
  final Set<int> selectedIds;

  const _EquipmentPickerSheet({
    required this.equipment,
    required this.selectedIds,
  });

  @override
  State<_EquipmentPickerSheet> createState() => _EquipmentPickerSheetState();
}

class _EquipmentPickerSheetState extends State<_EquipmentPickerSheet> {
  late final Set<int> _working = widget.selectedIds.toSet();

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle(
      style: TextStyle(
        fontFamily: '.SF Pro Text',
        decoration: TextDecoration.none,
        color: CupertinoColors.label.resolveFrom(context),
        fontSize: 16,
      ),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  'Оборудование',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                    color: CupertinoColors.label,
                  ),
                ),
              ),
              if (widget.equipment.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Text(
                    'В выбранном офисе нет доступного оборудования',
                    style: TextStyle(
                      fontSize: 15,
                      decoration: TextDecoration.none,
                      color: CupertinoColors.secondaryLabel,
                    ),
                  ),
                )
              else
                Flexible(
                  child: SingleChildScrollView(
                    child: CupertinoListSection.insetGrouped(
                      children: widget.equipment.map((e) {
                        final checked = _working.contains(e.id);
                        return CupertinoListTile(
                          title: Text(e.name),
                          trailing: checked
                              ? const Icon(
                                  CupertinoIcons.check_mark,
                                  color: CupertinoColors.activeBlue,
                                )
                              : null,
                          onTap: () {
                            setState(() {
                              if (checked) {
                                _working.remove(e.id);
                              } else {
                                _working.add(e.id);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: CupertinoButton(
                        onPressed: () => setState(_working.clear),
                        child: const Text('Сбросить'),
                      ),
                    ),
                    Expanded(
                      child: CupertinoButton.filled(
                        onPressed: () => Navigator.pop(context, _working),
                        child: const Text('Готово'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
