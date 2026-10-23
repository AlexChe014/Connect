import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'jitsi_meet_conference_options.dart';
import 'jitsi_meet_method_channel.dart';

/// Connect fork: the conference rendered inside the Flutter widget tree
/// (platform view) instead of a separate native screen, so the app can
/// draw its own controls around it.
///
/// The conference is joined when the view is created and left when it is
/// disposed. Only one view may exist at a time. Events arrive through
/// `JitsiMeet.setListener`, controls go through the regular `JitsiMeet`
/// methods (`setAudioMuted`, `hangUp`, …).
class JitsiMeetConferenceView extends StatelessWidget {
  const JitsiMeetConferenceView({super.key, required this.options});

  static const String viewType = 'jitsi_meet_flutter_sdk/conference_view';

  final JitsiMeetConferenceOptions options;

  @override
  Widget build(BuildContext context) {
    final params = MethodChannelJitsiMeet.encodeOptions(options);
    // All touches go to the conference: tiles, chat input, scroll.
    final gestures = <Factory<OneSequenceGestureRecognizer>>{
      Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
    };

    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return UiKitView(
          viewType: viewType,
          creationParams: params,
          creationParamsCodec: const StandardMessageCodec(),
          gestureRecognizers: gestures,
        );
      case TargetPlatform.android:
        // Hybrid composition: WebRTC renders into SurfaceViews, which
        // texture-based modes show as black.
        return PlatformViewLink(
          viewType: viewType,
          surfaceFactory: (context, controller) => AndroidViewSurface(
            controller: controller as AndroidViewController,
            gestureRecognizers: gestures,
            hitTestBehavior: PlatformViewHitTestBehavior.opaque,
          ),
          onCreatePlatformView: (params0) {
            return PlatformViewsService.initExpensiveAndroidView(
              id: params0.id,
              viewType: viewType,
              layoutDirection: TextDirection.ltr,
              creationParams: params,
              creationParamsCodec: const StandardMessageCodec(),
              onFocus: () => params0.onFocusChanged(true),
            )
              ..addOnPlatformViewCreatedListener(
                params0.onPlatformViewCreated,
              )
              ..create();
          },
        );
      default:
        return const SizedBox.shrink();
    }
  }
}
