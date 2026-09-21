import 'package:flutter/cupertino.dart';

import '../services/vpn_detector_service.dart';

/// Ненавязчивый баннер поверх приложения: предупреждает, что включён VPN,
/// из-за которого звонки/чаты/почта могут работать нестабильно. Виден, пока
/// VPN активен, и не перехватывает взаимодействие с остальным интерфейсом.
class VpnBanner extends StatelessWidget {
  const VpnBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: VpnDetectorService.instance.isVpnActive,
      builder: (context, isActive, _) {
        if (!isActive) return const SizedBox.shrink();
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
              child: const Row(
                children: [
                  Icon(
                    CupertinoIcons.exclamationmark_triangle_fill,
                    color: CupertinoColors.white,
                    size: 16,
                  ),
                  SizedBox(width: 8),
                  Expanded(
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
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
