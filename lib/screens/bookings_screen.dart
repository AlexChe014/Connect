import 'package:flutter/material.dart';

import 'package:connect/config/app_icons.dart';
import 'package:connect/config/app_theme.dart';
import 'package:connect/models/bookings/bookable_object.dart';
import 'package:connect/models/infrastructure/booking_object_type.dart';
import 'package:connect/models/infrastructure/building.dart';
import 'package:connect/models/infrastructure/equipment.dart';
import 'package:connect/models/infrastructure/space.dart';
import 'package:connect/repositories/bookings_repository.dart';
import 'package:connect/repositories/infrastructure_repository.dart';
import 'package:connect/screens/create_booking_screen.dart';
import 'package:connect/utils/booking_time_utils.dart';

class BookingsScreen extends StatefulWidget {
  const BookingsScreen({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen> {
  bool _isBootLoading = true;
  bool _isResultsLoading = false;
  String? _bootError;
  String? _resultsError;

  bool _filtersExpanded = false;

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
      final buildings = await InfrastructureRepository.instance.getActiveBuildings();
      if (buildings.isEmpty) {
        throw Exception('Нет активных офисов для бронирования');
      }

      final selectedBuilding = buildings.first;
      final spacesAndTypes =
          await InfrastructureRepository.instance.getActiveSpacesAndTypes(selectedBuilding.id);

      if (spacesAndTypes.spaces.isEmpty) {
        throw Exception('В выбранном офисе нет активных этажей для бронирования');
      }

      final initialSpace = spacesAndTypes.spaces.first;
      final initialTypes = initialSpace.types;

      if (initialTypes.isEmpty) {
        throw Exception('В выбранном офисе нет доступных типов объектов для бронирования');
      }

      final equipment =
          await InfrastructureRepository.instance.getActiveEquipment(selectedBuilding.id);

      _selectedDate = DateTime.now();
      final slots = BookingTimeUtils.slotsForDate(_selectedDate);
      final now = DateTime.now();
      _startSlotIndex = BookingTimeUtils.nearestSlotIndex(slots, now, floorToPrevious: false);
      _endSlotIndex = (_startSlotIndex + 1).clamp(0, (slots.length - 1).clamp(0, 9999));

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

  DateTime _startDateTime() =>
      BookingTimeUtils.slotAt(BookingTimeUtils.slotsForDate(_selectedDate), _startSlotIndex);

  DateTime _endDateTime() =>
      BookingTimeUtils.slotAt(BookingTimeUtils.slotsForDate(_selectedDate), _endSlotIndex);

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

  Future<void> _loadSpacesTypesAndEquipmentForBuilding(Building building) async {
    setState(() {
      _isBootLoading = true;
      _bootError = null;
    });
    try {
      final spacesAndTypes =
          await InfrastructureRepository.instance.getActiveSpacesAndTypes(building.id);
      if (spacesAndTypes.spaces.isEmpty) {
        throw Exception('В выбранном офисе нет активных этажей для бронирования');
      }

      final initialSpace = spacesAndTypes.spaces.first;
      final initialTypes = initialSpace.types;

      if (initialTypes.isEmpty) {
        throw Exception('В выбранном офисе нет доступных типов объектов для бронирования');
      }

      final equipment = await InfrastructureRepository.instance.getActiveEquipment(building.id);

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
        _results = items;
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Сначала выберите корректный интервал в фильтрах'),
        ),
      );
      return;
    }

    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Бронирование создано')),
      );
    }
  }

  Widget _buildBody() {
    if (_isBootLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_bootError != null) {
      return _ErrorState(
        message: _bootError!,
        onRetry: _bootstrap,
      );
    }

    final selectedBuilding = _selectedBuilding;
    final selectedSpace = _selectedSpace;
    final selectedType = _selectedType;
    if (selectedBuilding == null || selectedSpace == null || selectedType == null) {
      return _ErrorState(
        message: 'Не удалось инициализировать фильтры бронирования',
        onRetry: _bootstrap,
      );
    }

    final slots = BookingTimeUtils.slotsForDate(_selectedDate);
    final minStartIndex = BookingTimeUtils.minStartIndex(slots, _selectedDate);

    final startIndex = _startSlotIndex.clamp(minStartIndex, slots.length - 1);
    final minEndIndex = (startIndex + 1).clamp(0, slots.length - 1);
    final endIndex = _endSlotIndex.clamp(minEndIndex, slots.length - 1);

    if (startIndex != _startSlotIndex || endIndex != _endSlotIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _startSlotIndex = startIndex;
          _endSlotIndex = endIndex;
        });
      });
    }

    final showInlineTitle = !widget.showAppBar;

    return RefreshIndicator(
      onRefresh: _loadResults,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, showInlineTitle ? 0 : 16, 16, 16),
        children: [
          if (showInlineTitle) _InlinePageTitle(title: 'Бронирование'),
          _FiltersDisclosure(
            isExpanded: _filtersExpanded,
            title: 'Фильтры',
            summary:
                '${selectedBuilding.name} • ${selectedSpace.name} • ${selectedType.name}\n'
                '${BookingTimeUtils.formatDateShort(_selectedDate)} • ${BookingTimeUtils.formatHm(slots[_startSlotIndex])}'
                '—${BookingTimeUtils.formatHm(slots[_endSlotIndex])}'
                '${_capacityController.text.trim().isEmpty ? '' : ' • ${_capacityController.text.trim()} чел.'}'
                '${_selectedEquipmentIds.isEmpty ? '' : ' • Оборуд.: ${_selectedEquipmentIds.length}'}',
            onTap: () => setState(() => _filtersExpanded = !_filtersExpanded),
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
                onBuildingChanged: (b) => _loadSpacesTypesAndEquipmentForBuilding(b),
                onSpaceChanged: (s) async {
                  setState(() {
                    _selectedSpace = s;
                    _types = s.types;
                    _selectedType = s.types.isNotEmpty ? s.types.first : null;
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
                    final minStartIndex = BookingTimeUtils.minStartIndex(newSlots, d);
                    _startSlotIndex = _startSlotIndex.clamp(minStartIndex, newSlots.length - 1);
                    _endSlotIndex = (_startSlotIndex + 1).clamp(0, newSlots.length - 1);
                  });
                  await _loadResults();
                },
                onStartTimeChanged: (i) async {
                  setState(() {
                    _startSlotIndex = i;
                    if (_endSlotIndex <= _startSlotIndex) {
                      _endSlotIndex = (_startSlotIndex + 1).clamp(0, slots.length - 1);
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
            crossFadeState:
                _filtersExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 220),
            sizeCurve: Curves.easeOutCubic,
          ),
          const SizedBox(height: 8),
          if (_resultsError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _resultsError!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
              ),
            ),
          if (_isResultsLoading) const LinearProgressIndicator(),
          const SizedBox(height: 6),
          if (!_isResultsLoading && _resultsError == null && _results.isEmpty)
            _EmptyState(message: 'Нет доступных объектов по выбранным параметрам'),
          if (_results.isNotEmpty)
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.78,
              ),
              itemCount: _results.length,
              itemBuilder: (context, index) => _BookableObjectTile(
                object: _results[index],
                onTap: () => _openCreateBooking(_results[index]),
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.showAppBar) {
      return _buildBody();
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Бронирование'),
        centerTitle: true,
        elevation: 0,
      ),
      body: _buildBody(),
    );
  }
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

  static String formatHm(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _formatDate(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd.$mm.${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final endMinIndex = (startIndex + 1).clamp(0, slots.length - 1);

    InputDecoration decoration(String label, {Widget? suffixIcon}) {
      return InputDecoration(
        labelText: label,
        suffixIcon: suffixIcon,
      );
    }

    Future<T?> pickOption<T>({
      required String title,
      required List<T> options,
      required T current,
      required String Function(T) labelOf,
      bool Function(T)? enabledOf,
    }) {
      return showModalBottomSheet<T>(
        context: context,
        showDragHandle: true,
        builder: (context) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.45,
                  ),
                  child: ListView(
                    shrinkWrap: true,
                    children: options.map((option) {
                      final enabled = enabledOf?.call(option) ?? true;
                      final selected = option == current;
                      return ListTile(
                        dense: true,
                        enabled: enabled,
                        title: Text(
                          labelOf(option),
                          style: TextStyle(
                            color: enabled ? null : colorScheme.outline,
                          ),
                        ),
                        trailing: selected
                            ? Icon(Icons.check, color: colorScheme.primary)
                            : null,
                        onTap: enabled ? () => Navigator.pop(context, option) : null,
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      );
    }

    Widget optionField({
      required String label,
      required String value,
      required VoidCallback onTap,
    }) {
      return InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: InputDecorator(
          decoration: decoration(label, suffixIcon: const Icon(Icons.keyboard_arrow_down)),
          child: Text(value),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(AppColors.radius),
        border: Border.all(color: colorScheme.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            optionField(
              label: 'Офис',
              value: selectedBuilding.name,
              onTap: () async {
                final picked = await pickOption<Building>(
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
            const SizedBox(height: 12),
            optionField(
              label: 'Этаж',
              value: selectedSpace.name,
              onTap: () async {
                final picked = await pickOption<Space>(
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
            const SizedBox(height: 12),
            optionField(
              label: 'Объект бронирования',
              value: selectedType.name,
              onTap: () async {
                final picked = await pickOption<BookingObjectType>(
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
            const SizedBox(height: 12),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: selectedDate.isBefore(now) ? now : selectedDate,
                  firstDate: DateTime(now.year, now.month, now.day),
                  lastDate: DateTime(now.year + 1),
                );
                if (picked != null) onDateChanged(picked);
              },
              child: InputDecorator(
                decoration: decoration('Дата', suffixIcon: const AppIcon(AppIcons.date, size: 20)),
                child: Text(_formatDate(selectedDate)),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: optionField(
                    label: 'С',
                    value: formatHm(slots[startIndex.clamp(minStartIndex, slots.length - 1)]),
                    onTap: () async {
                      final indices = List<int>.generate(slots.length, (i) => i);
                      final picked = await pickOption<int>(
                        title: 'Начало',
                        options: indices,
                        current: startIndex.clamp(minStartIndex, slots.length - 1),
                        labelOf: (i) => formatHm(slots[i]),
                        enabledOf: (i) => i >= minStartIndex,
                      );
                      if (picked != null) onStartTimeChanged(picked);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: optionField(
                    label: 'По',
                    value: formatHm(slots[endIndex.clamp(endMinIndex, slots.length - 1)]),
                    onTap: () async {
                      final indices = List<int>.generate(slots.length, (i) => i);
                      final picked = await pickOption<int>(
                        title: 'Окончание',
                        options: indices,
                        current: endIndex.clamp(endMinIndex, slots.length - 1),
                        labelOf: (i) => formatHm(slots[i]),
                        enabledOf: (i) => i >= endMinIndex,
                      );
                      if (picked != null) onEndTimeChanged(picked);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: capacityController,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.search,
              decoration: decoration('Вместимость (необязательно)').copyWith(hintText: 'Например, 8'),
              onSubmitted: onCapacitySubmitted,
            ),
            const SizedBox(height: 12),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onEquipmentTap,
              child: InputDecorator(
                decoration: decoration(
                  'Оборудование (необязательно)',
                  suffixIcon: const AppIcon(AppIcons.sliders),
                ),
                child: selectedEquipmentIds.isEmpty
                    ? Text(
                        equipment.isEmpty ? 'Нет доступного оборудования' : 'Выберите оборудование',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: equipment.isEmpty ? colorScheme.outline : null,
                            ),
                      )
                    : Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: equipment
                            .where((e) => selectedEquipmentIds.contains(e.id))
                            .map((e) => Chip(label: Text(e.name)))
                            .toList(),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: () => onApplyPressed(),
                icon: const AppIcon(AppIcons.search),
                label: const Text('Показать доступные'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FiltersDisclosure extends StatelessWidget {
  final bool isExpanded;
  final String title;
  final String summary;
  final VoidCallback onTap;

  const _FiltersDisclosure({
    required this.isExpanded,
    required this.title,
    required this.summary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(AppColors.radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppColors.radius),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppColors.radius),
            border: Border.all(color: cs.outline),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: AppIcon(
                  AppIcons.sliders,
                  color: cs.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      summary,
                      maxLines: isExpanded ? 4 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            height: 1.25,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                color: cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlinePageTitle extends StatelessWidget {
  final String title;

  const _InlinePageTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appBarTheme = theme.appBarTheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: appBarTheme.backgroundColor ?? AppColors.surfaceElevated,
        border: const Border(bottom: BorderSide(color: AppColors.outline)),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: kToolbarHeight,
          child: Center(
            child: Text(
              title,
              style: appBarTheme.titleTextStyle ?? theme.textTheme.titleLarge,
            ),
          ),
        ),
      ),
    );
  }
}

class _BookableObjectTile extends StatelessWidget {
  final BookableObject object;
  final VoidCallback onTap;

  const _BookableObjectTile({
    required this.object,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = object.previewImageUrl;
    final description = (object.description ?? '').trim();
    final cs = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: cs.primaryContainer,
              child: imageUrl == null
                  ? AppIcon(
                      AppIcons.locationPin,
                      color: cs.onPrimaryContainer,
                      size: 40,
                    )
                  : Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Icon(
                        Icons.broken_image_outlined,
                        color: cs.onPrimaryContainer,
                        size: 36,
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
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.white.withValues(alpha: 0.92),
                                height: 1.2,
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
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Оборудование',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            if (widget.equipment.isEmpty)
              Text(
                'В выбранном офисе нет доступного оборудования',
                style: Theme.of(context).textTheme.bodyMedium,
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: widget.equipment.map((e) {
                    final checked = _working.contains(e.id);
                    return CheckboxListTile(
                      value: checked,
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            _working.add(e.id);
                          } else {
                            _working.remove(e.id);
                          }
                        });
                      },
                      title: Text(e.name),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    );
                  }).toList(),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(
                  onPressed: () => setState(_working.clear),
                  child: const Text('Сбросить'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () => Navigator.pop(context, _working),
                  child: const Text('Готово'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 42,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const AppIcon(AppIcons.refresh),
              label: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;

  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            AppIcon(
              AppIcons.info,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
