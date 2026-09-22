import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Определяет, включён ли на устройстве VPN, по системным сетевым
/// интерфейсам.
///
/// Отдельного API «есть ли VPN» во Flutter нет, поэтому используется
/// эвристика по именам интерфейсов — так ОС называет VPN-туннели:
/// `tun*`/`tap*`/`ppp*`/`ipsec*` на Android, `utun*` на iOS. Возможны редкие
/// ложные срабатывания, но для ненавязчивого предупреждения этого достаточно.
class VpnDetectorService {
  VpnDetectorService._();

  static final VpnDetectorService instance = VpnDetectorService._();

  static const _checkInterval = Duration(seconds: 8);
  static const _vpnInterfacePrefixes = ['tun', 'tap', 'ppp', 'ipsec', 'utun'];

  final ValueNotifier<bool> isVpnActive = ValueNotifier<bool>(false);

  Timer? _timer;

  void start() {
    if (_timer != null) return;
    unawaited(_check());
    _timer = Timer.periodic(_checkInterval, (_) => unawaited(_check()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    // Пока приложение свёрнуто, статус не проверяется и может устареть —
    // сбрасываем его, чтобы при следующем возобновлении баннер не мигнул
    // старым «VPN включён» до завершения свежей проверки в start().
    isVpnActive.value = false;
  }

  Future<void> _check() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
      );
      isVpnActive.value = interfaces.any(
        (interface) => _vpnInterfacePrefixes.any(
          (prefix) => interface.name.toLowerCase().startsWith(prefix),
        ),
      );
    } catch (_) {
      // Список интерфейсов недоступен — не считаем это признаком VPN.
      // Явно сбрасываем значение: иначе, если запрос не удался сразу после
      // возобновления работы приложения (paused → resumed), баннер может
      // показывать устаревшее «VPN включён» из прошлой сессии проверки.
      isVpnActive.value = false;
    }
  }
}
