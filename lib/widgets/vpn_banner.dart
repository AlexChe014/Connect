import 'package:flutter/cupertino.dart';

import '../services/vpn_detector_service.dart';

/// Ненавязчивый баннер поверх приложения: предупреждает, что включён VPN,
/// из-за которого звонки/чаты/почта могут работать нестабильно. Виден, пока
/// VPN активен, и не перехватывает взаимодействие с остальным интерфейсом.
///
/// Баннер можно закрыть крестиком — VPN не блокирует работу приложения
/// целиком (страдают в основном звонки), а до закрытия он перекрывал кнопку
/// меню. Закрытие сбрасывается при новом включении VPN (переход
/// выключен → включён), чтобы предупреждение не пропало навсегда после
/// одного случайного показа.
class VpnBanner extends StatefulWidget {
  const VpnBanner({super.key});

  @override
  State<VpnBanner> createState() => _VpnBannerState();
}

class _VpnBannerState extends State<VpnBanner> {
  bool _dismissed = false;
  bool _wasActive = false;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: VpnDetectorService.instance.isVpnActive,
      builder: (context, isActive, _) {
        if (isActive && !_wasActive) {
          _dismissed = false;
        }
        _wasActive = isActive;

        if (!isActive || _dismissed) return const SizedBox.shrink();

        return Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              color: CupertinoColors.systemOrange,
              child: Row(
                children: [
                  const Icon(
                    CupertinoIcons.exclamationmark_triangle_fill,
                    color: CupertinoColors.white,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Обнаружен включённый VPN — приложение может работать '
                      'нестабильно. Отключите VPN для корректной работы.',
                      style: TextStyle(
                        color: CupertinoColors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _dismissed = true),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        CupertinoIcons.xmark,
                        color: CupertinoColors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
